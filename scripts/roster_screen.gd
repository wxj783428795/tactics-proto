## 部队管理：名册、小队编成、装备、转职、战术与编队。
extends Control

const Game := preload("res://scripts/game.gd")
const CampaignState := preload("res://scripts/campaign_state.gd")
const Progression := preload("res://scripts/progression.gd")
const BattleEngine := preload("res://scripts/battle_engine.gd")
const Squad := preload("res://scripts/squad.gd")
const FormationEditor := preload("res://scripts/formation_editor.gd")
const RuleEditor := preload("res://scripts/rule_editor.gd")
const UI := preload("res://scripts/ui_util.gd")

var st
var selected_uid: String = ""
var _describer: BattleEngine
var top_label: Label
var unit_list: ItemList
var detail: RichTextLabel
var squad_opt: OptionButton
var slot_opts: Dictionary = {}
var promote_btn: Button
var squads_label: Label
var inv_label: Label
var message: Label
var overlay: Control = null
var _list_uids: Array = []
var _building: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if Game.state == null:
		Game.state = CampaignState.new()
		Game.state.new_game()
	st = Game.state
	_describer = BattleEngine.new()
	_describer.skills_db = st.skills
	_describer.passives_db = st.passives
	_describer.classes_db = st.classes
	_build()
	select_unit(st.roster[0].uid)


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.1, 0.13)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	top_label = UI.label(top, "", 20)
	top_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.button(top, "返回营地", func(): get_tree().change_scene_to_file(Game.SCENE_CAMP))

	var hb := HBoxContainer.new()
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", 14)
	root.add_child(hb)
	unit_list = ItemList.new()
	unit_list.custom_minimum_size = Vector2(300, 0)
	unit_list.add_theme_font_size_override("font_size", 15)
	unit_list.item_selected.connect(func(i): select_unit(_list_uids[i]))
	hb.add_child(unit_list)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 8)
	hb.add_child(mid)
	detail = RichTextLabel.new()
	detail.bbcode_enabled = true
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_theme_font_size_override("normal_font_size", 15)
	detail.add_theme_font_size_override("bold_font_size", 18)
	mid.add_child(detail)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	mid.add_child(grid)
	UI.label(grid, "所属小队", 15)
	squad_opt = OptionButton.new()
	squad_opt.custom_minimum_size = Vector2(300, 0)
	squad_opt.item_selected.connect(_on_squad_selected)
	grid.add_child(squad_opt)
	for slot in Progression.SLOTS:
		UI.label(grid, Progression.SLOT_NAMES[slot], 15)
		var o := OptionButton.new()
		o.custom_minimum_size = Vector2(300, 0)
		var sl: String = slot
		o.item_selected.connect(func(i): _on_equip_selected(sl, i))
		grid.add_child(o)
		slot_opts[slot] = o
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	mid.add_child(bar)
	promote_btn = UI.button(bar, "转职", do_promote)
	UI.button(bar, "编辑战术", open_tactics)
	UI.button(bar, "小队编队", open_formation)
	message = UI.label(mid, "", 14)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(330, 0)
	hb.add_child(right)
	UI.label(right, "小队编成（每队最多 %d 人）" % CampaignState.MAX_SQUAD_SIZE, 16)
	squads_label = UI.label(right, "", 14)
	squads_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	squads_label.custom_minimum_size = Vector2(320, 0)
	UI.label(right, "道具库存", 16)
	inv_label = UI.label(right, "", 14)
	inv_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inv_label.custom_minimum_size = Vector2(320, 0)


func select_unit(uid: String) -> void:
	selected_uid = uid
	refresh()


func current():
	return st.unit_by_uid(selected_uid)


