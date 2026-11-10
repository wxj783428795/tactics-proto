## 大地图上的编队编辑器：点击单位再点击另一格即可交换。
extends Control

signal closed
signal edit_tactics_requested(unit_index: int)

const UnitCell := preload("res://scripts/unit_cell.gd")
const MapModel := preload("res://scripts/map_model.gd")
const UI := preload("res://scripts/ui_util.gd")

var squad = null
var describer: Callable          # func(unit) -> String
var cells: Array = []
var selected_cell = null
var _info: Label


func setup(sq, describe_func: Callable) -> void:
	squad = sq
	describer = describe_func


func _ready() -> void:
	var box := UI.make_overlay(self, Vector2(640, 420))
	UI.label(box, "编队：%s（右侧为前排，面向敌人）" % squad.name, 18)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	box.add_child(hb)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	hb.add_child(grid)
	for c in 3:
		for r in [1, 0]:
			var cell := UnitCell.new()
			cell.team = 0
			cell.row = r
			cell.col = c
			cell.clicked.connect(_on_cell)
			grid.add_child(cell)
			cells.append(cell)
	_info = UI.label(hb, "点击单位查看战术。", 13)
	_info.custom_minimum_size = Vector2(260, 0)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var bar := HBoxContainer.new()
	box.add_child(bar)
	UI.button(bar, "编辑战术", func(): edit_tactics_requested.emit(_selected_index()))
	UI.button(bar, "完成", func(): closed.emit(); queue_free())
	refresh()


func _selected_index() -> int:
	if selected_cell != null and selected_cell.unit != null:
		return squad.units.find(selected_cell.unit)
	return 0


func refresh() -> void:
	for cell in cells:
		cell.unit = null
		for u in squad.units:
			if u.row == cell.row and u.col == cell.col:
				cell.unit = u
		cell.selected = cell == selected_cell
		cell.queue_redraw()


func _on_cell(cell) -> void:
	if cell.unit != null and describer.is_valid():
		_info.text = describer.call(cell.unit)
	if selected_cell == null:
		if cell.unit != null:
			selected_cell = cell
	elif selected_cell == cell:
		selected_cell = null
	else:
		MapModel.swap_slots(squad, selected_cell.row, selected_cell.col, cell.row, cell.col)
		selected_cell = null
	refresh()
