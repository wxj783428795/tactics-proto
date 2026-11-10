# 生成 data/campaign/*.json（地图、任务、招募）。全部为原创内容。
import json, os
OUT = os.path.join(os.path.dirname(__file__), "..", "data", "campaign")
os.makedirs(OUT, exist_ok=True)
FRONT = {"swordsman", "guardian", "cavalry", "assassin", "warden", "spearman", "blademaster", "bulwark"}

def units(lst):
    out, used = [], set()
    for name, cls, lv in lst:
        rows = [0, 1] if cls in FRONT else [1, 0]
        for r in rows:
            c = next((c for c in (1, 0, 2) if (r, c) not in used), None)
            if c is not None:
                used.add((r, c)); break
        out.append({"name": name, "class": cls, "level": lv, "row": r, "col": c})
    return out

DURABILITY = {"hq": 100, "fort": 60}  # 大本营 / 要塞耐久；普通据点没有

def node(id, name, typ, owner, x, y, **kw):
    d = {"id": id, "name": name, "type": typ, "owner": owner, "pos": [x, y]}
    if typ in DURABILITY:
        d["durability"] = DURABILITY[typ]
    d.update(kw); return d

def squad(id, name, color, start, ai, lst):
    return {"id": id, "name": name, "team": 1, "color": color, "start": start, "ai": ai, "units": units(lst)}

map1 = {
  "name": "白石渡", "objective": {"type": "capture_hq"},
  "nodes": [
    node("camp", "晨星营地", "hq", 0, 80, 330),
    node("r1", "", "road", -1, 200, 200), node("r2", "", "road", -1, 200, 470),
    node("farm", "芦花农庄", "base", -1, 330, 150, reward={"gold": 60}),
    node("mill", "石磨坊", "base", -1, 330, 510, reward={"items": ["amber_locket"]}),
    node("ford", "白石渡口", "fort", 1, 470, 330, reward={"items": ["greysteel_knife"]}),
    node("r3", "", "road", -1, 610, 200), node("r4", "", "road", -1, 610, 470),
    node("watch", "望潮哨", "base", 1, 730, 140, reward={"gold": 30, "items": ["ember_dagger"]}),
    node("ehq", "渡口营寨", "hq", 1, 840, 340),
  ],
  "edges": [["camp","r1"],["camp","r2"],["r1","farm"],["r2","mill"],["farm","ford"],["mill","ford"],["camp","ford"],
            ["ford","r3"],["ford","r4"],["r3","watch"],["watch","ehq"],["r4","ehq"],["r3","ehq"]],
  "squads": [
    squad("e_scout", "灰烬斥候", "#c0392b", "ford", {"mode": "defend", "radius": 140},
          [("灰兵甲", "swordsman", 2), ("灰弓乙", "archer", 2), ("灰祷丙", "cleric", 2)]),
    squad("e_raid", "灰烬游骑", "#e67e22", "watch", {"mode": "advance", "delay": 45, "targets": ["farm", "camp"]},
          [("游骑甲", "cavalry", 2), ("游骑乙", "swordsman", 2), ("游骑丙", "archer", 2)]),
    squad("e_guard", "渡口守军", "#8e2b2b", "ehq", {"mode": "defend", "radius": 150},
          [("守军甲", "guardian", 3), ("守军乙", "swordsman", 3), ("守军丙", "mage", 3), ("守军丁", "archer", 3)]),
  ],
}

map2 = {
  "name": "风车丘", "objective": {"type": "defend", "time": 150},
  "nodes": [
    node("village", "风车丘村", "hq", 0, 230, 330),
    node("hut", "苇塘小屋", "base", 0, 90, 170),
    node("well", "古井集", "base", -1, 390, 150, reward={"gold": 80, "items": ["frostspine_pike"]}),
    node("orchard", "梨园", "base", -1, 370, 520, reward={"items": ["windrunner_cloak"]}),
    node("bridge", "碎石桥", "fort", -1, 540, 330, reward={"items": ["tidemark_axe"]}),
    node("r1", "", "road", -1, 700, 200), node("r2", "", "road", -1, 700, 470),
    node("sp1", "东林道口", "road", -1, 880, 170), node("sp2", "南滩道口", "road", -1, 880, 500),
  ],
  "edges": [["hut","village"],["village","well"],["village","orchard"],["village","bridge"],["well","bridge"],
            ["orchard","bridge"],["well","r1"],["bridge","r1"],["bridge","r2"],["orchard","r2"],["r1","sp1"],["r2","sp2"]],
  "squads": [
    squad("w1", "灰烬前锋", "#c0392b", "sp1", {"mode": "advance", "delay": 5, "targets": ["well", "village"]},
          [("前锋甲", "swordsman", 3), ("前锋乙", "spearman", 3), ("前锋丙", "archer", 3)]),
    squad("w2", "赤沙骑队", "#e67e22", "sp2", {"mode": "advance", "delay": 30, "targets": ["orchard", "village"]},
          [("赤沙甲", "cavalry", 4), ("赤沙乙", "cavalry", 4), ("赤沙丙", "mage", 4)]),
    squad("w3", "鸦羽突袭队", "#6c3483", "sp1", {"mode": "advance", "delay": 65, "targets": ["bridge", "village"]},
          [("鸦羽甲", "skywing", 4), ("鸦羽乙", "skywing", 4), ("鸦羽丙", "bard", 4), ("鸦羽丁", "archer", 4)]),
    squad("w4", "铁棘重步", "#7b241c", "sp2", {"mode": "advance", "delay": 95, "targets": ["bridge", "village"]},
          [("铁棘甲", "warden", 5), ("铁棘乙", "spearman", 5), ("铁棘丙", "cleric", 5), ("铁棘丁", "archer", 5)]),
  ],
}

