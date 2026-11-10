## 大地图逻辑（纯数据 + 规则，不依赖节点/UI，可在无头测试中逐帧推进）。
##
## - 节点图（路口/据点/要塞/大本营）+ AStar2D 寻路
## - 小队沿路线即时移动，消耗体力；己方据点内恢复体力与 HP
## - 单独驻留在非己方据点上会逐渐占领
## - 敌我小队接近时产生"遭遇"，地图暂停，等待 UI（或测试）进行自动战斗后回写结果
## - 战后：败方沿道路被击退一小段（无路可退则原地硬直），双方进入数秒整备，期间不会再次遭遇
## - 大本营 / 要塞有耐久：守军在场时无法占领，进攻方每赢一场削减耐久，归零后守军溃退
## - 敌方 AI：defend / patrol / advance
extends RefCounted

const BattleEngine := preload("res://scripts/battle_engine.gd")
const BattleUnit := preload("res://scripts/battle_unit.gd")
const Squad := preload("res://scripts/squad.gd")
const Progression := preload("res://scripts/progression.gd")

const MOVE_SPEED := 55.0          # 像素/秒
const TIRED_SPEED_FACTOR := 0.4   # 体力为 0 时的速度倍率
const STAMINA_DRAIN := 3.0        # 行军每秒消耗
const STAMINA_BASE_REGEN := 15.0  # 在己方据点每秒恢复
const STAMINA_IDLE_REGEN := 2.0   # 野外停留每秒恢复
const BASE_HP_REGEN := 0.08       # 己方据点每秒恢复最大 HP 的 8%（倒下的单位也会被救起）
const CAPTURE_TIME := 3.0         # 占领所需秒数
const ENCOUNTER_DIST := 16.0      # 敌我小队距离小于此值即遭遇
const AI_INTERVAL := 1.0
const RECOVER_TIME := 3.0          # 战后整备秒数（双方）
const KNOCKBACK_DIST := 70.0       # 败方被击退的距离（像素）
const DRAW_KNOCKBACK := 35.0       # 平局时双方各自后退的距离
const DURABILITY_BY_TYPE := {"hq": 100, "fort": 60}  # 节点未写 durability 时的默认值；普通据点没有耐久
const DURABILITY_HIT := 35.0       # 每次攻方获胜削减的耐久（再乘以胜方剩余 HP 比例）
const DURABILITY_MIN_HIT := 10
const DURABILITY_REGEN := 2.0      # 附近没有敌军时每秒恢复
const SIEGE_RADIUS := 120.0        # 敌军在此距离内时耐久不恢复
const AI_RETREAT_HP := 0.4
const PURSUE_REPATH := 0.3         # 追击时每隔多少秒按目标当前位置重新寻路         # 敌方 AI：HP 低于此比例时撤回最近的己方据点休整
const INCOME_INTERVAL := 10.0     # 每 10 秒结算一次据点收入
const INCOME_BY_TYPE := {"base": 10, "fort": 15, "hq": 20, "road": 0}
const BATTLE_GOLD := 20           # 每场胜利的战利金
const OBJECTIVE_NAMES := {"capture_hq": "攻陷敌方大本营", "defend": "坚守大本营", "defeat_boss": "击败敌方首领"}

var skills_db: Dictionary = {}
var passives_db: Dictionary = {}
var classes_db: Dictionary = {}
var items_db: Dictionary = {}

# 战役任务相关
var map_name: String = ""
var objective: Dictionary = {"type": "capture_hq"}
var progression_enabled: bool = false  # 开启后：战斗给经验、胜利给金币
var gold_earned: int = 0               # 本场任务累计收入（据点 + 战斗 + 据点奖励）
var gold_from_bases: int = 0
var gold_from_battles: int = 0
var loot_items: Array = []             # 本场任务获得的道具 id
var progress_log: PackedStringArray = PackedStringArray()  # 升级 / 习得技能 等记录
var xp_gained: Dictionary = {}         # uid -> 本场累计经验
var battles_won: int = 0
var battles_lost: int = 0
var end_reason: String = ""
var _income_timer: float = 0.0

var nodes: Dictionary = {}        # id -> {id,name,type,owner,pos,capture_team,capture_progress}
var node_ids: Array = []
var edges: Array = []
var squads: Array = []
var time: float = 0.0
var pending_encounter: Array = [] # [我方小队, 敌方小队]
var game_over: bool = false
var winner: int = -1              # 0 我方胜 / 1 敌方胜
var ai_enabled: bool = true       # 测试时可关闭敌方 AI

var _astar := AStar2D.new()
var _adj: Dictionary = {}          # 节点 id -> 相邻节点 id 列表
var _ai_timer: float = 0.0


# ---------------------------------------------------------------- 加载

