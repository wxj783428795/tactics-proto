## 战斗界面：战前编队 + 自动战斗演出 + 战斗日志。
## 两种模式：
##   - 独立模式（scenes/battle_test.tscn）：从 data/battle_setup.json 读取，可反复重开；
##   - 地图模式：由大地图调用 configure(model, 我方小队, 敌方小队)，单位与地图共享，结束后发出 finished。
extends Control

signal finished(winner: int)

const BattleEngine := preload("res://scripts/battle_engine.gd")
const UnitCell := preload("res://scripts/unit_cell.gd")
const RuleEditor := preload("res://scripts/rule_editor.gd")
const UI := preload("res://scripts/ui_util.gd")

const CLASSES_PATH := "res://data/classes.json"
const SETUP_PATH := "res://data/battle_setup.json"
const SPEEDS := [0.7, 0.35, 0.1]

enum State { FORMATION, BATTLE, DONE }

var engine: BattleEngine
var state: State = State.FORMATION
var cells: Array = []
var selected_cell = null
var saved_formation: Dictionary = {}  # 独立模式：重开时保留阵型（单位名 -> Vector2i(row, col)）
var saved_tactics: Dictionary = {}    # 独立模式：重开时保留编辑过的战术
var speed_idx: int = 0

# 地图模式
var map_model = null
var squad_a = null
var squad_b = null

var status_label: Label
var info_label: Label
var log_box: RichTextLabel
var start_btn: Button
var speed_btn: Button
var restart_btn: Button
var reset_btn: Button
var tactics_btn: Button
var skip_btn: Button
var return_btn: Button
var title_btn: Button
var timer: Timer
var player_title: Label
var enemy_title: Label


func configure(model, a, b) -> void:
	map_model = model
	squad_a = a
	squad_b = b


func is_map_mode() -> bool:
	return map_model != null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	new_battle()


# ---------------------------------------------------------------- UI 搭建

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	status_label = UI.label(root, "", 18)

	var field := HBoxContainer.new()
	field.alignment = BoxContainer.ALIGNMENT_CENTER
	field.add_theme_constant_override("separation", 24)
	root.add_child(field)

	var pbox := VBoxContainer.new()
	player_title = UI.label(pbox, "")
	pbox.add_child(_make_grid(0))
	field.add_child(pbox)

	var vs := UI.label(field, "VS", 28)
	vs.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var ebox := VBoxContainer.new()
	enemy_title = UI.label(ebox, "")
	ebox.add_child(_make_grid(1))
	field.add_child(ebox)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	root.add_child(bar)
	start_btn = UI.button(bar, "开始战斗", _on_start_pressed)
	tactics_btn = UI.button(bar, "编辑战术", open_rule_editor)
	restart_btn = UI.button(bar, "重新开始（重载数据）", _on_restart_pressed)
	reset_btn = UI.button(bar, "重置阵型", _on_reset_formation_pressed)
	speed_btn = UI.button(bar, "", _on_speed_pressed)
	skip_btn = UI.button(bar, "跳过演出", _on_skip_pressed)
	return_btn = UI.button(bar, "返回地图", _on_return_pressed)
	title_btn = UI.button(bar, "返回标题", _on_title_pressed)
	_update_speed_text()

	var bottom := HBoxContainer.new()
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.add_theme_constant_override("separation", 10)
	root.add_child(bottom)

	log_box = RichTextLabel.new()
	log_box.scroll_following = true
	log_box.selection_enabled = true
	log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.size_flags_stretch_ratio = 2.0
	log_box.add_theme_font_size_override("normal_font_size", 14)
	bottom.add_child(log_box)

	info_label = UI.label(bottom, "")
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL

	timer = Timer.new()
	timer.timeout.connect(advance_battle)
	add_child(timer)


