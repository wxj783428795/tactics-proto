## 大地图主场景：即时行军、占领据点、遭遇战、编队与战术编辑入口。
extends Control

const MapModel := preload("res://scripts/map_model.gd")
const MapCanvas := preload("res://scripts/map_canvas.gd")
const BattleView := preload("res://scripts/battle_view.gd")
const FormationEditor := preload("res://scripts/formation_editor.gd")
const RuleEditor := preload("res://scripts/rule_editor.gd")
const BattleEngine := preload("res://scripts/battle_engine.gd")
const UI := preload("res://scripts/ui_util.gd")
const Game := preload("res://scripts/game.gd")

const CAMPAIGN_PATH := "res://data/campaign.json"
const CLASSES_PATH := "res://data/classes.json"
const SAVE_PATH := "user://squad_setups.json"
const SPEEDS := [1.0, 2.0, 4.0]

var model: MapModel
var canvas: MapCanvas
var selected = null
var paused: bool = false
var speed_idx: int = 0
var overlay: Control = null          # 当前打开的弹窗（战斗/编队/战术）；打开时地图暂停
var save_path: String = SAVE_PATH
var _describer: BattleEngine         # 仅用于生成战术说明文字
var mission_mode: bool = false       # 战役任务（Game.state 有当前任务）/ 沙盒

var hud: Label
var info: Label
var event_log: RichTextLabel
var pause_btn: Button
var speed_btn: Button
var formation_btn: Button
var tactics_btn: Button
var stop_btn: Button


