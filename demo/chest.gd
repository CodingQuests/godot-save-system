# A chest that opens once and stays open. It stores its own flag under its own
# id, so you can drop as many chests in a level as you like.
extends Area2D

const CLOSED := preload("res://assets/kenney_tiny-dungeon/tile_0089.png")
const OPEN := preload("res://assets/kenney_tiny-dungeon/tile_0091.png")

@export var potions_inside: int = 3

var opened := false
var _player_near: Node = null


func _ready() -> void:
	add_to_group("persist")
	body_entered.connect(func(body: Node) -> void:
		if body.is_in_group("player"):
			_player_near = body
	)
	body_exited.connect(func(body: Node) -> void:
		if body == _player_near:
			_player_near = null
	)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and _player_near and not opened:
		opened = true
		_player_near.add_potions(potions_inside)
		_refresh()


func _process(_delta: float) -> void:
	$Prompt.visible = _player_near != null and not opened


func _refresh() -> void:
	$Sprite2D.texture = OPEN if opened else CLOSED


func save_to_state(state: Dictionary) -> void:
	state[SaveManager.persist_id(self)] = {"opened": opened}


func load_from_state(state: Dictionary) -> void:
	var data: Dictionary = state.get(SaveManager.persist_id(self), {})
	opened = bool(data.get("opened", false))
	_refresh()
