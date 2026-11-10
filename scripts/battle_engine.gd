## 自动战斗引擎（纯逻辑，不依赖任何节点，可在无头模式下测试）。
##
## 回合流程：
##   1. 每"轮"开始时，把仍存活且锐气(EP) > 0 的单位按速度从高到低排成行动队列；
##   2. 每次 step() 让队首单位行动一次：按战术规则列表从上往下找第一条
##      "技能可用 + 锐气足够 + 条件满足 + 有合法目标" 的规则执行；
##   3. 被攻击时可能触发被动（掩护 / 反击），消耗守势(GP)；
##   4. 伤害考虑：增减益状态、兵种克制(bonus_vs)、首击加成、斩杀加成、会心、闪避（随机数可设种子）；
##   5. 一方全灭，或所有单位锐气耗尽 / 超过最大轮数时结束，按剩余 HP 比例判定胜负。
extends RefCounted

const BattleUnit := preload("res://scripts/battle_unit.gd")

const MAX_ROUNDS := 12
const BACK_ROW_MELEE_PENALTY := 0.75  # 后排单位使用近战技能伤害 ×0.75
const COVER_DAMAGE_RATE := 0.7        # 掩护时承受伤害 ×0.7
const RIPOSTE_POWER := 0.5            # 反击倍率
const CRIT_MULT := 1.5                # 会心伤害倍率
const BRACE_RATE := 0.6               # 「拒马」：受到骑兵攻击伤害 ×0.6
const DEFAULT_SEED := 20261109

var skills_db: Dictionary = {}
var passives_db: Dictionary = {}
var classes_db: Dictionary = {}
var squad_names: Array = ["我方", "敌方"]

var units: Array = []          # Array of BattleUnit
var round_no: int = 0
var queue: Array = []
var acted_this_round: bool = false  # 本轮是否有人真正行动（全员待机则结束战斗）
var finished: bool = false
var winner: int = -1           # 0 我方胜 / 1 敌方胜 / -1 平局或未结束
var battle_seed: int = DEFAULT_SEED  # 会心/闪避的随机种子，同种子结果可复现
var rng := RandomNumberGenerator.new()

# 供 UI 高亮使用：最近一次行动的行动者与目标
var last_actor = null
var last_targets: Array = []


# ---------------------------------------------------------------- 数据加载

static func load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("无法打开 %s" % path)
		return null
	var data = JSON.parse_string(f.get_as_text())
	if data == null:
		push_error("JSON 解析失败：%s" % path)
	return data


## 读取职业数据，并根据 battle_setup 生成两支小队的单位。
func load_data(classes_path: String, setup_path: String) -> bool:
	var cdata = load_json(classes_path)
	var sdata = load_json(setup_path)
	if cdata == null or sdata == null:
		return false
	skills_db = cdata.get("skills", {})
	passives_db = cdata.get("passives", {})
	classes_db = cdata.get("classes", {})
	units.clear()
	for squad in sdata.get("squads", []):
		var team_id := int(squad.get("team", 0))
		squad_names[team_id] = str(squad.get("name", squad_names[team_id]))
		for ud in squad.get("units", []):
			var cid := str(ud.get("class", ""))
			if not classes_db.has(cid):
				push_error("未知职业：%s" % cid)
				continue
			units.append(BattleUnit.from_data(cid, classes_db[cid], ud, team_id))
	return _validate()


## 检查阵型与战术数据是否合法，返回 false 时会 push_error。
func _validate() -> bool:
	var ok := true
	for t in [0, 1]:
		var used := {}
		var count := 0
		for u in units:
			if u.team != t:
				continue
			count += 1
			if u.row < 0 or u.row > 1 or u.col < 0 or u.col > 2:
				push_error("%s 的位置越界 (row=%d col=%d)" % [u.display_name, u.row, u.col])
				ok = false
			if used.has(u.slot_index()):
				push_error("%s 与 %s 位置重叠" % [u.display_name, used[u.slot_index()]])
				ok = false
			used[u.slot_index()] = u.display_name
			for rule in u.tactics:
				var sid := str(rule.get("skill", ""))
				if not u.skills.has(sid):
					push_error("%s(%s) 不会技能 %s" % [u.display_name, u.job_name, sid])
					ok = false
		if count > 6:
			push_error("小队 %d 超过 6 人" % t)
			ok = false
	return ok


