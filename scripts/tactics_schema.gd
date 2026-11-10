## 战术规则的"元数据"与纯函数操作（无 UI），供规则编辑器与测试使用。
extends RefCounted

const MAX_RULES := 8

## 条件定义：id、显示名、参数类型（none/percent/int/class/row）、默认值
const CONDITIONS := [
	{"id": "always", "label": "总是", "value": "none", "default": 0},
	{"id": "self_hp_below", "label": "自身HP低于", "value": "percent", "default": 0.5},
	{"id": "self_hp_above", "label": "自身HP高于", "value": "percent", "default": 0.5},
	{"id": "ally_hp_below", "label": "有队友HP低于", "value": "percent", "default": 0.5},
	{"id": "allies_hurt_at_least", "label": "受伤(<75%)队友至少", "value": "int", "default": 2},
	{"id": "self_first_action", "label": "本场首次行动", "value": "none", "default": 0},
	{"id": "self_not_taunting", "label": "自身未在挑衅", "value": "none", "default": 0},
	{"id": "ally_no_buff", "label": "有队友无增益", "value": "none", "default": 0},
	{"id": "ally_ep_at_most", "label": "有队友锐气至多", "value": "int0", "default": 0},
	{"id": "enemy_hp_below", "label": "目标HP低于", "value": "percent", "default": 0.5},
	{"id": "target_has_tag", "label": "目标兵种是", "value": "tag", "default": "cavalry"},
	{"id": "target_no_debuff", "label": "目标无减益", "value": "none", "default": 0},
	{"id": "enemy_class", "label": "目标职业是", "value": "class", "default": "mage"},
	{"id": "enemy_row", "label": "目标位于", "value": "row", "default": "back"},
	{"id": "row_count_at_least", "label": "目标所在排人数至少", "value": "int", "default": 2},
	{"id": "enemy_count_at_least", "label": "敌人数量至少", "value": "int", "default": 3},
]

const PICKS := [
	{"id": "", "label": "（技能默认）"},
	{"id": "lowest_hp", "label": "HP最低"},
	{"id": "lowest_hp_ratio", "label": "HP比例最低"},
	{"id": "highest_hp", "label": "HP最高"},
	{"id": "lowest_def", "label": "防御最低"},
	{"id": "highest_atk", "label": "攻击最高"},
	{"id": "highest_spd", "label": "速度最高"},
	{"id": "back_row_first", "label": "优先后排"},
	{"id": "first", "label": "按格子顺序"},
]

const ROWS := [{"id": "front", "label": "前排"}, {"id": "back", "label": "后排"}]

const TAGS := [
	{"id": "cavalry", "label": "骑兵"},
	{"id": "armored", "label": "重装"},
	{"id": "flying", "label": "飞行"},
	{"id": "infantry", "label": "步兵"},
]


static func condition_index(id: String) -> int:
	for i in CONDITIONS.size():
		if CONDITIONS[i]["id"] == id:
			return i
	return 0


static func condition_def(id: String) -> Dictionary:
	return CONDITIONS[condition_index(id)]


static func pick_index(id: String) -> int:
	for i in PICKS.size():
		if PICKS[i]["id"] == id:
			return i
	return 0


static func make_rule(skill_id: String, cond_id: String = "always") -> Dictionary:
	var rule := {"if": cond_id, "skill": skill_id}
	var d := condition_def(cond_id)
	if d["value"] != "none":
		rule["value"] = d["default"]
	return rule


## 修改条件时重置参数为该条件的默认值
static func set_condition(rule: Dictionary, cond_id: String) -> void:
	rule["if"] = cond_id
	var d := condition_def(cond_id)
	if d["value"] == "none":
		rule.erase("value")
	else:
		rule["value"] = d["default"]


static func set_pick(rule: Dictionary, pick_id: String) -> void:
	if pick_id == "":
		rule.erase("pick")
	else:
		rule["pick"] = pick_id


static func add_rule(list: Array, rule: Dictionary) -> bool:
	if list.size() >= MAX_RULES:
		return false
	list.append(rule)
	return true


static func remove_rule(list: Array, index: int) -> bool:
	if index < 0 or index >= list.size():
		return false
	list.remove_at(index)
	return true


## dir = -1 上移，+1 下移
static func move_rule(list: Array, index: int, dir: int) -> bool:
	var j := index + dir
	if index < 0 or index >= list.size() or j < 0 or j >= list.size():
		return false
	var tmp = list[index]
	list[index] = list[j]
	list[j] = tmp
	return true


## 返回错误描述，合法则返回空字符串
static func validate_rule(rule: Dictionary, unit_skills: Array) -> String:
	if not unit_skills.has(str(rule.get("skill", ""))):
		return "该职业不会技能 %s" % rule.get("skill", "")
	var cid := str(rule.get("if", ""))
	var known := false
	for c in CONDITIONS:
		if c["id"] == cid:
			known = true
	if not known:
		return "未知条件 %s" % cid
	return ""
