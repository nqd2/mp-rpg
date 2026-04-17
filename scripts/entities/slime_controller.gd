@tool
extends Node2D

@export var slime_texture: Texture2D
@export var sprite_scale: float = 4.0

@export var max_hp: int = 3
var hp: int = 3

@export var dust_hit_scene: PackedScene
@export var dust_texture: Texture2D

@export var patrol_offset: Vector2 = Vector2(240, 0)
@export var patrol_speed: float = 70.0
@export var chase_speed: float = 95.0

@export var aggro_radius: float = 260.0
@export var deaggro_radius: float = 340.0
@export var attack_radius: float = 55.0
@export var attack_cooldown_sec: float = 1.0

@export var player_node_path: NodePath = NodePath("../Player")

const COLS := 7
const ROWS := 13
const FRAME_W := 32
const FRAME_H := 32

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

enum Facing { DOWN, SIDE, UP }
enum State { PATROL, CHASE, ATTACK, HURT, DEATH }

var _origin: Vector2
var _patrol_target: Vector2
var _patrol_forward: bool = true

var _state: State = State.PATROL
var _last_facing: Facing = Facing.DOWN
var _side_dir: float = 1.0

var _attack_cd_left: float = 0.0


func _ready() -> void:
	if not animated_sprite.animation_finished.is_connected(_on_animation_finished):
		animated_sprite.animation_finished.connect(_on_animation_finished)

	animated_sprite.scale = Vector2(sprite_scale, sprite_scale)

	if slime_texture == null:
		push_error("Missing `slime_texture` on Slime node.")
		return

	hp = max_hp

	_build_sprite_frames(slime_texture)
	_set_anim("down_idle")

	_origin = global_position
	_patrol_target = _origin + patrol_offset


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if slime_texture == null:
		return

	_attack_cd_left = maxf(0.0, _attack_cd_left - delta)

	if _state == State.ATTACK or _state == State.HURT or _state == State.DEATH:
		return

	var player := _get_player()
	if player == null:
		_patrol(delta)
		return

	var dist := global_position.distance_to(player.global_position)
	var should_chase := false
	if _state == State.CHASE:
		should_chase = dist <= deaggro_radius
	else:
		should_chase = dist <= aggro_radius

	if should_chase:
		_state = State.CHASE
		_chase(delta, player, dist)
	else:
		_state = State.PATROL
		_patrol(delta)


func _patrol(delta: float) -> void:
	var target := _patrol_target if _patrol_forward else _origin
	var to_target := target - global_position

	if to_target.length() < 6.0:
		_patrol_forward = not _patrol_forward
		target = _patrol_target if _patrol_forward else _origin
		to_target = target - global_position

	var vel := _axis_choice(to_target).normalized() * patrol_speed
	_apply_motion(delta, vel)
	_refresh_move_anim(vel)


func _chase(delta: float, player: Node2D, dist: float) -> void:
	var to_player := player.global_position - global_position
	var axis_dir := _axis_choice(to_player)

	if dist <= attack_radius and _attack_cd_left <= 0.0:
		_start_attack(axis_dir)
		return

	var vel := axis_dir.normalized() * chase_speed
	_apply_motion(delta, vel)
	_refresh_move_anim(vel)


func _start_attack(axis_dir: Vector2) -> void:
	_state = State.ATTACK
	_attack_cd_left = attack_cooldown_sec
	_update_facing(axis_dir)
	_set_anim(_facing_to_anim("jump", _last_facing), false)


func take_hurt() -> void:
	if _state == State.DEATH:
		return
	_state = State.HURT
	_set_anim(_facing_to_anim("hurt", _last_facing), false)

func take_damage(amount: int = 1, hit_pos: Vector2 = Vector2.ZERO) -> void:
	if _state == State.DEATH:
		return

	hp = maxi(0, hp - amount)
	_spawn_hit_vfx(hit_pos if hit_pos != Vector2.ZERO else global_position)

	if hp <= 0:
		die()
	else:
		take_hurt()


func die() -> void:
	_state = State.DEATH
	_set_anim("death", false)


