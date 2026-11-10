## 战斗中的单个单位（纯数据，无节点），由 BattleEngine 管理。
extends RefCounted

const ROW_FRONT := 0
const ROW_BACK := 1

var uid: String = ""          # 唯一 ID，例如 "0_凯岚"
var display_name: String = ""
var class_id: String = ""
var job_name: String = ""     # 职业中文名
var team: int = 0             # 0 = 玩家，1 = 敌方
var row: int = ROW_FRONT      # 0 前排 / 1 后排
var col: int = 0              # 0..2
var color: Color = Color.WHITE

var max_hp: int = 0
var hp: int = 1
var atk: int = 0
var defense: int = 0
var spd: int = 0
var max_ep: int = 0           # 锐气：主动技能消耗
var ep: int = 0
var max_gp: int = 0           # 守势：被动技能（掩护/反击）消耗
var gp: int = 0

var crit: int = 5             # 会心率（%），会心伤害 ×1.5
var eva: int = 0              # 闪避率（%），只对可闪避的物理攻击生效
var tags: Array = []          # 兵种标签：infantry / cavalry / armored / flying
var statuses: Array = []      # 状态效果：{id, name, stat, amount, turns}，amount 为比例（+0.2 = +20%）
var has_acted: bool = false   # 本场战斗是否已行动过（骑兵首击加成用）

var skills: Array = []        # 主动技能 id 列表
var passives: Array = []      # 被动技能 id 列表
var tactics: Array = []       # 战术规则列表（Dictionary），从上到下优先


# ---- 成长与装备（大地图战役用）----
var level: int = 1
var xp: int = 0              # 当前等级内的经验值（满 100 升级）
var equipment: Dictionary = {}   # slot -> item_id（weapon / armor / accessory）
var start_effects: Array = []    # 装备带来的开战状态
var battle_actions: int = 0      # 本场行动次数（经验计算）
var battle_kills: int = 0        # 本场击倒数


static func from_data(cls_id: String, cls: Dictionary, data: Dictionary, team_id: int):
	var u = load("res://scripts/battle_unit.gd").new()
	u.class_id = cls_id
	u.display_name = str(data.get("name", cls.get("name", cls_id)))
	u.team = team_id
	u.uid = str(data.get("uid", "%d_%s" % [team_id, u.display_name]))
	u.row = int(data.get("row", ROW_FRONT))
	u.col = int(data.get("col", 0))
	u.level = maxi(1, int(data.get("level", 1)))
	u.xp = int(data.get("xp", 0))
	u.equipment = (data.get("equipment", {}) as Dictionary).duplicate()
	u.apply_class(cls, {})
	u.hp = u.max_hp
	var tac = data.get("tactics", null)
	if tac == null:
		tac = cls.get("default_tactics", [])
	u.tactics = (tac as Array).duplicate(true)
	return u