## 直接使用已有的数据库与单位（大地图模式：单位对象由 MapModel 持有，HP 会延续）。
func setup_with_units(skills: Dictionary, passives: Dictionary, classes: Dictionary, battle_units: Array, names: Array) -> bool:
	skills_db = skills
	passives_db = passives
	classes_db = classes
	units = battle_units.duplicate()
	squad_names = names.duplicate()
	return _validate()


## 战斗开始前重置状态。full_heal=false 时保留当前 HP（大地图连续作战）。
func reset_battle(full_heal: bool = true) -> void:
	round_no = 0
	queue.clear()
	acted_this_round = false
	finished = false
	winner = -1
	last_actor = null
	last_targets = []
	rng.seed = battle_seed
	for u in units:
		if full_heal:
			u.hp = u.max_hp
		u.statuses = []
		u.has_acted = false
		u.battle_actions = 0
		u.battle_kills = 0
		for eff in u.start_effects:  # 装备带来的开战状态
			u.add_status(eff)
		u.ep = u.max_ep
		u.gp = u.max_gp


# ---------------------------------------------------------------- 查询工具

func living(team_id: int) -> Array:
	return units.filter(func(u): return u.team == team_id and u.is_alive())


func unit_at(team_id: int, row: int, col: int):
	for u in units:
		if u.team == team_id and u.row == row and u.col == col:
			return u
	return null


func _allies(u) -> Array:
	return living(u.team)


func _enemies(u) -> Array:
	return living(1 - u.team)


## 近战只能攻击前排；前排全部倒下后才能攻击后排。
func _melee_reachable(pool: Array) -> Array:
	var front := pool.filter(func(e): return e.row == BattleUnit.ROW_FRONT)
	return front if not front.is_empty() else pool


# ---------------------------------------------------------------- 主循环

## 推进一步（一个单位行动一次），返回本步产生的日志行。
func step() -> PackedStringArray:
	var out := PackedStringArray()
	if finished:
		return out
	last_actor = null
	last_targets = []
	while true:
		if queue.is_empty():
			if not _start_round(out):
				return out
		var u = queue.pop_front()
		if u.is_alive() and u.ep > 0:
			_act(u, out)
			_check_end(out)
			return out
	return out


## 一直推进直到结束（无头测试用）。
func run_to_end(max_steps: int = 500) -> PackedStringArray:
	var all := PackedStringArray()
	var n := 0
	while not finished and n < max_steps:
		all.append_array(step())
		n += 1
	return all


func _start_round(out: PackedStringArray) -> bool:
	if round_no > 0 and not acted_this_round:
		out.append("—— 全员无可执行的行动，战斗结束 ——")
		_finish_by_hp(out)
		return false
	round_no += 1
	acted_this_round = false
	if round_no > MAX_ROUNDS:
		out.append("—— 已达最大轮数，战斗结束 ——")
		_finish_by_hp(out)
		return false
	# 状态持续时间 -1（第 1 轮不扣）
	if round_no > 1:
		for u in units:
			if u.is_alive():
				for n in u.tick_statuses():
					out.append("   · %s 的「%s」效果结束" % [u.display_name, n])
	queue = units.filter(func(u): return u.is_alive() and u.ep > 0)
	if queue.is_empty():
		out.append("—— 双方锐气耗尽，战斗结束 ——")
		_finish_by_hp(out)
		return false
	queue.sort_custom(_initiative_less)
	var names := PackedStringArray()
	for u in queue:
		names.append("%s(%d)" % [u.display_name, u.eff_spd()])
	out.append("===== 第 %d 轮 行动顺序：%s =====" % [round_no, " > ".join(names)])
	return true


## 先攻排序：速度高者先；同速时我方先；再按格子顺序。
func _initiative_less(a, b) -> bool:
	if a.eff_spd() != b.eff_spd():
		return a.eff_spd() > b.eff_spd()
	if a.team != b.team:
		return a.team < b.team
	return a.slot_index() < b.slot_index()


func _check_end(out: PackedStringArray) -> void:
	var a := living(0).size()
	var b := living(1).size()
	if a > 0 and b > 0:
		return
	finished = true
	queue.clear()
	if a == 0 and b == 0:
		winner = -1
		out.append("【结果】同归于尽，平局。")
	elif b == 0:
		winner = 0
		out.append("【结果】%s 全灭，%s 胜利！" % [squad_names[1], squad_names[0]])
	else:
		winner = 1
		out.append("【结果】%s 全灭，%s 胜利！" % [squad_names[0], squad_names[1]])


