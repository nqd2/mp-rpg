extends Node2D

@export var dust_texture: Texture2D
@export var sprite_scale: float = 4.0
@export var fps: float = 14.0

const COLS := 4

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	if dust_texture == null:
		push_error("Missing `dust_texture` on DustHit effect.")
		queue_free()
		return

	animated_sprite.scale = Vector2(sprite_scale, sprite_scale)
	animated_sprite.sprite_frames = _build_frames(dust_texture)
	animated_sprite.animation_finished.connect(_on_finished)
	animated_sprite.play("hit")


func _on_finished() -> void:
	queue_free()


func _build_frames(texture: Texture2D) -> SpriteFrames:
	var w := texture.get_width()
	var h := texture.get_height()
	var frame_w := int(w / COLS)
	var frame_h := h

	var frames := SpriteFrames.new()
	frames.add_animation("hit")
	frames.set_animation_loop("hit", false)
	frames.set_animation_speed("hit", fps)

	for col in range(COLS):
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2i(col * frame_w, 0, frame_w, frame_h)
		frames.add_frame("hit", atlas)

	return frames