## player_squads：可选，战役模式下由外部传入的我方小队
##   [{id, name, color, units: [BattleUnit...]}]，地图文件里的 team 0 小队会被忽略，
##   我方小队从 player_start（缺省为我方大本营）出发。单位对象与名册共享，经验/HP 直接写回。
func load_campaign(campaign_path: String, classes_path: String, player_squads: Array = [], items_path: String = "") -> bool:
	var cdata = BattleEngine.load_json(classes_path)
	var map = BattleEngine.load_json(campaign_path)
	if cdata == null or map == null:
		return false
	skills_db = cdata.get("skills", {})
	passives_db = cdata.get("passives", {})
	classes_db = cdata.get("classes", {})
	for sid in skills_db:
		Progression.skill_names[sid] = skills_db[sid].get("name", sid)
	if items_path != "":
		var idata = BattleEngine.load_json(items_path)
		if typeof(idata) == TYPE_DICTIONARY:
			items_db = idata.get("items", {})
	map_name = str(map.get("name", ""))
	objective = map.get("objective", {"type": "capture_hq"})
	var ok := true
	var i := 0
	for nd in map.get("nodes", []):
		var id := str(nd["id"])
		var p: Array = nd["pos"]
		nodes[id] = {
			"id": id, "name": str(nd.get("name", "")), "type": str(nd.get("type", "road")),
			"owner": int(nd.get("owner", -1)), "pos": Vector2(float(p[0]), float(p[1])),
			"capture_team": -1, "capture_progress": 0.0, "astar_id": i,
			"gold": int(nd.get("gold", INCOME_BY_TYPE.get(str(nd.get("type", "road")), 0))),
			"reward": nd.get("reward", {}), "reward_claimed": false,
		}
		var dur := int(nd.get("durability", DURABILITY_BY_TYPE.get(nodes[id]["type"], 0)))
		nodes[id]["max_durability"] = dur
		nodes[id]["durability"] = float(dur)
		node_ids.append(id)
		_astar.add_point(i, nodes[id]["pos"])
		i += 1
	for e in map.get("edges", []):
		if not nodes.has(e[0]) or not nodes.has(e[1]):
			push_error("边引用了不存在的节点：%s" % str(e))
			ok = false
			continue
		edges.append([str(e[0]), str(e[1])])
		_astar.connect_points(nodes[e[0]]["astar_id"], nodes[e[1]]["astar_id"])
		_adj[str(e[0])] = _adj.get(str(e[0]), []) + [str(e[1])]
		_adj[str(e[1])] = _adj.get(str(e[1]), []) + [str(e[0])]
	for sd in map.get("squads", []):
		if not player_squads.is_empty() and int(sd.get("team", 0)) == 0:
			continue
		var sq := Squad.new()
		sq.id = str(sd["id"])
		sq.name = str(sd.get("name", sq.id))
		sq.team = int(sd.get("team", 0))
		sq.color = Color.from_string(str(sd.get("color", "#ffffff")), Color.WHITE)
		sq.ai = sd.get("ai", {})
		sq.home = str(sd.get("start", ""))
		if not nodes.has(sq.home):
			push_error("小队 %s 的起点不存在" % sq.id)
			ok = false
			continue
		sq.at_node = sq.home
		sq.pos = nodes[sq.home]["pos"]
		for ud in sd.get("units", []):
			var cid := str(ud.get("class", ""))
			if not classes_db.has(cid):
				push_error("未知职业 %s" % cid)
				ok = false
				continue
			var data: Dictionary = ud.duplicate(true)
			if not data.has("tactics"):
				data["tactics"] = classes_db[cid].get("default_tactics", [])
			var u = BattleUnit.from_data(cid, classes_db[cid], data, sq.team)
			u.uid = "%s_%s" % [sq.id, u.display_name]
			sq.units.append(u)
		squads.append(sq)
	var start := str(map.get("player_start", hq_of(0)))
	for pd in player_squads:
		if not nodes.has(start):
			push_error("player_start 不存在")
			return false
		var ps := Squad.new()
		ps.id = str(pd["id"])
		ps.name = str(pd.get("name", ps.id))
		ps.team = 0
		ps.color = Color.from_string(str(pd.get("color", "#ffffff")), Color.WHITE)
		ps.home = start
		ps.at_node = start
		ps.pos = nodes[start]["pos"]
		ps.units = pd["units"]
		squads.append(ps)
	if hq_of(0) == "":
		push_error("我方需要一个 hq 节点")
		ok = false
	if str(objective.get("type", "")) == "capture_hq" and hq_of(1) == "":
		push_error("目标为攻陷大本营时，敌方需要一个 hq 节点")
		ok = false
	if str(objective.get("type", "")) == "defeat_boss" and squad_by_id(str(objective.get("squad", ""))) == null:
		push_error("首领小队不存在")
		ok = false
	return ok


