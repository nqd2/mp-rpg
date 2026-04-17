@tool
extends Node2D

@export var tile_texture: Texture2D

# Source image is 16x16, but we scale it to match the player sprite (x4).
@export var tile_size: int = 16
@export var tile_scale: float = 4.0

@export var grid_width: int = 50
@export var grid_height: int = 30

@export var background_z_index: int = -1

func _ready() -> void:
	# When running in-editor (@tool), avoid duplicating children on reload.
	for c in get_children():
		c.queue_free()

	if tile_texture == null:
		push_error("Missing `tile_texture` on Background node.")
		return

	var tex := tile_texture
	var scaled_step := int(tile_size * tile_scale)

	# Generate a simple tiled floor using Sprite2D instances.
	for x in range(grid_width):
		for y in range(grid_height):
			var s := Sprite2D.new()
			s.texture = tex
			s.centered = false
			s.scale = Vector2(tile_scale, tile_scale)
			s.position = Vector2(x * scaled_step, y * scaled_step)
			s.z_index = background_z_index
			add_child(s)
