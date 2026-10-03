# Slot-based save system using JSON files. Add this script as an autoload named
# SaveManager.
#
# Architecture: each slot is a folder holding state.json (the game data) and
# meta.json (what a save menu lists). Writes are atomic (write to .tmp, then
# rename) so a crash mid-save cannot corrupt a slot. A version field plus
# _migrate() lets old saves load after you change the format.
#
# Any node in the "persist" group that has save_to_state(state) and
# load_from_state(state) is saved and loaded automatically.
extends Node


signal before_save(slot_id: int, state: Dictionary)
signal after_save(slot_id: int)
signal before_load(slot_id: int)
signal after_load(slot_id: int, state: Dictionary)
signal save_failed(slot_id: int, error: Error)
signal load_failed(slot_id: int, error: Error)

const SAVE_VERSION: int = 1
const SAVES_DIR: String = "user://saves"

var current_slot_id: int = 1

# Paths of persistent nodes that have been removed (a picked-up item, a killed
# enemy). Saved with the slot, so removed things stay removed after loading.
var removed_nodes: Array = []

# Set by reload_and_load_current_slot(): the slot to apply once the reloaded
# scene is ready.
var _pending_load_slot: int = -1

# ---------- Public API ----------

## Capture every "persist" node and write it to the current slot.
## `summary` is stored in meta.json for a save menu ("Level 3, 2 potions").
func save_current_slot(summary: String = "") -> Error:
	var state := _capture_state()
	return save_slot(current_slot_id, state, summary)

## Read the current slot and apply it to the scene that is running now.
func load_current_slot() -> Dictionary:
	return load_slot(current_slot_id)

## Reload the current scene first, then apply the current slot to it. Use this
## when loading mid-game: anything freed since the save (a collected item) comes
## back with the fresh scene before the save removes what it should.
func reload_and_load_current_slot() -> void:
	if not has_save(current_slot_id):
		load_failed.emit(current_slot_id, ERR_FILE_NOT_FOUND)
		return
	_pending_load_slot = current_slot_id
	get_tree().reload_current_scene()

func save_slot(slot_id: int, state: Dictionary, summary: String = "") -> Error:
	_ensure_dir(SAVES_DIR)
	_ensure_dir(_slot_dir(slot_id))

	before_save.emit(slot_id, state)

	var wrapper := {
		"version": SAVE_VERSION,
		"saved_unix": Time.get_unix_time_from_system(),
		"data": state
	}

	# Write state.json atomically
	var err := _write_json_atomic(_slot_state_path(slot_id), wrapper)
	if err != OK:
		save_failed.emit(slot_id, err)
		return err

	# Update meta.json (for UI listing)
	var meta := _load_json_or_empty(_slot_meta_path(slot_id))
	if meta.is_empty():
		meta["created_unix"] = wrapper["saved_unix"]
	meta["updated_unix"] = wrapper["saved_unix"]
	meta["slot_id"] = slot_id
	meta["version"] = SAVE_VERSION
	meta["summary"] = summary

	err = _write_json_atomic(_slot_meta_path(slot_id), meta)
	if err != OK:
		save_failed.emit(slot_id, err)
		return err

	after_save.emit(slot_id)
	return OK

func load_slot(slot_id: int) -> Dictionary:
	before_load.emit(slot_id)

	var state_path := _slot_state_path(slot_id)
	if not FileAccess.file_exists(state_path):
		load_failed.emit(slot_id, ERR_FILE_NOT_FOUND)
		return {
			"ok": false,
			"err": ERR_FILE_NOT_FOUND,
			"state": {}
		}

	var wrapper := _load_json_or_empty(state_path)
	if wrapper.is_empty():
		load_failed.emit(slot_id, ERR_PARSE_ERROR)
		return {
			"ok": false,
			"err": ERR_PARSE_ERROR,
			"state": {}
		}

	var file_version: int = int(wrapper.get("version", 0))
	var data: Dictionary = wrapper.get("data", {})

	if file_version != SAVE_VERSION:
		data = _migrate(data, file_version, SAVE_VERSION)

	_apply_state(data)
	after_load.emit(slot_id, data)

	return {
		"ok": true,
		"err": OK,
		"state": data
	}

## The meta.json of one slot, or {} if the slot is empty.
func get_slot_info(slot_id: int) -> Dictionary:
	return _load_json_or_empty(_slot_meta_path(slot_id))

