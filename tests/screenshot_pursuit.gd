## 追击截图：xvfb-run godot --path . --rendering-driver opengl3 --resolution 1280x760 --script res://tests/screenshot_pursuit.gd
extends SceneTree

const Game := preload("res://scripts/game.gd")


func _initialize() -> void:
	Game.state = null
	var ow = load("res://scenes/overworld.tscn").instantiate()
	ow.save_path = "user://_shot_unused.json"
	root.add_child(ow)
	await process_frame
	var m = ow.model
	m.ai_enabled = false
	var dawn = m.squad_by_id("dawn")
	var crow = m.squad_by_id("crow")
	crow.at_node = "north_village"
	crow.pos = m.nodes["north_village"]["pos"]
	m.order_move(crow, "crow_tower")
	ow.select_squad(dawn)
	await process_frame
	await process_frame
	ow._on_map_clicked(ow.canvas.draw_positions[crow], MOUSE_BUTTON_LEFT)
	for i in 30:
		crow.stamina = 0.0
		for e in m.update(0.1):
			ow.log_event(e["text"])
	ow.paused = true
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://docs/pursuit.png"))
	print("saved docs/pursuit.png")
	quit()
