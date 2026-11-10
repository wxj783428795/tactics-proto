## 剧情对话：底部对话框 + 说话人色块头像。点击 / 空格 / 回车 推进，可跳过。
extends Control

const Game := preload("res://scripts/game.gd")
const UI := preload("res://scripts/ui_util.gd")

## 说话人颜色（原创角色）
const COLORS := {
	"凯岚": Color("#4aa3df"), "铎岩": Color("#7f8c8d"), "青翎": Color("#5cb85c"), "汐音": Color("#f0ad4e"),
	"寒栎": Color("#d9534f"), "绯鸢": Color("#e88fb0"), "焰朔": Color("#8e44ad"), "夜棠": Color("#6c5ce7"),
	"岳衡": Color("#16a085"), "落笙": Color("#e17055"), "柏翁": Color("#b8a07a"), "索格": Color("#922b21"),
}

var lines: Array = []
var index: int = 0
var next_scene: String = ""
var title_label: Label
var name_label: Label
var text_label: Label
var portrait: ColorRect
var portrait_char: Label
var page_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lines = Game.story_lines
	next_scene = Game.story_next if Game.story_next != "" else Game.SCENE_TITLE
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scenery := _Scenery.new()
	scenery.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scenery)
	title_label = UI.label(self, Game.story_title, 30)
	title_label.position = Vector2(40, 30)
	title_label.add_theme_color_override("font_color", Color(1, 0.92, 0.7))

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -230
	panel.offset_left = 40
	panel.offset_right = -40
	panel.offset_bottom = -30
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.16, 0.94)
	sb.border_color = Color(0.55, 0.6, 0.75)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	panel.add_child(hb)
	portrait = ColorRect.new()
	portrait.custom_minimum_size = Vector2(140, 140)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(portrait)
	portrait_char = UI.label(portrait, "", 64)
	portrait_char.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait_char.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_char.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	name_label = UI.label(vb, "", 22)
	text_label = UI.label(vb, "", 20)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var foot := HBoxContainer.new()
	vb.add_child(foot)
	page_label = UI.label(foot, "", 13)
	page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	var nb := UI.button(foot, "继续 >", advance)
	nb.focus_mode = Control.FOCUS_NONE
	var sk := UI.button(foot, "跳过", finish)
	sk.focus_mode = Control.FOCUS_NONE
	show_line()


func show_line() -> void:
	if index >= lines.size():
		return
	var l: Dictionary = lines[index]
	var who := str(l.get("who", ""))
	var narrator := who == "旁白"
	name_label.text = "" if narrator else who
	text_label.text = str(l.get("text", ""))
	text_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95) if narrator else Color(1, 1, 1))
	portrait.visible = not narrator
	var c: Color = COLORS.get(who, Color(0.45, 0.45, 0.5))
	portrait.color = c.darkened(0.15)
	portrait_char.text = who.substr(0, 1) if who != "???" else "?"
	name_label.add_theme_color_override("font_color", c.lightened(0.3))
	page_label.text = "%d / %d    点击 / 空格 继续" % [index + 1, lines.size()]


func advance() -> void:
	index += 1
	if index >= lines.size():
		finish()
	else:
		show_line()


func finish() -> void:
	index = lines.size()
	get_tree().change_scene_to_file(next_scene)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		advance()


class _Scenery extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		for i in 20:
			var t := float(i) / 20.0
			draw_rect(Rect2(0, h * t * 0.7, w, h * 0.7 / 20.0 + 1), Color(0.18, 0.22, 0.35).lerp(Color(0.55, 0.42, 0.38), t))
		draw_colored_polygon(PackedVector2Array([Vector2(0, h * 0.62), Vector2(w * 0.25, h * 0.45), Vector2(w * 0.45, h * 0.58),
			Vector2(w * 0.7, h * 0.42), Vector2(w, h * 0.56), Vector2(w, h), Vector2(0, h)]), Color(0.2, 0.24, 0.22))
		draw_rect(Rect2(0, h * 0.68, w, h * 0.32), Color(0.14, 0.18, 0.15))
		# 风车剪影
		var m := Vector2(w * 0.72, h * 0.5)
		draw_colored_polygon(PackedVector2Array([m + Vector2(-14, 80), m + Vector2(-8, 0), m + Vector2(8, 0), m + Vector2(14, 80)]), Color(0.1, 0.1, 0.12))
		for k in 4:
			var a := PI / 2.0 * k + 0.4
			draw_line(m, m + Vector2(cos(a), sin(a)) * 60, Color(0.1, 0.1, 0.12), 6)