func _finish_by_hp(out: PackedStringArray) -> void:
	finished = true
	var r := [0.0, 0.0]
	for t in [0, 1]:
		var cur := 0
		var mx := 0
		for u in units:
			if u.team == t:
				cur += u.hp
				mx += u.max_hp
		r[t] = float(cur) / float(max(1, mx))
	out.append("剩余 HP：%s %.0f%%  /  %s %.0f%%" % [squad_names[0], r[0] * 100.0, squad_names[1], r[1] * 100.0])
	if is_equal_approx(r[0], r[1]):
		winner = -1
		out.append("【结果】平局。")
	else:
		winner = 0 if r[0] > r[1] else 1
		out.append("【结果】按剩余 HP 判定，%s 获胜！" % squad_names[winner])


# ---------------------------------------------------------------- 战术判定

## 返回 {skill_id, skill, targets, rule}；找不到可执行行动时返回空字典。
func choose_action(u) -> Dictionary:
	for rule in u.tactics:
		var sid := str(rule.get("skill", ""))
		if not u.skills.has(sid) or not skills_db.has(sid):
			continue
		var skill: Dictionary = skills_db[sid]
		if u.ep < int(skill.get("cost", 1)):
			continue
		var targets := _resolve_targets(u, skill, rule)
		if not targets.is_empty():
			return {"skill_id": sid, "skill": skill, "targets": targets, "rule": rule}
	# 兜底：没有任何规则满足时，使用第一个攻击技能；没有攻击技能（治疗/辅助型）则待机。
	for sid0 in u.skills:
		var s0: Dictionary = skills_db.get(sid0, {})
		if s0.get("type", "") == "attack" and u.ep >= int(s0.get("cost", 1)):
			var t0 := _resolve_targets(u, s0, {"if": "always"})
			if not t0.is_empty():
				return {"skill_id": sid0, "skill": s0, "targets": t0, "rule": {"if": "(兜底)"}}
			break
	return {}


## 技能是否以己方为目标
static func is_friendly(skill: Dictionary) -> bool:
	return str(skill.get("type", "attack")) in ["heal", "support"]


## 该技能能"够到"的目标（未经过条件筛选）
func reachable_targets(u, skill: Dictionary) -> Array:
	var area := str(skill.get("area", "single"))
	if area == "self":
		return [u]
	if is_friendly(skill):
		var allies := _allies(u)
		if skill.get("exclude_self", false):
			allies.erase(u)
		return allies
	var enemies := _enemies(u)
	if skill.get("type", "attack") == "attack" and skill.get("reach", "melee") == "melee" and not skill.get("ignore_front", false):
		return _melee_reachable(enemies)
	return enemies


