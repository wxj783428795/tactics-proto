## 新职业截图：xvfb-run godot --path . --rendering-driver opengl3 --script res://tests/screenshot_classes.gd
extends SceneTree

var out_dir := ""


func shot(name: String) -> void:
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(out_dir + name)
	print("saved ", out_dir + name)


func _initialize() -> void:
	out_dir = ProjectSettings.globalize_path("res://docs/")
	var bv = load("res://scenes/battle_test.tscn").instantiate()
	root.add_child(bv)
	await process_frame
	bv._on_start_pressed()
	for i in 13:
		bv.advance_battle()
	await shot("battle_new_classes.png")
	bv._on_restart_pressed()
	await process_frame
	var ed = bv.open_rule_editor(1)  # 枪兵
	await shot("rule_editor_spearman.png")
	ed._unit_select.select(5)
	ed.current = 5  # 吟游者
	ed._rebuild()
	await shot("rule_editor_bard.png")
	ed._on_cancel()
	quit()
