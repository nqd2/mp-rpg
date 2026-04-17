@tool
extends Node2D

@export var speed: float = 140.0
@export var sprite_scale: float = 4.0
@export var player_texture: Texture2D
@export var attack_damage: int = 1
@export var gesture_controller_path: NodePath

const COLS := 6
const ROWS := 10
const ATTACK_COLS := 4 # Rows for atk/defeated have only 4 meaningful columns (2 trailing columns are empty)

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var attack_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D

enum Facing { DOWN, SIDE, UP }

var last_facing: Facing = Facing.DOWN
var side_dir: float = 1.0 # 1 = facing right, -1 = facing left

var is_attacking: bool = false
var is_defeated: bool = false

var _already_hit: Dictionary = {}
var _gesture_controller: Node

func _ready() -> void:
	if not animated_sprite.animation_finished.is_connected(_on_animation_finished):
		animated_sprite.animation_finished.connect(_on_animation_finished)

	if not attack_hitbox.area_entered.is_connected(_on_attack_hitbox_area_entered):
		attack_hitbox.area_entered.connect(_on_attack_hitbox_area_entered)

	animated_sprite.scale = Vector2(sprite_scale, sprite_scale)
	attack_shape.disabled = true

	if player_texture == null:
		push_error("Missing `player_texture` on Player node.")
		return

	_build_sprite_frames(player_texture)
	_set_animation("down_idle", false)
	_gesture_controller = get_node_or_null(gesture_controller_path)


func _physics_process(delta: float) -> void:
	if is_defeated:
		return

	# Attack freezes movement/animation changes until the animation ends.
	if is_attacking:
		_apply_facing_visuals()
		return

	var input_vec := _get_movement_input()
	if input_vec != Vector2.ZERO:
		# Choose which axis drives the facing/animation (better than diagonal ambiguity).
		var axis_choice := Vector2.ZERO
		if abs(input_vec.x) > abs(input_vec.y):
			axis_choice = Vector2(input_vec.x, 0.0)
		else:
			axis_choice = Vector2(0.0, input_vec.y)

		_update_facing_from_axis_choice(axis_choice)
		position += axis_choice.normalized() * speed * delta

		_refresh_animation_for_move(true)
	else:
		_refresh_animation_for_move(false)


func _unhandled_input(event: InputEvent) -> void:
	if is_defeated:
		return

	if !is_attacking and event.is_action_pressed("ui_accept"):
		_start_attack()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_start_defeated()
		get_viewport().set_input_as_handled()


func _get_wasd_dir() -> Vector2:
	var x := float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
	var y := float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	return Vector2(x, y)


func _get_movement_input() -> Vector2:
	if _gesture_controller != null:
		if _gesture_controller.has_method("has_valid_state") and _gesture_controller.call("has_valid_state"):
			if _gesture_controller.has_method("get_movement_vector"):
				var gesture_vec := _gesture_controller.call("get_movement_vector") as Vector2
				return gesture_vec
	return _get_wasd_dir()


func _update_facing_from_axis_choice(axis_choice: Vector2) -> void:
	if axis_choice.x != 0.0:
		last_facing = Facing.SIDE
		side_dir = sign(axis_choice.x)
	else:
		if axis_choice.y < 0.0:
			last_facing = Facing.UP
		else:
			last_facing = Facing.DOWN

	_apply_facing_visuals()


func _apply_facing_visuals() -> void:
	if last_facing == Facing.SIDE:
		animated_sprite.flip_h = side_dir < 0.0
	else:
		animated_sprite.flip_h = false


func _refresh_animation_for_move(moving: bool) -> void:
	if is_defeated or is_attacking:
		return

	var desired := ""
	if moving:
		desired = _facing_to_walk_anim(last_facing)
	else:
		desired = _facing_to_idle_anim(last_facing)

	# Don't restart the animation every frame; only switch when needed.
	_set_animation(desired, false)


func _start_attack() -> void:
	if is_defeated or is_attacking:
		return

	is_attacking = true
	_already_hit.clear()
	_update_attack_hitbox_transform()
	attack_shape.disabled = false
	_apply_facing_visuals()
	_set_animation(_facing_to_attack_anim(last_facing), false)


func _start_defeated() -> void:
	if is_defeated:
		return

	is_defeated = true
	is_attacking = false
	attack_shape.disabled = true
	_apply_facing_visuals()
	_set_animation("defeated", false)


