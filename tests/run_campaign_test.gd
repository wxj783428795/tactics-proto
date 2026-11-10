## 成长 / 装备 / 名册 / 战役流程 / 存档测试：
##   godot --headless --path . --script res://tests/run_campaign_test.gd
extends SceneTree

const BattleEngine := preload("res://scripts/battle_engine.gd")
const BattleUnit := preload("res://scripts/battle_unit.gd")
const MapModel := preload("res://scripts/map_model.gd")
const Progression := preload("res://scripts/progression.gd")
const CampaignState := preload("res://scripts/campaign_state.gd")
const Game := preload("res://scripts/game.gd")

const TEST_SAVE := "user://test_campaign_save.json"

var failures := 0
var classes: Dictionary
var items: Dictionary


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  [OK] ", msg)
	else:
		failures += 1
		printerr("  [FAIL] ", msg)


func unit(cid: String, lv: int = 1, extra: Dictionary = {}):
	var d := {"name": "测试" + cid, "level": lv}
	d.merge(extra)
	var u = BattleUnit.from_data(cid, classes[cid], d, 0)
	u.apply_class(classes[cid], items)
	u.hp = u.max_hp
	return u


## 自动驾驶：按任务目标指挥我方，遭遇自动结算。返回 [地图, 战斗场数]
func autopilot(model, max_time: float = 900.0) -> Array:
	var battles := 0
	var target := ""
	match str(model.objective.get("type", "")):
		"capture_hq":
			target = model.hq_of(1)
		"defeat_boss":
			target = model.squad_by_id(str(model.objective["squad"])).home
	var guard = model.living_squads(0)[-1] if model.living_squads(0).size() > 1 else null
	while not model.game_over and model.time < max_time:
		for sq in model.living_squads(0):
			if target == "" or sq.is_moving():
				continue
			if sq == guard and model.living_squads(0).size() > 1:
				model.order_move(sq, model.hq_of(0))  # 最后一支小队留守大本营
				continue
			var here: String = model.node_of(sq)
			var resting: bool = here != "" and model.nodes[here]["owner"] == 0 and (sq.hp_ratio() < 0.85 or sq.stamina < 50.0)
			if resting:
				continue
			if sq.hp_ratio() < 0.5:  # 残血：回最近的己方据点休整（不再有败退瞬移回营）
				var safe: String = model.nearest_friendly_node(sq)
				if safe != "":
					model.order_move(sq, safe)
					continue
			model.order_move(sq, target)
		model.update(0.1)
		if not model.pending_encounter.is_empty():
			model.resolve_encounter_auto()
			battles += 1
	return [model, battles]