func refresh() -> void:
	_building = true
	top_label.text = "部队管理      资金 %d 金      成员 %d 人" % [st.gold, st.roster.size()]
	unit_list.clear()
	_list_uids = []
	for u in st.roster:
		var si: int = st.squad_of(u.uid)
		var tag := "  ★可转职" if Progression.can_promote(u, st.classes) else ""
		unit_list.add_item("Lv%d %s（%s）· %s%s" % [u.level, u.display_name, u.job_name, st.squads[si]["name"] if si >= 0 else "待命", tag])
		_list_uids.append(u.uid)
		if u.uid == selected_uid:
			unit_list.select(unit_list.item_count - 1)
	var u = current()
	detail.text = _detail_text(u)
	# 小队下拉
	squad_opt.clear()
	squad_opt.add_item("待命（不出击）")
	for i in st.squads.size():
		squad_opt.add_item("%s（%d/%d）" % [st.squads[i]["name"], st.squads[i]["members"].size(), CampaignState.MAX_SQUAD_SIZE])
	squad_opt.select(st.squad_of(u.uid) + 1)
	# 装备下拉：当前装备 + 库存里同部位的道具（去重）
	for slot in Progression.SLOTS:
		var o: OptionButton = slot_opts[slot]
		o.clear()
		o.add_item("（无）")
		o.set_item_metadata(0, "")
		var cur := str(u.equipment.get(slot, ""))
		if cur != "":
			o.add_item("%s　%s" % [st.item_name(cur), st.items[cur]["desc"]])
			o.set_item_metadata(1, cur)
			o.select(1)
		var seen := {}
		for it in st.inventory:
			if seen.has(it) or str(st.items.get(it, {}).get("slot", "")) != slot:
				continue
			seen[it] = true
			var n: int = st.inventory.count(it)
			o.add_item("%s　%s%s" % [st.item_name(it), st.items[it]["desc"], ("　×%d" % n) if n > 1 else ""])
			o.set_item_metadata(o.item_count - 1, it)
	var can: bool = Progression.can_promote(u, st.classes)
	var to := Progression.promotion_target(u, st.classes)
	promote_btn.disabled = not can
	if to != "":
		promote_btn.text = "转职 → %s%s" % [st.classes[to]["name"], "" if can else "（Lv%d）" % int(st.classes[u.class_id]["promotion"]["level"])]
	else:
		promote_btn.text = "转职（已是进阶职业）" if int(st.classes[u.class_id].get("tier", 1)) == 2 else "转职（该职业无进阶）"
	# 右侧
	var lines := PackedStringArray()
	for i in st.squads.size():
		var parts := PackedStringArray()
		for su in st.squad_units(i):
			parts.append("%s(%s)" % [su.display_name, "前" if su.row == 0 else "后"])
		lines.append("%s %d/%d：%s" % [st.squads[i]["name"], parts.size(), CampaignState.MAX_SQUAD_SIZE, "、".join(parts) if not parts.is_empty() else "—"])
	var res := PackedStringArray(st.reserve_units().map(func(x): return x.display_name))
	lines.append("待命：%s" % ("、".join(res) if not res.is_empty() else "—"))
	squads_label.text = "\n".join(lines)
	var counts := {}
	for it in st.inventory:
		counts[it] = int(counts.get(it, 0)) + 1
	var inv := PackedStringArray()
	for it in counts:
		inv.append("%s%s" % [st.item_name(it), ("×%d" % counts[it]) if counts[it] > 1 else ""])
	inv_label.text = "、".join(inv) if not inv.is_empty() else "（空）"
	_building = false


func _detail_text(u) -> String:
	var cls: Dictionary = st.classes[u.class_id]
	var t := "[b]%s[/b]　%s　Lv%d　（经验 %d / %d）\n" % [u.display_name, u.job_name, u.level, u.xp, Progression.XP_PER_LEVEL]
	t += "HP %d　攻击 %d　防御 %d　速度 %d　会心 %d%%　闪避 %d%%　锐气 %d　守势 %d\n" % [u.max_hp, u.atk, u.defense, u.spd, u.crit, u.eva, u.max_ep, u.max_gp]
	var g: Dictionary = cls.get("growth", {})
	t += "[color=#9ab]成长：HP+%d 攻+%d 防+%d 速+%d / 级[/color]\n" % [int(g.get("hp", 0)), int(g.get("atk", 0)), int(g.get("def", 0)), int(g.get("spd", 0))]
	t += "技能："
	var unlocks: Dictionary = cls.get("skill_unlocks", {})
	var parts := PackedStringArray()
	for sid in cls.get("skills", []):
		var nm := str(st.skills[sid]["name"])
		if u.skills.has(sid):
			parts.append(nm)
		else:
			parts.append("[color=#777]%s（Lv%d 解锁）[/color]" % [nm, int(unlocks.get(sid, 1))])
	t += "、".join(parts) + "\n"
	var ps := PackedStringArray()
	for pid in u.passives:
		ps.append(str(st.passives.get(pid, {}).get("name", pid)))
	if not ps.is_empty():
		t += "被动：%s\n" % "、".join(ps)
	var to := Progression.promotion_target(u, st.classes)
	if to != "":
		var adv: Dictionary = st.classes[to]
		var news := PackedStringArray()
		for sid in adv["skills"]:
			if not cls["skills"].has(sid):
				news.append(str(st.skills[sid]["name"]))
		t += "[color=#fd6]转职：Lv%d → %s（HP %d 攻 %d 防 %d 速 %d 起，新技能 %s）[/color]\n" % [int(cls["promotion"]["level"]), adv["name"], int(adv["hp"]), int(adv["atk"]), int(adv["def"]), int(adv["spd"]), "、".join(news)]
	t += "\n[color=#bcd]战术：[/color]\n" + _describer.describe_tactics(u)
	return t


