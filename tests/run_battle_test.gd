## 无头战斗测试：godot --headless --path . --script res://tests/run_battle_test.gd
## 1) 用默认数据跑完整场战斗并打印日志；2) 检查若干不变量；3) 实例化主场景并自动跑一局。
extends SceneTree

const BattleEngine := preload("res://scripts/battle_engine.gd")
const MainScript := preload("res://scripts/battle_view.gd")

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  [OK] ", msg)
	else:
		failures += 1
		printerr("  [FAIL] ", msg)


func _initialize() -> void:
	print("=== 测试 1：纯逻辑战斗模拟 ===")
	var eng := BattleEngine.new()
	check(eng.load_data("res://data/classes.json", "res://data/battle_setup.json"), "数据加载与校验通过")
	eng.reset_battle()
	var lines := eng.run_to_end()
	for l in lines:
		print(l)
	check(eng.finished, "战斗在步数上限内结束")
	for u in eng.units:
		check(u.hp >= 0 and u.hp <= u.max_hp and u.ep >= 0 and u.gp >= 0,
			"%s 数值合法 HP %d/%d EP %d GP %d" % [u.display_name, u.hp, u.max_hp, u.ep, u.gp])

	print("=== 测试 2：同数据再跑一次，结果应可复现（确定性） ===")
	var eng2 := BattleEngine.new()
	eng2.load_data("res://data/classes.json", "res://data/battle_setup.json")
	eng2.reset_battle()
	var lines2 := eng2.run_to_end()
	check(lines == lines2 and eng.winner == eng2.winner, "两次日志一致")

	print("=== 测试 3：战术条件 ===")
	var eng3 := BattleEngine.new()
	eng3.load_data("res://data/classes.json", "res://data/battle_setup.json")
	eng3.reset_battle()
	var cleric = eng3.units.filter(func(u): return u.display_name == "汐音")[0]
	var sword = eng3.units.filter(func(u): return u.display_name == "凯岚")[0]
	check(eng3.choose_action(cleric).is_empty(), "全员满血时牧师不治疗（待机）")
	sword.hp = 30
	var act := eng3.choose_action(cleric)
	check(not act.is_empty() and act["skill_id"] == "mend" and act["targets"][0] == sword, "队友 HP<50% 时牧师对其施放愈光")
	var archer = eng3.units.filter(func(u): return u.display_name == "青翎")[0]
	var a2 := eng3.choose_action(archer)
	check(a2["skill_id"] == "piercing_shot" and a2["targets"][0].class_id == "mage", "弓手按第 1 条规则狙击敌方法师")
	var enemy_sword = eng3.units.filter(func(u): return u.display_name == "佣兵·芮卡")[0]
	var a3 := eng3.choose_action(enemy_sword)
	check(a3["targets"][0].row == 0, "近战只能攻击前排")

	print("=== 测试 4：主场景实例化并自动打完 ===")
	var scene: PackedScene = load("res://scenes/battle_test.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	await process_frame
	main._on_start_pressed()
	var guard := 0
	while main.state != MainScript.State.DONE and guard < 500:
		main.advance_battle()
		guard += 1
	await process_frame
	check(main.state == MainScript.State.DONE, "UI 战斗结束：" + main.status_label.text)
	main._on_restart_pressed()
	check(main.state == MainScript.State.FORMATION, "重新开始回到编队阶段")
	# 模拟编队：点击我方 凯岚(前排0) 再点空格 前排第3格
	var c_from = main.cells.filter(func(c): return c.team == 0 and c.row == 0 and c.col == 0)[0]
	var c_to = main.cells.filter(func(c): return c.team == 0 and c.row == 0 and c.col == 2)[0]
	main._on_cell_clicked(c_from)
	main._on_cell_clicked(c_to)
	check(c_to.unit != null and c_to.unit.display_name == "凯岚", "点击交换阵型生效")
	main._on_restart_pressed()
	var moved = main.engine.unit_at(0, 0, 2)
	check(moved != null and moved.display_name == "凯岚", "重新开始后保留玩家阵型")

	print("=== 测试 5：独立战斗中编辑战术（规则编辑器 UI）===")
	var ed = main.open_rule_editor(0)
	await process_frame
	var first = ed.units[0]
	var before: int = first.tactics.size()
	ed._on_add()
	await process_frame
	check(ed.draft_for(0).size() == before + 1 and first.tactics.size() == before, "添加规则只改草稿")
	ed._on_save()
	await process_frame
	check(first.tactics.size() == before + 1, "保存后写回单位（%d → %d 条）" % [before, first.tactics.size()])
	main._on_restart_pressed()
	var again = main.engine.units.filter(func(u): return u.display_name == first.display_name)[0]
	check(again.tactics.size() == before + 1, "重新开始后保留编辑过的战术")

	print("=== 结果：%s（失败 %d 项）===" % ["全部通过" if failures == 0 else "有失败", failures])
	quit(1 if failures > 0 else 0)
