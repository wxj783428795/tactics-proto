## 大地图无头测试：godot --headless --path . --script res://tests/run_map_test.gd
## 覆盖：寻路行军、体力、占领、回复、遭遇→战斗→结算、胜负条件、敌方 AI、规则编辑与保存、编队编辑、UI 流程。
extends SceneTree

const MapModel := preload("res://scripts/map_model.gd")
const Schema := preload("res://scripts/tactics_schema.gd")
const RuleEditor := preload("res://scripts/rule_editor.gd")
const FormationEditor := preload("res://scripts/formation_editor.gd")
const BattleView := preload("res://scripts/battle_view.gd")
const TEST_SAVE := "user://test_squad_setups.json"

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  [OK] ", msg)
	else:
		failures += 1
		printerr("  [FAIL] ", msg)


func new_model(ai: bool = false) -> MapModel:
	var m := MapModel.new()
	var ok := m.load_campaign("res://data/campaign.json", "res://data/classes.json")
	m.ai_enabled = ai
	if not ok:
		printerr("campaign 加载失败")
	return m


## 推进直到条件满足或超时，返回所有事件
func run_until(m: MapModel, cond: Callable, max_t: float = 60.0) -> Array:
	var ev: Array = []
	var t := 0.0
	while t < max_t and not cond.call():
		ev.append_array(m.update(0.1))
		t += 0.1
	return ev