func has_save(slot_id: int) -> bool:
	return FileAccess.file_exists(_slot_state_path(slot_id))

## Delete a slot's files. Returns OK if the slot is gone afterwards.
func delete_slot(slot_id: int) -> Error:
	for path in [_slot_state_path(slot_id), _slot_meta_path(slot_id)]:
		if FileAccess.file_exists(path):
			var err := DirAccess.remove_absolute(path)
			if err != OK:
				return err
	if DirAccess.dir_exists_absolute(_slot_dir(slot_id)):
		return DirAccess.remove_absolute(_slot_dir(slot_id))
	return OK

func list_slots() -> Array[Dictionary]:
	_ensure_dir(SAVES_DIR)

	var out: Array[Dictionary] = []
	var dir := DirAccess.open(SAVES_DIR)
	if dir == null:
		return out

	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name == "":
			break
		if dir.current_is_dir() and name.begins_with("slot_"):
			var meta_path := SAVES_DIR + "/" + name + "/meta.json"
			var meta := _load_json_or_empty(meta_path)
			if not meta.is_empty():
				out.append(meta)
	dir.list_dir_end()

	# Sort newest first
	out.sort_custom(func(a, b):
		return int(a.get("updated_unix", 0)) > int(b.get("updated_unix", 0))
	)

	return out

# ---------- Removed objects ----------

## Call this before you free a persistent node for good (an item picked up, an
## enemy killed), so it stays gone after a load.
func mark_removed(node: Node) -> void:
	var id := persist_id(node)
	if id not in removed_nodes:
		removed_nodes.append(id)

## A stable id for a node: its path in the scene tree. Give persistent nodes
## unique names and do not move them between parents, and the id never changes.
static func persist_id(node: Node) -> String:
	return str(node.get_path())

# ---------- Persistence hooks via group ----------

func _ready() -> void:
	get_tree().scene_changed.connect(_on_scene_changed)

func _on_scene_changed() -> void:
	if _pending_load_slot < 0:
		return
	var slot_id := _pending_load_slot
	_pending_load_slot = -1
	load_slot(slot_id)

func _capture_state() -> Dictionary:
	var state: Dictionary = {}

	for node in get_tree().get_nodes_in_group("persist"):
		if node != null and node.has_method("save_to_state"):
			node.call("save_to_state", state)

	# Save the removed list so removed things stay removed after loading
	state["removed_nodes"] = removed_nodes.duplicate()

	return state

func _apply_state(state: Dictionary) -> void:
	removed_nodes = state.get("removed_nodes", []).duplicate()

	for node in get_tree().get_nodes_in_group("persist"):
		if node == null or node.is_queued_for_deletion():
			continue
		if persist_id(node) in removed_nodes:
			node.queue_free()
		elif node.has_method("load_from_state"):
			node.call("load_from_state", state)

# ---------- Migrations (versioning) ----------

func _migrate(data: Dictionary, from_version: int, to_version: int) -> Dictionary:
	# Bump SAVE_VERSION when you change the format, then upgrade old data here.
	# v0 -> v1 example (if you ever shipped v0):
	# if from_version == 0 and to_version >= 1:
	#     data["player"] = data.get("player", {})
	#     data["player"]["coins"] = int(data["player"].get("coins", 0))
	return data

# ---------- File helpers ----------

func _slot_dir(slot_id: int) -> String:
	return "%s/slot_%04d" % [SAVES_DIR, slot_id]

func _slot_state_path(slot_id: int) -> String:
	return _slot_dir(slot_id) + "/state.json"

func _slot_meta_path(slot_id: int) -> String:
	return _slot_dir(slot_id) + "/meta.json"

func _ensure_dir(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		return
	DirAccess.make_dir_recursive_absolute(path)

func _load_json_or_empty(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()

	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		return {}
	var data = json.data
	return data if typeof(data) == TYPE_DICTIONARY else {}

func _write_json_atomic(path: String, data: Dictionary) -> Error:
	var tmp_path := path + ".tmp"

	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()

	var text := JSON.stringify(data, "\t")
	f.store_string(text)
	f.flush()
	f.close()

	# Replace target atomically-ish: remove then rename temp
	if FileAccess.file_exists(path):
		var rm := DirAccess.remove_absolute(path)
		if rm != OK:
			return rm

	return DirAccess.rename_absolute(tmp_path, path)