## 根据职业基础值 + 等级成长 + 装备重新计算属性与可用技能。
## items_db 为空时忽略装备加成。HP 按比例保持（满血仍满血）。
func apply_class(cls: Dictionary, items_db: Dictionary) -> void:
	var old_max := max_hp
	var old_hp := hp
	job_name = str(cls.get("name", class_id))
	color = Color.from_string(str(cls.get("color", "#ffffff")), Color.WHITE)
	var g: Dictionary = cls.get("growth", {})
	var lv := level - 1
	var bonus := {"hp": 0, "atk": 0, "def": 0, "spd": 0, "crit": 0, "eva": 0, "ep": 0, "gp": 0}
	start_effects = []
	for slot in equipment:
		var it: Dictionary = items_db.get(str(equipment[slot]), {})
		for k in it.get("stats", {}):
			bonus[k] = int(bonus.get(k, 0)) + int(it["stats"][k])
		start_effects.append_array(it.get("start_effects", []))
	max_hp = int(cls.get("hp", 100)) + int(g.get("hp", 0)) * lv + bonus["hp"]
	atk = int(cls.get("atk", 10)) + int(g.get("atk", 0)) * lv + bonus["atk"]
	defense = int(cls.get("def", 5)) + int(g.get("def", 0)) * lv + bonus["def"]
	spd = maxi(1, int(cls.get("spd", 10)) + int(g.get("spd", 0)) * lv + bonus["spd"])
	crit = int(cls.get("crit", 5)) + bonus["crit"]
	eva = int(cls.get("eva", 0)) + bonus["eva"]
	max_ep = int(cls.get("ep", 1)) + bonus["ep"]
	max_gp = int(cls.get("gp", 0)) + bonus["gp"]
	ep = max_ep
	gp = max_gp
	tags = (cls.get("tags", ["infantry"]) as Array).duplicate()
	passives = (cls.get("passives", []) as Array).duplicate()
	# 等级解锁的技能
	var unlocks: Dictionary = cls.get("skill_unlocks", {})
	skills = []
	for sid in cls.get("skills", []):
		if level >= int(unlocks.get(sid, 1)):
			skills.append(sid)
	if old_max <= 0 or old_hp >= old_max:
		hp = max_hp
	else:
		hp = clampi(int(round(float(old_hp) / old_max * max_hp)), 0, max_hp)


func to_dict() -> Dictionary:
	return {"uid": uid, "name": display_name, "class": class_id, "level": level, "xp": xp,
		"row": row, "col": col, "equipment": equipment.duplicate(), "tactics": tactics.duplicate(true)}


func is_alive() -> bool:
	return hp > 0


func hp_ratio() -> float:
	return float(hp) / float(max(1, max_hp))


func slot_index() -> int:
	return row * 3 + col


func row_name() -> String:
	return "前排" if row == ROW_FRONT else "后排"


# ---------------------------------------------------------------- 状态效果

## 某属性的总倍率（所有同属性状态叠加，最低 0.3）
func stat_mult(stat: String) -> float:
	var m := 1.0
	for st in statuses:
		if st.get("stat", "") == stat:
			m += float(st.get("amount", 0.0))
	return maxf(0.3, m)


func eff_atk() -> int:
	return int(round(atk * stat_mult("atk")))


func eff_def() -> int:
	return int(round(defense * stat_mult("def")))


func eff_spd() -> int:
	return int(round(spd * stat_mult("spd")))


func has_status(id: String) -> bool:
	for st in statuses:
		if st.get("id", "") == id:
			return true
	return false


func has_buff() -> bool:
	for st in statuses:
		if float(st.get("amount", 0.0)) > 0.0 or st.get("id", "") == "taunt":
			return true
	return false


func has_debuff() -> bool:
	for st in statuses:
		if float(st.get("amount", 0.0)) < 0.0:
			return true
	return false


func has_tag(tag: String) -> bool:
	return tags.has(tag)


## 施加状态：同 id 的状态只刷新持续时间，不叠加
func add_status(effect: Dictionary) -> void:
	for st in statuses:
		if st.get("id", "") == effect.get("id", ""):
			st["turns"] = maxi(int(st["turns"]), int(effect.get("turns", 1)))
			return
	statuses.append(effect.duplicate())


## 每轮开始时调用：持续时间 -1，返回本次结束的状态名
func tick_statuses() -> PackedStringArray:
	var ended := PackedStringArray()
	for st in statuses:
		st["turns"] = int(st["turns"]) - 1
		if st["turns"] <= 0:
			ended.append(str(st.get("name", st.get("id", ""))))
	statuses = statuses.filter(func(st): return int(st["turns"]) > 0)
	return ended


## 简短的状态文字，例如 "攻↑ 防↓ 挑衅"
func status_text() -> String:
	var names := {"atk": "攻", "def": "防", "spd": "速"}
	var parts := PackedStringArray()
	for st in statuses:
		if st.get("id", "") == "taunt":
			parts.append("挑衅")
		elif names.has(st.get("stat", "")):
			parts.append(names[st["stat"]] + ("↑" if float(st["amount"]) > 0 else "↓"))
	return " ".join(parts)
