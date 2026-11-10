## 战役进度：名册、小队编成、金币、库存、任务进度；可存档到 user://。
## 纯数据，不依赖 UI。
extends RefCounted

const BattleEngine := preload("res://scripts/battle_engine.gd")
const BattleUnit := preload("res://scripts/battle_unit.gd")
const MapModel := preload("res://scripts/map_model.gd")
const Progression := preload("res://scripts/progression.gd")

const CLASSES_PATH := "res://data/classes.json"
const ITEMS_PATH := "res://data/items.json"
const MISSIONS_PATH := "res://data/campaign/missions.json"
const RECRUITS_PATH := "res://data/campaign/recruits.json"
const SAVE_PATH := "user://campaign_save.json"
const SAVE_VERSION := 1
const MAX_SQUAD_SIZE := 5
const FRONT_CLASSES := ["swordsman", "guardian", "cavalry", "assassin", "warden", "spearman",
	"blademaster", "bulwark"]

var classes: Dictionary = {}
var skills: Dictionary = {}
var passives: Dictionary = {}
var items: Dictionary = {}
var missions: Array = []
var recruits: Array = []
var start_data: Dictionary = {}
var prologue: Array = []

var gold: int = 0
var inventory: Array = []         # 道具 id（可重复）
var roster: Array = []            # BattleUnit
var squads: Array = []            # {id, name, color, members: [uid]}
var cleared: Array = []           # 已完成的任务 id
var hired: Array = []             # 已招募的招募者 id
var current_mission: int = -1


func load_data() -> bool:
	var c = BattleEngine.load_json(CLASSES_PATH)
	var it = BattleEngine.load_json(ITEMS_PATH)
	var m = BattleEngine.load_json(MISSIONS_PATH)
	var r = BattleEngine.load_json(RECRUITS_PATH)
	if c == null or it == null or m == null or r == null:
		return false
	classes = c["classes"]
	skills = c["skills"]
	passives = c["passives"]
	for sid in skills:
		Progression.skill_names[sid] = skills[sid].get("name", sid)
	items = it["items"]
	missions = m["missions"]
	start_data = m["start"]
	prologue = m.get("prologue", [])
	recruits = r["recruits"]
	return true


# ---------------------------------------------------------------- 新游戏 / 名册

func new_game() -> bool:
	if not load_data():
		return false
	gold = int(start_data.get("gold", 0))
	inventory = (start_data.get("inventory", []) as Array).duplicate()
	roster = []
	squads = []
	cleared = []
	hired = []
	current_mission = -1
	for sd in start_data.get("squads", []):
		squads.append({"id": str(sd["id"]), "name": str(sd["name"]), "color": str(sd["color"]), "members": []})
	for ud in start_data.get("units", []):
		var u = make_unit(ud)
		roster.append(u)
		var sq := int(ud.get("squad", -1))
		if sq >= 0:
			assign(u.uid, sq)
	return true


func make_unit(ud: Dictionary):
	var cid := str(ud["class"])
	var data: Dictionary = ud.duplicate(true)
	data["uid"] = "u_" + str(ud["name"])
	var u = BattleUnit.from_data(cid, classes[cid], data, 0)
	u.apply_class(classes[cid], items)
	u.hp = u.max_hp
	return u


func unit_by_uid(uid: String):
	for u in roster:
		if u.uid == uid:
			return u
	return null


## 单位所在小队索引，-1 = 待命
func squad_of(uid: String) -> int:
	for i in squads.size():
		if squads[i]["members"].has(uid):
			return i
	return -1


func squad_units(i: int) -> Array:
	var out: Array = []
	for uid in squads[i]["members"]:
		var u = unit_by_uid(uid)
		if u != null:
			out.append(u)
	return out


func reserve_units() -> Array:
	return roster.filter(func(u): return squad_of(u.uid) == -1)