map3 = {
  "name": "灰塔", "objective": {"type": "defeat_boss", "squad": "boss"},
  "nodes": [
    node("outpost", "晨星前哨", "hq", 0, 70, 500),
    node("r1", "", "road", -1, 180, 350), node("r2", "", "road", -1, 220, 590),
    node("ruins", "旧城墟", "base", -1, 300, 210, reward={"items": ["glowstone_staff"]}),
    node("salt", "盐田镇", "base", -1, 390, 570, reward={"gold": 100}),
    node("gate", "铁门关", "fort", 1, 480, 380, reward={"items": ["riveted_mail"]}),
    node("r3", "", "road", -1, 610, 220), node("r4", "断桥营", "fort", 1, 630, 540, reward={"gold": 80}),
    node("shrine", "风语祠", "base", 1, 720, 110, reward={"items": ["dawnstar_badge"]}),
    node("dock", "黑锚码头", "base", 1, 770, 580, reward={"items": ["wardrum_charm"]}),
    node("tower", "灰塔", "hq", 1, 860, 340, gold=30),
  ],
  "edges": [["outpost","r1"],["outpost","r2"],["r1","ruins"],["r1","gate"],["r2","salt"],["salt","gate"],
            ["ruins","r3"],["gate","r3"],["gate","r4"],["salt","r4"],["r3","shrine"],["r4","dock"],
            ["shrine","tower"],["dock","tower"],["r3","tower"],["r4","tower"]],
  "squads": [
    squad("gate_guard", "铁门守备队", "#c0392b", "gate", {"mode": "defend", "radius": 150},
          [("守备甲", "spearman", 6), ("守备乙", "guardian", 6), ("守备丙", "archer", 6), ("守备丁", "cleric", 6)]),
    squad("crows", "鸦羽巡哨", "#6c3483", "shrine", {"mode": "patrol", "route": ["shrine", "r3", "ruins", "r3"]},
          [("巡哨甲", "skywing", 6), ("巡哨乙", "archer", 6), ("巡哨丙", "bard", 6)]),
    squad("dock_raid", "黑锚突击队", "#e67e22", "dock", {"mode": "advance", "delay": 70, "targets": ["salt", "outpost"]},
          [("黑锚甲", "cavalry", 6), ("黑锚乙", "assassin", 6), ("黑锚丙", "mage", 6)]),
    squad("bridge_guard", "断桥守军", "#922b21", "r4", {"mode": "defend", "radius": 130},
          [("断桥甲", "warden", 6), ("断桥乙", "swordsman", 6), ("断桥丙", "mage", 6), ("断桥丁", "cleric", 6)]),
    squad("boss", "灰烬团长·索格", "#5d0f0f", "tower", {"mode": "defend", "radius": 170, "boss": True, "morale": 100},
          [("索格", "blademaster", 9), ("灰烬亲卫", "bulwark", 7), ("灰烬术士", "pyrosage", 7), ("灰烬司祭", "dawnpriest", 7), ("灰烬射手", "stargazer", 7)]),
  ],
}

def L(*pairs):
    return [{"who": w, "text": t} for w, t in pairs]

