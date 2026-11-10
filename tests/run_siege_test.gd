## 战后处理 / 攻城测试：godot --headless --path . --script res://tests/run_siege_test.gd
## 覆盖：攻打大本营反复触发战斗的回归、击退、战后整备、耐久、溃退、平局、耐久恢复、据点内回复、AI。
extends SceneTree

const MapModel := preload("res://scripts/map_model.gd")

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  [OK] ", msg)
	else:
		failures += 1
		printerr("  [FAIL] ", msg)


func new_model() -> MapModel:
	var m := MapModel.new()
	m.load_campaign("res://data/campaign.json", "res://data/classes.json")
	m.ai_enabled = false
	return m


func place(m: MapModel, sq, node: String) -> void:
	sq.at_node = node
	sq.pos = m.nodes[node]["pos"]
	sq.path = []


## 只留下 keep 中的敌方小队
func only_enemies(m: MapModel, keep: Array) -> void:
	for sq in m.living_squads(1):
		if not keep.has(sq.id):
			sq.alive = false


func buff(sq, lv: int) -> void:
	for u in sq.units:
		u.level = lv
		u.apply_class(_classes[u.class_id], {})
		u.hp = u.max_hp


var _classes: Dictionary


func _initialize() -> void:
	_classes = new_model().classes_db

	print("=== 1. 回归：攻打敌方大本营不会连续触发战斗（强制我方每战获胜）===")
	var m := new_model()
	only_enemies(m, ["ash"])
	var dawn = m.squad_by_id("dawn")
	var ash = m.squad_by_id("ash")
	place(m, dawn, "r5")
	m.order_move(dawn, "E_HQ")
	var enc_times: Array = []
	var durs: Array = []
	var all_ev: Array = []
	while m.time < 120.0 and not m.game_over:
		all_ev.append_array(m.update(0.1))
		if not m.pending_encounter.is_empty():
			enc_times.append(m.time)
			all_ev.append_array(m.apply_battle_result(m.pending_encounter[0], m.pending_encounter[1], 0))
			durs.append(m.nodes["E_HQ"]["durability"])
	print("    遭遇时刻：", enc_times.map(func(t): return snappedf(t, 0.1)))
	print("    每战后大本营耐久：", durs)
	var min_gap := INF
	for i in range(1, enc_times.size()):
		min_gap = minf(min_gap, enc_times[i] - enc_times[i - 1])
	check(enc_times.size() >= 2 and min_gap >= MapModel.RECOVER_TIME - 0.05, "两次遭遇间隔不小于整备时间（最小间隔 %.1f 秒，共 %d 场）" % [min_gap, enc_times.size()])
	var in_window := enc_times.filter(func(t): return t - enc_times[0] < MapModel.RECOVER_TIME - 0.05)
	check(in_window.size() == 1, "第一战后的整备窗口内只发生 1 次遭遇")
	var decreasing := true
	for i in range(1, durs.size()):
		decreasing = decreasing and durs[i] < durs[i - 1]
	check(decreasing and durs.size() <= 6, "每赢一场耐久都下降，%d 场内耗尽" % durs.size())
	check(all_ev.any(func(e): return e["type"] == "breached"), "耐久归零：防御被攻破")
	check(m.game_over and m.winner == 0 and m.nodes["E_HQ"]["owner"] == 0, "守军溃退后大本营被占领 → 胜利（%.1f 秒）" % m.time)
	check(ash.alive and ash.pos.distance_to(m.nodes["E_HQ"]["pos"]) > 30.0, "溃退的守军离开了大本营（撤往己方据点）")

	print("=== 2. 回归：真实自动战斗下攻城（我方 Lv10）===")
	var r := new_model()
	only_enemies(r, ["ash"])
	var rd = r.squad_by_id("dawn")
	buff(rd, 10)
	place(r, rd, "r5")
	r.order_move(rd, "E_HQ")
	var times2: Array = []
	var res2: Array = []
	while r.time < 300.0 and not r.game_over:
		r.update(0.1)
		if not r.pending_encounter.is_empty():
			times2.append(r.time)
			var rr: Array = r.resolve_encounter_auto()
			res2.append(rr[1].map(func(e): return e["text"]))
		if rd.alive and not rd.is_moving() and not r.game_over and not rd.is_recovering():
			r.order_move(rd, "E_HQ")
	var gap2 := INF
	for i in range(1, times2.size()):
		gap2 = minf(gap2, times2[i] - times2[i - 1])
	for x in res2:
		print("    ", " / ".join(PackedStringArray(x)))
	check(times2.size() <= 1 or gap2 >= MapModel.RECOVER_TIME - 0.05, "真实战斗：%d 场，最小间隔 %.1f 秒" % [times2.size(), gap2])
	check(r.game_over and r.winner == 0, "大本营最终被攻陷（%.0f 秒）" % r.time)

	print("=== 3. 击退：行军途中战败，沿道路后退 ===")
	var k := new_model()
	only_enemies(k, ["sand"])
	var kd = k.squad_by_id("dawn")
	var ks = k.squad_by_id("sand")
	place(k, kd, "P_HQ")
	k.order_move(kd, "ford")
	for i in 30:
		k.update(0.1)  # 前进约 165 像素
	place(k, ks, "ford")
	ks.pos = kd.pos + Vector2(10, 0)
	var before: Vector2 = kd.pos
	var ks_before: Vector2 = ks.pos
	var ev3 := k.apply_battle_result(kd, ks, 1)
	var back: float = before.distance_to(kd.pos)
	check(absf(back - MapModel.KNOCKBACK_DIST) < 0.5, "败方被击退 %.0f 像素" % back)
	check(kd.pos.distance_to(k.nodes["P_HQ"]["pos"]) < before.distance_to(k.nodes["P_HQ"]["pos"]) and kd.path.is_empty() and k.edge_of(kd).has("P_HQ") and k.edge_of(kd).has("ford"), "朝来路（晨星营地）方向后退，停在道路上（%s）" % str(k.edge_of(kd)))
	check(ev3.any(func(e): return e["type"] == "knockback"), "产生击退事件：" + str(ev3.map(func(e): return e["text"])))
	check(ks.pos == ks_before, "胜方原地不动")

	print("=== 4. 战后整备：双方原地停留，不会和任何人遭遇 ===")
	check(ks.is_recovering() and not ks.waiting and absf(ks.recover_time - MapModel.RECOVER_TIME) < 0.01, "胜方进入 %.1f 秒整备" % MapModel.RECOVER_TIME)
	check(kd.waiting and absf(kd.recover_time - MapModel.WAIT_TIME) < 0.01, "败方进入 %.1f 秒待机" % MapModel.WAIT_TIME)
	var wolf = k.squad_by_id("wolf")
	place(k, wolf, "ford")  # 第三支小队直接站到敌人身上
	wolf.pos = ks.pos
	var p_before: Vector2 = kd.pos
	var enc4 := 0
	for i in 20:
		k.update(0.1)
		if not k.pending_encounter.is_empty():
			enc4 += 1
			break
	check(enc4 == 0, "整备期间即使有其他敌队重叠也不会遭遇")
	check(kd.pos == p_before, "整备期间不移动")
	for i in 15:
		k.update(0.1)
	check(not ks.is_recovering() and not k.pending_encounter.is_empty(), "整备结束后可以再次遭遇")
	k.pending_encounter = []
	wolf.pos = Vector2(-999, -999)
	for i in 15:
		k.update(0.1)
	check(not kd.is_recovering() and not kd.waiting and kd.pos == p_before and kd.path.is_empty() and k.node_of(kd) == "", "待机结束后仍停在击退位置，不会自己走到节点")

	_parked_checks()

	print("=== 5. 击退：站在普通据点上战败，被推离据点 ===")
	var n := new_model()
	only_enemies(n, ["crow"])
	var nd = n.squad_by_id("dawn")
	var nc = n.squad_by_id("crow")
	place(n, nc, "windmill")
	place(n, nd, "ford")
	n.order_move(nd, "windmill")
	while n.pending_encounter.is_empty() and n.time < 20.0:
		n.update(0.1)
	n.apply_battle_result(nd, nc, 0)
	var wp: Vector2 = n.nodes["windmill"]["pos"]
	check(nc.pos.distance_to(wp) > 60.0 and nc.pos.x > wp.x, "敌方被推离风车丘，朝远离我方的东侧（距离 %.0f）" % nc.pos.distance_to(wp))
	var ne: Array = n.edge_of(nc)
	check(nc.path.is_empty() and ne.has("windmill") and (ne.has("r5") or ne.has("r6") or ne.has("r3") or ne.has("r4")), "停在通往相邻节点的道路上 %s" % str(ne))

	print("=== 6. 耐久：守军在场无法占领，战败原地硬直 ===")
	var d := new_model()
	only_enemies(d, ["ash"])
	var dd = d.squad_by_id("dawn")
	var da = d.squad_by_id("ash")
	check(d.nodes["E_HQ"]["max_durability"] == 100 and d.nodes["red_fort"]["max_durability"] == 60 and d.nodes["ford"]["max_durability"] == 0, "耐久来自数据：大本营 100 / 要塞 60 / 普通据点无")
	place(d, dd, "E_HQ")
	for i in 50:
		d.update(0.1)
	d.pending_encounter = []
	check(d.nodes["E_HQ"]["owner"] == 1 and d.nodes["E_HQ"]["capture_progress"] == 0.0, "守军在场时进度不增加，无法占领")
	for u in dd.units:
		u.hp = u.max_hp / 2
	var ev6 := d.apply_battle_result(dd, da, 0)
	var expect := int(round(MapModel.DURABILITY_HIT * dd.hp_ratio()))
	check(int(d.nodes["E_HQ"]["durability"]) == 100 - expect, "耐久按胜方剩余 HP 比例削减：-%d（HP %.0f%%）" % [expect, dd.hp_ratio() * 100])
	check(da.stunned and da.is_recovering() and d.node_of(da) == "E_HQ", "守军无路可退：原地硬直")
	check(ev6.any(func(e): return e["type"] == "stunned"), "产生硬直事件")
	print("=== 7. 据点内回复：硬直中的守军仍会回复 HP ===")
	da.units[0].hp = 10
	d.update(1.0)
	d.update(1.0)
	d.pending_encounter = []
	check(da.units[0].hp == 10 + 2 * int(ceil(da.units[0].max_hp * MapModel.BASE_HP_REGEN)), "守军 2 秒 HP 10 → %d（每秒 2%%）" % da.units[0].hp)

	print("=== 8. 耐久归零：守军溃退，据点可被占领 ===")
	da.recover_time = 0.0
	dd.recover_time = 0.0
	d.nodes["E_HQ"]["durability"] = 5.0
	var ev8 := d.apply_battle_result(dd, da, 0)
	check(d.nodes["E_HQ"]["durability"] == 0.0 and ev8.any(func(e): return e["type"] == "breached"), "耐久归零，防御被攻破")
	check(da.alive and da.is_moving() and d.node_of(da) != "E_HQ" and da.pos.distance_to(d.nodes["E_HQ"]["pos"]) > 60.0, "守军溃退，撤往「%s」" % d.nodes[da.destination()]["name"])
	var ev8b: Array = []
	while not d.game_over and d.time < 30.0:
		ev8b.append_array(d.update(0.1))
		d.pending_encounter = []
	check(d.game_over and d.winner == 0, "无人防守后按时占领大本营 → 胜利")
	print("=== 9. 无处可退的守军溃散 ===")
	var z := new_model()
	only_enemies(z, ["ash"])
	for id in z.node_ids:
		if id != "E_HQ" and z.is_capturable(id):
			z.nodes[id]["owner"] = 0
	var zd = z.squad_by_id("dawn")
	var za = z.squad_by_id("ash")
	place(z, zd, "E_HQ")
	z.nodes["E_HQ"]["durability"] = 1.0
	z.apply_battle_result(zd, za, 0)
	check(not za.alive, "没有己方据点可撤：守军溃散")

	print("=== 10. 平局：不削减耐久，双方后退一点 ===")
	var q := new_model()
	only_enemies(q, ["ash", "crow"])
	var qd = q.squad_by_id("dawn")
	var qa = q.squad_by_id("ash")
	place(q, qd, "E_HQ")
	q.apply_battle_result(qd, qa, -1)
	check(q.nodes["E_HQ"]["durability"] == 100.0 and q.node_of(qa) == "E_HQ", "守军平局：耐久不变，守军留在大本营")
	check(qd.pos.distance_to(q.nodes["E_HQ"]["pos"]) > MapModel.DRAW_KNOCKBACK - 1.0 and qd.is_recovering() and qa.is_recovering(), "进攻方后退 %.0f 像素，双方都进入整备" % qd.pos.distance_to(q.nodes["E_HQ"]["pos"]))
	var qc = q.squad_by_id("crow")
	place(q, qc, "windmill")
	var qw = q.squad_by_id("wolf")
	place(q, qw, "windmill")
	qw.pos += Vector2(-8, 0)
	var c0: Vector2 = qc.pos
	var w0: Vector2 = qw.pos
	q.apply_battle_result(qw, qc, -1)
	check(qc.pos.distance_to(c0) > 20.0 and qw.pos.distance_to(w0) > 20.0, "野外平局：双方各自后退（%.0f / %.0f 像素）" % [qc.pos.distance_to(c0), qw.pos.distance_to(w0)])
	check(qc.pos.distance_to(qw.pos) > MapModel.ENCOUNTER_DIST, "平局后双方分开，不再重叠")

	print("=== 11. 耐久恢复 ===")
	var g := new_model()
	only_enemies(g, ["ash"])
	g.nodes["E_HQ"]["durability"] = 50.0
	for i in 100:
		g.update(0.1)
	check(absf(g.nodes["E_HQ"]["durability"] - 70.0) < 0.6, "附近无敌军：10 秒恢复到 %.1f" % g.nodes["E_HQ"]["durability"])
	var gd = g.squad_by_id("dawn")
	place(g, gd, "r5")
	gd.pos = g.nodes["E_HQ"]["pos"] + Vector2(-80, 0)  # 停在大本营附近（SIEGE_RADIUS 内）
	var dur0: float = g.nodes["E_HQ"]["durability"]
	for i in 50:
		g.update(0.1)
	check(g.nodes["E_HQ"]["durability"] == dur0, "敌军在附近时不恢复")

	print("=== 12. 敌方 AI：整备中不行动，残血时撤回己方据点 ===")
	var a := new_model()
	a.ai_enabled = true
	only_enemies(a, ["sand"])
	var asd = a.squad_by_id("sand")
	place(a, asd, "windmill")
	asd.ai = {"mode": "advance", "targets": ["P_HQ"]}
	asd.recover_time = 2.0
	var ap: Vector2 = asd.pos
	for i in 15:
		a.update(0.1)
	check(asd.pos == ap, "整备中的敌队不移动")
	for u in asd.units:
		u.hp = int(u.max_hp * 0.2)
	for i in 20:
		a.update(0.1)
	check(asd.destination() == "red_fort" or asd.destination() == "crow_tower", "残血敌队撤往己方据点「%s」" % a.nodes[asd.destination()]["name"])

	print("=== 结果：%s（失败 %d 项）===" % ["全部通过" if failures == 0 else "有失败", failures])
	quit(1 if failures > 0 else 0)