func _init() -> void:
	var cdata = BattleEngine.load_json("res://data/classes.json")
	classes = cdata["classes"]
	for sid in cdata["skills"]:
		Progression.skill_names[sid] = cdata["skills"][sid]["name"]
	items = BattleEngine.load_json("res://data/items.json")["items"]

	print("=== 1. 经验与升级 ===")
	var u = unit("swordsman")
	u.battle_actions = 3
	u.battle_kills = 2
	check(Progression.battle_xp(u, true) == 3 * 5 + 2 * 15 + 20, "战斗经验 = 行动×5 + 击倒×15 + 胜利20（=%d）" % Progression.battle_xp(u, true))
	check(Progression.battle_xp(u, false) == 3 * 5 + 2 * 15 + 5, "失利只得 5 点基础经验")
	var hp1: int = u.max_hp
	var atk1: int = u.atk
	check(not u.skills.has("shadow_bind"), "Lv1 剑士尚未习得「缚影斩」")
	var lines: PackedStringArray = Progression.gain_xp(u, 250, classes, items)
	var g: Dictionary = classes["swordsman"]["growth"]
	check(u.level == 3 and u.xp == 50, "获得 250 经验：Lv1 → Lv3，剩余 50（实际 Lv%d / %d）" % [u.level, u.xp])
	check(u.max_hp == hp1 + 2 * int(g["hp"]) and u.atk == atk1 + 2 * int(g["atk"]), "属性按职业成长率增长（HP %d→%d，攻 %d→%d）" % [hp1, u.max_hp, atk1, u.atk])
	check(u.skills.has("shadow_bind"), "Lv3 解锁「缚影斩」")
	check("\n".join(lines).contains("习得新技能「缚影斩」"), "升级提示包含习得技能：%s" % " / ".join(lines))
	var top = unit("archer", Progression.MAX_LEVEL)
	Progression.gain_xp(top, 500, classes, items)
	check(top.level == Progression.MAX_LEVEL and top.xp == 0, "满级后不再获得经验")
	var g2 = unit("guardian")
	var g2b = unit("guardian")
	g2.level = 4
	g2.apply_class(classes["guardian"], items)
	check(g2.defense == g2b.defense + 3 * int(classes["guardian"]["growth"]["def"]), "重甲成长：Lv4 防御 = 基础 + 3×成长")

	print("=== 2. 转职 ===")
	var p = unit("swordsman", 4)
	check(not Progression.can_promote(p, classes), "Lv4 剑士不能转职")
	check(Progression.promote(p, classes, items) == "", "条件不足时转职失败")
	Progression.gain_xp(p, 100, classes, items)
	check(p.level == 5 and Progression.can_promote(p, classes), "升到 Lv5 后可以转职")
	var before_atk: int = p.atk
	var msg := Progression.promote(p, classes, items)
	print("    ", msg)
	check(p.class_id == "blademaster" and p.job_name == "锋刃宗师" and p.level == 5, "剑士 → 锋刃宗师，等级保留")
	check(p.skills.has("thousand_edges") and p.skills.has("slash"), "转职后获得「千锋连闪」并保留原技能")
	check(str(p.tactics[0].get("skill", "")) == "thousand_edges", "新技能规则被放在战术列表首位")
	check(p.atk > before_atk, "转职后攻击提升（%d → %d）" % [before_atk, p.atk])
	check(not Progression.can_promote(p, classes), "进阶职业不能再次转职")
	for base in ["swordsman", "guardian", "archer", "mage", "cleric"]:
		var to := str(classes[base]["promotion"]["to"])
		var nu = unit(base, 5)
		Progression.promote(nu, classes, items)
		var adv_skill := ""
		for s in classes[to]["skills"]:
			if not classes[base]["skills"].has(s):
				adv_skill = s
		check(nu.class_id == to and nu.skills.has(adv_skill) and int(classes[to].get("tier", 1)) == 2,
			"%s → %s（新技能 %s）" % [classes[base]["name"], classes[to]["name"], adv_skill])

	print("=== 3. 装备数值 ===")
	var inv: Array = ["greysteel_knife", "tidemark_axe", "riveted_mail", "dawnstar_badge", "wardrum_charm"]
	var e = unit("swordsman", 2)
	var base_atk: int = e.atk
	var base_spd: int = e.spd
	var base_def: int = e.defense
	check(Progression.equip(e, "greysteel_knife", inv, classes, items) and e.atk == base_atk + 3, "装备灰钢短刃：攻击 +3")
	check(not inv.has("greysteel_knife"), "装备后从库存移除")
	Progression.equip(e, "tidemark_axe", inv, classes, items)
	check(e.atk == base_atk + 6 and e.spd == base_spd - 1 and inv.has("greysteel_knife"), "换成潮纹战斧：攻击 +6 速度 -1，旧武器回到库存")
	Progression.equip(e, "riveted_mail", inv, classes, items)
	check(e.defense == base_def + 5 and e.spd == base_spd - 2, "铆钉链甲：防御 +5，速度累计 -2")
	var ep0: int = e.max_ep
	Progression.equip(e, "dawnstar_badge", inv, classes, items)
	check(e.max_ep == ep0 + 1, "晨星徽章：锐气上限 +1")
	check(not Progression.equip(e, "northwall_tower", inv, classes, items), "库存中没有的道具无法装备")
	Progression.equip(e, "wardrum_charm", inv, classes, items)
	check(inv.has("dawnstar_badge") and e.equipment["accessory"] == "wardrum_charm", "同部位替换饰品")
	var foe = unit("guardian")
	foe.team = 1
	var eng := BattleEngine.new()
	eng.setup_with_units(cdata["skills"], cdata["passives"], classes, [e, foe], ["甲", "乙"])
	eng.reset_battle(true)
	check(e.has_status("war_drum") and absf(e.stat_mult("atk") - 1.15) < 0.001, "战鼓护符：开战时攻击 +15%%")
	Progression.unequip(e, "weapon", inv, classes, items)
	Progression.unequip(e, "armor", inv, classes, items)
	check(e.atk == base_atk and e.defense == base_def and e.spd == base_spd, "卸下装备后属性还原")
	check(items.size() >= 15, "道具数据共 %d 件" % items.size())

	print("=== 4. 名册、招募与编队 ===")
	var st = CampaignState.new()
	check(st.new_game(), "新游戏初始化")
	check(st.roster.size() == 7 and st.squad_units(0).size() == 4 and st.squad_units(1).size() == 3, "初始名册 7 人，晨星小队 4 人，苍狼小队 3 人")
	check(st.gold == 300 and st.unit_by_uid("u_凯岚").equipment.get("weapon", "") == "greysteel_knife", "初始资金 300，凯岚持有灰钢短刃")
	check(st.unit_by_uid("u_凯岚").atk == int(classes["swordsman"]["atk"]) + int(classes["swordsman"]["growth"]["atk"]) + 3, "名册单位的属性计入等级与装备")
	check(st.available_recruits().size() == 3, "开局可招募 3 人（其余需推进剧情）")
	check(not st.recruit("r_lange"), "未解锁的招募者无法招募")
	check(st.recruit("r_youling") and st.gold == 100, "招募柚铃花费 200 金")
	check(not st.recruit("r_hezhao"), "金币不足（100 < 250）时招募失败")
	var yl = st.unit_by_uid("u_柚铃")
	check(yl != null and st.squad_of(yl.uid) == 0 and st.squad_units(0).size() == 5, "新成员自动编入有空位的晨星小队")
	check(yl.row == 1, "治疗职业优先放在后排")
	var hz = st.make_unit({"name": "多余", "class": "cavalry"})
	st.roster.append(hz)
	check(not st.assign(hz.uid, 0), "小队已满 5 人时无法再编入")
	check(st.assign(hz.uid, 1) and st.squad_units(1).size() == 4, "编入苍狼小队")
	check(st.assign(hz.uid, -1) and st.squad_of(hz.uid) == -1 and st.reserve_units().size() == 1, "移回待命")
	check(st.assign(hz.uid, 2) and st.deployable_squads() == [0, 1, 2], "编入银枝小队后 3 支小队可出击")
	st.assign(hz.uid, -1)
	var slots := {}
	var dup := false
	for uu in st.squad_units(0):
		var key := Vector2i(uu.row, uu.col)
		dup = dup or slots.has(key)
		slots[key] = true
	check(not dup, "小队内没有重叠的格子")

	print("=== 5. 金币经济（据点收入 / 占领奖励 / 战斗奖励）===")
	var m1 = st.create_mission_model(0)
	check(m1 != null and m1.progression_enabled, "生成第一章地图")
	check(st.create_mission_model(1) == null, "第二章尚未解锁")
	m1.ai_enabled = false
	var inc: int = m1.income_per_tick(0)
	check(inc == 20, "开局只有大本营：每 10 秒收入 20（实际 %d）" % inc)
	for i in 101:  # 0.1 累加有浮点误差，多推进一帧
		m1.update(0.1)
	check(m1.gold_from_bases == 20, "10 秒后据点收入 20（实际 %d）" % m1.gold_from_bases)
	var sq0 = m1.living_squads(0)[0]
	m1.order_move(sq0, "farm")
	var ev_all: Array = []
	for i in 200:
		ev_all.append_array(m1.update(0.1))
		if m1.nodes["farm"]["owner"] == 0:
			break
	check(m1.nodes["farm"]["owner"] == 0, "占领芦花农庄")
	check(ev_all.any(func(x): return x["type"] == "reward"), "占领时获得据点奖励")
	var g_before: int = m1.gold_earned
	check(m1.income_per_tick(0) == 30, "占领后每轮收入 30")
	var ab: int = m1.battles_won
	var scout = m1.squad_by_id("e_scout")
	m1.pending_encounter = [sq0, scout]
	m1.apply_battle_result(sq0, scout, 0)
	check(m1.battles_won == ab + 1 and m1.gold_earned == g_before + MapModel.BATTLE_GOLD, "战斗胜利 +%d 金" % MapModel.BATTLE_GOLD)
	check(m1.xp_gained.has("u_凯岚") and int(m1.xp_gained["u_凯岚"]) >= 20, "参战成员获得经验")

	print("=== 6. 战役流程 1 → 2 → 3 ===")
	var c = CampaignState.new()
	c.new_game()
	for uu in c.roster:  # 测试用：提高等级，保证自动驾驶能稳定通关
		uu.level = 6
		uu.apply_class(c.classes[uu.class_id], c.items)
	check(c.next_mission_index() == 0 and c.is_unlocked(0) and not c.is_unlocked(1), "初始只开放第一章")
	var gold0: int = c.gold
	var r1: Array = autopilot(c.create_mission_model(0))
	var res1: Dictionary = c.finish_mission(r1[0])
	print("    第一章：%s，用时 %.0f 秒，战斗 %d 场，金币 +%d，道具 %s" % ["胜利" if res1["won"] else "失败", res1["time"], r1[1], res1["gold_total"], str(res1["items"])])
	check(res1["won"] and c.cleared == ["m1"], "第一章胜利（攻陷大本营）")
	check(c.gold == gold0 + res1["gold_total"] and res1["gold_reward"] == 200, "结算金币写回（任务奖励 200）")
	check(res1["items"].has("鸣羽长弓") and c.inventory.has("singing_bow"), "获得任务奖励道具「鸣羽长弓」")
	check(c.unit_by_uid("u_夜棠") != null and res1["joined"].size() == 1, "剧情加入：夜棠")
	check(c.is_unlocked(1) and c.available_recruits().size() == 5, "第二章与新招募者解锁")
	var r2: Array = autopilot(c.create_mission_model(1))
	var res2: Dictionary = c.finish_mission(r2[0])
	print("    第二章：%s，用时 %.0f 秒，%s" % ["胜利" if res2["won"] else "失败", res2["time"], res2["reason"]])
	check(res2["won"] and c.cleared.has("m2"), "第二章胜利（坚守）")
	check(c.unit_by_uid("u_岳衡") != null and c.unit_by_uid("u_落笙") != null, "剧情加入：岳衡、落笙")
	for uu in c.roster:  # 终章前转职
		if Progression.can_promote(uu, c.classes):
			c.promote(uu.uid)
	var r3: Array = autopilot(c.create_mission_model(2))
	var res3: Dictionary = c.finish_mission(r3[0])
	print("    第三章：%s，用时 %.0f 秒，%s" % ["胜利" if res3["won"] else "失败", res3["time"], res3["reason"]])
	check(res3["won"] and c.is_complete(), "第三章胜利，战役完成")
	check(res3["progress"] is PackedStringArray or res3["progress"] is Array, "结算包含成长记录（%d 条）" % res3["progress"].size())

	print("=== 7. 失败结算 ===")
	var d = CampaignState.new()
	d.new_game()
	var dm = d.create_mission_model(0)
	dm._end_game(1, [], "测试")
	var gd0: int = d.gold
	var dres: Dictionary = d.finish_mission(dm)
	check(not dres["won"] and d.gold == gd0 and d.cleared.is_empty() and d.current_mission == -1, "失败：不获得金币与道具，任务不计完成")

	print("=== 8. 存档 / 读档 ===")
	check(c.save(TEST_SAVE), "写入存档")
	var l = CampaignState.new()
	check(l.load_save(TEST_SAVE), "读取存档")
	check(JSON.stringify(l.to_dict()) == JSON.stringify(c.to_dict()), "读档后数据与存档前完全一致")
	var k1 = c.unit_by_uid("u_凯岚")
	var k2 = l.unit_by_uid("u_凯岚")
	check(k2.level == k1.level and k2.class_id == k1.class_id and k2.atk == k1.atk and k2.max_hp == k1.max_hp, "凯岚：Lv%d %s 攻%d HP%d" % [k2.level, k2.job_name, k2.atk, k2.max_hp])
	check(l.gold == c.gold and l.inventory == c.inventory and l.cleared == c.cleared, "金币 / 库存 / 进度一致")
	check(typeof(k2.tactics[0].get("value", 0)) != TYPE_FLOAT or not str(k2.tactics[0].get("if")).ends_with("at_least"), "整数型条件值读档后仍为整数")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))

	print("=== 9. 平衡参考（默认等级、自动驾驶，仅供参考，不计入通过/失败）===")
	var b = CampaignState.new()
	b.new_game()
	for i in 3:
		var rr: Array = autopilot(b.create_mission_model(i))
		var resb: Dictionary = b.finish_mission(rr[0])
		var lv := PackedStringArray()
		for uu in b.roster:
			lv.append("%s%d" % [uu.display_name, uu.level])
		print("    第%d章：%s 用时 %.0f 秒 战斗 %d 场（胜 %d 负 %d）金币 %d | %s" % [i + 1, "胜利" if resb["won"] else "失败", resb["time"], rr[1], resb["battles_won"], resb["battles_lost"], b.gold, " ".join(lv)])
		if not resb["won"]:
			break
		for uu in b.roster:
			if Progression.can_promote(uu, b.classes):
				b.promote(uu.uid)

	await _scene_checks()
	print("=== 结果：%s（失败 %d 项）===" % ["全部通过" if failures == 0 else "有失败", failures])
	quit(1 if failures > 0 else 0)