## 3 列 × 2 排的格子。屏幕上每支小队显示为 3 行(列号) × 2 列(前/后排)，前排朝向对手。
func _make_grid(team: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	for c in 3:
		var order := [1, 0] if team == 0 else [0, 1]
		for r in order:
			var cell := UnitCell.new()
			cell.team = team
			cell.row = r
			cell.col = c
			cell.clicked.connect(_on_cell_clicked)
			g.add_child(cell)
			cells.append(cell)
	return g


# ---------------------------------------------------------------- 流程

func new_battle() -> void:
	timer.stop()
	var ok := true
	if is_map_mode():
		engine = map_model.create_battle(squad_a, squad_b)
	else:
		engine = BattleEngine.new()
		ok = engine.load_data(CLASSES_PATH, SETUP_PATH)
		_apply_saved_setup()
		engine.reset_battle(true)
	state = State.FORMATION
	selected_cell = null
	log_box.clear()
	_log("编队阶段：点击我方单位，再点击另一个格子即可交换位置。点击单位查看战术，「编辑战术」可修改。")
	_log("规则：近战只能打前排（前排全灭后才能打后排）；弓/魔法可打任意位置；后排使用近战伤害 ×0.75。")
	if is_map_mode():
		_log("地图遭遇战：HP 沿用地图上的状态，倒下的单位不会参战。")
	if not ok:
		_log("⚠ 数据校验有错误，请查看输出面板。")
	info_label.text = "点击任意单位查看战术规则。"
	_refresh()


func _apply_saved_setup() -> void:
	for u in engine.units:
		if u.team != 0:
			continue
		if saved_formation.has(u.display_name):
			var p: Vector2i = saved_formation[u.display_name]
			u.row = p.x
			u.col = p.y
		if saved_tactics.has(u.display_name):
			u.tactics = (saved_tactics[u.display_name] as Array).duplicate(true)


func _save_setup() -> void:
	for u in engine.units:
		if u.team == 0:
			saved_formation[u.display_name] = Vector2i(u.row, u.col)
			saved_tactics[u.display_name] = u.tactics.duplicate(true)


func _on_start_pressed() -> void:
	if state != State.FORMATION:
		return
	state = State.BATTLE
	_set_selected(null)
	_log("—— 战斗开始！——")
	timer.start(SPEEDS[speed_idx])
	_refresh()


func _on_restart_pressed() -> void:
	new_battle()


func _on_reset_formation_pressed() -> void:
	saved_formation.clear()
	saved_tactics.clear()
	new_battle()


func _on_speed_pressed() -> void:
	speed_idx = (speed_idx + 1) % SPEEDS.size()
	_update_speed_text()
	if not timer.is_stopped():
		timer.start(SPEEDS[speed_idx])


func _on_skip_pressed() -> void:
	if state == State.FORMATION:
		_on_start_pressed()
	var guard := 0
	while state == State.BATTLE and guard < 500:
		advance_battle()
		guard += 1


func _on_title_pressed() -> void:
	if ResourceLoader.exists("res://scenes/title.tscn"):
		get_tree().change_scene_to_file("res://scenes/title.tscn")


func _on_return_pressed() -> void:
	if state == State.DONE:
		finished.emit(engine.winner)


func _update_speed_text() -> void:
	speed_btn.text = "速度：%s" % ["慢", "中", "快"][speed_idx]


## 推进一步（计时器 / 跳过 / 无头测试都调用它）。
func advance_battle() -> void:
	if state != State.BATTLE:
		return
	for line in engine.step():
		_log(line)
	_update_highlights()
	if engine.finished:
		timer.stop()
		state = State.DONE
	_refresh()


func open_rule_editor(start_index: int = 0):
	if state != State.FORMATION:
		return null
	var mine: Array = engine.units.filter(func(u): return u.team == 0)
	var ed := RuleEditor.new()
	ed.setup(mine, engine.skills_db, engine.classes_db, start_index)
	ed.closed.connect(func(saved): _on_rules_closed(saved))
	add_child(ed)
	return ed


func _on_rules_closed(saved: bool) -> void:
	if saved:
		_log("战术已更新。")
		if not is_map_mode():
			_save_setup()
	_refresh()


func _on_cell_clicked(cell) -> void:
	if cell.unit != null:
		info_label.text = engine.describe_tactics(cell.unit)
	if state != State.FORMATION or cell.team != 0:
		return
	if selected_cell == null:
		if cell.unit != null:
			_set_selected(cell)
		return
	if selected_cell == cell:
		_set_selected(null)
		return
	var a = selected_cell.unit
	var b = cell.unit
	a.row = cell.row
	a.col = cell.col
	if b != null:
		b.row = selected_cell.row
		b.col = selected_cell.col
	if not is_map_mode():
		_save_setup()
	_log("阵型调整：%s → %s第%d格" % [a.display_name, "前排" if cell.row == 0 else "后排", cell.col + 1])
	_set_selected(null)
	_refresh()


func _set_selected(cell) -> void:
	if selected_cell != null:
		selected_cell.selected = false
		selected_cell.queue_redraw()
	selected_cell = cell
	if cell != null:
		cell.selected = true
		cell.queue_redraw()


# ---------------------------------------------------------------- 显示刷新

func _refresh() -> void:
	for cell in cells:
		cell.unit = engine.unit_at(cell.team, cell.row, cell.col)
		cell.tooltip_text = engine.describe_tactics(cell.unit) if cell.unit != null else ""
		if state == State.FORMATION:
			cell.highlight = Color(0, 0, 0, 0)
		cell.queue_redraw()
	player_title.text = "%s（我方 · 前排在右）" % engine.squad_names[0]
	enemy_title.text = "%s（敌方 · 前排在左）" % engine.squad_names[1]
	start_btn.disabled = state != State.FORMATION
	tactics_btn.disabled = state != State.FORMATION
	restart_btn.visible = not is_map_mode()
	reset_btn.visible = not is_map_mode()
	skip_btn.disabled = state == State.DONE
	return_btn.visible = is_map_mode()
	title_btn.visible = not is_map_mode() and get_parent() == get_tree().root
	return_btn.disabled = state != State.DONE
	match state:
		State.FORMATION:
			status_label.text = "【编队】调整阵型后点击「开始战斗」"
		State.BATTLE:
			status_label.text = "【战斗中】第 %d 轮" % engine.round_no
		State.DONE:
			var res := "平局"
			if engine.winner == 0:
				res = "胜利！"
			elif engine.winner == 1:
				res = "败北……"
			status_label.text = "【战斗结束】%s  %s" % [res, "点击「返回地图」" if is_map_mode() else "点击「重新开始」再来一局"]
	if engine != null and engine.first_strike_team >= 0 and state != State.DONE:
		status_label.text = "【先制攻击！%s 第一轮全员抢先行动】 " % ("我方" if engine.first_strike_team == 0 else "敌方") + status_label.text


func _update_highlights() -> void:
	for cell in cells:
		cell.highlight = Color(0, 0, 0, 0)
		if cell.unit == null:
			continue
		if cell.unit == engine.last_actor:
			cell.highlight = Color(0.3, 0.8, 1.0)
		elif engine.last_targets.has(cell.unit):
			cell.highlight = Color(1.0, 0.35, 0.3)


func _log(line: String) -> void:
	log_box.add_text(line + "\n")
