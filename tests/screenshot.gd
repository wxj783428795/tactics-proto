## 截图工具（需要图形环境，非无头）：
##   xvfb-run godot --path . --rendering-driver opengl3 --script res://tests/screenshot.gd
## 输出到 docs/ 目录。
extends SceneTree

var out_dir := ""


func shot(name: String) -> void:
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(out_dir + name)
	print("saved ", out_dir + name)


func _initialize() -> void:
	out_dir = ProjectSettings.globalize_path("res://docs/")
	DisplayServer.window_set_size(Vector2i(1280, 760))
	var ow = load("res://scenes/overworld.tscn").instantiate()
	ow.save_path = "user://screenshot_tmp.json"
	root.add_child(ow)
	await process_frame
	# 推进一段时间：派出两支小队，让敌方 AI 动起来
	ow.select_squad(ow.model.squad_by_id("wolf"))
	ow.command_move("north_village")
	ow.select_squad(ow.model.squad_by_id("silver"))
	ow.command_move("reed_fort")
	ow.select_squad(ow.model.squad_by_id("dawn"))
	ow.command_move("windmill")
	for i in 330:
		ow.process_map(0.1)
		if ow.overlay != null:
			break
	if ow.overlay == null:
		ow.paused = true
	await shot("map.png")
	if ow.overlay != null:
		await shot("map_battle.png")
		ow.overlay._on_skip_pressed()
		await shot("map_battle_done.png")
		ow.overlay._on_return_pressed()
		await process_frame
		ow.paused = true
		await shot("map_after_battle.png")
	ow.select_squad(ow.model.squad_by_id("dawn"))
	var ed = ow.open_rule_editor(2)
	await shot("rule_editor.png")
	ed._on_cancel()
	await process_frame
	ow.open_formation_editor()
	await shot("formation_editor.png")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://screenshot_tmp.json"))
	quit()