func _on_squad_selected(i: int) -> void:
	if _building:
		return
	if not st.assign(selected_uid, i - 1):
		message.text = "无法编入：小队已满（最多 %d 人）。" % CampaignState.MAX_SQUAD_SIZE
	else:
		message.text = ""
	refresh()


func _on_equip_selected(slot: String, i: int) -> void:
	if _building:
		return
	var o: OptionButton = slot_opts[slot]
	var id := str(o.get_item_metadata(i))
	var u = current()
	if id == "":
		st.unequip(selected_uid, slot)
	elif id != str(u.equipment.get(slot, "")):
		st.equip(selected_uid, id)
		message.text = "%s 装备了「%s」。" % [u.display_name, st.item_name(id)]
	refresh()


func do_promote() -> Control:
	var msg: String = st.promote(selected_uid)
	refresh()
	if msg == "":
		return null
	return _popup("转职成功！", msg + "\n新技能的规则已加到战术列表最前面，可在「编辑战术」中调整。", current())


func _popup(title: String, text: String, u) -> Control:
	if overlay != null:
		overlay.queue_free()
	overlay = Control.new()
	add_child(overlay)
	var box := UI.make_overlay(overlay, Vector2(560, 260))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	box.add_child(hb)
	if u != null:
		var sw := ColorRect.new()
		sw.color = u.color
		sw.custom_minimum_size = Vector2(110, 110)
		hb.add_child(sw)
		var ch := UI.label(sw, u.display_name.substr(0, 1), 52)
		ch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ch.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	var tl := UI.label(vb, title, 26)
	tl.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	var l := UI.label(vb, text, 16)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(380, 0)
	if u != null:
		UI.label(vb, "HP %d　攻击 %d　防御 %d　速度 %d" % [u.max_hp, u.atk, u.defense, u.spd], 15)
	UI.button(box, "好", close_overlay)
	return overlay


func close_overlay() -> void:
	if overlay != null:
		overlay.queue_free()
		overlay = null
	refresh()


func open_tactics() -> Control:
	var u = current()
	var si: int = st.squad_of(u.uid)
	var units: Array = st.squad_units(si) if si >= 0 else [u]
	var ed := RuleEditor.new()
	ed.setup(units, st.skills, st.classes, maxi(0, units.find(u)))
	ed.closed.connect(func(_saved): refresh())
	add_child(ed)
	return ed


func open_formation() -> Control:
	var si: int = st.squad_of(selected_uid)
	if si < 0:
		message.text = "待命成员不在任何小队里。"
		return null
	var sq := Squad.new()
	sq.name = st.squads[si]["name"]
	sq.units = st.squad_units(si)
	var fe := FormationEditor.new()
	fe.setup(sq, func(x): return _describer.describe_tactics(x))
	fe.closed.connect(refresh)
	fe.edit_tactics_requested.connect(func(i): _rules_over(fe, sq.units, i))
	add_child(fe)
	return fe


func _rules_over(parent: Control, units: Array, i: int) -> void:
	var ed := RuleEditor.new()
	ed.setup(units, st.skills, st.classes, i)
	ed.closed.connect(func(_saved): parent.refresh())
	parent.add_child(ed)