func _on_animation_finished() -> void:
	if _state == State.ATTACK:
		_state = State.CHASE
		_set_anim(_facing_to_anim("move", _last_facing))
	elif _state == State.HURT:
		_state = State.CHASE
		_set_anim(_facing_to_anim("move", _last_facing))
	elif _state == State.DEATH:
		# Optional: remove after death animation completes.
		queue_free()


func _spawn_hit_vfx(pos: Vector2) -> void:
	if dust_hit_scene == null:
		return

	var fx := dust_hit_scene.instantiate()
	if fx == null:
		return

	fx.global_position = pos
	if dust_texture != null and fx.has_method("set"):
		# `DustHit` root exports `dust_texture`.
		fx.set("dust_texture", dust_texture)
	# Match slime scale by default if effect supports it.
	if fx.has_method("set"):
		fx.set("sprite_scale", sprite_scale)

	get_tree().current_scene.add_child(fx)


func _get_player() -> Node2D:
	if player_node_path == NodePath():
		return null
	var n := get_node_or_null(player_node_path)
	return n as Node2D


func _apply_motion(delta: float, vel: Vector2) -> void:
	if vel == Vector2.ZERO:
		return
	global_position += vel * delta


func _refresh_move_anim(vel: Vector2) -> void:
	if vel == Vector2.ZERO:
		_set_anim(_facing_to_anim("idle", _last_facing))
		return

	_update_facing(vel)
	_set_anim(_facing_to_anim("move", _last_facing))


func _axis_choice(v: Vector2) -> Vector2:
	if abs(v.x) > abs(v.y):
		return Vector2(v.x, 0.0)
	return Vector2(0.0, v.y)


func _update_facing(v: Vector2) -> void:
	if v == Vector2.ZERO:
		return

	if v.x != 0.0:
		_last_facing = Facing.SIDE
		_side_dir = sign(v.x)
	else:
		_last_facing = Facing.UP if v.y < 0.0 else Facing.DOWN

	animated_sprite.flip_h = (_last_facing == Facing.SIDE and _side_dir < 0.0)


func _set_anim(anim: String, allow_restart: bool = false) -> void:
	if allow_restart or animated_sprite.animation != anim:
		animated_sprite.play(anim)


func _facing_to_anim(prefix: String, facing: Facing) -> String:
	match facing:
		Facing.DOWN:
			return "down_%s" % prefix
		Facing.SIDE:
			return "side_%s" % prefix
		_:
			return "up_%s" % prefix


func _build_sprite_frames(texture: Texture2D) -> void:
	# slime.png is 224x416 => 7 cols x 13 rows, each frame 32x32.
	var frames := SpriteFrames.new()

	_add_row(frames, "down_idle", 0, 4, true, 6.0, texture)
	_add_row(frames, "side_idle", 1, 4, true, 6.0, texture)
	_add_row(frames, "up_idle", 2, 4, true, 6.0, texture)

	_add_row(frames, "down_move", 3, 6, true, 10.0, texture)
	_add_row(frames, "side_move", 4, 6, true, 10.0, texture)
	_add_row(frames, "up_move", 5, 6, true, 10.0, texture)

	_add_row(frames, "down_jump", 6, 7, false, 14.0, texture)
	_add_row(frames, "side_jump", 7, 7, false, 14.0, texture)
	_add_row(frames, "up_jump", 8, 7, false, 14.0, texture)

	_add_row(frames, "down_hurt", 9, 3, false, 12.0, texture)
	_add_row(frames, "side_hurt", 10, 3, false, 12.0, texture)
	_add_row(frames, "up_hurt", 11, 3, false, 12.0, texture)

	_add_row(frames, "death", 12, 6, false, 10.0, texture)

	animated_sprite.sprite_frames = frames


func _add_row(
	frames: SpriteFrames,
	anim: String,
	row_0: int,
	frame_count: int,
	looped: bool,
	fps: float,
	texture: Texture2D
) -> void:
	frames.add_animation(anim)
	frames.set_animation_loop(anim, looped)
	frames.set_animation_speed(anim, fps)

	for col in range(frame_count):
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2i(col * FRAME_W, row_0 * FRAME_H, FRAME_W, FRAME_H)
		frames.add_frame(anim, atlas)
