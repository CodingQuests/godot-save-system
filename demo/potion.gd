# A potion you pick up by walking over it. It saves nothing itself: it joins the
# "persist" group only so SaveManager can remove it on load once it has been
# collected. mark_removed() is the whole trick.
extends Area2D


func _ready() -> void:
	add_to_group("persist")
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if not body.has_method("add_potions"):
		return
	body.add_potions(1)
	SaveManager.mark_removed(self)
	queue_free()
