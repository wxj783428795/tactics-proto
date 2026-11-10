## 营地：任务选择与简报、出击、部队管理、招募、存档。
extends Control

const Game := preload("res://scripts/game.gd")
const CampaignState := preload("res://scripts/campaign_state.gd")
const BattleEngine := preload("res://scripts/battle_engine.gd")
const UI := preload("res://scripts/ui_util.gd")

const OBJ_NAMES := {"capture_hq": "攻陷大本营", "defend": "坚守", "defeat_boss": "讨伐首领"}

var st
var selected_mission: int = 0
var top_label: Label
var mission_box: VBoxContainer
var brief_title: Label
var brief_text: Label
var brief_info: Label
var deploy_label: Label
var sortie_btn: Button
var message: Label
var overlay: Control = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if Game.state == null:  # 直接运行本场景时，开一个新战役方便调试
		Game.state = CampaignState.new()
		Game.state.new_game()
	st = Game.state
	var nxt: int = st.next_mission_index()
	selected_mission = nxt if nxt >= 0 else st.missions.size() - 1
	_build()
	refresh()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.1, 0.13)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	top_label = UI.label(root, "", 22)
	var hb := HBoxContainer.new()
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", 18)
	root.add_child(hb)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	hb.add_child(left)
	UI.label(left, "任务", 18)
	mission_box = VBoxContainer.new()
	left.add_child(mission_box)

	var mid := _panel(hb)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 10)
	mid.add_child(mv)
	brief_title = UI.label(mv, "", 24)
	brief_title.add_theme_color_override("font_color", Color(1, 0.92, 0.7))
	brief_info = UI.label(mv, "", 15)
	brief_info.add_theme_color_override("font_color", Color(0.75, 0.85, 1))
	brief_text = UI.label(mv, "", 16)
	brief_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	brief_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UI.label(mv, "出击部队", 16)
	deploy_label = UI.label(mv, "", 14)
	deploy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sortie_btn = UI.button(mv, "出击！", sortie)
	sortie_btn.custom_minimum_size = Vector2(0, 46)
	sortie_btn.add_theme_font_size_override("font_size", 20)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(220, 0)
	right.add_theme_constant_override("separation", 10)
	hb.add_child(right)
	UI.label(right, "营地", 18)
	for pair in [["部队管理（编成 / 装备 / 转职）", open_roster], ["招募", open_recruit], ["存档", save_game], ["返回标题", back_to_title]]:
		var b := UI.button(right, pair[0], pair[1])
		b.custom_minimum_size = Vector2(0, 40)
	message = UI.label(right, "", 14)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size = Vector2(220, 0)


