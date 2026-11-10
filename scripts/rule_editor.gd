## 战术规则编辑器（遮罩弹窗）。
## 编辑的是草稿副本，点"保存"才写回单位；"取消"放弃所有修改。
extends Control

signal closed(saved: bool)

const Schema := preload("res://scripts/tactics_schema.gd")
const UI := preload("res://scripts/ui_util.gd")
const BattleEngine := preload("res://scripts/battle_engine.gd")

var units: Array = []
var skills_db: Dictionary = {}
var classes_db: Dictionary = {}
var drafts: Dictionary = {}     # 单位下标 -> 规则数组副本
var current: int = 0

var _unit_select: OptionButton
var _info: Label
var _rows: VBoxContainer
var _preview: Label
var _skill_help: Label


## 打开编辑器：units 为可编辑的 BattleUnit 列表
func setup(edit_units: Array, skills: Dictionary, classes: Dictionary, start_index: int = 0) -> void:
	units = edit_units
	skills_db = skills
	classes_db = classes
	current = clampi(start_index, 0, max(0, units.size() - 1))


func _ready() -> void:
	var box := UI.make_overlay(self, Vector2(900, 520))
	UI.label(box, "战术编辑 —— 从上到下优先，执行第一条「条件成立且有目标」的规则", 18)
	var top := HBoxContainer.new()
	box.add_child(top)
	UI.label(top, "单位：")
	_unit_select = OptionButton.new()
	for u in units:
		_unit_select.add_item("%s（%s）" % [u.display_name, u.job_name])
	_unit_select.item_selected.connect(func(i): current = i; _rebuild())
	top.add_child(_unit_select)
	_info = UI.label(top, "", 13)
	_skill_help = UI.label(box, "", 12)
	_skill_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_skill_help.custom_minimum_size = Vector2(860, 0)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(860, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)
	_preview = UI.label(box, "", 13)
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	box.add_child(bar)
	UI.button(bar, "＋ 添加规则", _on_add)
	UI.button(bar, "恢复职业默认", _on_default)
	UI.button(bar, "保存", _on_save)
	UI.button(bar, "取消", _on_cancel)
	if not units.is_empty():
		_unit_select.select(current)
	_rebuild()


## 当前单位的草稿（懒创建）
func draft_for(i: int) -> Array:
	if not drafts.has(i):
		drafts[i] = (units[i].tactics as Array).duplicate(true)
	return drafts[i]


## 把所有草稿写回单位（测试也直接调用）
func apply_drafts() -> void:
	for i in drafts:
		var clean: Array = []
		for rule in drafts[i]:
			if Schema.validate_rule(rule, units[i].skills) == "":
				clean.append(rule)
		units[i].tactics = clean
	drafts.clear()


func _on_add() -> void:
	if units.is_empty():
		return
	var u = units[current]
	Schema.add_rule(draft_for(current), Schema.make_rule(str(u.skills[0])))
	_rebuild.call_deferred()


func _on_default() -> void:
	var u = units[current]
	drafts[current] = (classes_db.get(u.class_id, {}).get("default_tactics", []) as Array).duplicate(true)
	_rebuild.call_deferred()


func _on_save() -> void:
	apply_drafts()
	closed.emit(true)
	queue_free()


func _on_cancel() -> void:
	drafts.clear()
	closed.emit(false)
	queue_free()


func _rebuild() -> void:
	if _rows == null:
		return
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	if units.is_empty():
		return
	var u = units[current]
	var skill_names := PackedStringArray()
	for sid in u.skills:
		skill_names.append(skills_db.get(sid, {}).get("name", sid))
	_info.text = "  职业：%s  技能：%s  锐气 %d" % [u.job_name, "、".join(skill_names), u.max_ep]
	var descs := PackedStringArray()
	for sid in u.skills:
		var sk: Dictionary = skills_db.get(sid, {})
		if sk.has("desc"):
			descs.append("%s：%s" % [sk.get("name", sid), sk["desc"]])
	_info.tooltip_text = "\n".join(descs)
	_skill_help.text = "  ".join(descs)
	var list := draft_for(current)
	for i in list.size():
		_rows.add_child(_make_row(u, list, i))
	if list.is_empty():
		UI.label(_rows, "（没有规则：攻击型职业会使用第一个技能兜底，治疗型会待机）", 13)
	_update_preview()


func _update_preview() -> void:
	var lines := PackedStringArray()
	var list := draft_for(current)
	for i in list.size():
		var r: Dictionary = list[i]
		lines.append("%d. %s → %s" % [i + 1, BattleEngine.describe_rule(r), skills_db.get(str(r.get("skill", "")), {}).get("name", "?")])
	_preview.text = "预览：" + ("；".join(lines) if not lines.is_empty() else "无")