missions = {
  "prologue": L(
    ("旁白", "苇河自北向南穿过平原，两岸的村镇靠它运粮、磨面、过冬。"),
    ("旁白", "晨星营是一支只有七个人的小佣兵队，接的多是护送商队、驱赶狼群之类的零活。"),
    ("凯岚", "汐音，这回的委托信写了什么？"),
    ("汐音", "下游三个村子联名——「河上来了收税的兵，船过不去了。」报酬是……一百二十枚铜币和两车干草。"),
    ("铎岩", "哈，干草。给你们这些年轻人当床正好。"),
    ("凯岚", "去看看吧。要是真有人封了河，平原上的冬天会很难熬。"),
  ),
  "start": {
    "gold": 300,
    "inventory": ["wayfarer_leather", "votive_robe"],
    "squads": [
      {"id": "p_dawn", "name": "晨星小队", "color": "#4aa3df"},
      {"id": "p_wolf", "name": "苍狼小队", "color": "#5cb85c"},
      {"id": "p_silver", "name": "银枝小队", "color": "#d6b656"},
      {"id": "p_heron", "name": "白鹭小队", "color": "#d9a0e0"},
    ],
    "units": [
      {"name": "凯岚", "class": "swordsman", "level": 2, "squad": 0, "equipment": {"weapon": "greysteel_knife"}},
      {"name": "铎岩", "class": "guardian", "level": 1, "squad": 0},
      {"name": "青翎", "class": "archer", "level": 1, "squad": 0},
      {"name": "汐音", "class": "cleric", "level": 1, "squad": 0},
      {"name": "寒栎", "class": "swordsman", "level": 1, "squad": 1},
      {"name": "绯鸢", "class": "archer", "level": 1, "squad": 1},
      {"name": "焰朔", "class": "mage", "level": 1, "squad": 1},
    ],
  },
  "missions": [
    {
      "id": "m1", "goal": "攻陷敌方大本营「渡口营寨」", "title": "第一章　白石渡的火光", "map": "res://data/campaign/map1.json",
      "briefing": "灰烬佣兵团占据了苇河上的白石渡口，向过往粮船强收「过河税」。\n攻下渡口对岸的营寨，重新打开河道。\n\n提示：沿途的农庄与磨坊无人把守，先占下来可以获得补给与资金。",
      "difficulty": "★☆☆",
      "reward": {"gold": 200, "items": ["singing_bow"]},
      "join": [{"name": "夜棠", "class": "assassin", "level": 2}],
      "pre_story": L(
        ("旁白", "苇河平原，秋收时节。本该满载谷粮的河船，三天来一艘也没有靠岸。"),
        ("铎岩", "白石渡那边升起了黑旗。是灰烬团的人——一群只认钱的佣兵。"),
        ("凯岚", "所以河下游的村子才托我们晨星营过来。工钱不多，可总得有人去。"),
        ("汐音", "我在河祠抄过旧地图。渡口北面有座芦花农庄，南面是石磨坊，都能落脚。"),
        ("青翎", "那就先拿下两边，再从正面过桥。我的箭够得着对岸的哨塔。"),
        ("凯岚", "好。晨星营，出发！"),
      ),
      "post_story": L(
        ("旁白", "渡口营寨的黑旗被扯了下来。被困多日的船夫们划着空船靠了岸。"),
        ("???", "……别动手。我不是来打的。"),
        ("夜棠", "我叫夜棠，在灰烬团里当过探子。他们收的过河税，根本不归团长自己。"),
        ("凯岚", "那归谁？"),
        ("夜棠", "上游的「盐铁会」。他们想把整条苇河的粮道握在手里。下一个目标是风车丘。"),
        ("汐音", "风车丘的磨坊供着半个平原的面粉……要是落到他们手里，冬天就难熬了。"),
        ("凯岚", "夜棠，跟我们一起走吧。你认得他们的路数。"),
        ("夜棠", "……行。就当是还我自己一个人情。"),
      ),
    },
    {
      "id": "m2", "goal": "坚守「风车丘村」150 秒", "title": "第二章　守住风车丘", "map": "res://data/campaign/map2.json",
      "briefing": "灰烬团的援军正从东林与南滩两条道口压向风车丘村。\n守住村子 150 秒，直到村民撤离、邻镇的民兵赶到。\n\n提示：敌军分四批来袭，越往后越强。占下古井集与梨园能增加收入，但别让大本营空着太久。",
      "difficulty": "★★☆",
      "reward": {"gold": 300, "items": ["riveted_mail", "gale_plume"]},
      "join": [{"name": "岳衡", "class": "warden", "level": 3}, {"name": "落笙", "class": "bard", "level": 3}],
      "pre_story": L(
        ("旁白", "风车丘。十二架风车在丘顶缓缓转动，村民正把粮袋装上牛车。"),
        ("柏翁", "晨星营的各位，老朽是这里的村长。邻镇的民兵最快也要两刻钟才能到。"),
        ("岳衡", "我是镇上的守夜人岳衡。人手不够，我和我的盾就算一份。"),
        ("落笙", "还有我，落笙，唱曲的。别看我这样，鼓点一响，大家的腿脚都会快上几分。"),
        ("夜棠", "东边和南边各有一条道口。灰烬团惯用两路夹击，后面还会跟着鸦羽队。"),
        ("凯岚", "那就守住村口，撑到援军来。谁都别逞强。"),
      ),
      "post_story": L(
        ("旁白", "号角声从西边传来，邻镇的民兵举着火把翻过了丘顶。灰烬团的残兵向东退去。"),
        ("柏翁", "村子保住了……风车也保住了。这份恩情，风车丘记下了。"),
        ("岳衡", "凯岚队长，我想跟你们走一趟。守夜守了十年，这回想守点更大的东西。"),
        ("落笙", "我也去。好曲子总得有个结尾吧？"),
        ("夜棠", "灰烬团的团长索格在灰塔。只要他倒下，盐铁会就没了刀。"),
        ("凯岚", "那就去灰塔，把这件事做个了断。"),
      ),
    },
    {
      "id": "m3", "goal": "击败灰烬团长·索格（士气归零或全员倒下）", "title": "第三章　灰塔决战", "map": "res://data/campaign/map3.json",
      "briefing": "灰烬团长索格坐镇灰塔，身边有转职后的精锐亲卫。\n索格久经沙场，一场败仗打不垮他：每次战胜他的小队都会削减其「士气」（胜得越干净、我方剩余兵力越多，削得越狠），士气归零或其小队全员倒下即为讨伐成功（攻下灰塔也算胜利）。\n他的伤势会一直带着，只有回到灰塔里才会缓慢恢复，倒下的亲卫在本战中不会再站起来；士气也只在塔中休整时慢慢回升，别给他喘息的时间。\n战败的小队会原地「待机」片刻，此时被敌人攻击会遭到先制攻击——这对双方都一样。\n\n提示：铁门关有重兵把守，风语祠一带有鸦羽巡哨。建议先在营地为成员转职、整理装备与战术。",
      "difficulty": "★★★",
      "reward": {"gold": 500, "items": ["oathkeeper_ring", "northwall_tower"]},
      "join": [],
      "pre_story": L(
        ("旁白", "灰塔立在苇河上游的石岬上，原本是一座灯塔，如今塔顶燃着灰色的狼烟。"),
        ("夜棠", "索格以前是边境的老兵，后来拿了盐铁会的钱，就再没回头。"),
        ("汐音", "他手下的亲卫穿着重甲，还有会念禁咒的术士。我们得互相照应。"),
        ("铎岩", "老头子我挡在最前面。你们只管往塔里冲。"),
        ("凯岚", "这一仗之后，苇河上就不该再有人收过河税了。晨星营，全员出击！"),
      ),
      "post_story": L(
        ("索格", "……一群拿着微薄工钱的雇工，居然真能打到这里。"),
        ("凯岚", "工钱是少了点。可河边的人吃得上饭，这就够了。"),
        ("索格", "盐铁会的账本在塔顶。拿去吧……我也看厌了。"),
        ("旁白", "账本被送往平原各镇。盐铁会垄断粮道的事传开后，再也没人愿意替他们收税。"),
        ("旁白", "第二年春天，白石渡的渡船重新开张。船头挂着一面小小的晨星旗。"),
        ("凯岚", "下一单活儿，是什么来着？"),
        ("汐音", "帮风车丘的柏翁修风车。……工钱是一袋面粉。"),
        ("旁白", "—— 第一部　完 ——"),
      ),
    },
  ],
}