func objective_text() -> String:
	var t := str(objective.get("type", "capture_hq"))
	match t:
		"defend":
			return "坚守大本营 %d 秒（剩余 %d 秒）" % [int(objective.get("time", 0)), maxi(0, int(ceil(float(objective.get("time", 0)) - time)))]
		"defeat_boss":
			var b = squad_by_id(str(objective.get("squad", "")))
			return "击败敌方首领「%s」" % (b.name if b != null else "?")
	return "攻陷敌方大本营「%s」" % (nodes[hq_of(1)]["name"] if hq_of(1) != "" else "?")


## 当前每轮（10 秒）据点收入
func income_per_tick(team: int = 0) -> int:
	var g := 0
	for id in node_ids:
		if nodes[id]["owner"] == team:
			g += int(nodes[id]["gold"])
	return g


## 任务结算用的汇总
func summary() -> Dictionary:
	return {
		"map": map_name, "won": winner == 0, "reason": end_reason, "time": time,
		"gold": gold_earned, "gold_bases": gold_from_bases, "gold_battles": gold_from_battles,
		"items": loot_items.duplicate(), "progress": progress_log.duplicate(), "xp": xp_gained.duplicate(),
		"battles_won": battles_won, "battles_lost": battles_lost,
	}


# ---------------------------------------------------------------- 查询

func hq_of(team: int) -> String:
	for id in node_ids:
		var n: Dictionary = nodes[id]
		if n["type"] == "hq" and n["owner"] == team:
			return id
	# 大本营已失守时，返回该方初始大本营（用于撤退判断）
	return ""


func squad_by_id(id: String):
	for sq in squads:
		if sq.id == id:
			return sq
	return null


func living_squads(team: int) -> Array:
	return squads.filter(func(s): return s.alive and s.team == team)


## 小队若静止停在某节点上，返回该节点 id，否则返回 ""
func node_of(sq) -> String:
	if sq.is_moving():
		return ""
	if sq.pos.distance_to(nodes[sq.at_node]["pos"]) < 1.0:
		return sq.at_node
	return ""


func is_capturable(id: String) -> bool:
	return nodes[id]["type"] != "road"


## 返回 [我方据点数, 敌方据点数, 中立据点数]
func base_counts() -> Array:
	var c := [0, 0, 0]
	for id in node_ids:
		if not is_capturable(id):
			continue
		var o: int = nodes[id]["owner"]
		c[2 if o < 0 else o] += 1
	return c


func nearest_node(p: Vector2, max_dist: float = 1e9) -> String:
	var best := ""
	var bd := max_dist
	for id in node_ids:
		var d: float = p.distance_to(nodes[id]["pos"])
		if d < bd:
			bd = d
			best = id
	return best


## 节点间最短路（含起点）
func find_path(from_id: String, to_id: String) -> Array:
	var ids := _astar.get_id_path(nodes[from_id]["astar_id"], nodes[to_id]["astar_id"])
	var out: Array = []
	for aid in ids:
		out.append(node_ids[aid])
	return out


func path_length(p: Array) -> float:
	var total := 0.0
	for i in range(1, p.size()):
		total += (nodes[p[i - 1]]["pos"] as Vector2).distance_to(nodes[p[i]]["pos"])
	return total


# ---------------------------------------------------------------- 命令

## 命令小队前往节点；行军途中可掉头（自动选择更近的方向）。新命令会取消追击。
func order_move(sq, dest: String) -> bool:
	if not sq.alive or not nodes.has(dest):
		return false
	sq.pursue_target = null
	return _route(sq, dest)


func _route(sq, dest: String) -> bool:
	if not sq.is_moving():
		if dest == sq.at_node:
			return true
		var p := find_path(sq.at_node, dest)
		if p.is_empty():
			return false
		p.remove_at(0)
		sq.path = p
		return true
	# 行军途中：比较"继续前进到下一个节点"与"返回上一个节点"两种走法
	var best: Array = []
	var best_len := INF
	for via in [sq.path[0], sq.at_node]:
		var p2 := find_path(via, dest)
		if p2.is_empty():
			continue
		var l: float = sq.pos.distance_to(nodes[via]["pos"]) + path_length(p2)
		if l < best_len:
			best_len = l
			best = p2
	if best.is_empty():
		return false
	sq.path = best
	return true


func stop(sq) -> void:
	sq.pursue_target = null
	# 停在最近经过的节点方向：直接返回上一个节点
	if sq.is_moving():
		sq.path = [sq.at_node] if sq.pos.distance_to(nodes[sq.at_node]["pos"]) > 0.5 else []


# ---------------------------------------------------------------- 追击

## 命令小队追击一支敌方小队：沿道路朝目标的当前位置前进，定期重新寻路，接触后照常遭遇。
func order_pursue(sq, target) -> bool:
	if not sq.alive or target == null or not target.alive or target.team == sq.team:
		return false
	sq.pursue_target = target
	sq.repath_timer = PURSUE_REPATH
	_repath_pursuit(sq)
	return true


