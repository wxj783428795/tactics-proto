## 首领士气 / 战败待机 / 先制攻击测试：godot --headless --path . --script res://tests/run_boss_test.gd
## 覆盖：险胜不结束任务、多次获胜靠士气归零、全灭立刻结束、HP 延续、士气只在据点恢复、
## 先制攻击行动顺序、待机小队可被第三方攻击但不会瞬间连战、首领 AI 休整 / 出击、第三章平衡参考。
extends SceneTree

const MapModel := preload("res://scripts/map_model.gd")
const Progression := preload("res://scripts/progression.gd")
const CampaignState := preload("res://scripts/campaign_state.gd")

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  [OK] ", msg)
	else:
		failures += 1
		printerr("  [FAIL] ", msg)


func ch3(c = null) -> MapModel:
	if c == null:
		c = CampaignState.new()
		c.new_game()
		c.cleared = ["m1", "m2"]
	var m: MapModel = c.create_mission_model(2)
	m.ai_enabled = false
	return m


func place(m: MapModel, sq, node: String) -> void:
	sq.at_node = node
	sq.pos = m.nodes[node]["pos"]
	sq.path = []


func set_ratio(sq, r: float) -> void:
	for u in sq.units:
		if u.is_alive():
			u.hp = maxi(1, int(round(u.max_hp * r)))


func hp_list(sq) -> Array:
	return sq.units.map(func(u): return u.hp)


## 只留下 keep 中的敌方小队，其余移除（避免干扰）
func only_enemies(m: MapModel, keep: Array) -> void:
	for sq in m.living_squads(1):
		if not keep.has(sq.id):
			sq.alive = false


