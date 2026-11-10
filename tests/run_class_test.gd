## 新职业与新机制测试：godot --headless --path . --script res://tests/run_class_test.gd
## 覆盖：兵种标签与克制、拒马、首击加成、纵列攻击、越过前排、挑衅/无视挑衅、斩杀、
##       会心/不屈、闪避/必中、增益/减益与持续时间、锐气赋予、新战术条件、规则编辑器新下拉框。
extends SceneTree

const BattleEngine := preload("res://scripts/battle_engine.gd")
const BattleUnit := preload("res://scripts/battle_unit.gd")
const Schema := preload("res://scripts/tactics_schema.gd")
const RuleEditor := preload("res://scripts/rule_editor.gd")

const NEW_CLASSES := ["cavalry", "assassin", "warden", "bard", "spearman", "skywing"]

var failures := 0
var cdata: Dictionary


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  [OK] ", msg)
	else:
		failures += 1
		printerr("  [FAIL] ", msg)


## 用简写创建战斗：每个单位 [名字, 职业, row, col]，可选第 5 项为战术
func make(p: Array, e: Array, seed: int = 1) -> BattleEngine:
	var units: Array = []
	for team in [0, 1]:
		for d in (p if team == 0 else e):
			var data := {"name": d[0], "row": d[2], "col": d[3]}
			if d.size() > 4:
				data["tactics"] = d[4]
			units.append(BattleUnit.from_data(d[1], cdata["classes"][d[1]], data, team))
	var eng := BattleEngine.new()
	var ok := eng.setup_with_units(cdata["skills"], cdata["passives"], cdata["classes"], units, ["甲队", "乙队"])
	if not ok:
		printerr("setup 校验失败")
	eng.battle_seed = seed
	eng.reset_battle(true)
	return eng


func unit(eng, name: String):
	for u in eng.units:
		if u.display_name == name:
			return u
	return null