## 小队若在某条道路中间（不在节点上），返回 [起点, 终点]，否则返回 []
func edge_of(sq) -> Array:
	if sq.is_moving() and sq.pos.distance_to(nodes[sq.at_node]["pos"]) > 0.5:
		return [sq.at_node, sq.path[0]]
	return []


## 从小队当前位置沿道路到节点 dest 的路程
func route_cost(sq, dest: String) -> float:
	var e := edge_of(sq)
	if e.is_empty():
		var p := find_path(sq.at_node, dest)
		return path_length(p) + sq.pos.distance_to(nodes[sq.at_node]["pos"]) if not p.is_empty() else INF
	var best := INF
	for via in e:
		var p2 := find_path(via, dest)
		if not p2.is_empty():
			best = minf(best, sq.pos.distance_to(nodes[via]["pos"]) + path_length(p2))
	return best


func _repath_pursuit(sq) -> void:
	var t = sq.pursue_target
	var te := edge_of(t)
	if te.is_empty():
		if edge_of(sq).is_empty():
			sq.path = []
		_route(sq, t.at_node)  # 目标停在节点上：直接去那个节点
		return
	var se := edge_of(sq)
	var a: String = te[0]
	var b: String = te[1]
	if not se.is_empty() and ((se[0] == a and se[1] == b) or (se[0] == b and se[1] == a)):
		# 同一条路上：朝目标那一侧的端点走（必然经过目标）
		var far: String = a if t.pos.distance_to(nodes[a]["pos"]) < sq.pos.distance_to(nodes[a]["pos"]) else b
		sq.path = [far]
		sq.at_node = b if far == a else a
		return
	# 先到目标所在道路较合适的一端，再沿这条路走向另一端（途中必然接触目标）
	var ca: float = route_cost(sq, a) + t.pos.distance_to(nodes[a]["pos"])
	var cb: float = route_cost(sq, b) + t.pos.distance_to(nodes[b]["pos"])
	var entry: String = a if ca <= cb else b
	var other: String = b if entry == a else a
	if se.is_empty():
		sq.path = []
	_route(sq, entry)
	if sq.path.is_empty():
		if sq.at_node == entry:
			sq.path = [other]
	elif sq.path.back() == entry:
		sq.path.append(other)


func _update_pursuit(delta: float, ev: Array) -> void:
	for sq in squads:
		if not sq.alive or sq.pursue_target == null:
			continue
		var t = sq.pursue_target
		if not t.alive:
			sq.pursue_target = null
			stop(sq)
			ev.append({"type": "pursuit_lost", "squad": sq.id, "text": "%s 失去了追击目标「%s」，原地待命" % [sq.name, t.name]})
			continue
		sq.repath_timer -= delta
		if sq.repath_timer <= 0.0:
			sq.repath_timer = PURSUE_REPATH
			_repath_pursuit(sq)


# ---------------------------------------------------------------- 主循环

## 推进 delta 秒，返回事件列表（Dictionary：type = encounter/captured/destroyed/retreat/game_over/info）
func update(delta: float) -> Array:
	var ev: Array = []
	if game_over or not pending_encounter.is_empty():
		return ev
	time += delta
	for sq in squads:
		if sq.recover_time > 0.0:
			sq.recover_time = maxf(0.0, sq.recover_time - delta)
			if sq.recover_time <= 0.0:
				sq.stunned = false
	_ai_timer -= delta
	if _ai_timer <= 0.0 and ai_enabled:
		_ai_timer = AI_INTERVAL
		_run_ai()
	_update_pursuit(delta, ev)
	for sq in squads:
		if sq.alive:
			_move(sq, delta)
	_check_encounters(ev)
	if not pending_encounter.is_empty():
		return ev
	_update_bases(delta, ev)
	_update_durability(delta)
	_recover(delta)
	_income(delta, ev)
	if str(objective.get("type", "")) == "defend" and time >= float(objective.get("time", 0)):
		_end_game(0, ev, "坚守了 %d 秒，援军赶到" % int(objective.get("time", 0)))
	return ev


func _income(delta: float, ev: Array) -> void:
	if not progression_enabled:
		return
	_income_timer += delta
	while _income_timer >= INCOME_INTERVAL:
		_income_timer -= INCOME_INTERVAL
		var g := income_per_tick(0)
		gold_earned += g
		gold_from_bases += g
		if g > 0:
			ev.append({"type": "income", "gold": g, "text": "据点收入 +%d 金" % g})


func _move(sq, delta: float) -> void:
	if not sq.is_moving() or sq.is_recovering():
		return
	var speed := MOVE_SPEED * (1.0 if sq.stamina > 0.0 else TIRED_SPEED_FACTOR)
	var step := speed * delta
	sq.stamina = maxf(0.0, sq.stamina - STAMINA_DRAIN * delta)
	while step > 0.0 and sq.is_moving():
		var target: Vector2 = nodes[sq.path[0]]["pos"]
		var d: float = sq.pos.distance_to(target)
		if d <= step:
			sq.pos = target
			sq.at_node = sq.path.pop_front()
			step -= d
		else:
			sq.pos += (target - sq.pos).normalized() * step
			step = 0.0


