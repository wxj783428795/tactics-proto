## 任务战报：胜负、金币、道具、经验与升级。
extends Control

const Game := preload("res://scripts/game.gd")
const UI := preload("res://scripts/ui_util.gd")

var res: Dictionary
var body: RichTextLabel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	res = Game.last_result
	if Game.state != null:
		Game.state.save()  # 任务结束自动存档
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var won: bool = res.get("won", false)
	var t := UI.label(root, "%s　%s" % [res.get("title", ""), "任务成功" if won else "任务失败"], 30)
	t.add_theme_color_override("font_color", Color(1, 0.85, 0.4) if won else Color(0.9, 0.5, 0.5))
	var tm := int(res.get("time", 0))
	UI.label(root, "%s　用时 %02d:%02d　战斗 胜 %d / 负 %d" % [res.get("reason", ""), tm / 60, tm % 60, int(res.get("battles_won", 0)), int(res.get("battles_lost", 0))], 16)
	var hb := HBoxContainer.new()
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hb.add_theme_constant_override("separation", 20)
	root.add_child(hb)
	var left := RichTextLabel.new()
	left.bbcode_enabled = true
	left.custom_minimum_size = Vector2(440, 0)
	left.add_theme_font_size_override("normal_font_size", 16)
	hb.add_child(left)
	var lt := ""
	if won:
		lt += "[color=#fd6]资金 +%d[/color]\n　据点收入与占领奖励 %d\n　战斗战利金 %d\n　任务奖励 %d%s\n\n" % [int(res["gold_total"]), int(res["gold_bases"]), int(res["gold_battles"]), int(res["gold_reward"]), "" if res.get("first_clear", false) else "（重玩不再发放）"]
		lt += "[color=#fd6]获得道具[/color]\n　%s\n\n" % ("、".join(PackedStringArray(res.get("items", []))) if not res.get("items", []).is_empty() else "无")
		if not res.get("joined", []).is_empty():
			lt += "[color=#8f8]新成员加入[/color]\n　%s\n\n" % "、".join(PackedStringArray(res["joined"]))
	else:
		lt += "未能完成目标。获得的经验会保留，资金与道具不会带回。\n可以在营地调整编成、装备与战术后再次挑战。\n\n"
	lt += "[color=#fd6]当前资金[/color] %d 金" % (Game.state.gold if Game.state != null else 0)
	left.text = lt
	body = RichTextLabel.new()
	body.bbcode_enabled = true
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("normal_font_size", 15)
	hb.add_child(body)
	var bt := "[color=#9cf]经验[/color]\n"
	for x in res.get("xp", []):
		bt += "　%s（%s Lv%d）+%d\n" % [x["name"], x["job"], int(x["level"]), int(x["xp"])]
	bt += "\n[color=#9cf]成长记录[/color]\n"
	var prog: Array = Array(res.get("progress", []))
	if prog.is_empty():
		bt += "　（本次没有人升级）\n"
	for l in prog:
		bt += "　" + str(l) + "\n"
	body.text = bt
	var b := UI.button(root, "继续", continue_on)
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 20)


func continue_on() -> void:
	var i := int(res.get("mission", -1))
	if res.get("won", false) and res.get("first_clear", false) and Game.state != null and i >= 0:
		var m: Dictionary = Game.state.missions[i]
		Game.play_story(get_tree(), m["title"] + "　终", m.get("post_story", []), Game.SCENE_CAMP)
	else:
		get_tree().change_scene_to_file(Game.SCENE_CAMP)
