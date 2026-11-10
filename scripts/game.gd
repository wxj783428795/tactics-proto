## 跨场景共享的全局状态（静态变量，不使用 autoload，方便无头测试）。
extends RefCounted

const SCENE_TITLE := "res://scenes/title.tscn"
const SCENE_CAMP := "res://scenes/camp.tscn"
const SCENE_ROSTER := "res://scenes/roster.tscn"
const SCENE_STORY := "res://scenes/story.tscn"
const SCENE_MAP := "res://scenes/overworld.tscn"
const SCENE_RESULTS := "res://scenes/results.tscn"
const SCENE_QUICK := "res://scenes/battle_test.tscn"

static var state = null          # CampaignState；为 null 时大地图进入沙盒模式
static var story_title: String = ""
static var story_lines: Array = []   # [{who, text}]
static var story_next: String = ""   # 剧情结束后切换到的场景
static var last_result: Dictionary = {}


static func play_story(tree: SceneTree, title: String, lines: Array, next_scene: String) -> void:
	if lines.is_empty():
		tree.change_scene_to_file(next_scene)
		return
	story_title = title
	story_lines = lines
	story_next = next_scene
	tree.change_scene_to_file(SCENE_STORY)
