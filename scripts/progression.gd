## 成长系统（纯函数）：经验、升级、技能解锁、转职、装备。
extends RefCounted

const XP_PER_LEVEL := 100
const MAX_LEVEL := 15
const XP_ACTION := 5     # 每次行动
const XP_KILL := 15      # 每击倒一名敌人
const XP_WIN := 20       # 胜利奖励
const XP_LOSS := 5      # 失利也有少量经验
const SLOTS := ["weapon", "armor", "accessory"]
const SLOT_NAMES := {"weapon": "武器", "armor": "防具", "accessory": "饰品"}

## 技能 id -> 显示名（由加载数据的一方填充，仅用于提示文字）
static var skill_names: Dictionary = {}


static func battle_xp(u, won: bool) -> int:
	return u.battle_actions * XP_ACTION + u.battle_kills * XP_KILL + (XP_WIN if won else XP_LOSS)


## 获得经验，返回升级 / 习得技能 / 可转职 的提示文字
static func gain_xp(u, amount: int, classes: Dictionary, items: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	if u.level >= MAX_LEVEL:
		return lines
	u.xp += amount
	while u.xp >= XP_PER_LEVEL and u.level < MAX_LEVEL:
		u.xp -= XP_PER_LEVEL
		var before := {"hp": u.max_hp, "atk": u.atk, "def": u.defense, "spd": u.spd}
		var old_skills: Array = u.skills.duplicate()
		u.level += 1
		u.apply_class(classes[u.class_id], items)
		u.hp = u.max_hp
		lines.append("%s 升到 Lv%d！HP+%d 攻击+%d 防御+%d 速度+%d" % [u.display_name, u.level,
			u.max_hp - before["hp"], u.atk - before["atk"], u.defense - before["def"], u.spd - before["spd"]])
		for sid in u.skills:
			if not old_skills.has(sid):
				var nm: String = str(skill_names.get(sid, sid))
				lines.append("%s 习得新技能「%s」（可在战术编辑中使用）" % [u.display_name, nm])
		if can_promote(u, classes) and u.level == int(classes[u.class_id]["promotion"]["level"]):
			lines.append("%s 可以转职为「%s」了！" % [u.display_name, classes[promotion_target(u, classes)]["name"]])
	if u.level >= MAX_LEVEL:
		u.xp = 0
	return lines


## 战斗结束后给我方小队发经验。返回 {lines, xp: {uid: 数值}}
static func award_battle(units: Array, won: bool, classes: Dictionary, items: Dictionary) -> Dictionary:
	var lines := PackedStringArray()
	var gained := {}
	for u in units:
		var x := battle_xp(u, won)
		gained[u.uid] = x
		lines.append_array(gain_xp(u, x, classes, items))
	return {"lines": lines, "xp": gained}


static func promotion_target(u, classes: Dictionary) -> String:
	var p: Dictionary = classes.get(u.class_id, {}).get("promotion", {})
	return str(p.get("to", ""))


static func can_promote(u, classes: Dictionary) -> bool:
	var p: Dictionary = classes.get(u.class_id, {}).get("promotion", {})
	return not p.is_empty() and classes.has(str(p["to"])) and u.level >= int(p.get("level", 99))


## 转职：更换职业、重算属性，并把新职业专属技能的默认规则放到战术列表最前面。返回说明文字（失败为空）
static func promote(u, classes: Dictionary, items: Dictionary) -> String:
	if not can_promote(u, classes):
		return ""
	var old_name: String = u.job_name
	var old_skills: Array = u.skills.duplicate()
	var to := promotion_target(u, classes)
	u.class_id = to
	u.apply_class(classes[to], items)
	u.hp = u.max_hp
	var new_skills: Array = u.skills.filter(func(s): return not old_skills.has(s))
	var added: Array = []
	for rule in classes[to].get("default_tactics", []):
		if new_skills.has(rule.get("skill", "")):
			added.append(rule.duplicate())
	u.tactics = added + u.tactics
	return "%s 由「%s」转职为「%s」！新技能：%s" % [u.display_name, old_name, u.job_name, "、".join(PackedStringArray(new_skills.map(func(sid): return str(skill_names.get(sid, sid)))))]


## 装备：从库存取出，原有装备放回库存
static func equip(u, item_id: String, inventory: Array, classes: Dictionary, items: Dictionary) -> bool:
	if not inventory.has(item_id) or not items.has(item_id):
		return false
	var slot := str(items[item_id]["slot"])
	if u.equipment.has(slot):
		inventory.append(u.equipment[slot])
	inventory.erase(item_id)
	u.equipment[slot] = item_id
	u.apply_class(classes[u.class_id], items)
	return true


static func unequip(u, slot: String, inventory: Array, classes: Dictionary, items: Dictionary) -> bool:
	if not u.equipment.has(slot):
		return false
	inventory.append(u.equipment[slot])
	u.equipment.erase(slot)
	u.apply_class(classes[u.class_id], items)
	return true
