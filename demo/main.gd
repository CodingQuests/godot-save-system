# The demo: a room with potions to pick up, a chest to open, and three save
# slots. Everything in this script is demo scaffolding. The save system itself
# is save_system/SaveManager.gd (an autoload) and save_system/SaveUtils.gd.
extends Node2D

const SLOT_COUNT := 3
const GRID := 32
const ROOM := Rect2(-208, -144, 416, 288)

@onready var _player := $Player
@onready var _potions_label: Label = $HUD/Potions
@onready var _status: Label = $HUD/Panel/Margin/VBox/Status

var _slot_info: Array[Label] = []
var _load_buttons: Array[Button] = []
var _delete_buttons: Array[Button] = []


func _ready() -> void:
	_build_slot_rows()
	_player.potions_changed.connect(_on_potions_changed)
	_on_potions_changed(_player.potions)
	SaveManager.after_save.connect(_on_after_save)
	SaveManager.after_load.connect(_on_after_load)
	SaveManager.save_failed.connect(_on_failed.bind("Save"))
	SaveManager.load_failed.connect(_on_failed.bind("Load"))
	_refresh_slots()


func _draw() -> void:
	draw_rect(ROOM, Color(0.11, 0.1, 0.13))
	var x := ROOM.position.x
	while x <= ROOM.end.x:
		draw_line(Vector2(x, ROOM.position.y), Vector2(x, ROOM.end.y), Color(1, 1, 1, 0.05))
		x += GRID
	var y := ROOM.position.y
	while y <= ROOM.end.y:
		draw_line(Vector2(ROOM.position.x, y), Vector2(ROOM.end.x, y), Color(1, 1, 1, 0.05))
		y += GRID
	draw_rect(ROOM, Color(0.45, 0.4, 0.5), false, 3.0)


func _build_slot_rows() -> void:
	var rows: VBoxContainer = $HUD/Panel/Margin/VBox/Slots
	for slot_id in range(1, SLOT_COUNT + 1):
		var row := VBoxContainer.new()
		var line := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = "Slot %d" % slot_id
		name_label.custom_minimum_size = Vector2(60, 0)
		line.add_child(name_label)
		for action in ["Save", "Load", "Delete"]:
			var button := Button.new()
			button.text = action
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.focus_mode = Control.FOCUS_NONE
			button.pressed.connect(_on_slot_button.bind(action, slot_id))
			line.add_child(button)
			if action == "Load":
				_load_buttons.append(button)
			elif action == "Delete":
				_delete_buttons.append(button)
		row.add_child(line)
		var info := Label.new()
		info.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		info.add_theme_font_size_override("font_size", 13)
		row.add_child(info)
		_slot_info.append(info)
		rows.add_child(row)


func _on_slot_button(action: String, slot_id: int) -> void:
	SaveManager.current_slot_id = slot_id
	match action:
		"Save":
			SaveManager.save_current_slot(_summary())
		"Load":
			# Reload the room first, so potions picked up after the save come back.
			SaveManager.reload_and_load_current_slot()
		"Delete":
			SaveManager.delete_slot(slot_id)
			_status.text = "Deleted slot %d." % slot_id
			_refresh_slots()


func _summary() -> String:
	var chest_open := false
	for chest in get_tree().get_nodes_in_group("persist"):
		if "opened" in chest and chest.opened:
			chest_open = true
	var potions := "1 potion" if _player.potions == 1 else "%d potions" % _player.potions
	return "%s, chest %s" % [potions, "open" if chest_open else "closed"]


func _refresh_slots() -> void:
	for i in SLOT_COUNT:
		var slot_id := i + 1
		var info := SaveManager.get_slot_info(slot_id)
		if info.is_empty():
			_slot_info[i].text = "Empty"
		else:
			# meta.json stores UTC; shift by the system time zone to show local time.
			var local_unix := int(info.get("updated_unix", 0)) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
			var when := Time.get_datetime_string_from_unix_time(local_unix, true)
			_slot_info[i].text = "%s  (saved %s)" % [info.get("summary", ""), when.substr(11)]
		_load_buttons[i].disabled = info.is_empty()
		_delete_buttons[i].disabled = info.is_empty()


func _on_potions_changed(count: int) -> void:
	_potions_label.text = "Potions: %d" % count


func _on_after_save(slot_id: int) -> void:
	_status.text = "Saved slot %d." % slot_id
	_refresh_slots()


func _on_after_load(slot_id: int, _state: Dictionary) -> void:
	_status.text = "Loaded slot %d." % slot_id
	_refresh_slots()


func _on_failed(slot_id: int, error: Error, what: String) -> void:
	_status.text = "%s failed for slot %d: %s" % [what, slot_id, error_string(error)]