## 把单位分配到小队（-1 = 待命）。小队满员或没有空格时失败。
func assign(uid: String, squad_index: int) -> bool:
	var u = unit_by_uid(uid)
	if u == null or squad_index >= squads.size():
		return false
	var cur := squad_of(uid)
	if cur == squad_index:
		return true
	if squad_index >= 0:
		var members: Array = squads[squad_index]["members"]
		if members.size() >= MAX_SQUAD_SIZE:
			return false
		var slot := _free_slot(squad_index, FRONT_CLASSES.has(u.class_id))
		if slot.is_empty():
			return false
		if cur >= 0:
			squads[cur]["members"].erase(uid)
		members.append(uid)
		u.row = slot[0]
		u.col = slot[1]
	elif cur >= 0:
		squads[cur]["members"].erase(uid)
	return true


func _free_slot(squad_index: int, prefer_front: bool) -> Array:
	var used := {}
	for u in squad_units(squad_index):
		used[Vector2i(u.row, u.col)] = true
	var rows := [0, 1] if prefer_front else [1, 0]
	for r in rows:
		for c in [1, 0, 2]:
			if not used.has(Vector2i(r, c)):
				return [r, c]
	return []


func available_recruits() -> Array:
	return recruits.filter(func(r): return not hired.has(r["id"]) and cleared.size() >= int(r.get("after", 0)))


func recruit(rid: String) -> bool:
	for r in available_recruits():
		if r["id"] == rid:
			if gold < int(r["cost"]):
				return false
			gold -= int(r["cost"])
			hired.append(rid)
			var u = make_unit(r)
			roster.append(u)
			_auto_place(u)
			return true
	return false


## 有空位的小队自动编入，否则待命
func _auto_place(u) -> void:
	for i in squads.size():
		if assign(u.uid, i):
			return


func equip(uid: String, item_id: String) -> bool:
	var u = unit_by_uid(uid)
	return u != null and Progression.equip(u, item_id, inventory, classes, items)


func unequip(uid: String, slot: String) -> bool:
	var u = unit_by_uid(uid)
	return u != null and Progression.unequip(u, slot, inventory, classes, items)


func promote(uid: String) -> String:
	var u = unit_by_uid(uid)
	if u == null:
		return ""
	return Progression.promote(u, classes, items)


func item_name(id: String) -> String:
	return str(items.get(id, {}).get("name", id))


# ---------------------------------------------------------------- 任务

func is_unlocked(i: int) -> bool:
	return i >= 0 and i < missions.size() and (i == 0 or cleared.has(missions[i - 1]["id"]))


func next_mission_index() -> int:
	for i in missions.size():
		if not cleared.has(missions[i]["id"]):
			return i
	return -1


func is_complete() -> bool:
	return next_mission_index() == -1


func deployable_squads() -> Array:
	var out: Array = []
	for i in squads.size():
		if not squads[i]["members"].is_empty():
			out.append(i)
	return out


## 出击：生成任务地图（单位对象与名册共享）
func create_mission_model(i: int):
	if not is_unlocked(i) or deployable_squads().is_empty():
		return null
	for u in roster:
		u.apply_class(classes[u.class_id], items)
		u.hp = u.max_hp
		u.statuses = []
	var ps: Array = []
	for si in deployable_squads():
		var s: Dictionary = squads[si]
		ps.append({"id": s["id"], "name": s["name"], "color": s["color"], "units": squad_units(si)})
	var model := MapModel.new()
	if not model.load_campaign(str(missions[i]["map"]), CLASSES_PATH, ps, ITEMS_PATH):
		return null
	model.progression_enabled = true
	current_mission = i
	return model