func _resolve_targets(u, skill: Dictionary, rule: Dictionary) -> Array:
	var friendly := is_friendly(skill)
	var cond := str(rule.get("if", "always"))
	var val = rule.get("value", 0)
	var reach := reachable_targets(u, skill)
	var pool: Array = reach

	match cond:
		"always":
			pass
		"self_hp_below":
			if u.hp_ratio() >= float(val):
				return []
		"self_hp_above":
			if u.hp_ratio() <= float(val):
				return []
		"self_first_action":  # 本场战斗第一次行动
			if u.has_acted:
				return []
		"self_not_taunting":
			if u.has_status("taunt"):
				return []
		"ally_hp_below":
			var hurt := _allies(u).filter(func(a): return a.hp_ratio() < float(val))
			if hurt.is_empty():
				return []
			if friendly:
				pool = pool.filter(func(a): return hurt.has(a))
		"allies_hurt_at_least":  # 至少 N 名队友 HP < 75%
			var n := _allies(u).filter(func(a): return a.hp_ratio() < 0.75).size()
			if n < int(val):
				return []
		"ally_no_buff":  # 有队友身上没有增益
			var plain := _allies(u).filter(func(a): return not a.has_buff())
			if plain.is_empty():
				return []
			if friendly:
				pool = pool.filter(func(a): return plain.has(a))
		"ally_ep_at_most":  # 有其他队友锐气 ≤ N（且还活着）
			var low := _allies(u).filter(func(a): return a != u and a.ep <= int(val))
			if low.is_empty():
				return []
			if friendly:
				pool = pool.filter(func(a): return low.has(a))
		"enemy_hp_below":
			if friendly:
				return []
			pool = pool.filter(func(e): return e.hp_ratio() < float(val))
		"enemy_class":
			if friendly:
				return []
			pool = pool.filter(func(e): return e.class_id == str(val))
		"target_has_tag":
			if friendly:
				return []
			pool = pool.filter(func(e): return e.has_tag(str(val)))
		"target_no_debuff":
			if friendly:
				return []
			pool = pool.filter(func(e): return not e.has_debuff())
		"enemy_row":
			if friendly:
				return []
			var want := BattleUnit.ROW_FRONT if str(val) == "front" else BattleUnit.ROW_BACK
			pool = pool.filter(func(e): return e.row == want)
		"row_count_at_least":  # 用于横排攻击：目标所在排至少 N 人
			if friendly:
				return []
			var enemies := _enemies(u)
			pool = pool.filter(func(e): return enemies.filter(func(x): return x.row == e.row).size() >= int(val))
		"enemy_count_at_least":
			if _enemies(u).size() < int(val):
				return []
		_:
			push_warning("未知战术条件：%s" % cond)
			return []

	if pool.is_empty():
		return []
	var default_pick := "lowest_hp_ratio" if friendly else "lowest_hp"
	var main_target = _pick(pool, str(rule.get("pick", default_pick)))

	var area := str(skill.get("area", "single"))
	# 挑衅：单体/纵列攻击会被够得到的挑衅者吸引（技能带 ignore_taunt 则无视）
	if not friendly and skill.get("type", "attack") == "attack" and area in ["single", "column"] and not skill.get("ignore_taunt", false):
		var taunters := reach.filter(func(e): return e.has_status("taunt"))
		if not taunters.is_empty() and not taunters.has(main_target):
			main_target = _pick(taunters, "first")

	var side := _allies(u) if friendly else _enemies(u)
	match area:
		"self":
			return [u]
		"row":
			return side.filter(func(x): return x.row == main_target.row)
		"column":  # 目标及其同一列的另一排
			var col_units := side.filter(func(x): return x.col == main_target.col and x != main_target)
			return [main_target] + col_units
		"all":
			if friendly and skill.get("exclude_self", false):
				side.erase(u)
			return side
		_:
			return [main_target]


func _pick(pool: Array, how: String):
	var best = pool[0]
	for c in pool:
		match how:
			"lowest_hp":
				if c.hp < best.hp: best = c
			"highest_hp":
				if c.hp > best.hp: best = c
			"lowest_hp_ratio":
				if c.hp_ratio() < best.hp_ratio(): best = c
			"lowest_def":
				if c.eff_def() < best.eff_def(): best = c
			"highest_atk":
				if c.eff_atk() > best.eff_atk(): best = c
			"highest_spd":
				if c.eff_spd() > best.eff_spd(): best = c
			"back_row_first":
				if c.row > best.row or (c.row == best.row and c.hp < best.hp): best = c
			_:  # "first"：按格子顺序
				if c.slot_index() < best.slot_index(): best = c
	return best


# ---------------------------------------------------------------- 执行行动

func _act(u, out: PackedStringArray) -> void:
	var choice := choose_action(u)
	if choice.is_empty():
		# 待机：不消耗锐气，留到下一轮（全员待机一整轮则战斗结束，防止死循环）
		out.append("%s 没有满足条件的战术，待机。" % u.display_name)
		last_actor = u
		return
	acted_this_round = true
	var skill: Dictionary = choice["skill"]
	u.ep -= int(skill.get("cost", 1))
	last_actor = u
	last_targets = (choice["targets"] as Array).duplicate()
	var rule: Dictionary = choice["rule"]
	var cond_txt := describe_rule(rule) if rule.get("if", "") != "(兜底)" else "无规则满足→兜底"
	out.append("▶ %s(%s·%s) 使用「%s」 [锐气 %d/%d] ‹%s›" % [
		u.display_name, u.job_name, u.row_name(), skill.get("name", "?"), u.ep, u.max_ep, cond_txt])
	var first_action: bool = not u.has_acted
	u.has_acted = true
	u.battle_actions += 1

	match str(skill.get("type", "attack")):
		"heal":
			var amount := int(round(u.eff_atk() * float(skill.get("power", 1.0)) + float(skill.get("flat", 0))))
			for t in choice["targets"]:
				if not t.is_alive():
					continue
				var before: int = t.hp
				t.hp = min(t.max_hp, t.hp + amount)
				if t.hp > before:
					out.append("   ✚ %s 回复 %d HP (%d/%d)" % [t.display_name, t.hp - before, t.hp, t.max_hp])
				_apply_effects(t, skill, out)
		"support", "debuff":
			for t in choice["targets"]:
				if t.is_alive():
					_apply_effects(t, skill, out)
		_:
			for t in choice["targets"]:
				var landed := false
				for i in int(skill.get("hits", 1)):
					if not t.is_alive() or not u.is_alive():
						break
					if _do_hit(u, t, skill, out, first_action):
						landed = true
				if landed and t.is_alive():
					_apply_effects(t, skill, out)
	for eff in skill.get("self_effects", []):
		u.add_status(eff)
		out.append("   ★ %s 获得「%s」" % [u.display_name, eff.get("name", "")])