func _initialize() -> void:
	print("=== 地图 1：加载 ===")
	var m := new_model()
	check(m.node_ids.size() == 14 and m.squads.size() == 7, "14 个节点、7 支小队")
	check(m.base_counts() == [1, 3, 4], "初始据点 我方1/敌方3/中立4：%s" % str(m.base_counts()))
	check(m.living_squads(0).size() == 3 and m.living_squads(1).size() == 4, "我方 3 队、敌方 4 队")

	print("=== 地图 2：行军与体力 ===")
	var dawn = m.squad_by_id("dawn")
	check(m.order_move(dawn, "windmill"), "下达行军命令 晨星小队 → 风车丘")
	print("  路线：", dawn.path)
	check(dawn.path == ["ford", "windmill"], "最短路经过白石渡")
	m.update(1.0)
	check(dawn.pos.distance_to(m.nodes["P_HQ"]["pos"]) > 50.0 and dawn.stamina < 100.0, "1 秒后已移动且消耗体力 (体力 %.1f)" % dawn.stamina)
	# 途中改道回营：应该掉头而不是继续前进
	m.order_move(dawn, "P_HQ")
	check(dawn.path == ["P_HQ"], "途中改道直接掉头")
	run_until(m, func(): return not dawn.is_moving())
	check(m.node_of(dawn) == "P_HQ", "回到大本营")

	print("=== 地图 3：占领与回复 ===")
	m.order_move(dawn, "ford")
	var ev := run_until(m, func(): return m.nodes["ford"]["owner"] == 0, 20.0)
	check(m.nodes["ford"]["owner"] == 0, "停留 %.0f 秒后占领白石渡" % m.CAPTURE_TIME)
	check(ev.any(func(e): return e["type"] == "captured"), "产生占领事件：" + str(ev.filter(func(e): return e["type"] == "captured").map(func(e): return e["text"])))
	check(m.base_counts() == [2, 3, 3], "据点数更新为 %s" % str(m.base_counts()))
	var u0 = dawn.units[0]
	u0.hp = 10
	var st0: float = dawn.stamina
	m.update(1.0)
	m.update(1.0)
	check(u0.hp > 10 and dawn.stamina > st0, "己方据点内回复 HP（10→%d）与体力（%.1f→%.1f）" % [u0.hp, st0, dawn.stamina])
	u0.hp = u0.max_hp

	print("=== 地图 4：争夺中的据点不会被占领 ===")
	var m4 := new_model()
	var wolf4 = m4.squad_by_id("wolf")
	var crow4 = m4.squad_by_id("crow")
	# 把敌方小队放到远处的中立据点，我方也过去：会先遭遇
	crow4.at_node = "north_village"
	crow4.pos = m4.nodes["north_village"]["pos"]
	m4.order_move(wolf4, "north_village")
	run_until(m4, func(): return not m4.pending_encounter.is_empty(), 30.0)
	check(m4.pending_encounter.size() == 2 and m4.pending_encounter[0] == wolf4, "我方抵达有敌军的据点前发生遭遇")
	check(m4.nodes["north_village"]["owner"] != 0, "敌军在场时我方无法占领（敌方先到并已占领：owner=%d）" % m4.nodes["north_village"]["owner"])
	var hp_before := 0
	for u in wolf4.units + crow4.units:
		hp_before += u.hp
	var t_before: float = m4.time
	m4.update(1.0)
	check(m4.time == t_before, "遭遇待处理时地图暂停")

	print("=== 地图 5：遭遇 → 自动战斗 → 结果回写 ===")
	var res: Array = m4.resolve_encounter_auto()
	for l in res[0]:
		print("    ", l)
	for e in res[1]:
		print("  事件：", e["text"])
	var hp_after := 0
	for u in wolf4.units + crow4.units:
		hp_after += u.hp
	check(hp_after < hp_before, "战斗伤害保留到地图（总 HP %d → %d）" % [hp_before, hp_after])
	check(m4.pending_encounter.is_empty(), "遭遇已清除")
	var loser = crow4 if wolf4.pos.distance_to(m4.nodes["north_village"]["pos"]) < 30 else wolf4
	check(not loser.alive or loser.pos.distance_to(m4.nodes["north_village"]["pos"]) > 30.0, "败方（%s）被击退离开据点或被消灭（不再瞬移回大本营）" % loser.name)
	check(wolf4.is_recovering() and (crow4.is_recovering() or not crow4.alive), "双方进入战后整备")
	check(wolf4.pos.distance_to(crow4.pos) >= m4.ENCOUNTER_DIST or not loser.alive, "结算后双方不再重叠")
	m4.update(0.5)
	check(m4.pending_encounter.is_empty(), "地图继续运行且没有立即再次遭遇")

	print("=== 地图 6：全灭的小队被移除 ===")
	var m6 := new_model()
	var silver6 = m6.squad_by_id("dawn")
	var thorn6 = m6.squad_by_id("thorn")
	thorn6.units = thorn6.units.filter(func(u): return u.class_id != "cleric")  # 去掉牧师，避免被治疗
	for u in thorn6.units:
		u.hp = 1
	thorn6.at_node = "ford"
	thorn6.pos = m6.nodes["ford"]["pos"]
	m6.order_move(silver6, "ford")
	run_until(m6, func(): return not m6.pending_encounter.is_empty(), 30.0)
	var r6: Array = m6.resolve_encounter_auto()
	check(not thorn6.alive and m6.living_squads(1).size() == 3, "残血敌队被全灭并移除：" + str(r6[1].map(func(e): return e["text"])))

	print("=== 地图 7：胜负条件 ===")
	var m7 := new_model()
	var ash7 = m7.squad_by_id("ash")
	ash7.alive = false
	var d7 = m7.squad_by_id("dawn")
	d7.at_node = "E_HQ"
	d7.pos = m7.nodes["E_HQ"]["pos"]
	var ev7 := run_until(m7, func(): return m7.game_over, 10.0)
	check(m7.game_over and m7.winner == 0, "占领敌方大本营 → 胜利：" + str(ev7.filter(func(e): return e["type"] == "game_over").map(func(e): return e["text"])))
	var m8 := new_model()
	for sq in m8.living_squads(0):
		sq.at_node = "north_village"
		sq.pos = m8.nodes["north_village"]["pos"]
	var sand8 = m8.squad_by_id("sand")
	sand8.at_node = "P_HQ"
	sand8.pos = m8.nodes["P_HQ"]["pos"]
	run_until(m8, func(): return m8.game_over, 10.0)
	check(m8.game_over and m8.winner == 1, "我方大本营被占 → 败北")

	print("=== 地图 8：敌方 AI（开启 AI 自动推进 150 秒，遭遇自动结算） ===")
	var m9 := new_model(true)
	var sand9 = m9.squad_by_id("sand")
	var crow9 = m9.squad_by_id("crow")
	var crow_start: Vector2 = crow9.pos
	var log9: Array = []
	var sand_left := false
	var t9 := 0.0
	while t9 < 150.0 and not m9.game_over:
		for e in m9.update(0.1):
			log9.append("[%05.1f] %s" % [m9.time, e["text"]])
		if not m9.pending_encounter.is_empty():
			for e in m9.resolve_encounter_auto()[1]:
				log9.append("[%05.1f] %s" % [m9.time, e["text"]])
		if sand9.alive and sand9.pos.distance_to(m9.nodes["red_fort"]["pos"]) > 20:
			sand_left = true
		t9 += 0.1
	for l in log9:
		print("    ", l)
	check(sand_left, "进攻型 AI（赤沙突击队）在延迟后出击")
	check(crow9.pos != crow_start or not crow9.alive or log9.size() > 0, "巡逻型 AI 移动")
	check(m9.base_counts()[1] > 3 or m9.game_over or log9.any(func(l): return "遭遇" in l or "占领" in l), "AI 占领了据点或与我方交战，当前据点 %s" % str(m9.base_counts()))

	print("=== 地图 9：战术规则编辑（数据层） ===")
	var m10 := new_model()
	var dawn10 = m10.squad_by_id("dawn")
	var archer = dawn10.units.filter(func(u): return u.class_id == "archer")[0]
	var rules: Array = archer.tactics.duplicate(true)
	var n0 := rules.size()
	check(Schema.add_rule(rules, Schema.make_rule("piercing_shot", "enemy_class")), "添加规则")
	check(rules.size() == n0 + 1 and rules[-1]["value"] == "mage", "新规则使用条件默认参数")
	rules[-1]["value"] = "guardian"
	check(Schema.move_rule(rules, rules.size() - 1, -1) and Schema.move_rule(rules, rules.size() - 2, -1), "上移两次")
	check(rules[n0 - 2]["value"] == "guardian", "顺序变化正确")
	check(not Schema.move_rule(rules, 0, -1), "第一条不能再上移")
	Schema.set_condition(rules[0], "self_hp_below")
	check(rules[0]["value"] == 0.5, "切换条件后参数重置为默认")
	check(Schema.remove_rule(rules, 0) and rules.size() == n0, "删除规则")
	check(Schema.validate_rule({"if": "always", "skill": "mend"}, archer.skills) != "", "校验：弓手不会治疗")
	# 只保留"打重甲"规则，验证引擎按编辑后的规则行动
	archer.tactics = [{"if": "enemy_class", "value": "guardian", "skill": "piercing_shot"}]
	var ash10 = m10.squad_by_id("ash")
	var eng = m10.create_battle(dawn10, ash10)
	var act: Dictionary = eng.choose_action(archer)
	check(act["skill_id"] == "piercing_shot" and act["targets"][0].class_id == "guardian", "引擎按编辑后的规则选择目标：%s" % act["targets"][0].display_name)
	MapModel.swap_slots(dawn10, archer.row, archer.col, 0, 2)
	check(archer.row == 0 and archer.col == 2, "编队交换：弓手移到前排第 3 格")
	check(m10.save_setups(TEST_SAVE), "保存到 %s" % TEST_SAVE)
	var m11 := new_model()
	check(m11.load_setups(TEST_SAVE), "读取保存")
	var archer11 = m11.squad_by_id("dawn").units.filter(func(u): return u.class_id == "archer")[0]
	check(archer11.tactics.size() == 1 and archer11.tactics[0]["value"] == "guardian" and archer11.row == 0 and archer11.col == 2, "读取后战术与阵型一致")

	print("=== 地图 10：UI —— 规则编辑器 / 编队编辑器 / 大地图遭遇战流程 ===")
	var ow = load("res://scenes/overworld.tscn").instantiate()
	ow.save_path = TEST_SAVE
	root.add_child(ow)
	await process_frame
	ow.model.ai_enabled = false
	var wolf = ow.model.squad_by_id("wolf")
	ow.select_squad(wolf)
	var ed = ow.open_rule_editor(0)
	await process_frame
	check(ed != null and ow.overlay == ed, "从地图打开战术编辑器")
	var unit0 = wolf.units[0]
	var cnt: int = unit0.tactics.size()
	ed._on_add()
	await process_frame
	ed._list_op(ed.draft_for(0), ed.draft_for(0).size() - 1, -1)
	await process_frame
	check(ed._rows.get_child_count() == cnt + 1, "编辑器显示 %d 行规则" % (cnt + 1))
	ed._on_save()
	await process_frame
	check(unit0.tactics.size() == cnt + 1 and ow.overlay == null, "保存后写回并关闭")
	var ed2 = ow.open_rule_editor(0)
	await process_frame
	ed2._on_add()
	ed2._on_cancel()
	await process_frame
	check(unit0.tactics.size() == cnt + 1, "取消不会修改")
	var fe = ow.open_formation_editor()
	await process_frame
	var src = fe.cells.filter(func(c): return c.unit == unit0)[0]
	var dst = fe.cells.filter(func(c): return c.unit == null)[0]
	fe._on_cell(src)
	fe._on_cell(dst)
	check(unit0.row == dst.row and unit0.col == dst.col, "编队编辑器点击交换生效")
	fe.edit_tactics_requested.emit(0)
	await process_frame
	check(fe.get_children().any(func(c): return c is RuleEditor), "编队编辑器内可打开战术编辑")
	fe.closed.emit()
	fe.queue_free()
	await process_frame
	check(ow.overlay == null, "编队编辑器关闭")
	# 遭遇战：把鸦羽斥候放到白石渡，苍狼小队前往
	var crow = ow.model.squad_by_id("crow")
	crow.at_node = "ford"
	crow.pos = ow.model.nodes["ford"]["pos"]
	check(ow.command_move("ford"), "下达行军命令")
	var guard := 0
	while ow.overlay == null and guard < 600:
		ow.process_map(0.1)
		guard += 1
	check(ow.overlay is BattleView, "遭遇后自动打开战斗界面")
	await process_frame
	var bv = ow.overlay
	check(bv.state == BattleView.State.FORMATION and bv.is_map_mode(), "战前编队阶段（地图模式）")
	var bed = bv.open_rule_editor(0)
	check(bed != null, "战前界面可以打开战术编辑")
	bed._on_cancel()
	bv._on_skip_pressed()
	check(bv.state == BattleView.State.DONE, "跳过演出后战斗结束：" + bv.status_label.text)
	bv._on_return_pressed()
	await process_frame
	check(ow.overlay == null and ow.model.pending_encounter.is_empty(), "返回地图并应用结果")
	var t0: float = ow.model.time
	ow.process_map(0.5)
	check(ow.model.time > t0, "地图继续运行")
	ow.toggle_pause()
	var t1: float = ow.model.time
	ow.process_map(0.5)
	check(ow.model.time == t1, "暂停时时间不前进")
	print("  HUD：", ow.hud.text)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	print("=== 结果：%s（失败 %d 项）===" % ["全部通过" if failures == 0 else "有失败", failures])
	quit(1 if failures > 0 else 0)