## 复现第 3 节：晨星小队从营地开往白石渡，途中被沙蝎小队击败并击退。返回 [模型, 败方, 胜方]
func parked_scenario(player_wins: bool = false) -> Array:
	var k := new_model()
	only_enemies(k, ["sand"])
	var kd = k.squad_by_id("dawn")
	var ks = k.squad_by_id("sand")
	place(k, kd, "P_HQ")
	k.order_move(kd, "ford")
	for i in 30:
		k.update(0.1)
	place(k, ks, "ford")
	ks.pos = kd.pos + Vector2(10, 0)
	ks.at_node = "ford"
	ks.path = []
	ks.edge_other = "P_HQ"
	if player_wins:
		k.apply_battle_result(kd, ks, 0)
		return [k, ks, kd]
	k.apply_battle_result(kd, ks, 1)
	return [k, kd, ks]


## 沿道路行军直到到达 dest；每一步都检查是否在 y=330 这条路（营地—白石渡—风车丘）上
func walk_on_row(k, sq, dest: String, max_t: float = 30.0) -> bool:
	var on_road := true
	var t := 0.0
	while sq.at_node != dest and t < max_t:
		k.update(0.1)
		t += 0.1
		if sq.at_node != dest and absf(sq.pos.y - 330.0) > 0.5:
			on_road = false
	return on_road and sq.at_node == dest