## 施加技能附带的状态与锐气增加
func _apply_effects(t, skill: Dictionary, out: PackedStringArray) -> void:
	for eff in skill.get("effects", []):
		t.add_status(eff)
		var amt := float(eff.get("amount", 0.0))
		var sign_txt := ""
		if eff.has("stat"):
			sign_txt = " %s%+d%%" % [{"atk": "攻击", "def": "防御", "spd": "速度"}.get(eff["stat"], eff["stat"]), int(round(amt * 100))]
		out.append("   %s %s 获得「%s」%s（%d轮）" % ["▼" if amt < 0 else "▲", t.display_name, eff.get("name", ""), sign_txt, int(eff.get("turns", 1))])
	var gain := int(skill.get("ep_gain", 0))
	if gain > 0:
		t.ep = mini(t.max_ep + gain, t.ep + gain)
		out.append("   ▲ %s 锐气 +%d (%d)" % [t.display_name, gain, t.ep])


## 伤害的确定部分（不含会心/闪避/掩护），便于测试。
func base_damage(attacker, victim, skill: Dictionary, first_action: bool = false) -> float:
	var power := float(skill.get("power", 1.0))
	# 首击加成（骑兵冲锋）
	if first_action and skill.has("first_action_bonus"):
		power *= float(skill["first_action_bonus"])
	# 兵种克制
	var bonus: Dictionary = skill.get("bonus_vs", {})
	for tag in bonus:
		if victim.has_tag(tag):
			power *= float(bonus[tag])
	# 斩杀：目标 HP 低于 50%
	if skill.has("execute_bonus") and victim.hp_ratio() < 0.5:
		power *= float(skill["execute_bonus"])
	var raw: float
	if skill.get("dmg", "physical") == "physical":
		raw = attacker.eff_atk() * power - victim.eff_def()
	else:
		raw = attacker.eff_atk() * power - victim.eff_def() * 0.5
	# 后排使用近战有惩罚（能越过前排的技能除外）
	if skill.get("reach", "melee") == "melee" and attacker.row == BattleUnit.ROW_BACK and not skill.get("ignore_front", false):
		raw *= BACK_ROW_MELEE_PENALTY
	# 被动「拒马」：受到骑兵攻击时减伤
	if victim.passives.has("brace") and attacker.has_tag("cavalry"):
		raw *= BRACE_RATE
	return raw


## 结算一次命中。返回是否命中（被闪避则 false）
func _do_hit(attacker, target, skill: Dictionary, out: PackedStringArray, first_action: bool = false) -> bool:
	var physical: bool = skill.get("dmg", "physical") == "physical"
	var melee: bool = skill.get("reach", "melee") == "melee"
	var victim = target
	var rate := 1.0

	# 被动「铁壁掩护」：后排队友被物理单体攻击时，前排的护卫代为承受
	if physical and skill.get("area", "single") == "single" and target.row == BattleUnit.ROW_BACK:
		var guard = _find_cover(target)
		if guard != null:
			guard.gp -= 1
			victim = guard
			rate = COVER_DAMAGE_RATE
			out.append("   ◆ %s 发动「%s」，替 %s 挡下攻击 [守势 %d/%d]" % [
				guard.display_name, passives_db.get("cover", {}).get("name", "掩护"), target.display_name, guard.gp, guard.max_gp])

	# 闪避：只对物理且非必中的攻击
	if physical and not skill.get("sure_hit", false) and victim.eva > 0:
		if rng.randi_range(1, 100) <= victim.eva:
			out.append("   ≈ %s 闪避了攻击！" % victim.display_name)
			if not last_targets.has(victim):
				last_targets.append(victim)
			return false

	var raw := base_damage(attacker, victim, skill, first_action) * rate
	# 会心（「不屈」被动免疫会心）
	var crit_chance: int = attacker.crit + int(skill.get("crit_bonus", 0))
	var crit := false
	if crit_chance > 0 and not victim.passives.has("steadfast") and rng.randi_range(1, 100) <= crit_chance:
		crit = true
		raw *= CRIT_MULT
	var dmg := maxi(1, int(round(raw)))
	victim.hp = maxi(0, victim.hp - dmg)
	out.append("   ● %s 受到 %d 点伤害%s (%d/%d)" % [victim.display_name, dmg, "【会心！】" if crit else "", victim.hp, victim.max_hp])
	if not last_targets.has(victim):
		last_targets.append(victim)
	if not victim.is_alive():
		attacker.battle_kills += 1
		out.append("   × %s 倒下了！" % victim.display_name)
		return true

	# 被动「回刃反击」：受到近战攻击后反击
	if melee and victim.passives.has("riposte") and victim.gp > 0 and attacker.is_alive():
		victim.gp -= 1
		var c := maxi(1, int(round(victim.eff_atk() * RIPOSTE_POWER - attacker.eff_def() * 0.5)))
		attacker.hp = maxi(0, attacker.hp - c)
		out.append("   ◇ %s 发动「%s」，对 %s 造成 %d 点伤害 (%d/%d)" % [
			victim.display_name, passives_db.get("riposte", {}).get("name", "反击"), attacker.display_name, c, attacker.hp, attacker.max_hp])
		if not attacker.is_alive():
			victim.battle_kills += 1
			out.append("   × %s 倒下了！" % attacker.display_name)
	return true