func _check_encounters(ev: Array) -> void:
	for a in living_squads(0):
		if a.is_recovering():
			continue
		for b in living_squads(1):
			if b.is_recovering():
				continue
			if a.pos.distance_to(b.pos) < ENCOUNTER_DIST:
				pending_encounter = [a, b]
				ev.append({"type": "encounter", "text": "%s 与 %s 遭遇！" % [a.name, b.name]})
				return


func _update_bases(delta: float, ev: Array) -> void:
	for id in node_ids:
		if not is_capturable(id):
			continue
		var n: Dictionary = nodes[id]
		var teams := {}
		for sq in squads:
			if sq.alive and node_of(sq) == id:
				teams[sq.team] = true
		if teams.size() != 1:
			n["capture_team"] = -1
			n["capture_progress"] = 0.0
			continue
		var t: int = teams.keys()[0]
		if n["owner"] == t:
			n["capture_team"] = -1
			n["capture_progress"] = 0.0
			continue
		if n["capture_team"] != t:
			n["capture_team"] = t
			n["capture_progress"] = 0.0
		n["capture_progress"] += delta
		if n["capture_progress"] >= CAPTURE_TIME:
			var was_hq: bool = n["type"] == "hq"
			n["owner"] = t
			n["durability"] = n["max_durability"] * 0.5  # 刚夺下的据点只有一半耐久
			n["capture_team"] = -1
			n["capture_progress"] = 0.0
			ev.append({"type": "captured", "node": id, "team": t,
				"text": "%s 占领了「%s」" % ["我方" if t == 0 else "敌方", n["name"]]})
			if t == 0 and not n["reward_claimed"] and not (n["reward"] as Dictionary).is_empty():
				n["reward_claimed"] = true
				_claim_reward(n, ev)
			if was_hq:
				_end_game(t, ev, "大本营「%s」被攻陷！" % n["name"])


## 附近（SIEGE_RADIUS 内）没有敌军时，耐久缓慢恢复
func _update_durability(delta: float) -> void:
	for id in node_ids:
		var n: Dictionary = nodes[id]
		if n["max_durability"] <= 0 or n["durability"] >= n["max_durability"]:
			continue
		var threatened := false
		for sq in squads:
			if sq.alive and sq.team != n["owner"] and sq.pos.distance_to(n["pos"]) < SIEGE_RADIUS:
				threatened = true
				break
		if not threatened:
			n["durability"] = minf(float(n["max_durability"]), n["durability"] + DURABILITY_REGEN * delta)


func durability_text(id: String) -> String:
	var n: Dictionary = nodes[id]
	if n["max_durability"] <= 0:
		return ""
	return "%d/%d" % [int(ceil(n["durability"])), n["max_durability"]]


func _recover(delta: float) -> void:
	for sq in squads:
		if not sq.alive or sq.is_moving():
			continue
		var id := node_of(sq)
		var own_base: bool = id != "" and is_capturable(id) and nodes[id]["owner"] == sq.team
		if own_base:
			sq.stamina = minf(100.0, sq.stamina + STAMINA_BASE_REGEN * delta)
			sq.regen_timer += delta
			while sq.regen_timer >= 1.0:
				sq.regen_timer -= 1.0
				for u in sq.units:
					u.hp = mini(u.max_hp, u.hp + int(ceil(u.max_hp * BASE_HP_REGEN)))
		else:
			sq.regen_timer = 0.0
			sq.stamina = minf(100.0, sq.stamina + STAMINA_IDLE_REGEN * delta)


func _claim_reward(n: Dictionary, ev: Array) -> void:
	var r: Dictionary = n["reward"]
	var parts := PackedStringArray()
	var g := int(r.get("gold", 0))
	if g > 0:
		gold_earned += g
		gold_from_bases += g
		parts.append("%d 金" % g)
	for it in r.get("items", []):
		loot_items.append(str(it))
		parts.append("「%s」" % str(items_db.get(it, {}).get("name", it)))
	if not parts.is_empty():
		ev.append({"type": "reward", "node": n["id"], "text": "在「%s」获得：%s" % [n["name"], "、".join(parts)]})


func _end_game(team_won: int, ev: Array, reason: String) -> void:
	if game_over:
		return
	game_over = true
	winner = team_won
	end_reason = reason
	ev.append({"type": "game_over", "winner": team_won,
		"text": "%s —— %s" % [reason, "我方胜利！" if team_won == 0 else "我方败北……"]})


# ---------------------------------------------------------------- 战斗衔接