func _initialize() -> void:
	cdata = BattleEngine.load_json("res://data/classes.json")
	var skills: Dictionary = cdata["skills"]

	print("=== 1. 数据完整性 ===")
	for cid in NEW_CLASSES:
		var c: Dictionary = cdata["classes"].get(cid, {})
		var ok: bool = not c.is_empty() and not c.get("tags", []).is_empty()
		for sid in c.get("skills", []):
			ok = ok and skills.has(sid)
		for rule in c.get("default_tactics", []):
			ok = ok and Schema.validate_rule(rule, c["skills"]) == ""
		check(ok, "%s（%s）标签 %s，技能 %s，默认战术 %d 条均合法" % [c.get("name", cid), cid, str(c.get("tags")), str(c.get("skills")), c.get("default_tactics", []).size()])

	print("=== 2. 兵种克制 / 拒马 / 首击 ===")
	var e := make([["枪", "spearman", 0, 0], ["骑", "cavalry", 0, 1], ["弓", "archer", 1, 0]],
		[["敌骑", "cavalry", 0, 0], ["敌剑", "swordsman", 0, 1], ["敌翼", "skywing", 1, 1], ["敌枪", "spearman", 0, 2]])
	var spear = unit(e, "枪")
	var cav = unit(e, "敌骑")
	var sword = unit(e, "敌剑")
	sword.defense = cav.defense
	var d_cav: float = e.base_damage(spear, cav, skills["thrust"])
	var d_inf: float = e.base_damage(spear, sword, skills["thrust"])
	check(is_equal_approx(d_cav, 30 * 0.85 * 1.6 - 12) and is_equal_approx(d_inf, 30 * 0.85 - 12), "贯穿刺对骑兵 %.1f vs 对步兵 %.1f（×1.6 克制）" % [d_cav, d_inf])
	var archer = unit(e, "弓")
	var wing = unit(e, "敌翼")
	check(is_equal_approx(e.base_damage(archer, wing, skills["arrow"]), 30 * 1.5 - 8), "弓箭对飞行 ×1.5：%.1f" % e.base_damage(archer, wing, skills["arrow"]))
	var my_cav = unit(e, "骑")
	var enemy_spear = unit(e, "敌枪")
	sword.defense = enemy_spear.defense
	var vs_spear: float = e.base_damage(my_cav, enemy_spear, skills["charge"])
	var vs_sword: float = e.base_damage(my_cav, sword, skills["charge"])
	check(is_equal_approx(vs_spear, vs_sword * 0.6), "「拒马」：骑兵打枪兵 %.1f = 打剑士 %.1f × 0.6" % [vs_spear, vs_sword])
	var first: float = e.base_damage(my_cav, sword, skills["charge"], true)
	check(is_equal_approx(first, 33 * 1.6 - sword.defense), "奔袭突击首次行动 ×1.6：%.1f（平时 %.1f）" % [first, vs_sword])
	var act: Dictionary = e.choose_action(my_cav)
	check(act["rule"]["if"] == "self_first_action", "骑兵默认战术：首次行动 → 奔袭突击")
	my_cav.has_acted = true
	act = e.choose_action(my_cav)
	check(act["rule"]["if"] != "self_first_action", "行动过后「本场首次行动」条件不再成立（改用：%s）" % BattleEngine.describe_rule(act["rule"]))

	print("=== 3. 纵列攻击 / 越过前排 ===")
	var e3 := make([["枪", "spearman", 0, 1, [{"if": "always", "skill": "thrust", "pick": "first"}]], ["刺", "assassin", 0, 0], ["剑", "swordsman", 0, 2]],
		[["前1", "swordsman", 0, 1], ["后1", "cleric", 1, 1], ["后2", "mage", 1, 2]])
	var t3: Array = e3.choose_action(unit(e3, "枪"))["targets"]
	check(t3.size() == 2 and t3[0].display_name == "前1" and t3[1].display_name == "后1", "贯穿刺命中同一列前后两人：%s" % str(t3.map(func(x): return x.display_name)))
	var reach_assassin: Array = e3.reachable_targets(unit(e3, "刺"), skills["shadow_strike"])
	var reach_sword: Array = e3.reachable_targets(unit(e3, "剑"), skills["slash"])
	check(reach_assassin.any(func(x): return x.row == 1) and reach_sword.all(func(x): return x.row == 0), "刺客可攻击后排（%d 个目标），剑士只能打前排（%d 个）" % [reach_assassin.size(), reach_sword.size()])
	var aact: Dictionary = e3.choose_action(unit(e3, "刺"))
	check(aact["targets"][0].class_id == "cleric", "刺客默认战术优先刺杀敌方牧师（后排）")
	unit(e3, "刺").row = 1
	check(is_equal_approx(e3.base_damage(unit(e3, "刺"), unit(e3, "后2"), skills["shadow_strike"]), 31 * 0.9 - 5), "越过前排的技能在后排使用没有近战惩罚")

	print("=== 4. 挑衅 / 无视挑衅 / 斩杀 ===")
	var e4 := make([["剑", "swordsman", 0, 0, [{"if": "always", "skill": "slash", "pick": "lowest_hp"}]], ["弓", "archer", 1, 0, [{"if": "always", "skill": "arrow", "pick": "lowest_hp"}]],
		["刺", "assassin", 0, 2, [{"if": "always", "skill": "throat_cut", "pick": "lowest_hp"}]], ["法", "mage", 1, 1, [{"if": "always", "skill": "thunder_row", "pick": "first"}]]],
		[["盾", "warden", 0, 1], ["脆", "mage", 0, 0], ["奶", "cleric", 1, 1]])
	var warden = unit(e4, "盾")
	var w_act: Dictionary = e4.choose_action(warden)
	check(w_act["skill_id"] == "provoke" and w_act["targets"] == [warden], "盾卫默认战术：未挑衅 → 挑衅怒吼（自身）")
	var lines := PackedStringArray()
	e4._act(warden, lines)
	check(warden.has_status("taunt") and is_equal_approx(warden.stat_mult("def"), 1.3), "获得挑衅与防御+30%%（防御 %d → %d）" % [warden.defense, warden.eff_def()])
	check(e4.choose_action(unit(e4, "剑"))["targets"] == [warden], "剑士本想打 HP 最低的法师，被挑衅吸引到盾卫")
	check(e4.choose_action(unit(e4, "弓"))["targets"] == [warden], "弓箭单体攻击同样被吸引")
	check(e4.choose_action(unit(e4, "刺"))["targets"][0].display_name == "脆", "断喉无视挑衅")
	check(e4.choose_action(unit(e4, "法"))["targets"].size() == 2, "横排魔法不受挑衅影响")
	check(e4.choose_action(warden).get("skill_id", "") != "provoke", "挑衅中不会重复挑衅")
	var squishy = unit(e4, "脆")
	var full_hp: float = e4.base_damage(unit(e4, "刺"), squishy, skills["throat_cut"])
	squishy.hp = int(squishy.max_hp * 0.4)
	var low_hp: float = e4.base_damage(unit(e4, "刺"), squishy, skills["throat_cut"])
	check(is_equal_approx(low_hp, 31 * 1.2 * 1.6 - 5) and low_hp > full_hp, "断喉斩杀：目标 HP<50%% 时 %.1f（满血 %.1f）" % [low_hp, full_hp])
	warden.tick_statuses()
	check(warden.has_status("taunt"), "第 1 次结算后挑衅仍在（剩 1 轮）")
	warden.tick_statuses()
	check(not warden.has_status("taunt") and is_equal_approx(warden.stat_mult("def"), 1.0), "2 轮后挑衅与增防结束")

	print("=== 5. 会心 / 不屈 / 闪避 / 必中 ===")
	var e5 := make([["刺", "assassin", 0, 0], ["法", "mage", 1, 0]], [["剑", "swordsman", 0, 0], ["盾", "warden", 0, 1]], 7)
	var assassin = unit(e5, "刺")
	assassin.crit = 100
	unit(e5, "剑").eva = 0
	var out := PackedStringArray()
	e5._do_hit(assassin, unit(e5, "剑"), skills["shadow_strike"], out)
	check("\n".join(out).contains("会心"), "会心率 100%：" + out[0].strip_edges())
	out = PackedStringArray()
	e5._do_hit(assassin, unit(e5, "盾"), skills["shadow_strike"], out)
	check(not "\n".join(out).contains("会心"), "「不屈」免疫会心：" + out[0].strip_edges())
	var dodger = unit(e5, "剑")
	dodger.eva = 100
	var hp0: int = dodger.hp
	out = PackedStringArray()
	var hit: bool = e5._do_hit(assassin, dodger, skills["shadow_strike"], out)
	check(not hit and dodger.hp == hp0 and out[0].contains("闪避"), "闪避率 100%：" + out[0].strip_edges())
	out = PackedStringArray()
	check(e5._do_hit(unit(e5, "法"), dodger, skills["ember"], out) and dodger.hp < hp0, "魔法必中，无视闪避：" + out[0].strip_edges())
	# 统计：25% 闪避的刺客被攻击 400 次
	var e6 := make([["剑", "swordsman", 0, 0]], [["刺", "assassin", 0, 0]], 42)
	var att = unit(e6, "剑")
	att.crit = 0
	var tgt = unit(e6, "刺")
	var misses := 0
	for i in 400:
		tgt.hp = tgt.max_hp
		var o := PackedStringArray()
		if not e6._do_hit(att, tgt, skills["slash"], o):
			misses += 1
	check(misses > 60 and misses < 140, "刺客 25%% 闪避：400 次中闪避 %d 次" % misses)

	print("=== 6. 增益 / 减益 / 锐气赋予 ===")
	var e7 := make([["吟", "bard", 1, 1], ["剑", "swordsman", 0, 0], ["枪", "spearman", 0, 1]],
		[["敌剑", "swordsman", 0, 0], ["敌重", "guardian", 0, 1]])
	var bard = unit(e7, "吟")
	var s7 = unit(e7, "剑")
	var a7: Dictionary = e7.choose_action(bard)
	check(a7["skill_id"] == "battle_hymn" and a7["targets"].size() == 3, "吟游者：有队友无增益 → 破晓战歌（全体 3 人）")
	e7._act(bard, PackedStringArray())
	check(s7.eff_atk() == int(round(34 * 1.2)), "战歌后剑士攻击 %d → %d" % [s7.atk, s7.eff_atk()])
	s7.add_status(cdata["skills"]["battle_hymn"]["effects"][0])
	check(is_equal_approx(s7.stat_mult("atk"), 1.2), "同一状态不叠加，只刷新持续时间")
	s7.ep = 0
	a7 = e7.choose_action(bard)
	check(a7["skill_id"] == "tempo" and a7["targets"] == [s7], "有队友锐气≤0 → 疾律给剑士（不会给自己）")
	e7._act(bard, PackedStringArray())
	check(s7.ep == 1 and s7.eff_spd() > s7.spd, "剑士锐气 0 → %d，速度 %d → %d" % [s7.ep, s7.spd, s7.eff_spd()])
	bard.ep = 2
	a7 = e7.choose_action(bard)
	check(a7.get("skill_id", "") == "dirge", "目标无减益 → 低回哀曲")
	e7._act(bard, PackedStringArray())
	var es = unit(e7, "敌剑")
	check(es.eff_atk() == int(round(34 * 0.8)) and es.has_debuff(), "哀曲后敌方攻击 %d → %d" % [es.atk, es.eff_atk()])
	check(e7.choose_action(bard).is_empty(), "全员已有增益、敌人都有减益、锐气不足 → 吟游者待机")
	var spear7 = unit(e7, "枪")
	var g7 = unit(e7, "敌重")
	var a8: Dictionary = e7.choose_action(spear7)
	check(a8.get("skill_id", "") == "armor_break" and a8["targets"] == [g7], "枪兵：目标是重装 → 破甲刺")
	var e8 := make([["枪", "spearman", 0, 1, [{"if": "target_no_debuff", "skill": "armor_break", "pick": "first"}, {"if": "always", "skill": "thrust"}]]],
		[["重", "guardian", 0, 1]], 3)
	var sp8 = unit(e8, "枪")
	var g8 = unit(e8, "重")
	sp8.crit = 0
	e8._act(sp8, PackedStringArray())
	check(g8.has_debuff() and g8.eff_def() == int(round(20 * 0.7)), "破甲：重甲防御 %d → %d（2 轮）" % [g8.defense, g8.eff_def()])
	sp8.ep = 2
	check(e8.choose_action(sp8)["skill_id"] == "thrust", "目标已有减益 → 跳过破甲规则")

	print("=== 7. 战术条件元数据与规则编辑器 ===")
	var ids := Schema.CONDITIONS.map(func(c): return c["id"])
	var needed := ["self_first_action", "self_not_taunting", "ally_no_buff", "ally_ep_at_most", "target_has_tag", "target_no_debuff"]
	check(needed.all(func(x): return ids.has(x)), "新条件已加入编辑器下拉框：%s" % str(needed))
	var described := needed.map(func(x): return BattleEngine.describe_rule(Schema.make_rule("slash", x)))
	check(not described.any(func(t): return needed.has(t)), "新条件都有中文描述：%s" % "、".join(PackedStringArray(described)))
	check(Schema.PICKS.any(func(p): return p["id"] == "highest_spd"), "新目标选择：速度最高")
	var e9 := make([["枪", "spearman", 0, 0], ["吟", "bard", 1, 0]], [["敌", "swordsman", 0, 0]])
	var ed := RuleEditor.new()
	ed.setup([unit(e9, "枪"), unit(e9, "吟")], cdata["skills"], cdata["classes"], 0)
	root.add_child(ed)
	await process_frame
	var row0: Node = ed._rows.get_child(0)
	var tag_dd: Array = row0.get_children().filter(func(c): return c is OptionButton and c.item_count == Schema.TAGS.size())
	check(not tag_dd.is_empty() and tag_dd[0].get_item_text(tag_dd[0].selected) == "骑兵", "枪兵第 1 条规则显示「目标兵种是 [骑兵]」下拉框")
	Schema.set_condition(ed.draft_for(0)[0], "ally_ep_at_most")
	ed._rebuild()
	await process_frame
	var spins: Array = ed._rows.get_child(0).get_children().filter(func(c): return c is SpinBox)
	check(not spins.is_empty() and spins[0].min_value == 0, "切换为「有队友锐气至多」后显示 0~3 数值框")
	check(ed._skill_help.text.contains("对骑兵威力×1.6"), "编辑器显示技能说明")
	ed._on_cancel()

	print("=== 8. 全职业混战（固定种子可复现） ===")
	var roster_a := [["凯", "cavalry", 0, 0], ["盾", "warden", 0, 1], ["枪", "spearman", 0, 2], ["吟", "bard", 1, 0], ["刺", "assassin", 1, 1], ["奶", "cleric", 1, 2]]
	var roster_b := [["翼", "skywing", 0, 0], ["重", "guardian", 0, 1], ["骑", "cavalry", 0, 2], ["弓", "archer", 1, 0], ["法", "mage", 1, 1], ["吟2", "bard", 1, 2]]
	var b1 := make(roster_a, roster_b, 99)
	var log1: PackedStringArray = b1.run_to_end()
	var b2 := make(roster_a, roster_b, 99)
	var log2: PackedStringArray = b2.run_to_end()
	for l in log1:
		print("    ", l)
	check(b1.finished and log1 == log2, "战斗结束，同种子日志完全一致")
	check(b1.units.all(func(u): return u.hp >= 0 and u.hp <= u.max_hp and u.ep >= 0), "所有单位数值合法")
	var text := "\n".join(log1)
	for cid in NEW_CLASSES:
		var job: String = cdata["classes"][cid]["name"]
		check(text.contains("(%s·" % job), "%s 在混战中出手" % job)
	for kw in ["挑衅", "破晓战歌", "奔袭突击"]:
		check(text.contains(kw), "日志中出现「%s」" % kw)
	b1.reset_battle(true)
	check(b1.units.all(func(u): return u.statuses.is_empty() and not u.has_acted), "重置战斗会清除状态与首击标记")

	print("=== 结果：%s（失败 %d 项）===" % ["全部通过" if failures == 0 else "有失败", failures])
	quit(1 if failures > 0 else 0)