func _initialize() -> void:
	print("=== 1. 首领数据与目标文字 ===")
	var m := ch3()
	var boss = m.squad_by_id("boss")
	check(boss != null and boss.max_morale == 100 and is_equal_approx(boss.morale, 100.0), "第三章首领士气 100/100")
	check(m.objective_text().contains("士气 100/100"), "HUD 目标：" + m.objective_text())

	print("=== 2. 险胜不会结束任务；首领 HP 延续 ===")
	only_enemies(m, ["boss"])
	var p = m.living_squads(0)[0]
	place(m, boss, "r3")
	place(m, p, "r3")
	set_ratio(p, 0.40)
	set_ratio(boss, 0.35)
	var expect_loss := maxi(15, int(round((20.0 + 60.0 * (p.hp_ratio() - boss.hp_ratio())) * (0.5 + 0.5 * p.hp_ratio()))))
	var hp_before := hp_list(boss)
	var ev := m.apply_battle_result(p, boss, 0)
	check(not m.game_over and boss.alive, "险胜（HP 比例 %.2f vs %.2f）后任务继续" % [p.hp_ratio(), boss.hp_ratio()])
	check(is_equal_approx(boss.morale, 100.0 - expect_loss), "士气按公式 max(15, (20+60×差距)×(0.5+0.5×胜方HP)) 下降：-%d → %d" % [expect_loss, int(boss.morale)])
	check(ev.any(func(e): return e["type"] == "morale" and e["text"].contains("士气 -")), "日志：" + str(ev.filter(func(e): return e["type"] == "morale").map(func(e): return e["text"])))
	check(hp_list(boss) == hp_before, "战后首领 HP 不回满（延续）")
	check(boss.waiting and absf(boss.recover_time - MapModel.WAIT_TIME) < 0.01, "败方首领进入 %.0f 秒待机" % MapModel.WAIT_TIME)
	check(p.is_recovering() and not p.waiting and absf(p.recover_time - MapModel.RECOVER_TIME) < 0.01, "胜方只整备 %.1f 秒" % MapModel.RECOVER_TIME)
	m.pending_first_strike = 0
	var e2 = m.create_battle(p, boss)
	check(hp_list(boss) == hp_before, "下一场战斗开始时 HP 仍然延续")
	m.pending_first_strike = -1

	print("=== 3. 连续获胜：士气归零才算讨伐 ===")
	m = ch3()
	only_enemies(m, ["boss"])
	boss = m.squad_by_id("boss")
	p = m.living_squads(0)[0]
	var wins := 0
	var logs: Array = []
	while not m.game_over and wins < 10:
		place(m, boss, "r3")
		place(m, p, "r3")
		set_ratio(p, 0.8)
		set_ratio(boss, 0.5)
		boss.recover_time = 0.0
		boss.waiting = false
		var evs := m.apply_battle_result(p, boss, 0)
		wins += 1
		for x in evs:
			if x["type"] == "morale":
				logs.append(x["text"])
	print("    ", " / ".join(logs))
	check(m.game_over and m.winner == 0 and wins == 3, "比例 0.8 vs 0.5 的胜利每次 -34，第 3 胜士气归零（实际 %d 胜）" % wins)
	check(m.end_reason.contains("士气崩溃"), "结束原因：" + m.end_reason)

	print("=== 4. 首领全员倒下：立即结束 ===")
	m = ch3()
	boss = m.squad_by_id("boss")
	p = m.living_squads(0)[0]
	place(m, boss, "r3")
	place(m, p, "r3")
	for u in boss.units:
		u.hp = 0
	m.apply_battle_result(p, boss, 0)
	check(m.game_over and m.winner == 0 and boss.morale >= 99.0, "士气未动但全员倒下 → 胜利")
	check(m.end_reason.contains("全员倒下"), "结束原因：" + m.end_reason)

	print("=== 5. 士气只在己方据点恢复；首领回血慢、倒下成员不复活 ===")
	m = ch3()
	only_enemies(m, ["boss"])
	boss = m.squad_by_id("boss")
	for sq in m.living_squads(0):
		place(m, sq, "outpost")
	boss.morale = 50.0
	var a: Vector2 = m.nodes["r3"]["pos"]
	var bpos: Vector2 = m.nodes["tower"]["pos"]
	boss.at_node = "r3"
	boss.pos = a.lerp(bpos, 0.5)
	boss.path = []
	for i in 100:
		m.update(0.1)
	check(is_equal_approx(boss.morale, 50.0), "在路上静止 10 秒：士气不变（%.1f）" % boss.morale)
	place(m, boss, "r3")
	for i in 100:
		m.update(0.1)
	check(is_equal_approx(boss.morale, 50.0), "停在路口 10 秒：士气不变")
	place(m, boss, "tower")
	set_ratio(boss, 0.3)
	boss.units[1].hp = 0
	var hp0: Array = hp_list(boss)
	for i in 100:
		m.update(0.1)
	check(absf(boss.morale - 55.0) < 0.2, "在灰塔休整 10 秒：士气 50 → %.1f（每秒 0.5）" % boss.morale)
	check(boss.units[1].hp == 0, "倒下的亲卫不会复活")
	var u0 = boss.units[0]
	var gain: int = u0.hp - int(hp0[0])
	check(gain > 0 and gain <= 10 * int(ceil(u0.max_hp * MapModel.BOSS_HP_REGEN)), "首领 10 秒只恢复 %d HP（上限 %d，普通小队为 %d）" % [gain, 10 * int(ceil(u0.max_hp * MapModel.BOSS_HP_REGEN)), 10 * int(ceil(u0.max_hp * MapModel.BASE_HP_REGEN))])

	print("=== 6. 先制攻击：第一轮攻方全员先行动 ===")
	m = ch3()
	only_enemies(m, ["boss"])
	boss = m.squad_by_id("boss")
	p = m.living_squads(0)[0]
	for u in boss.units:
		u.spd = 200  # 首领方极快：正常情况下必然先手
	place(m, boss, "r3")
	place(m, p, "r3")
	m.pending_encounter = [p, boss]
	m.pending_first_strike = -1
	var e0 = m.create_battle(p, boss)
	e0._start_round(PackedStringArray())
	check(e0.queue[0].team == 1, "对照：无先制时速度 200 的首领方先行动")
	boss.waiting = true
	boss.recover_time = MapModel.WAIT_TIME
	m.pending_encounter = []
	m.update(0.1)
	check(m.pending_encounter.size() == 2 and m.pending_first_strike == 0, "攻击待机中的首领 → 我方获得先制")
	var ef = m.create_battle(p, boss)
	var out := PackedStringArray()
	ef._start_round(out)
	var teams: Array = ef.queue.map(func(u): return u.team)
	var n0: int = teams.count(0)
	check(n0 > 0 and teams.slice(0, n0).all(func(t): return t == 0), "第一轮行动顺序：我方 %d 人全部排在敌方之前 %s" % [n0, str(teams)])
	check("\n".join(out).contains("【先制攻击！】"), "战斗日志出现「先制攻击！」")
	var r2 := PackedStringArray()
	ef.queue.clear()
	ef.acted_this_round = true
	ef._start_round(r2)
	check(ef.queue[0].team == 1, "第二轮恢复按速度排序")

	print("=== 7. 待机小队：可被第三方攻击，但不会瞬间连战 ===")
	m = ch3()
	var foe = m.living_squads(1).filter(func(s): return s.id != "boss")[0]
	only_enemies(m, [foe.id, "boss"])  # 首领留在灰塔（移除首领会直接判定任务胜利）
	var ps: Array = m.living_squads(0)
	var p1 = ps[0]
	var p2 = ps[1]
	place(m, foe, "r1")
	place(m, p1, "r1")
	place(m, p2, "outpost")
	for sq in ps.slice(2):
		place(m, sq, "outpost")
	m.apply_battle_result(p1, foe, 0)
	p1.pos = foe.pos  # 胜方贴着待机中的败方
	var first_t := -1.0
	var t := 0.0
	while t < MapModel.WAIT_TIME and first_t < 0.0:
		m.update(0.1)
		t += 0.1
		if not m.pending_encounter.is_empty():
			first_t = t
	check(first_t >= MapModel.RECOVER_TIME - 0.05, "胜方整备结束前不会再战（首次遭遇在 %.1f 秒，整备 %.1f 秒）" % [first_t, MapModel.RECOVER_TIME])
	check(m.pending_first_strike == 0 and foe.waiting, "整备结束的胜方攻击仍在待机的败方 → 先制")
	# 第三支小队：胜方仍在整备时也能攻击待机的败方
	m = ch3()
	foe = m.living_squads(1).filter(func(s): return s.id != "boss")[0]
	only_enemies(m, [foe.id, "boss"])
	ps = m.living_squads(0)
	p1 = ps[0]
	p2 = ps[1]
	for sq in ps:
		place(m, sq, "outpost")
	place(m, foe, "r1")
	place(m, p1, "r1")
	m.apply_battle_result(p1, foe, 0)
	m.update(0.1)
	check(m.pending_encounter.is_empty(), "胜方整备中：与败方重叠也不遭遇")
	p2.pos = foe.pos
	p2.at_node = "r1"
	m.update(0.1)
	check(m.pending_encounter.size() == 2 and m.pending_encounter[0] == p2 and m.pending_first_strike == 0, "第三支小队攻击待机的败方 → 立即遭遇并先制")
	m.pending_encounter = []
	# 待机方不能主动交战：双方都在待机时不遭遇；我方待机时被敌方攻击，敌方先制
	p2.waiting = true
	p2.recover_time = MapModel.WAIT_TIME
	m.update(0.1)
	check(m.pending_encounter.is_empty(), "双方都在待机：不会遭遇")
	foe.waiting = false
	foe.recover_time = 0.0
	m.update(0.1)
	check(m.pending_encounter.size() == 2 and m.pending_first_strike == 1, "我方待机时被敌军攻击 → 敌方先制")
	m.pending_encounter = []

	print("=== 8. 首领 AI：残血回塔休整，恢复后出击 ===")
	m = ch3()
	only_enemies(m, ["boss"])
	m.ai_enabled = true
	boss = m.squad_by_id("boss")
	for sq in m.living_squads(0):
		place(m, sq, "outpost")
	place(m, boss, "r3")
	set_ratio(boss, 0.3)
	for i in 10:
		m.update(0.1)
	check(boss.resting and (boss.destination() == "tower" or m.node_of(boss) == "tower"), "HP 30%%：回灰塔休整（目的地 %s）" % boss.destination())
	place(m, boss, "tower")
	set_ratio(boss, 1.0)
	var intruder = m.living_squads(0)[0]
	place(m, intruder, "shrine")
	for i in 10:
		m.update(0.1)
	check(not boss.resting, "HP 回满后结束休整、照常迎击")

	print("=== 9. 第三章平衡参考（自动驾驶，不同等级）===")
	var wins_list: Array = []
	for lv in [7, 8, 9, 10]:
		var c = CampaignState.new()
		c.new_game()
		c.cleared = ["m1", "m2"]
		for uu in c.roster:
			uu.level = lv
			uu.apply_class(c.classes[uu.class_id], c.items)
			if Progression.can_promote(uu, c.classes):
				c.promote(uu.uid)
		var r := autopilot(ch3(c))
		var mm: MapModel = r[0]
		wins_list.append(r[2])
		print("    全员 Lv%d：%s 用时 %.0f 秒 战斗 %d 场 战胜首领 %d 次 | %s" % [lv, "胜利" if mm.winner == 0 else "失败", mm.time, r[1], r[2], mm.end_reason])
	var good: int = wins_list.filter(func(w): return w >= 2 and w <= 4).size()
	check(good >= 3, "多数等级需要战胜首领 2–4 次（%s）" % str(wins_list))

	print("=== 结果：%s（失败 %d 项）===" % ["全部通过" if failures == 0 else "有失败", failures])
	quit(1 if failures > 0 else 0)