func _parked_checks() -> void:
	print("=== 4b. 击退后原地待命，直到收到新命令 ===")
	var r := parked_scenario()
	var k = r[0]
	var kd = r[1]
	var ks = r[2]
	ks.alive = false  # 移除胜方，避免干扰行军
	var p0: Vector2 = kd.pos
	check(kd.path.is_empty() and k.node_of(kd) == "" and kd.destination() == "" and k.is_parked(kd), "击退后：不在节点上、没有行军路线（停在 %s 之间）" % str(k.edge_of(kd)))
	for i in int((MapModel.WAIT_TIME + 1.5) / 0.1):
		k.update(0.1)
	check(not kd.waiting and kd.pos.distance_to(p0) < 0.01 and kd.path.is_empty(), "待机结束 1.5 秒后仍在原位（位移 %.3f）" % kd.pos.distance_to(p0))
	k.stop(kd)
	check(kd.path.is_empty() and kd.pos == p0, "对停在路上的小队「原地停止」不会让它走回节点")
	check(k.nearest_friendly_node(kd) == "P_HQ" and absf(k.route_cost(kd, "P_HQ") - p0.distance_to(k.nodes["P_HQ"]["pos"])) < 0.5, "路程按所在道路计算（到营地 %.0f）" % k.route_cost(kd, "P_HQ"))
	# 往回走：去营地后面的 r1，必须先沿这条路回到营地，不能斜穿
	k.order_move(kd, "r1")
	check(kd.path.size() == 2 and kd.path[0] == "P_HQ" and kd.at_node == "ford", "去 r1：先沿道路回营地 %s" % str(kd.path))
	check(walk_on_row(k, kd, "P_HQ"), "回营地途中一直在道路上")
	# 往前走
	r = parked_scenario()
	k = r[0]
	kd = r[1]
	r[2].alive = false
	for i in int(MapModel.WAIT_TIME / 0.1) + 2:
		k.update(0.1)
	k.order_move(kd, "windmill")
	check(kd.path == ["ford", "windmill"] and kd.at_node == "P_HQ", "去风车丘：沿道路向前经白石渡 %s" % str(kd.path))
	check(walk_on_row(k, kd, "windmill"), "向前行军一直在道路上并到达风车丘")
	# 追击停在路上的敌人
	r = parked_scenario(true)
	k = r[0]
	var loser = r[1]  # 敌方沙蝎，停在路上
	var winner = r[2]
	check(k.is_parked(loser), "敌方败者也停在路上 %s" % str(k.edge_of(loser)))
	var wolf = k.squad_by_id("wolf")
	place(k, wolf, "windmill")
	winner.alive = false
	k.order_pursue(wolf, loser)
	var t := 0.0
	while k.pending_encounter.is_empty() and t < 20.0:
		k.update(0.1)
		t += 0.1
	check(not k.pending_encounter.is_empty() and k.pending_encounter[0] == wolf, "从风车丘追击停在路上的敌人，%.1f 秒后接触" % t)

	print("=== 4c. 胜方保留原命令；停在路上的小队再次战败会继续后退 ===")
	r = parked_scenario(true)
	k = r[0]
	loser = r[1]
	winner = r[2]
	var w0: Vector2 = winner.pos
	check(winner.path == ["ford"], "胜方保留前往白石渡的命令")
	var moved_after := false
	for i in int(MapModel.RECOVER_TIME / 0.1) + 4:
		k.update(0.1)
		if not k.pending_encounter.is_empty():
			break
	moved_after = winner.pos.x > w0.x
	check(moved_after and winner.destination() == "ford", "整备结束后胜方继续前往白石渡（x %.0f → %.0f）" % [w0.x, winner.pos.x])
	# 第二次击退：停在路上的败者再次战败
	r = parked_scenario()
	k = r[0]
	kd = r[1]
	ks = r[2]
	var e0: Array = k.edge_of(kd)
	var pa: Vector2 = kd.pos
	ks.pos = kd.pos + Vector2(10, 0)
	ks.recover_time = 0.0
	k.apply_battle_result(kd, ks, 1)
	check(kd.path.is_empty() and (k.edge_of(kd) == e0 or k.node_of(kd) == "P_HQ") and kd.pos.x < pa.x, "再次被击退：沿同一条路继续后退并停下（x %.0f → %.0f）" % [pa.x, kd.pos.x])
	# AI：敌方败者待机结束后可以自己下新命令（不是残留的击退路线）
	r = parked_scenario(true)
	k = r[0]
	loser = r[1]
	r[2].alive = false
	loser.ai = {"mode": "advance", "targets": ["windmill", "ford", "P_HQ"]}  # 去掉 60 秒延迟
	k.ai_enabled = true
	var le: Array = k.edge_of(loser)
	for i in int((MapModel.WAIT_TIME + 2.0) / 0.1):
		k.update(0.1)
		if loser.is_moving():
			break
	check(loser.is_moving() and le.has(loser.at_node) and absf(loser.pos.y - 330.0) < 0.5, "敌方 AI 待机后从路上出发，沿所在道路（%s）经端点「%s」前往 %s" % [str(le), loser.at_node, str(loser.path)])