func _scene_checks() -> void:
	print("=== 10. 界面场景（无头加载与交互）===")
	var st = CampaignState.new()
	st.new_game()
	Game.state = st
	# 标题
	var title = load("res://scenes/title.tscn").instantiate()
	title.save_path = TEST_SAVE
	root.add_child(title)
	await process_frame
	check(title.continue_btn.disabled, "标题：没有存档时「继续」不可用")
	st.save(TEST_SAVE)
	title.refresh()
	check(not title.continue_btn.disabled, "标题：有存档后「继续」可用")
	title.queue_free()
	# 剧情
	Game.story_title = st.missions[0]["title"]
	Game.story_lines = st.missions[0]["pre_story"]
	Game.story_next = Game.SCENE_CAMP
	var story = load("res://scenes/story.tscn").instantiate()
	root.add_child(story)
	await process_frame
	check(story.text_label.text == str(st.missions[0]["pre_story"][0]["text"]), "剧情：显示第一句")
	story.advance()
	check(story.index == 1 and story.name_label.text == str(st.missions[0]["pre_story"][1]["who"]), "剧情：推进到第二句（%s）" % story.name_label.text)
	story.queue_free()
	# 营地
	var camp = load("res://scenes/camp.tscn").instantiate()
	root.add_child(camp)
	await process_frame
	var mbtns: Array = camp.mission_box.get_children().filter(func(c): return c is Button)
	check(mbtns.size() == 3 and not mbtns[0].disabled and mbtns[1].disabled and mbtns[2].disabled, "营地：3 个任务，只有第一章可选")
	check(not camp.sortie_btn.disabled and camp.brief_text.text.contains("白石渡"), "营地：显示简报，可以出击")
	camp.open_recruit()
	await process_frame
	check(camp.overlay != null, "营地：打开招募窗口")
	var g0: int = st.gold
	camp._do_recruit("r_youling", camp.overlay.get_child(1).get_child(0).get_child(0))
	check(st.gold == g0 - 200 and camp.message.text.contains("柚铃"), "营地：招募柚铃（%s）" % camp.message.text)
	camp.close_overlay()
	camp.queue_free()
	# 部队管理
	var roster = load("res://scenes/roster.tscn").instantiate()
	root.add_child(roster)
	await process_frame
	check(roster.unit_list.item_count == st.roster.size(), "名册：列出全部 %d 名成员" % st.roster.size())
	roster.select_unit("u_铎岩")
	var opt: OptionButton = roster.slot_opts["armor"]
	var idx := -1
	for i in opt.item_count:
		if str(opt.get_item_metadata(i)) == "wayfarer_leather":
			idx = i
	var def0: int = st.unit_by_uid("u_铎岩").defense
	roster._on_equip_selected("armor", idx)
	check(idx > 0 and st.unit_by_uid("u_铎岩").defense == def0 + 2 and not st.inventory.has("wayfarer_leather"), "名册：通过下拉框装备旅人皮甲（防御 +2）")
	roster._on_equip_selected("armor", 0)
	check(st.unit_by_uid("u_铎岩").defense == def0 and st.inventory.has("wayfarer_leather"), "名册：选择（无）卸下装备")
	roster.select_unit("u_寒栎")
	roster._on_squad_selected(0)
	check(st.squad_of("u_寒栎") == -1, "名册：把寒栎移到待命")
	roster._on_squad_selected(2)
	check(st.squad_of("u_寒栎") == 1, "名册：再编回苍狼小队")
	var kl = st.unit_by_uid("u_凯岚")
	Progression.gain_xp(kl, 300, st.classes, st.items)
	roster.select_unit("u_凯岚")
	check(not roster.promote_btn.disabled and roster.promote_btn.text.contains("锋刃宗师"), "名册：Lv5 显示转职按钮（%s）" % roster.promote_btn.text)
	var pop = roster.do_promote()
	await process_frame
	check(pop != null and kl.class_id == "blademaster", "名册：转职为锋刃宗师并弹出提示")
	roster.close_overlay()
	var ed = roster.open_tactics()
	await process_frame
	var found := false
	for ob in ed.find_children("*", "OptionButton", true, false):
		for i in ob.item_count:
			found = found or ob.get_item_text(i).contains("千锋连闪")
	check(found, "战术编辑器中可以选择转职新技能「千锋连闪」")
	ed.queue_free()
	var fe = roster.open_formation()
	await process_frame
	check(fe != null, "名册：打开小队编队窗口")
	fe.queue_free()
	roster.queue_free()
	# 大地图（任务模式）
	st.current_mission = 0
	var ow = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(ow)
	await process_frame
	check(ow.mission_mode and ow.hud.text.contains("攻陷敌方大本营"), "大地图：任务模式，HUD 显示目标")
	check(ow.model.living_squads(0).size() == st.deployable_squads().size(), "大地图：出击小队数与编成一致")
	for i in 30:
		ow.process_map(0.5)
	check(ow.model.time > 10.0 and ow.hud.text.contains("本场资金"), "大地图：时间推进，资金累计（+%d）" % ow.model.gold_earned)
	ow.abandon_mission()
	check(ow.model.game_over and ow.model.winner == 1 and ow.overlay != null, "大地图：撤退 → 任务失败弹窗")
	Game.last_result = st.finish_mission(ow.model)
	ow.queue_free()
	# 战报
	var rs = load("res://scenes/results.tscn").instantiate()
	root.add_child(rs)
	await process_frame
	check(rs.body.text.contains("经验"), "战报：显示经验与成长记录")
	rs.queue_free()
	await process_frame
	Game.state = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
