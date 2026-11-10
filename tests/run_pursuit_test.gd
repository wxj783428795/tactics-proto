## 追击测试：godot --headless --path . --script res://tests/run_pursuit_test.gd
## 覆盖：同一道路迎面、目标沿另一条路离开（重新寻路）、目标在道路中间、目标消失取消、新命令取消、与战后整备的配合、界面点击。
extends SceneTree

const MapModel := preload("res://scripts/map_model.gd")
const Game := preload("res://scripts/game.gd")

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  [OK] ", msg)
	else:
		failures += 1
		printerr("  [FAIL] ", msg)


func new_model(keep: Array) -> MapModel:
	var m := MapModel.new()
	m.load_campaign("res://data/campaign.json", "res://data/classes.json")
	m.ai_enabled = false
	for sq in m.living_squads(1):
		if not keep.has(sq.id):
			sq.alive = false
	return m


func place(m: MapModel, sq, node: String) -> void:
	sq.at_node = node
	sq.pos = m.nodes[node]["pos"]
	sq.path = []


## 推进直到发生遭遇或超时，返回用时
func run_to_encounter(m: MapModel, max_t: float, ev: Array = []) -> float:
	var t0: float = m.time
	while m.pending_encounter.is_empty() and m.time - t0 < max_t:
		ev.append_array(m.update(0.1))
	return m.time - t0