func _make_row(u, list: Array, i: int) -> HBoxContainer:
	var rule: Dictionary = list[i]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	UI.label(row, "%d." % (i + 1))

	# 条件
	var cond := OptionButton.new()
	for c in Schema.CONDITIONS:
		cond.add_item(c["label"])
	cond.select(Schema.condition_index(str(rule.get("if", "always"))))
	cond.item_selected.connect(func(idx):
		Schema.set_condition(rule, Schema.CONDITIONS[idx]["id"])
		_rebuild.call_deferred())
	row.add_child(cond)

	# 条件参数
	var def := Schema.condition_def(str(rule.get("if", "always")))
	match str(def["value"]):
		"percent":
			var sp := SpinBox.new()
			sp.min_value = 5
			sp.max_value = 95
			sp.step = 5
			sp.suffix = "%"
			sp.value = round(float(rule.get("value", 0.5)) * 100.0)
			sp.value_changed.connect(func(v): rule["value"] = v / 100.0; _update_preview())
			row.add_child(sp)
		"int":
			var sp2 := SpinBox.new()
			sp2.min_value = 1
			sp2.max_value = 6
			sp2.value = int(rule.get("value", 2))
			sp2.value_changed.connect(func(v): rule["value"] = int(v); _update_preview())
			row.add_child(sp2)
		"class":
			var ob := OptionButton.new()
			var ids: Array = classes_db.keys()
			for k in ids:
				ob.add_item(str(classes_db[k].get("name", k)))
			ob.select(max(0, ids.find(str(rule.get("value", "")))))
			if ids.find(str(rule.get("value", ""))) < 0 and not ids.is_empty():
				rule["value"] = ids[0]
			ob.item_selected.connect(func(idx): rule["value"] = ids[idx]; _update_preview())
			row.add_child(ob)
		"int0":
			var sp3 := SpinBox.new()
			sp3.min_value = 0
			sp3.max_value = 3
			sp3.value = int(rule.get("value", 0))
			sp3.value_changed.connect(func(v): rule["value"] = int(v); _update_preview())
			row.add_child(sp3)
		"tag":
			var ob3 := OptionButton.new()
			var cur := 0
			for ti in Schema.TAGS.size():
				ob3.add_item(Schema.TAGS[ti]["label"])
				if Schema.TAGS[ti]["id"] == str(rule.get("value", "")):
					cur = ti
			ob3.select(cur)
			rule["value"] = Schema.TAGS[cur]["id"]
			ob3.item_selected.connect(func(idx): rule["value"] = Schema.TAGS[idx]["id"]; _update_preview())
			row.add_child(ob3)
		"row":
			var ob2 := OptionButton.new()
			for rr in Schema.ROWS:
				ob2.add_item(rr["label"])
			ob2.select(0 if str(rule.get("value", "back")) == "front" else 1)
			ob2.item_selected.connect(func(idx): rule["value"] = Schema.ROWS[idx]["id"]; _update_preview())
			row.add_child(ob2)

	UI.label(row, "→")
	# 技能
	var sk := OptionButton.new()
	for sid in u.skills:
		var s: Dictionary = skills_db.get(sid, {})
		sk.add_item("%s(%d锐气)" % [s.get("name", sid), int(s.get("cost", 1))])
	sk.select(max(0, u.skills.find(str(rule.get("skill", "")))))
	sk.item_selected.connect(func(idx): rule["skill"] = u.skills[idx]; _update_preview())
	row.add_child(sk)

	UI.label(row, "目标：")
	var pk := OptionButton.new()
	for p in Schema.PICKS:
		pk.add_item(p["label"])
	pk.select(Schema.pick_index(str(rule.get("pick", ""))))
	pk.item_selected.connect(func(idx): Schema.set_pick(rule, Schema.PICKS[idx]["id"]); _update_preview())
	row.add_child(pk)

	UI.button(row, "↑", func(): _list_op(list, i, -1))
	UI.button(row, "↓", func(): _list_op(list, i, 1))
	UI.button(row, "×", func(): _list_op(list, i, 0))
	return row


## dir: -1 上移 / +1 下移 / 0 删除
func _list_op(list: Array, i: int, dir: int) -> void:
	var changed := Schema.remove_rule(list, i) if dir == 0 else Schema.move_rule(list, i, dir)
	if changed:
		_rebuild.call_deferred()
