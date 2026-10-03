# Demo player for the save system. It joins the "persist" group so SaveManager
# finds it, and implements save_to_state() / load_from_state(): the pattern
# every persistent node follows. Its data lives under the "player" key.
extends CharacterBody2D

signal potions_changed(count: int)

@export var speed: float = 160.0

var potions: int = 0


func _ready() -> void:
	add_to_group("persist")
	add_to_group("player")


func _physics_process(_delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * speed
	move_and_slide()
	if absf(dir.x) > 0.1:
		$Sprite2D.flip_h = dir.x < 0.0


func add_potions(amount: int) -> void:
	potions += amount
	potions_changed.emit(potions)


# Called by SaveManager._capture_state(): write this node's data into the dict.
func save_to_state(state: Dictionary) -> void:
	state["player"] = {
		"position": SaveUtils.vec2_to_dict(global_position),
		"potions": potions,
	}


# Called by SaveManager._apply_state(): read this node's data back.
func load_from_state(state: Dictionary) -> void:
	var p: Dictionary = state.get("player", {})
	global_position = SaveUtils.dict_to_vec2(p.get("position", SaveUtils.vec2_to_dict(global_position)))
	potions = int(p.get("potions", 0))
	potions_changed.emit(potions)
