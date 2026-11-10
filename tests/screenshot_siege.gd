## 攻城截图（耐久条 + 战后整备圈）：xvfb-run godot --path . --rendering-driver opengl3 --resolution 1280x760 --script res://tests/screenshot_siege.gd
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
	for sq in m.living_squads(1):
		if sq.id != "ash":
			sq.alive = false
	var dawn = m.squad_by_id("dawn")
	dawn.at_node = "r5"
	dawn.pos = m.nodes["r5"]["pos"]
	m.order_move(dawn, "E_HQ")
	var battles := 0
	while battles < 1 and m.time < 60.0:
		for e in m.update(0.1):
			ow.log_event(e["text"])
		if not m.pending_encounter.is_empty():
			var r: Array = m.resolve_encounter_auto()
			for e in r[1]:
				ow.log_event(e["text"])
			battles += 1
	for i in 10:
		m.update(0.1)
	ow.paused = true
	ow.select_squad(dawn)
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://docs/siege_durability.png"))
	print("saved docs/siege_durability.png")
	quit()