## 简易自动驾驶：全员冲向灰塔，残血回最近据点，最后一队守营。返回 [模型, 战斗数, 战胜首领次数]
func autopilot(model: MapModel, max_time: float = 900.0) -> Array:
	model.ai_enabled = true
	var battles := 0
	var boss_wins := 0
	var target: String = model.squad_by_id("boss").home
	var guard = model.living_squads(0)[-1] if model.living_squads(0).size() > 1 else null
	while not model.game_over and model.time < max_time:
		for sq in model.living_squads(0):
			if sq.is_moving():
				continue
			if sq == guard and model.living_squads(0).size() > 1:
				model.order_move(sq, model.hq_of(0))
				continue
			var here: String = model.node_of(sq)
			if here != "" and model.nodes[here]["owner"] == 0 and (sq.hp_ratio() < 0.85 or sq.stamina < 50.0):
				continue
			if sq.hp_ratio() < 0.5:
				var safe: String = model.nearest_friendly_node(sq)
				if safe != "":
					model.order_move(sq, safe)
					continue
			model.order_move(sq, target)
		model.update(0.1)
		if not model.pending_encounter.is_empty():
			var rr: Array = model.resolve_encounter_auto()
			battles += 1
			for e in rr[1]:
				if e["type"] == "morale":
					boss_wins += 1
	return [model, battles, boss_wins]
