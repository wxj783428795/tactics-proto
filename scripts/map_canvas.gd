## 大地图绘制：道路、据点、小队、选中路线。点击发出 clicked(局部坐标, 鼠标键)。
extends Control

signal clicked(pos: Vector2, button: int)

const OWNER_COLORS := {-1: Color(0.55, 0.55, 0.58), 0: Color(0.29, 0.64, 1.0), 1: Color(0.95, 0.36, 0.3)}
const STACK_OFFSETS := [Vector2(0, 0), Vector2(18, -14), Vector2(-18, -14), Vector2(18, 14), Vector2(-18, 14), Vector2(0, 22)]

var model = null
var selected = null
var draw_positions: Dictionary = {}   # squad -> 绘制位置（叠放时会偏移），用于点击判定


func _init() -> void:
	custom_minimum_size = Vector2(920, 640)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		clicked.emit(event.position, event.button_index)


func squad_at(p: Vector2, radius: float = 14.0):
	var best = null
	var bd := radius
	for sq in draw_positions:
		var d: float = p.distance_to(draw_positions[sq])
		if d < bd:
			bd = d
			best = sq
	return best


func _is_pursued(sq) -> bool:
	for o in model.squads:
		if o.alive and o.team == 0 and o.pursue_target == sq:
			return true
	return false


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.22, 0.17))
	if model == null:
		return
	var font := get_theme_default_font()
	# 道路
	for e in model.edges:
		draw_line(model.nodes[e[0]]["pos"], model.nodes[e[1]]["pos"], Color(0.45, 0.38, 0.26), 7.0, true)
	# 选中小队的追击路线：红色虚线，终点连到目标当前位置
	if selected != null and selected.alive and selected.pursue_target != null and selected.pursue_target.alive:
		var pts2 := PackedVector2Array([selected.pos])
		for id in selected.path:
			pts2.append(model.nodes[id]["pos"])
		if pts2.size() > 1:
			pts2.remove_at(pts2.size() - 1)  # 路线最后一段换成直接指向目标
		pts2.append(selected.pursue_target.pos)
		for i in range(1, pts2.size()):
			draw_dashed_line(pts2[i - 1], pts2[i], Color(1, 0.25, 0.2, 0.95), 3.0, 10.0)
	# 选中小队的行军路线
	elif selected != null and selected.alive and selected.is_moving():
		var pts := PackedVector2Array([selected.pos])
		for id in selected.path:
			pts.append(model.nodes[id]["pos"])
		draw_polyline(pts, Color(1, 0.9, 0.3, 0.8), 3.0, true)
	# 节点
	for id in model.node_ids:
		var n: Dictionary = model.nodes[id]
		var p: Vector2 = n["pos"]
		var col: Color = OWNER_COLORS[n["owner"]]
		match n["type"]:
			"road":
				draw_circle(p, 5.0, Color(0.6, 0.52, 0.38))
			"base":
				draw_circle(p, 15.0, col)
				draw_arc(p, 15.0, 0, TAU, 24, Color(0.1, 0.1, 0.1), 2.0)
			"fort":
				draw_rect(Rect2(p - Vector2(15, 15), Vector2(30, 30)), col)
				draw_rect(Rect2(p - Vector2(15, 15), Vector2(30, 30)), Color(0.1, 0.1, 0.1), false, 2.0)
			"hq":
				draw_rect(Rect2(p - Vector2(22, 22), Vector2(44, 44)), col)
				draw_rect(Rect2(p - Vector2(22, 22), Vector2(44, 44)), Color(1, 0.85, 0.3), false, 3.0)
		if n["name"] != "":
			draw_string(font, p + Vector2(-30, 40), n["name"], HORIZONTAL_ALIGNMENT_CENTER, 60, 13, Color(0.92, 0.92, 0.85))
		if n.get("max_durability", 0) > 0:
			# 耐久条（据点上方）
			var frac_d: float = n["durability"] / float(n["max_durability"])
			var top := p + Vector2(-22, -36 if n["type"] == "hq" else -28)
			draw_rect(Rect2(top, Vector2(44, 6)), Color(0.1, 0.1, 0.1))
			draw_rect(Rect2(top, Vector2(44 * frac_d, 6)), Color(0.95, 0.8, 0.3).lerp(Color(0.95, 0.3, 0.2), 1.0 - frac_d))
			draw_rect(Rect2(top, Vector2(44, 6)), Color(0, 0, 0), false, 1.0)
		if n["capture_team"] >= 0:
			var frac: float = n["capture_progress"] / model.CAPTURE_TIME
			draw_arc(p, 26.0, -PI / 2, -PI / 2 + TAU * frac, 32, OWNER_COLORS[n["capture_team"]], 5.0)
	# 小队（同一位置的小队错开绘制）
	draw_positions.clear()
	var stacks := {}
	for sq in model.squads:
		if not sq.alive:
			continue
		var key := Vector2i(roundi(sq.pos.x / 6.0), roundi(sq.pos.y / 6.0))
		var idx: int = stacks.get(key, 0)
		stacks[key] = idx + 1
		var dp: Vector2 = sq.pos + STACK_OFFSETS[idx % STACK_OFFSETS.size()]
		draw_positions[sq] = dp
		var border := Color.WHITE if sq.team == 0 else Color.BLACK
		if sq.team == 0:
			draw_circle(dp, 10.0, sq.color)
		else:
			draw_colored_polygon(PackedVector2Array([dp + Vector2(0, -12), dp + Vector2(11, 9), dp + Vector2(-11, 9)]), sq.color)
		draw_arc(dp, 11.0, 0, TAU, 20, border, 1.5)
		if sq == selected:
			draw_arc(dp, 16.0, 0, TAU, 24, Color(1, 0.9, 0.2), 3.0)
		if _is_pursued(sq):
			# 追击目标标记：红色准星
			var rc2 := Color(1, 0.25, 0.2)
			draw_arc(dp, 19.0, 0, TAU, 28, rc2, 2.0)
			for k in 4:
				var dir := Vector2.from_angle(PI / 2.0 * k)
				draw_line(dp + dir * 14.0, dp + dir * 25.0, rc2, 2.0)
		if sq.is_recovering():
			# 倒计时圈：胜方整备为白色；败方待机为橙色（据点内硬直为紫色），并标注「待机」
			var full: float = model.WAIT_TIME if sq.waiting else model.RECOVER_TIME
			var rf: float = clampf(sq.recover_time / full, 0.0, 1.0)
			var rc := Color(0.85, 0.95, 1.0)
			if sq.waiting:
				rc = Color(0.75, 0.45, 1.0) if sq.stunned else Color(1.0, 0.6, 0.2)
			draw_arc(dp, 20.0, -PI / 2, -PI / 2 + TAU * rf, 28, rc, 3.0)
			draw_string(font, dp + Vector2(14, -10), "%.0f" % ceil(sq.recover_time), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, rc)
			if sq.waiting:
				draw_string(font, dp + Vector2(-40, 0), "待机", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, rc)
		# 叠放时名字上下交替，避免重叠
		var name_y := -16.0 if idx % 2 == 0 else 32.0
		draw_string(font, dp + Vector2(-40, name_y), sq.name, HORIZONTAL_ALIGNMENT_CENTER, 80, 12, Color.WHITE)
		if sq.max_morale > 0:
			# 首领士气条（紫红色），在名字上方
			var my := name_y - 18.0 if name_y < 0 else -30.0
			draw_rect(Rect2(dp + Vector2(-18, my), Vector2(36, 5)), Color(0.15, 0.15, 0.15))
			draw_rect(Rect2(dp + Vector2(-18, my), Vector2(36 * sq.morale / float(sq.max_morale), 5)), Color(0.9, 0.3, 0.75))
			draw_string(font, dp + Vector2(20, my + 6), "士气%d" % int(ceil(sq.morale)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.95, 0.6, 0.9))
		# 体力条
		draw_rect(Rect2(dp + Vector2(-14, 14), Vector2(28, 4)), Color(0.15, 0.15, 0.15))
		draw_rect(Rect2(dp + Vector2(-14, 14), Vector2(28 * sq.stamina / 100.0, 4)), Color(0.95, 0.85, 0.3))
