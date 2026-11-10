## 战役截图：xvfb-run godot --path . --rendering-driver opengl3 --resolution 1280x760 --script res://tests/screenshot_campaign.gd
extends SceneTree

const CampaignState := preload("res://scripts/campaign_state.gd")
const Progression := preload("res://scripts/progression.gd")
const Game := preload("res://scripts/game.gd")

var out_dir := ""


func shot(name: String) -> void:
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(out_dir + name)
	print("saved ", out_dir + name)


func clear_root() -> void:
	for c in root.get_children():
		c.queue_free()
	await process_frame


## 在大地图场景里按目标推进 sim_time 秒（遭遇自动结算，写入战况记录）
func run_map(ow, sim_time: float) -> void:
	var m = ow.model
	var target := ""
	match str(m.objective.get("type", "")):
		"capture_hq":
			target = m.hq_of(1)
		"defeat_boss":
			target = m.squad_by_id(str(m.objective["squad"])).home
	var squads: Array = m.living_squads(0)
	var t0: float = m.time
	while m.time - t0 < sim_time and not m.game_over:
		for k in squads.size():
			var sq = squads[k]
			if not sq.alive or sq.is_moving():
				continue
			if target != "" and k == 0:
				m.order_move(sq, target)
			elif k == 1 and m.nodes.has("farm"):
				m.order_move(sq, "farm" if m.nodes["farm"]["owner"] != 0 else "mill")
			elif k == 1 and m.nodes.has("well"):
				m.order_move(sq, "well")
			elif k == 1 and m.nodes.has("ruins"):
				m.order_move(sq, "ruins")
		for e in m.update(0.1):
			ow.log_event(e["text"])
		if not m.pending_encounter.is_empty():
			var a = m.pending_encounter[0]
			var b = m.pending_encounter[1]
			var r: Array = m.resolve_encounter_auto()
			ow.log_event("%s 与 %s 交战（自动结算）" % [a.name, b.name])
			for e in r[1]:
				ow.log_event(e["text"])
	ow.select_squad(squads[0])
	ow._refresh_hud()


func _initialize() -> void:
	out_dir = ProjectSettings.globalize_path("res://docs/")
	var st = CampaignState.new()
	st.new_game()
	Game.state = st

	var title = load("res://scenes/title.tscn").instantiate()
	root.add_child(title)
	await shot("campaign_title.png")
	await clear_root()

	Game.story_title = st.missions[0]["title"]
	Game.story_lines = st.missions[0]["pre_story"]
	Game.story_next = Game.SCENE_CAMP
	var story = load("res://scenes/story.tscn").instantiate()
	root.add_child(story)
	await process_frame
	story.advance()
	story.advance()
	await shot("campaign_story.png")
	await clear_root()

	var camp = load("res://scenes/camp.tscn").instantiate()
	root.add_child(camp)
	await shot("campaign_camp.png")
	camp.open_recruit()
	await shot("campaign_recruit.png")
	await clear_root()

	# 第一章（真实流程：默认等级，脚本指挥）
	st.current_mission = 0
	var ow = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(ow)
	await process_frame
	run_map(ow, 9.0)
	await shot("campaign_map1.png")
	run_map(ow, 600.0)
	if ow.model.game_over:
		ow._show_game_over()
	await shot("campaign_map1_end.png")
	Game.last_result = st.finish_mission(ow.model)
	await clear_root()
	var rs = load("res://scenes/results.tscn").instantiate()
	root.add_child(rs)
	await shot("campaign_results.png")
	await clear_root()

	# 部队管理：装备 + 转职
	var roster = load("res://scenes/roster.tscn").instantiate()
	root.add_child(roster)
	await process_frame
	st.equip("u_青翎", "singing_bow")
	st.equip("u_铎岩", "wayfarer_leather")
	st.equip("u_汐音", "votive_robe")
	roster.select_unit("u_青翎")
	await shot("campaign_roster_equip.png")
	var kl = st.unit_by_uid("u_凯岚")
	if kl.level < 5:
		Progression.gain_xp(kl, (5 - kl.level) * Progression.XP_PER_LEVEL, st.classes, st.items)
	roster.select_unit("u_凯岚")
	await shot("campaign_roster_promotable.png")
	roster.do_promote()
	await shot("campaign_promotion.png")
	await clear_root()

	# 第二、三章地图
	if not st.cleared.has("m1"):
		st.cleared.append("m1")
	st.current_mission = 1
	ow = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(ow)
	await process_frame
	run_map(ow, 45.0)
	await shot("campaign_map2.png")
	await clear_root()
	if not st.cleared.has("m2"):
		st.cleared.append("m2")
	st.current_mission = 2
	ow = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(ow)
	await process_frame
	run_map(ow, 8.0)
	await shot("campaign_map3.png")
	await clear_root()
	Game.state = null
	quit()