func _find_cover(target):
	var best = null
	for a in _allies(target):
		if a == target or a.row != BattleUnit.ROW_FRONT:
			continue
		if not a.passives.has("cover") or a.gp <= 0:
			continue
		# 优先同一列的护卫
		if best == null or (a.col == target.col and best.col != target.col):
			best = a
	return best


# ---------------------------------------------------------------- 文本描述

const TAG_NAMES := {"infantry": "步兵", "cavalry": "骑兵", "armored": "重装", "flying": "飞行"}


static func describe_rule(rule: Dictionary) -> String:
	var v = rule.get("value", 0)
	var c := ""
	match str(rule.get("if", "always")):
		"always": c = "总是"
		"self_hp_below": c = "自身HP<%d%%" % int(round(float(v) * 100))
		"self_hp_above": c = "自身HP>%d%%" % int(round(float(v) * 100))
		"self_first_action": c = "本场首次行动"
		"self_not_taunting": c = "自身未在挑衅"
		"ally_hp_below": c = "有队友HP<%d%%" % int(round(float(v) * 100))
		"allies_hurt_at_least": c = "≥%d名队友HP<75%%" % int(v)
		"ally_no_buff": c = "有队友无增益"
		"ally_ep_at_most": c = "有队友锐气≤%d" % int(v)
		"enemy_hp_below": c = "敌人HP<%d%%" % int(round(float(v) * 100))
		"enemy_class": c = "目标职业[%s]" % str(v)
		"target_has_tag": c = "目标是%s" % TAG_NAMES.get(str(v), str(v))
		"target_no_debuff": c = "目标无减益"
		"enemy_row": c = "敌方%s" % ("前排" if str(v) == "front" else "后排")
		"row_count_at_least": c = "敌方同排≥%d人" % int(v)
		"enemy_count_at_least": c = "敌人≥%d名" % int(v)
		_: c = str(rule.get("if"))
	return c


func describe_tactics(u) -> String:
	var lines := PackedStringArray()
	var tag_txt := PackedStringArray()
	for t in u.tags:
		tag_txt.append(TAG_NAMES.get(t, t))
	lines.append("%s（%s·%s）HP %d ATK %d DEF %d SPD %d 会心%d%% 闪避%d%% 锐气 %d 守势 %d" % [
		u.display_name, u.job_name, "/".join(tag_txt), u.max_hp, u.atk, u.defense, u.spd, u.crit, u.eva, u.max_ep, u.max_gp])
	if not u.statuses.is_empty():
		lines.append("状态：%s" % u.status_text())
	var i := 1
	for rule in u.tactics:
		var sname = skills_db.get(str(rule.get("skill", "")), {}).get("name", rule.get("skill", "?"))
		lines.append("%d. %s → %s%s" % [i, describe_rule(rule), sname,
			("（目标:%s）" % rule["pick"]) if rule.has("pick") else ""])
		i += 1
	for p in u.passives:
		lines.append("被动：%s" % passives_db.get(p, {}).get("desc", p))
	return "\n".join(lines)