func _initialize() -> void:
	print("=== 1. 同一条路迎面追击 ===")
	var m := new_model(["sand"])
	var dawn = m.squad_by_id("dawn")
	var sand = m.squad_by_id("sand")
	place(m, dawn, "P_HQ")
	place(m, sand, "ford")
	m.order_move(sand, "P_HQ")
	m.update(0.5)
	check(m.order_pursue(dawn, sand), "下达追击命令")
	check(dawn.pursue_target == sand and dawn.path == ["ford"], "沿同一条路朝目标那一端前进：%s" % str(dawn.path))
	var t1 := run_to_encounter(m, 20.0)
	check(m.pending_encounter == [dawn, sand], "%.1f 秒后迎面接触，触发遭遇" % t1)
	var mid: Vector2 = dawn.pos
	check(mid.x > m.nodes["P_HQ"]["pos"].x + 40 and mid.x < m.nodes["ford"]["pos"].x - 40, "在道路中间相遇（x=%.0f）" % mid.x)

	print("=== 2. 目标沿另一条路离开：重新寻路 ===")
	var m2 := new_model(["crow"])
	var d2 = m2.squad_by_id("dawn")
	var c2 = m2.squad_by_id("crow")
	place(m2, d2, "P_HQ")
	place(m2, c2, "north_village")
	c2.stamina = 0.0  # 疲劳：目标移动较慢
	m2.order_move(c2, "crow_tower")  # 经 r3 向东北离开
	m2.order_pursue(d2, c2)
	var dests := {}
	var heads := {}
	var t2 := 0.0
	while m2.pending_encounter.is_empty() and t2 < 60.0:
		m2.update(0.1)
		t2 += 0.1
		c2.stamina = 0.0
		if d2.is_moving():
			dests[d2.destination()] = true
			heads[d2.path[0]] = true
	print("    追击方经过的路线终点：", dests.keys())
	check(dests.size() >= 2, "随着目标换路，追击路线的终点改变了 %d 次" % (dests.size() - 1))
	check(dests.has("r3") or dests.has("crow_tower"), "追到了目标离开的那条路（r3 / 鸦巢塔方向）")
	check(m2.pending_encounter.size() == 2 and m2.pending_encounter[1] == c2, "%.1f 秒后追上目标并遭遇" % t2)

	print("=== 3. 目标在道路中间 ===")
	var m3 := new_model(["crow"])
	var d3 = m3.squad_by_id("dawn")
	var c3 = m3.squad_by_id("crow")
	place(m3, d3, "north_village")
	place(m3, c3, "ford")
	m3.order_move(c3, "windmill")
	c3.pos = m3.nodes["ford"]["pos"] + Vector2(40, 0)  # 白石渡 → 风车丘 的路上
	c3.stamina = 0.0
	m3.order_pursue(d3, c3)
	check(d3.path == ["ford", "windmill"], "先到目标所在道路较近的一端（白石渡），再沿路走向另一端：%s" % str(d3.path))
	var t3 := 0.0
	while m3.pending_encounter.is_empty() and t3 < 30.0:
		m3.update(0.1)
		t3 += 0.1
		c3.stamina = 0.0
	var on_edge: bool = not m3.edge_of(c3).is_empty()
	check(m3.pending_encounter.size() == 2 and on_edge, "在道路中间追上目标（目标 x=%.0f，%.1f 秒）" % [c3.pos.x, t3])
	var m3b := new_model(["crow"])
	var d3b = m3b.squad_by_id("dawn")
	var c3b = m3b.squad_by_id("crow")
	place(m3b, d3b, "ford")
	place(m3b, c3b, "ford")
	m3b.order_move(c3b, "windmill")
	c3b.pos = m3b.nodes["ford"]["pos"] + Vector2(80, 0)
	c3b.stamina = 0.0
	m3b.order_move(d3b, "windmill")
	m3b.update(0.2)  # 追击方也已在这条路上
	m3b.order_pursue(d3b, c3b)
	check(d3b.path == ["windmill"] and d3b.at_node == "ford", "已在同一条路上：直接朝目标一侧的端点前进")
	run_to_encounter(m3b, 20.0)
	check(m3b.pending_encounter.size() == 2, "同路追上目标")

	print("=== 4. 目标消失：取消追击并停下 ===")
	var m4 := new_model(["crow"])
	var d4 = m4.squad_by_id("dawn")
	var c4 = m4.squad_by_id("crow")
	place(m4, d4, "P_HQ")
	place(m4, c4, "windmill")
	m4.order_pursue(d4, c4)
	for i in 10:
		m4.update(0.1)
	c4.alive = false  # 被别的小队消灭 / 溃散
	var ev4 := m4.update(0.1)
	check(d4.pursue_target == null and ev4.any(func(e): return e["type"] == "pursuit_lost"), "目标消失：取消追击并记录：" + str(ev4.map(func(e): return e["text"])))
	var p4: Vector2 = d4.pos
	for i in 30:
		m4.update(0.1)
	check(not d4.is_moving() and m4.node_of(d4) != "", "停在最近的节点「%s」，不再前进" % m4.node_of(d4))
	check(not m4.order_pursue(d4, c4), "不能追击已消失的小队")
	check(not m4.order_pursue(d4, m4.squad_by_id("wolf")), "不能追击我方小队")

	print("=== 5. 新命令取消追击 ===")
	var m5 := new_model(["crow"])
	var d5 = m5.squad_by_id("dawn")
	var c5 = m5.squad_by_id("crow")
	place(m5, d5, "P_HQ")
	place(m5, c5, "windmill")
	m5.order_pursue(d5, c5)
	m5.update(0.5)
	m5.order_move(d5, "north_village")
	check(d5.pursue_target == null and d5.destination() == "north_village", "改为行军命令后不再追击")
	for i in 10:
		m5.update(0.1)
	check(d5.destination() == "north_village", "后续重新寻路不会改回追击路线")
	m5.order_pursue(d5, c5)
	m5.stop(d5)
	check(d5.pursue_target == null, "原地停止也会取消追击")

	print("=== 6. 与战后整备的配合 ===")
	var m6 := new_model(["sand"])
	var d6 = m6.squad_by_id("dawn")
	var s6 = m6.squad_by_id("sand")
	place(m6, d6, "P_HQ")
	place(m6, s6, "windmill")
	m6.order_pursue(d6, s6)
	run_to_encounter(m6, 30.0)
	check(m6.pending_encounter.size() == 2, "第一次接触")
	m6.apply_battle_result(d6, s6, 0)  # 我方获胜，目标被击退
	check(d6.pursue_target == s6 and d6.is_recovering(), "胜方整备中，追击命令保留")
	var p6: Vector2 = d6.pos
	var enc6 := 0
	var t6 := 0.0
	while t6 < MapModel.RECOVER_TIME - 0.1:
		m6.update(0.1)
		t6 += 0.1
		if not m6.pending_encounter.is_empty():
			enc6 += 1
			m6.pending_encounter = []
	check(enc6 == 0 and d6.pos == p6, "整备期间不移动、不算接触")
	var t6b := run_to_encounter(m6, 30.0)
	check(m6.pending_encounter.size() == 2 and m6.pending_encounter[1] == s6, "整备结束后继续追击，%.1f 秒后再次接触" % t6b)
	var ev6 := m6.apply_battle_result(d6, s6, 1)  # 这次我方战败
	check(d6.pursue_target == null and ev6.any(func(e): return e["type"] == "pursuit_lost"), "追击方战败：中止追击并被击退")

	print("=== 7. 目标躲进有守军的据点：继续追击并照常攻城 ===")
	var m7 := new_model(["ash"])
	var d7 = m7.squad_by_id("dawn")
	var a7 = m7.squad_by_id("ash")
	place(m7, d7, "r5")
	m7.order_pursue(d7, a7)
	run_to_encounter(m7, 20.0)
	m7.apply_battle_result(d7, a7, 0)
	check(m7.nodes["E_HQ"]["durability"] < 100.0 and a7.stunned, "接触后按攻城处理：耐久 %d，守军硬直" % int(m7.nodes["E_HQ"]["durability"]))

	print("=== 8. 界面：点击敌方小队下达追击 ===")
	Game.state = null
	var ow = load("res://scenes/overworld.tscn").instantiate()
	ow.save_path = "user://_pursuit_test_unused.json"
	root.add_child(ow)
	await process_frame
	ow.paused = true
	var od = ow.model.squad_by_id("dawn")
	var oc = ow.model.squad_by_id("crow")
	ow.select_squad(od)
	ow.canvas.queue_redraw()
	await process_frame
	await process_frame
	ow._on_map_clicked(ow.canvas.draw_positions[oc], MOUSE_BUTTON_LEFT)
	check(od.pursue_target == oc and ow.selected == od, "选中我方小队后左键点敌方：追击，选中不变")
	ow._refresh_hud()
	check(ow.info.text.contains("追击：" + oc.name), "信息栏显示「%s」" % ow.info.text.split("\n")[1])
	var ow_wolf = ow.model.squad_by_id("wolf")
	ow._on_map_clicked(ow.canvas.draw_positions[ow_wolf], MOUSE_BUTTON_LEFT)
	check(ow.selected == ow_wolf and od.pursue_target == oc, "左键点我方小队：切换选中，不影响原追击")
	ow._on_map_clicked(ow.canvas.draw_positions[oc], MOUSE_BUTTON_RIGHT)
	check(ow.selected == oc and ow_wolf.pursue_target == null, "右键点敌方小队：只查看")
	ow.queue_free()
	await process_frame

	print("=== 结果：%s（失败 %d 项）===" % ["全部通过" if failures == 0 else "有失败", failures])
	quit(1 if failures > 0 else 0)