recruits = {"recruits": [
  {"id": "r_hezhao", "name": "赫照", "class": "cavalry", "level": 2, "cost": 250, "after": 0, "desc": "退役的驿站骑手，熟悉平原上的每一条小路。"},
  {"id": "r_yange", "name": "晏戈", "class": "spearman", "level": 2, "cost": 220, "after": 0, "desc": "渔村出身的枪兵，擅长对付骑兵。"},
  {"id": "r_youling", "name": "柚铃", "class": "cleric", "level": 2, "cost": 200, "after": 0, "desc": "草药铺的学徒，治疗手法稳当。"},
  {"id": "r_lange", "name": "澜歌", "class": "mage", "level": 3, "cost": 320, "after": 1, "desc": "流浪的术士，据说烧掉过半座书院。"},
  {"id": "r_jichuan", "name": "霁川", "class": "skywing", "level": 3, "cost": 320, "after": 1, "desc": "驯养巨隼的山民，能越过敌人的前排。"},
  {"id": "r_shiling", "name": "石苓", "class": "guardian", "level": 4, "cost": 400, "after": 2, "desc": "采石场的工头，一个人能扛起一扇城门。"},
]}

for name, data in [("map1", map1), ("map2", map2), ("map3", map3), ("missions", missions), ("recruits", recruits)]:
    with open(os.path.join(OUT, name + ".json"), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
print("ok")