## 为当前遭遇创建战斗引擎（单位对象与地图共享，HP 延续）。
func create_battle(a, b):
	var e := BattleEngine.new()
	e.setup_with_units(skills_db, passives_db, classes_db, a.units + b.units, [a.name, b.name])
	e.battle_seed = BattleEngine.DEFAULT_SEED + int(time * 10.0)  # 每场遭遇不同但可复现
	e.reset_battle(false)
	return e


## 战斗结束后回写结果：败方撤退回大本营（全灭则移除）。返回事件列表。
func apply_battle_result(a, b, battle_winner: int) -> Array:
	var ev: Array = []
	pending_encounter = []
	for sq in [a, b]:
		for u in sq.units:  # 地图上锐气/守势回满（只有 HP 延续）
			u.ep = u.max_ep
			u.gp = u.max_gp
			u.statuses = []
	var loser = b if battle_winner == 0 else a
	var winner_sq = a if battle_winner == 0 else b
	if progression_enabled:
		var res: Dictionary = Progression.award_battle(a.units, battle_winner == 0, classes_db, items_db)
		for uid in res["xp"]:
			xp_gained[uid] = int(xp_gained.get(uid, 0)) + int(res["xp"][uid])
		for line in res["lines"]:
			progress_log.append(line)
			ev.append({"type": "progress", "text": line})
		if battle_winner == 0:
			battles_won += 1
			gold_earned += BATTLE_GOLD
			gold_from_battles += BATTLE_GOLD
			ev.append({"type": "income", "gold": BATTLE_GOLD, "text": "战斗胜利，战利金 +%d" % BATTLE_GOLD})
		else:
			battles_lost += 1
	# 首领被击败（战败）即视为讨伐成功
	var boss_down := false
	if loser == b and battle_winner == 0 and bool(b.ai.get("boss", false)):
		b.alive = false
		b.path = []
		boss_down = true
		ev.append({"type": "destroyed", "squad": b.id, "text": "敌方首领「%s」被击败！" % b.name})
	for sq in [a, b]:
		if sq.living_count() == 0:
			sq.alive = false
			sq.path = []
			ev.append({"type": "destroyed", "squad": sq.id, "text": "%s 全军覆没" % sq.name})
	if battle_winner == -1:
		# 平局：不削减耐久，双方各自后退一点（死守据点的一方原地不动）
		for pair in [[a, b], [b, a]]:
			if pair[0].alive and defended_node(pair[0]) == "":
				_knockback(pair[0], pair[1], DRAW_KNOCKBACK, ev)
	elif loser.alive:
		if loser.pursue_target != null:
			ev.append({"type": "pursuit_lost", "squad": loser.id, "text": "%s 战败，中止追击" % loser.name})
			loser.pursue_target = null
		var held := defended_node(loser)
		if held != "":
			_siege_hit(held, winner_sq, loser, ev)
		else:
			_knockback(loser, winner_sq, KNOCKBACK_DIST, ev)
	for sq in [a, b]:
		if sq.alive:
			sq.recover_time = maxf(sq.recover_time, RECOVER_TIME)
	if boss_down and str(objective.get("type", "")) == "defeat_boss" and str(objective.get("squad", "")) == b.id:
		_end_game(0, ev, "首领「%s」已被讨伐" % b.name)
	for t in [0, 1]:
		if living_squads(t).is_empty():
			_end_game(1 - t, ev, "%s 的所有小队都已覆没" % ("我方" if t == 0 else "敌方"))
	return ev


## 小队静止在己方带耐久的据点（大本营 / 要塞）上时，返回该节点 id —— 它是"守军"
func defended_node(sq) -> String:
	var id := node_of(sq)
	if id != "" and nodes[id]["owner"] == sq.team and nodes[id]["max_durability"] > 0:
		return id
	return ""


## 攻方赢下针对守军的一战：削减耐久；归零则该节点上的守军全部溃退
func _siege_hit(id: String, winner_sq, loser, ev: Array) -> void:
	var n: Dictionary = nodes[id]
	var hit := maxi(DURABILITY_MIN_HIT, int(round(DURABILITY_HIT * winner_sq.hp_ratio())))
	n["durability"] = maxf(0.0, n["durability"] - hit)
	ev.append({"type": "siege", "node": id, "text": "「%s」耐久 -%d（剩余 %s）" % [n["name"], hit, durability_text(id)]})
	if n["durability"] > 0.0:
		loser.stunned = true
		ev.append({"type": "stunned", "squad": loser.id, "text": "%s 死守「%s」，阵脚大乱（硬直 %d 秒）" % [loser.name, n["name"], int(RECOVER_TIME)]})
		return
	ev.append({"type": "breached", "node": id, "text": "「%s」的防御被攻破！" % n["name"]})
	for sq in squads.duplicate():
		if sq.alive and sq.team == loser.team and node_of(sq) == id:
			_rout(sq, id, winner_sq, ev)