func _panel(parent: Node) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.14, 0.19)
	sb.border_color = Color(0.35, 0.4, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(16)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	return p


func refresh() -> void:
	top_label.text = "晨星营 · 营地      资金 %d 金      成员 %d 人      道具库存 %d 件      进度 %d / %d" % [
		st.gold, st.roster.size(), st.inventory.size(), st.cleared.size(), st.missions.size()]
	for c in mission_box.get_children():
		c.queue_free()
	for i in st.missions.size():
		var m: Dictionary = st.missions[i]
		var mark := "✓ " if st.cleared.has(m["id"]) else ("　" if st.is_unlocked(i) else "× ")
		var b := Button.new()
		b.text = "%s%s" % [mark, m["title"]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(290, 44)
		b.disabled = not st.is_unlocked(i)
		b.toggle_mode = true
		b.button_pressed = i == selected_mission
		var idx: int = i
		b.pressed.connect(func(): select_mission(idx))
		mission_box.add_child(b)
	if st.is_complete():
		var l := Label.new()
		l.text = "\n战役已完成！可以重玩任何章节来积累经验与资金（首通奖励只发一次）。"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(290, 0)
		mission_box.add_child(l)
	var m2: Dictionary = st.missions[selected_mission]
	brief_title.text = m2["title"]
	var rw: Dictionary = m2.get("reward", {})
	var names := PackedStringArray()
	for it in rw.get("items", []):
		names.append(st.item_name(it))
	brief_info.text = "目标：%s      难度：%s\n首通奖励：%d 金%s%s" % [m2.get("goal", ""), m2.get("difficulty", ""),
		int(rw.get("gold", 0)), ("、" + "、".join(names)) if not names.is_empty() else "",
		"（已领取）" if st.cleared.has(m2["id"]) else ""]
	brief_text.text = m2.get("briefing", "")
	var lines := PackedStringArray()
	for si in st.squads.size():
		var us: Array = st.squad_units(si)
		if us.is_empty():
			continue
		var parts := PackedStringArray()
		for u in us:
			parts.append("%s Lv%d" % [u.display_name, u.level])
		lines.append("%s（%d/%d）：%s" % [st.squads[si]["name"], us.size(), CampaignState.MAX_SQUAD_SIZE, "、".join(parts)])
	var reserve: Array = st.reserve_units()
	if not reserve.is_empty():
		lines.append("待命（不出击）：%s" % "、".join(PackedStringArray(reserve.map(func(u): return u.display_name))))
	deploy_label.text = "\n".join(lines) if not lines.is_empty() else "没有可出击的小队！请在部队管理中编成。"
	sortie_btn.disabled = st.deployable_squads().is_empty() or not st.is_unlocked(selected_mission)


func select_mission(i: int) -> void:
	if st.is_unlocked(i):
		selected_mission = i
	refresh()


func sortie() -> void:
	if st.deployable_squads().is_empty():
		return
	st.current_mission = selected_mission
	var m: Dictionary = st.missions[selected_mission]
	Game.play_story(get_tree(), m["title"], m.get("pre_story", []), Game.SCENE_MAP)


func open_roster() -> void:
	get_tree().change_scene_to_file(Game.SCENE_ROSTER)


func save_game() -> void:
	message.text = "已存档。" if st.save() else "存档失败！"


func back_to_title() -> void:
	get_tree().change_scene_to_file(Game.SCENE_TITLE)


# ---------------------------------------------------------------- 招募

func open_recruit() -> Control:
	if overlay != null:
		overlay.queue_free()
	overlay = Control.new()
	add_child(overlay)
	var box := UI.make_overlay(overlay, Vector2(640, 380))
	_fill_recruit(box)
	return overlay


func _fill_recruit(box: VBoxContainer) -> void:
	for c in box.get_children():
		c.queue_free()
	UI.label(box, "招募 —— 资金 %d 金" % st.gold, 20)
	var av: Array = st.available_recruits()
	if av.is_empty():
		UI.label(box, "现在没有可以招募的人。推进剧情后会有新的人来投奔。", 15)
	for r in av:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		box.add_child(row)
		var cls: Dictionary = st.classes[r["class"]]
		var sw := ColorRect.new()
		sw.color = Color.from_string(str(cls.get("color", "#fff")), Color.WHITE)
		sw.custom_minimum_size = Vector2(28, 28)
		row.add_child(sw)
		var l := UI.label(row, "%s　%s Lv%d　%d 金\n%s" % [r["name"], cls["name"], int(r["level"]), int(r["cost"]), r.get("desc", "")], 14)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var rid: String = r["id"]
		var b := UI.button(row, "招募", func(): _do_recruit(rid, box))
		b.disabled = st.gold < int(r["cost"])
	var locked: int = st.recruits.size() - st.hired.size() - av.size()
	if locked > 0:
		UI.label(box, "（还有 %d 人会在推进剧情后出现）" % locked, 13)
	UI.button(box, "关闭", close_overlay)


func close_overlay() -> void:
	if overlay != null:
		overlay.queue_free()
		overlay = null
	refresh()


func _do_recruit(rid: String, box: VBoxContainer) -> void:
	if st.recruit(rid):
		var u = st.roster[st.roster.size() - 1]
		var si: int = st.squad_of(u.uid)
		message.text = "%s 加入了晨星营！%s" % [u.display_name, ("编入" + st.squads[si]["name"]) if si >= 0 else "（小队已满，暂时待命）"]
	_fill_recruit(box)
	refresh()