func _on_animation_finished() -> void:
	if is_attacking and animated_sprite.animation.ends_with("_attack"):
		is_attacking = false
		attack_shape.disabled = true
		_refresh_animation_for_move(_get_movement_input() != Vector2.ZERO)


func _set_animation(anim_name: String, allow_restart: bool) -> void:
	# allow_restart=true helps ensure we switch instantly when direction changes,
	# while allow_restart=false avoids disrupting end-of-attack animations.
	if allow_restart or animated_sprite.animation != anim_name:
		animated_sprite.play(anim_name)


func _build_sprite_frames(texture: Texture2D) -> void:
	var frame_w: int = texture.get_width() / COLS
	var frame_h: int = texture.get_height() / ROWS

	if frame_w <= 0 or frame_h <= 0:
		push_error("Invalid sprite sheet size for 6x10 grid.")
		return

	var frames := SpriteFrames.new()

	# Idle
	_add_row_animation(frames, "down_idle", 0, true, 6.0, texture, frame_w, frame_h)
	_add_row_animation(frames, "side_idle", 1, true, 6.0, texture, frame_w, frame_h)
	_add_row_animation(frames, "up_idle", 2, true, 6.0, texture, frame_w, frame_h)

	# Walk (rows 4-6)
	_add_row_animation(frames, "down_walk", 3, true, 10.0, texture, frame_w, frame_h)
	_add_row_animation(frames, "side_walk", 4, true, 10.0, texture, frame_w, frame_h)
	_add_row_animation(frames, "up_walk", 5, true, 10.0, texture, frame_w, frame_h)

	# Attack (rows 7-9)
	_add_row_animation(frames, "down_attack", 6, false, 12.0, texture, frame_w, frame_h, ATTACK_COLS)
	_add_row_animation(frames, "side_attack", 7, false, 12.0, texture, frame_w, frame_h, ATTACK_COLS)
	_add_row_animation(frames, "up_attack", 8, false, 12.0, texture, frame_w, frame_h, ATTACK_COLS)

	# Defeated (row 10)
	_add_row_animation(frames, "defeated", 9, false, 6.0, texture, frame_w, frame_h, ATTACK_COLS)

	animated_sprite.sprite_frames = frames


func _add_row_animation(
	frames: SpriteFrames,
	anim_name: String,
	row_index_0based: int,
	looped: bool,
	fps: float,
	texture: Texture2D,
	frame_w: int,
	frame_h: int,
	col_count: int = COLS
) -> void:
	frames.add_animation(anim_name)
	frames.set_animation_loop(anim_name, looped)
	frames.set_animation_speed(anim_name, fps)

	for col in range(col_count):
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2i(col * frame_w, row_index_0based * frame_h, frame_w, frame_h)
		frames.add_frame(anim_name, atlas)


func _facing_to_idle_anim(f: Facing) -> String:
	match f:
		Facing.DOWN:
			return "down_idle"
		Facing.SIDE:
			return "side_idle"
		_:
			return "up_idle"


func _facing_to_walk_anim(f: Facing) -> String:
	match f:
		Facing.DOWN:
			return "down_walk"
		Facing.SIDE:
			return "side_walk"
		_:
			return "up_walk"


func _facing_to_attack_anim(f: Facing) -> String:
	match f:
		Facing.DOWN:
			return "down_attack"
		Facing.SIDE:
			return "side_attack"
		_:
			return "up_attack"


func _update_attack_hitbox_transform() -> void:
	# Position the hitbox slightly in front of the player based on facing.
	# (Sizes are small; tweak via `TestScene.tscn` shapes if desired.)
	match last_facing:
		Facing.DOWN:
			attack_hitbox.position = Vector2(0, 18)
		Facing.UP:
			attack_hitbox.position = Vector2(0, -18)
		Facing.SIDE:
			attack_hitbox.position = Vector2(18 * side_dir, 6)


func _on_attack_hitbox_area_entered(area: Area2D) -> void:
	if not is_attacking or is_defeated:
		return
	if area == null:
		return

	# Expecting slime hurtbox: `Slime/Hurtbox` (Area2D).
	var target := area.get_parent()
	if target == null:
		return

	var id := target.get_instance_id()
	if _already_hit.has(id):
		return
	_already_hit[id] = true

	if target.has_method("take_damage"):
		target.call("take_damage", attack_damage, area.global_position)


func _process(_delta: float) -> void:
	if is_defeated or is_attacking:
		return
	if _gesture_controller == null:
		return
	if _gesture_controller.has_method("consume_attack_pressed"):
		if _gesture_controller.call("consume_attack_pressed"):
			_start_attack()