func _ready() -> void:
	var loaded := false
	if Game.state != null and Game.state.current_mission >= 0:
		model = Game.state.create_mission_model(Game.state.current_mission)
		mission_mode = model != null
	if not mission_mode:
		model = MapModel.new()
		if not model.load_campaign(CAMPAIGN_PATH, CLASSES_PATH):
			push_error("战役数据加载失败")
		loaded = model.load_setups(save_path)
	_describer = BattleEngine.new()
	_describer.skills_db = model.skills_db
	_describer.passives_db = model.passives_db
	_describer.classes_db = model.classes_db
	_build_ui()
	if mission_mode:
		log_event("%s —— 任务目标：%s。守住我方大本营「%s」。" % [Game.state.missions[Game.state.current_mission]["title"], model.objective_text(), model.nodes[model.hq_of(0)]["name"]])
		log_event("占领据点可获得资金（每 10 秒结算），部分据点首次占领会获得道具。")
	else:
		log_event("沙盒地图开始！目标：攻陷敌方大本营「灰烬要塞」，守住「晨星营地」。")
	if loaded:
		log_event("已读取保存的编队与战术。")
	select_squad(model.living_squads(0)[0])


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	margin.add_child(hb)

	var left := VBoxContainer.new()
	hb.add_child(left)
	hud = UI.label(left, "", 16)
	canvas = MapCanvas.new()
	canvas.model = model
	canvas.clicked.connect(_on_map_clicked)
	left.add_child(canvas)
	UI.label(left, "左键：选择我方小队 / 点据点或路口行军 / 点敌方小队追击   右键：查看任意小队   空格：暂停   F：切换速度", 13)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(320, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	hb.add_child(right)

	var row1 := HBoxContainer.new()
	right.add_child(row1)
	pause_btn = UI.button(row1, "", toggle_pause)
	speed_btn = UI.button(row1, "", toggle_speed)
	if mission_mode:
		UI.button(row1, "撤退", abandon_mission)
	else:
		UI.button(row1, "保存", save_setups)
		UI.button(row1, "标题", func(): get_tree().change_scene_to_file(Game.SCENE_TITLE))
	var row2 := HBoxContainer.new()
	right.add_child(row2)
	for sq in model.living_squads(0):
		UI.button(row2, sq.name, func(): select_squad(sq))
	info = UI.label(right, "", 14)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(300, 250)
	var row3 := HBoxContainer.new()
	right.add_child(row3)
	formation_btn = UI.button(row3, "编队", open_formation_editor)
	tactics_btn = UI.button(row3, "战术", func(): open_rule_editor(0))
	stop_btn = UI.button(row3, "原地停止", _on_stop)
	UI.label(right, "战况记录", 14)
	event_log = RichTextLabel.new()
	event_log.scroll_following = true
	event_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	event_log.add_theme_font_size_override("normal_font_size", 13)
	right.add_child(event_log)
	# 防止空格触发按钮
	for b in find_children("*", "Button", true, false):
		b.focus_mode = Control.FOCUS_NONE
	_refresh_hud()


# ---------------------------------------------------------------- 主循环

func _process(delta: float) -> void:
	process_map(delta)


## 推进地图（也供无头测试调用）
func process_map(delta: float) -> void:
	if overlay == null and not paused and not model.game_over:
		for e in model.update(delta * SPEEDS[speed_idx]):
			log_event(e["text"])
			if e["type"] == "game_over":
				_show_game_over()
		if not model.pending_encounter.is_empty() and overlay == null:
			open_battle()
	_refresh_hud()


func _input(event: InputEvent) -> void:
	if overlay != null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			toggle_pause()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F:
			toggle_speed()


func toggle_pause() -> void:
	paused = not paused


func toggle_speed() -> void:
	speed_idx = (speed_idx + 1) % SPEEDS.size()


func _on_map_clicked(p: Vector2, button: int) -> void:
	if overlay != null or model.game_over:
		return
	var sq = canvas.squad_at(p)
	var mine: bool = selected != null and selected.team == 0 and selected.alive
	# 已选中我方小队时，左键点敌方小队 = 追击；右键点任意小队 = 查看
	if sq != null and sq.team == 1 and mine and button == MOUSE_BUTTON_LEFT:
		command_pursue(sq)
		return
	if sq != null and (button == MOUSE_BUTTON_RIGHT or sq.team == 0 or not mine):
		select_squad(sq)
		return
	var nid := model.nearest_node(p, 24.0)
	if nid != "" and selected != null and selected.team == 0:
		command_move(nid)
	elif sq != null:
		select_squad(sq)


func select_squad(sq) -> void:
	selected = sq
	canvas.selected = sq
	_refresh_hud()


func command_pursue(target) -> bool:
	if selected == null or selected.team != 0 or not selected.alive:
		return false
	var ok: bool = model.order_pursue(selected, target)
	if ok:
		log_event("%s 开始追击「%s」" % [selected.name, target.name])
	return ok


func command_move(node_id: String) -> bool:
	if selected == null or selected.team != 0 or not selected.alive:
		return false
	var ok: bool = model.order_move(selected, node_id)
	if ok:
		var n: Dictionary = model.nodes[node_id]
		log_event("%s 出发前往「%s」" % [selected.name, n["name"] if n["name"] != "" else "路口"])
	return ok


# ---------------------------------------------------------------- 弹窗

func open_battle() -> Control:
	var a = model.pending_encounter[0]
	var b = model.pending_encounter[1]
	var bv := BattleView.new()
	bv.configure(model, a, b)
	bv.finished.connect(func(w): _on_battle_finished(bv, a, b, w))
	_open_overlay(bv)
	return bv


func _on_battle_finished(bv: Control, a, b, w: int) -> void:
	for e in model.apply_battle_result(a, b, w):
		log_event(e["text"])
		if e["type"] == "game_over":
			_show_game_over()
	log_event("战斗结果：%s" % ("我方胜利" if w == 0 else ("敌方胜利" if w == 1 else "平局")))
	_close_overlay(bv)
	save_setups()
	if selected != null and not selected.alive:
		var rest := model.living_squads(0)
		select_squad(rest[0] if not rest.is_empty() else null)


func open_formation_editor() -> Control:
	if selected == null or selected.team != 0 or overlay != null:
		return null
	var fe := FormationEditor.new()
	fe.setup(selected, func(u): return _describer.describe_tactics(u))
	fe.closed.connect(func(): _overlay_closed(fe); save_setups())
	fe.edit_tactics_requested.connect(func(i): _open_rules_over(fe, i))
	_open_overlay(fe)
	return fe


func open_rule_editor(index: int = 0) -> Control:
	if selected == null or selected.team != 0 or overlay != null:
		return null
	var ed := RuleEditor.new()
	ed.setup(selected.units, model.skills_db, model.classes_db, index)
	ed.closed.connect(func(saved): _on_rules_closed(ed, saved))
	_open_overlay(ed)
	return ed


## 在编队窗口之上再打开战术编辑
func _open_rules_over(parent: Control, index: int) -> void:
	var ed := RuleEditor.new()
	ed.setup(selected.units, model.skills_db, model.classes_db, index)
	ed.closed.connect(func(_saved): parent.refresh())
	parent.add_child(ed)


func _on_rules_closed(ed: Control, saved: bool) -> void:
	_overlay_closed(ed)
	if saved:
		save_setups()


func _on_stop() -> void:
	if selected != null and selected.team == 0:
		model.stop(selected)


func _open_overlay(c: Control) -> void:
	overlay = c
	add_child(c)


func _overlay_closed(c: Control) -> void:
	if overlay == c:
		overlay = null
	_refresh_hud()


func _close_overlay(c: Control) -> void:
	_overlay_closed(c)
	c.queue_free()


func _show_game_over() -> void:
	if overlay != null and overlay.has_meta("game_over"):
		return
	if overlay != null:
		overlay.queue_free()
	var go := Control.new()
	go.set_meta("game_over", true)
	var box := UI.make_overlay(go, Vector2(460, 170))
	if mission_mode:
		UI.label(box, "任务成功！" if model.winner == 0 else "任务失败……", 26)
		UI.label(box, model.end_reason, 16)
		UI.button(box, "查看战报", show_results)
	else:
		UI.label(box, "胜利！敌方大本营已被攻陷。" if model.winner == 0 else "败北……我方大本营失守。", 22)
		UI.button(box, "重新开始战役", func(): get_tree().reload_current_scene())
		UI.button(box, "返回标题", func(): get_tree().change_scene_to_file(Game.SCENE_TITLE))
	overlay = go
	add_child(go)


## 任务结算并进入战报界面
func show_results() -> void:
	Game.last_result = Game.state.finish_mission(model)
	get_tree().change_scene_to_file(Game.SCENE_RESULTS)


func abandon_mission() -> void:
	if overlay != null or model.game_over:
		return
	var ev: Array = []
	model._end_game(1, ev, "部队撤出了战场")
	for e in ev:
		log_event(e["text"])
	_show_game_over()


func save_setups() -> void:
	if mission_mode:
		return  # 战役中编队/战术直接写入名册，随战役存档保存
	if model.save_setups(save_path):
		log_event("编队与战术已保存。")


func log_event(text: String) -> void:
	if event_log != null:
		var t := int(model.time) if model != null else 0
		event_log.add_text("[%02d:%02d] %s\n" % [t / 60, t % 60, text])


# ---------------------------------------------------------------- HUD

func _refresh_hud() -> void:
	if hud == null:
		return
	var c: Array = model.base_counts()
	var t := int(model.time)
	hud.text = "时间 %02d:%02d   速度 x%d   %s   据点：我方 %d / 敌方 %d / 中立 %d   小队：我方 %d / 敌方 %d" % [
		t / 60, t % 60, int(SPEEDS[speed_idx]), "【已暂停】" if paused else "", c[0], c[1], c[2],
		model.living_squads(0).size(), model.living_squads(1).size()]
	var hq0 := model.hq_of(0)
	var hq1 := model.hq_of(1)
	var dur := PackedStringArray()
	if hq0 != "" and model.durability_text(hq0) != "":
		dur.append("我方大本营耐久 %s" % model.durability_text(hq0))
	if hq1 != "" and model.durability_text(hq1) != "":
		dur.append("敌方大本营耐久 %s" % model.durability_text(hq1))
	var head := "  ".join(dur)
	if mission_mode:
		head = "【%s】目标：%s    %s" % [model.map_name, model.objective_text(), head]
		hud.text += "   本场资金 +%d（每 10 秒 +%d）" % [model.gold_earned, model.income_per_tick(0)]
	if head != "":
		hud.text = head + "\n" + hud.text
	pause_btn.text = "继续(空格)" if paused else "暂停(空格)"
	speed_btn.text = "速度 x%d" % int(SPEEDS[speed_idx])
	var mine: bool = selected != null and selected.team == 0 and selected.alive
	formation_btn.disabled = not mine
	tactics_btn.disabled = not mine
	stop_btn.disabled = not mine
	if selected == null or not selected.alive:
		info.text = "未选择小队"
		return
	var where := ""
	var here: String = model.node_of(selected)
	if here != "":
		var n: Dictionary = model.nodes[here]
		where = "驻留：%s" % (n["name"] if n["name"] != "" else "路口")
		if model.durability_text(here) != "":
			where += "（耐久 %s）" % model.durability_text(here)
	elif selected.is_moving():
		var d: Dictionary = model.nodes[selected.destination()]
		where = "行军中 → %s" % (d["name"] if d["name"] != "" else "路口")
	if selected.pursue_target != null:
		where = "追击：%s" % selected.pursue_target.name
	var lines := PackedStringArray()
	lines.append("%s（%s）" % [selected.name, "我方" if selected.team == 0 else "敌方"])
	if selected.is_recovering():
		var st := "战后整备"
		if selected.waiting:
			st = "硬直待机（可被先制攻击）" if selected.stunned else "战败待机（可被先制攻击）"
		where += "　%s %.1f 秒" % [st, selected.recover_time]
	lines.append(where)
	lines.append("体力 %d / 100%s" % [int(selected.stamina), "（疲劳：移动减速）" if selected.stamina <= 0.0 else ""])
	for u in selected.units:
		lines.append("%s %s Lv%d（%s·%s） HP %d/%d" % ["×" if not u.is_alive() else "·", u.display_name, u.level, u.job_name, u.row_name(), u.hp, u.max_hp])
	if selected.team == 1:
		lines.append("AI：%s%s" % [str(selected.ai.get("mode", "")), "（首领）" if bool(selected.ai.get("boss", false)) else ""])
		if selected.max_morale > 0:
			lines.append("士气 %d / %d%s" % [int(ceil(selected.morale)), selected.max_morale, "（回据点休整中）" if selected.resting else ""])
	info.text = "\n".join(lines)
