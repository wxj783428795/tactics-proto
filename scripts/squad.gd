## 大地图上的一支小队（纯数据）。units 为 BattleUnit 对象，战斗时直接交给 BattleEngine，HP 自然延续。
extends RefCounted

var id: String = ""
var name: String = ""
var team: int = 0
var color: Color = Color.WHITE
var units: Array = []
var pos: Vector2 = Vector2.ZERO
var at_node: String = ""      # 最近经过/所在的节点
var path: Array = []          # 接下来要依次到达的节点 id
var stamina: float = 100.0    # 体力：行军消耗，己方据点内恢复
var ai: Dictionary = {}       # 敌方 AI 配置：{"mode": "defend"/"patrol"/"advance", ...}
var home: String = ""
var alive: bool = true
var regen_timer: float = 0.0
var patrol_index: int = 0
var recover_time: float = 0.0  # 战后整备剩余秒数：期间原地不动、不会触发遭遇
var pursue_target = null        # 追击目标（敌方小队）；为 null 时按普通行军
var repath_timer: float = 0.0
var stunned: bool = false      # 死守据点战败、无路可退时陷入硬直（同样计入 recover_time）


func is_recovering() -> bool:
	return recover_time > 0.0


func is_moving() -> bool:
	return not path.is_empty()


func destination() -> String:
	return path.back() if not path.is_empty() else at_node


func living_count() -> int:
	var n := 0
	for u in units:
		if u.is_alive():
			n += 1
	return n


func hp_ratio() -> float:
	var cur := 0
	var mx := 0
	for u in units:
		cur += u.hp
		mx += u.max_hp
	return float(cur) / float(max(1, mx))