## 守军溃退：沿道路撤往最近的己方据点；无处可去则溃散
func _rout(sq, from_id: String, winner_sq, ev: Array) -> void:
	var target := nearest_friendly_node(sq, from_id)
	if target == "":
		sq.alive = false
		sq.path = []
		ev.append({"type": "destroyed", "squad": sq.id, "text": "%s 无处可退，溃散了" % sq.name})
		return
	var p := find_path(from_id, target)
	p.remove_at(0)
	sq.path = p
	sq.at_node = from_id
	_advance(sq, KNOCKBACK_DIST)
	sq.recover_time = RECOVER_TIME
	ev.append({"type": "retreat", "squad": sq.id, "text": "%s 溃退，撤往「%s」" % [sq.name, nodes[target]["name"]]})


## 沿当前路线前进 dist 像素（不耗体力，用于击退 / 溃退）
func _advance(sq, dist: float) -> void:
	while dist > 0.0 and sq.is_moving():
		var target: Vector2 = nodes[sq.path[0]]["pos"]
		var d: float = sq.pos.distance_to(target)
		if d <= dist:
			sq.pos = target
			sq.at_node = sq.path.pop_front()
			dist -= d
		else:
			sq.pos += (target - sq.pos).normalized() * dist
			dist = 0.0


## 最近的己方据点（按路程，可排除某个节点）
func nearest_friendly_node(sq, exclude: String = "") -> String:
	var start: String = sq.path[0] if sq.is_moving() else sq.at_node
	var best := ""
	var best_len := INF
	for id in node_ids:
		if id == exclude or not is_capturable(id) or nodes[id]["owner"] != sq.team:
			continue
		var p := find_path(start, id)
		if p.is_empty():
			continue
		var l: float = path_length(p) + sq.pos.distance_to(nodes[start]["pos"])
		if l < best_len:
			best_len = l
			best = id
	return best


## 击退：沿道路远离 from_sq 推开 dist 像素。之后小队会走到被推向的那个节点。
## 无路可退（没有相邻道路）时原地硬直。
func _knockback(sq, from_sq, dist: float, ev: Array) -> void:
	var away: Vector2 = sq.pos - from_sq.pos
	var on_edge: bool = sq.is_moving() and sq.pos.distance_to(nodes[sq.at_node]["pos"]) > 0.5
	if on_edge:
		var ea: String = sq.at_node
		var eb: String = sq.path[0]
		# 选择离胜方更远的一端
		var to: String = ea
		if from_sq.pos.distance_to(nodes[eb]["pos"]) > from_sq.pos.distance_to(nodes[ea]["pos"]) + 0.5:
			to = eb
		sq.path = [to]
		sq.at_node = eb if to == ea else ea
	else:
		var here: String = sq.at_node
		sq.pos = nodes[here]["pos"]
		var nbrs: Array = _adj.get(here, [])
		if nbrs.is_empty():
			sq.path = []
			sq.stunned = true
			ev.append({"type": "stunned", "squad": sq.id, "text": "%s 无路可退，陷入硬直" % sq.name})
			return
		if away.length() < 1.0:
			# 双方几乎重合：朝己方据点 / 出发地的方向退
			var t := nearest_friendly_node(sq, here)
			if t == "":
				t = sq.home
			var p: Array = find_path(here, t) if t != "" and t != here else []
			if p.size() > 1:
				away = nodes[p[1]]["pos"] - nodes[here]["pos"]
			else:
				away = Vector2.LEFT if sq.team == 0 else Vector2.RIGHT
		var best := ""
		var best_score := -INF
		for m in nbrs:
			var dir: Vector2 = (nodes[m]["pos"] - nodes[here]["pos"]).normalized()
			var score := dir.dot(away.normalized())
			if nodes[m]["owner"] == sq.team:
				score += 0.3
			for o in squads:
				if o.alive and o.team != sq.team and o.pos.distance_to(nodes[m]["pos"]) < 1.0:
					score -= 2.0
			if score > best_score:
				best_score = score
				best = m
		sq.path = [best]
		sq.at_node = here
	_advance(sq, dist)
	var dest: String = sq.destination()
	var dn: String = nodes[dest]["name"] if nodes[dest]["name"] != "" else "路口"
	ev.append({"type": "knockback", "squad": sq.id, "text": "%s 被击退，退向「%s」" % [sq.name, dn]})


## 无 UI 时直接自动打完当前遭遇（测试 / 快速结算用）。返回 [日志, 事件]
func resolve_encounter_auto() -> Array:
	if pending_encounter.is_empty():
		return [PackedStringArray(), []]
	var a = pending_encounter[0]
	var b = pending_encounter[1]
	var e = create_battle(a, b)
	var battle_log: PackedStringArray = e.run_to_end()
	return [battle_log, apply_battle_result(a, b, e.winner)]


# ---------------------------------------------------------------- 敌方 AI