## 任务结束结算。胜利：获得收入、道具、任务奖励与剧情加入者；失败：只保留经验。
func finish_mission(model) -> Dictionary:
	var i := current_mission
	var m: Dictionary = missions[i] if i >= 0 else {}
	var s: Dictionary = model.summary()
	var won: bool = s["won"]
	var res := {
		"mission": i, "title": str(m.get("title", "")), "won": won, "reason": s["reason"],
		"time": s["time"], "battles_won": s["battles_won"], "battles_lost": s["battles_lost"],
		"gold_bases": 0, "gold_battles": 0, "gold_reward": 0, "gold_total": 0,
		"items": [], "joined": [], "progress": s["progress"], "xp": [],
		"first_clear": false,
	}
	for u in roster:
		if s["xp"].has(u.uid):
			res["xp"].append({"name": u.display_name, "xp": s["xp"][u.uid], "level": u.level, "job": u.job_name})
	if won:
		var first: bool = not cleared.has(m.get("id", ""))
		res["first_clear"] = first
		res["gold_bases"] = s["gold_bases"]
		res["gold_battles"] = s["gold_battles"]
		var got_items: Array = s["items"].duplicate()
		var rw: Dictionary = m.get("reward", {})
		if first:
			res["gold_reward"] = int(rw.get("gold", 0))
			got_items.append_array(rw.get("items", []))
			for jd in m.get("join", []):
				var u = make_unit(jd)
				roster.append(u)
				_auto_place(u)
				res["joined"].append("%s（%s Lv%d）" % [u.display_name, u.job_name, u.level])
			cleared.append(m["id"])
		res["gold_total"] = res["gold_bases"] + res["gold_battles"] + res["gold_reward"]
		gold += res["gold_total"]
		inventory.append_array(got_items)
		for it in got_items:
			res["items"].append(item_name(it))
	for u in roster:
		u.apply_class(classes[u.class_id], items)
		u.hp = u.max_hp
		u.statuses = []
	current_mission = -1
	return res


# ---------------------------------------------------------------- 存档

func to_dict() -> Dictionary:
	var units: Array = []
	for u in roster:
		units.append(u.to_dict())
	return {"version": SAVE_VERSION, "gold": gold, "inventory": inventory.duplicate(),
		"roster": units, "squads": squads.duplicate(true), "cleared": cleared.duplicate(),
		"hired": hired.duplicate()}


func save(path: String = SAVE_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("无法写入存档 %s" % path)
		return false
	f.store_string(JSON.stringify(to_dict(), "  "))
	return true


static func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


func load_save(path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path) or not load_data():
		return false
	var d = BattleEngine.load_json(path)
	if typeof(d) != TYPE_DICTIONARY or int(d.get("version", 0)) != SAVE_VERSION:
		return false
	gold = int(d["gold"])
	inventory = (d["inventory"] as Array).duplicate()
	cleared = (d["cleared"] as Array).duplicate()
	hired = (d["hired"] as Array).duplicate()
	squads = []
	for s in d["squads"]:
		var members: Array = []
		for uid in s["members"]:
			members.append(str(uid))
		squads.append({"id": str(s["id"]), "name": str(s["name"]), "color": str(s["color"]), "members": members})
	roster = []
	for ud in d["roster"]:
		var cid := str(ud["class"])
		if not classes.has(cid):
			continue
		var data: Dictionary = ud.duplicate(true)
		data["tactics"] = _fix_tactics(ud.get("tactics", []))
		var u = BattleUnit.from_data(cid, classes[cid], data, 0)
		u.apply_class(classes[cid], items)
		u.hp = u.max_hp
		roster.append(u)
	current_mission = -1
	return true


## JSON 读回来的整数会变成 float，按条件类型还原
static func _fix_tactics(tac: Array) -> Array:
	var out: Array = []
	for rule in tac:
		var r: Dictionary = rule.duplicate()
		if r.has("value") and typeof(r["value"]) == TYPE_FLOAT and r.get("if", "") in ["allies_hurt_at_least", "row_count_at_least", "enemy_count_at_least", "ally_ep_at_most"]:
			r["value"] = int(r["value"])
		out.append(r)
	return out
