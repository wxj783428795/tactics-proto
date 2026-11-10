## 阵型格子：用色块 + HP 条绘制一个单位（或空位）。点击会发出 clicked 信号。
extends Control

signal clicked(cell)

var team: int = 0
var row: int = 0
var col: int = 0
var unit = null              # BattleUnit 或 null
var selected: bool = false   # 编队时被选中
var highlight: Color = Color(0, 0, 0, 0)  # 行动者/受击高亮


func _init() -> void:
	custom_minimum_size = Vector2(170, 92)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)


func _draw() -> void:
	var font := get_theme_default_font()
	var fs := 14
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.13, 0.14, 0.18))
	draw_rect(r, Color(0.35, 0.37, 0.45), false, 1.0)
	# 排位提示
	var tag := "前排" if row == 0 else "后排"
	draw_string(font, Vector2(size.x - 34, size.y - 6), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.52, 0.6))

	if unit == null:
		draw_string(font, Vector2(10, size.y * 0.5 + 5), "（空）", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.45, 0.47, 0.55))
	else:
		var alive: bool = unit.is_alive()
		var c: Color = unit.color if alive else Color(0.3, 0.3, 0.3)
		draw_rect(Rect2(8, 8, 30, 30), c)  # 单位色块
		if not alive:
			draw_line(Vector2(8, 8), Vector2(38, 38), Color(0.8, 0.2, 0.2), 2.0)
			draw_line(Vector2(38, 8), Vector2(8, 38), Color(0.8, 0.2, 0.2), 2.0)
		var txt_col := Color(0.95, 0.95, 0.95) if alive else Color(0.5, 0.5, 0.5)
		draw_string(font, Vector2(46, 22), unit.display_name, HORIZONTAL_ALIGNMENT_LEFT, size.x - 50, fs, txt_col)
		draw_string(font, Vector2(46, 38), "%s  速%d" % [unit.job_name, unit.eff_spd()], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.72, 0.8))
		var st: String = unit.status_text()
		if st != "" and alive:
			draw_string(font, Vector2(size.x - 70, 38), st, HORIZONTAL_ALIGNMENT_RIGHT, 64, 11, Color(1.0, 0.8, 0.4))
		# HP 条
		var bar := Rect2(8, 46, size.x - 16, 10)
		draw_rect(bar, Color(0.25, 0.08, 0.08))
		var ratio: float = unit.hp_ratio()
		var hp_col := Color(0.3, 0.85, 0.35) if ratio > 0.5 else (Color(0.95, 0.75, 0.2) if ratio > 0.25 else Color(0.95, 0.3, 0.25))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), hp_col)
		draw_string(font, Vector2(8, 72), "HP %d/%d" % [unit.hp, unit.max_hp], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, txt_col)
		# 锐气 ● / 守势 ◆
		var pips := "锐" + "●".repeat(unit.ep) + "○".repeat(max(0, unit.max_ep - unit.ep))
		if unit.max_gp > 0:
			pips += " 守" + "◆".repeat(unit.gp) + "◇".repeat(max(0, unit.max_gp - unit.gp))
		draw_string(font, Vector2(8, 87), pips, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.8, 1.0))

	if highlight.a > 0.0:
		draw_rect(r.grow(-2), highlight, false, 3.0)
	if selected:
		draw_rect(r.grow(-1), Color(1, 0.9, 0.2), false, 3.0)