func _run_ai() -> void:
	for sq in living_squads(1):
		if sq.is_recovering():
			continue
		# 残血：撤回最近的己方据点休整（已在己方据点上则原地休整）
		if sq.hp_ratio() < AI_RETREAT_HP:
			var here := node_of(sq)
			if here != "" and is_capturable(here) and nodes[here]["owner"] == 1:
				continue
			var safe := nearest_friendly_node(sq)
			if safe != "":
				if sq.destination() != safe:
					order_move(sq, safe)
				continue
		match str(sq.ai.get("mode", "defend")):
			"defend":
				_ai_defend(sq)
			"patrol":
				_ai_patrol(sq)
			"advance":
				_ai_advance(sq)


func _target_node_of(sq) -> String:
	return sq.path[0] if sq.is_moving() else sq.at_node


func _ai_defend(sq) -> void:
	var home_pos: Vector2 = nodes[sq.home]["pos"]
	var radius := float(sq.ai.get("radius", 150))
	var intruder = null
	var bd := radius
	for p in living_squads(0):
		var d: float = p.pos.distance_to(home_pos)
		if d < bd:
			bd = d
			intruder = p
	if intruder != null:
		order_move(sq, _target_node_of(intruder))
	elif sq.destination() != sq.home:
		order_move(sq, sq.home)


func _ai_patrol(sq) -> void:
	var route: Array = sq.ai.get("route", [])
	if route.is_empty() or sq.is_moving():
		return
	if sq.stamina < 30.0 and node_of(sq) != "" and nodes[node_of(sq)]["owner"] == 1:
		return  # 在己方据点休整
	sq.patrol_index = (sq.patrol_index + 1) % route.size()
	order_move(sq, str(route[sq.patrol_index]))


func _ai_advance(sq) -> void:
	if time < float(sq.ai.get("delay", 0)):
		return
	if not sq.is_moving():
		var here := node_of(sq)
		if here != "" and is_capturable(here) and nodes[here]["owner"] == 1 and (sq.stamina < 70.0 or sq.hp_ratio() < 0.7):
			return  # 体力或 HP 不足，在己方据点休整到恢复为止
	var here2 := node_of(sq)
	if here2 != "" and is_capturable(here2) and nodes[here2]["owner"] != 1:
		return  # 正在占领
	# 选择路程最近的非己方据点（大本营距离打 8 折，越往后越倾向直取大本营）
	var start := _target_node_of(sq)
	var best := ""
	var best_len := INF
	# 指定了进攻目标列表：按顺序取第一个非己方据点
	var targets: Array = sq.ai.get("targets", [])
	for tid in targets:
		if nodes.has(tid) and nodes[tid]["owner"] != 1:
			best = str(tid)
			best_len = 0.0
			break
	for id in ([] if not targets.is_empty() else node_ids):
		if not is_capturable(id) or nodes[id]["owner"] == 1:
			continue
		var l := path_length(find_path(start, id))
		if nodes[id]["type"] == "hq":
			l *= 0.8
		if l < best_len:
			best_len = l
			best = id
	if best != "" and sq.destination() != best:
		order_move(sq, best)


# ---------------------------------------------------------------- 保存 / 读取 编队与战术

func export_setups() -> Dictionary:
	var out := {}
	for sq in squads:
		if sq.team != 0:
			continue
		var arr: Array = []
		for u in sq.units:
			arr.append({"name": u.display_name, "row": u.row, "col": u.col, "tactics": u.tactics.duplicate(true)})
		out[sq.id] = arr
	return out


func save_setups(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("无法写入 %s" % path)
		return false
	f.store_string(JSON.stringify(export_setups(), "  "))
	return true


func load_setups(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var data = BattleEngine.load_json(path)
	if typeof(data) != TYPE_DICTIONARY:
		return false
	for sid in data:
		var sq = squad_by_id(sid)
		if sq == null:
			continue
		for ud in data[sid]:
			for u in sq.units:
				if u.display_name == str(ud.get("name", "")):
					u.row = int(ud.get("row", u.row))
					u.col = int(ud.get("col", u.col))
					var tac: Array = []
					for rule in ud.get("tactics", []):
						var r: Dictionary = rule.duplicate()
						if r.has("value") and typeof(r["value"]) == TYPE_FLOAT and r["if"] in ["allies_hurt_at_least", "row_count_at_least", "enemy_count_at_least", "ally_ep_at_most"]:
							r["value"] = int(r["value"])
						if u.skills.has(str(r.get("skill", ""))):
							tac.append(r)
					u.tactics = tac
	return true


## 交换小队内两个格子（目标格可以为空）
static func swap_slots(sq, r1: int, c1: int, r2: int, c2: int) -> bool:
	var a = null
	var b = null
	for u in sq.units:
		if u.row == r1 and u.col == c1:
			a = u
		elif u.row == r2 and u.col == c2:
			b = u
	if a == null:
		return false
	a.row = r2
	a.col = c2
	if b != null:
		b.row = r1
		b.col = c1
	return true
