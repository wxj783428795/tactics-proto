## 标题画面：新游戏 / 继续 / 快速战斗 / 沙盒地图
extends Control

const Game := preload("res://scripts/game.gd")
const CampaignState := preload("res://scripts/campaign_state.gd")
const UI := preload("res://scripts/ui_util.gd")

var continue_btn: Button
var message: Label
var save_path: String = CampaignState.SAVE_PATH


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := _TitleArt.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(360, 0)
	center.add_child(box)
	var t := UI.label(box, "晨星战旗", 56)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	var sub := UI.label(box, "苇河平原的佣兵们", 20)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	box.add_child(_spacer(24))
	_big(UI.button(box, "新游戏", new_game))
	continue_btn = _big(UI.button(box, "继续", continue_game))
	_big(UI.button(box, "快速战斗", func(): get_tree().change_scene_to_file(Game.SCENE_QUICK)))
	_big(UI.button(box, "沙盒地图", open_sandbox))
	message = UI.label(box, "", 14)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ver := UI.label(self, "原创原型 · Godot 4.3 · 所有角色与剧情均为原创", 12)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	ver.position += Vector2(12, -24)
	refresh()


func refresh() -> void:
	continue_btn.disabled = not CampaignState.has_save(save_path)
	continue_btn.tooltip_text = "" if not continue_btn.disabled else "还没有存档"


func _big(b: Button) -> Button:
	b.custom_minimum_size = Vector2(320, 46)
	b.add_theme_font_size_override("font_size", 20)
	return b


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func new_game() -> void:
	var st = CampaignState.new()
	if not st.new_game():
		message.text = "战役数据加载失败"
		return
	Game.state = st
	st.save(save_path)
	Game.play_story(get_tree(), "序章　晨星营", st.prologue, Game.SCENE_CAMP)


func continue_game() -> void:
	var st = CampaignState.new()
	if not st.load_save(save_path):
		message.text = "存档读取失败"
		return
	Game.state = st
	get_tree().change_scene_to_file(Game.SCENE_CAMP)


func open_sandbox() -> void:
	Game.state = null
	get_tree().change_scene_to_file(Game.SCENE_MAP)


## 用简单几何图形画的标题背景：夜空、星、远山、河流、旗帜
class _TitleArt extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		for i in 24:
			var t := float(i) / 24.0
			draw_rect(Rect2(0, h * t, w, h / 24.0 + 1), Color(0.05, 0.07, 0.16).lerp(Color(0.32, 0.2, 0.3), t))
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 90:
			var p := Vector2(rng.randf() * w, rng.randf() * h * 0.55)
			draw_circle(p, rng.randf_range(0.8, 2.2), Color(1, 1, 0.9, rng.randf_range(0.3, 0.9)))
		# 晨星
		var star := Vector2(w * 0.78, h * 0.18)
		var pts := PackedVector2Array()
		for i in 8:
			var r := 34.0 if i % 2 == 0 else 8.0
			var a := PI / 4.0 * i - PI / 2.0
			pts.append(star + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, Color(1, 0.95, 0.75))
		draw_circle(star, 60, Color(1, 0.9, 0.6, 0.08))
		# 远山
		draw_colored_polygon(PackedVector2Array([Vector2(0, h * 0.72), Vector2(w * 0.18, h * 0.5), Vector2(w * 0.35, h * 0.68),
			Vector2(w * 0.55, h * 0.46), Vector2(w * 0.8, h * 0.66), Vector2(w, h * 0.54), Vector2(w, h), Vector2(0, h)]), Color(0.12, 0.12, 0.2))
		draw_colored_polygon(PackedVector2Array([Vector2(0, h * 0.82), Vector2(w * 0.3, h * 0.7), Vector2(w * 0.6, h * 0.8),
			Vector2(w, h * 0.72), Vector2(w, h), Vector2(0, h)]), Color(0.08, 0.1, 0.13))
		# 河
		draw_colored_polygon(PackedVector2Array([Vector2(w * 0.42, h), Vector2(w * 0.5, h * 0.84), Vector2(w * 0.62, h * 0.78),
			Vector2(w * 0.66, h * 0.79), Vector2(w * 0.56, h * 0.86), Vector2(w * 0.52, h)]), Color(0.25, 0.35, 0.55, 0.8))
		# 旗帜
		var base := Vector2(w * 0.16, h * 0.86)
		draw_line(base, base + Vector2(0, -150), Color(0.8, 0.75, 0.6), 4)
		draw_colored_polygon(PackedVector2Array([base + Vector2(2, -150), base + Vector2(90, -132), base + Vector2(2, -108)]), Color(0.29, 0.64, 0.87))
		draw_circle(base + Vector2(30, -130), 6, Color(1, 0.95, 0.75))
