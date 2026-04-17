class_name HandGestureState
extends RefCounted

enum GestureType {
	NONE,
	CLOSED,
	DIRECTIONAL,
	FULLY_OPEN
}

var is_valid: bool = false
var is_closed: bool = false
var is_fully_open: bool = false
var angle_deg: float = 0.0
var movement_vector: Vector2 = Vector2.ZERO
var direction_name: String = "none"
var gesture_type: GestureType = GestureType.NONE


static func make_closed() -> HandGestureState:
	var s := HandGestureState.new()
	s.is_valid = true
	s.is_closed = true
	s.gesture_type = GestureType.CLOSED
	s.direction_name = "closed"
	return s


static func make_fully_open() -> HandGestureState:
	var s := HandGestureState.new()
	s.is_valid = true
	s.is_fully_open = true
	s.gesture_type = GestureType.FULLY_OPEN
	s.direction_name = "fully_open"
	return s


static func make_directional(angle: float) -> HandGestureState:
	var s := HandGestureState.new()
	s.is_valid = true
	s.angle_deg = _normalize_degrees(angle)
	s.gesture_type = GestureType.DIRECTIONAL
	s.direction_name = quantize_direction_name(s.angle_deg)
	s.movement_vector = quantize_direction_vector(s.angle_deg)
	return s


static func make_invalid() -> HandGestureState:
	return HandGestureState.new()


static func quantize_direction_name(angle: float) -> String:
	var idx := _angle_sector_index(angle)
	match idx:
		0:
			return "right"
		1:
			return "up_right"
		2:
			return "up"
		3:
			return "up_left"
		4:
			return "left"
		5:
			return "down_left"
		6:
			return "down"
		_:
			return "down_right"


static func quantize_direction_vector(angle: float) -> Vector2:
	var idx := _angle_sector_index(angle)
	match idx:
		0:
			return Vector2.RIGHT
		1:
			return Vector2(1.0, -1.0).normalized()
		2:
			return Vector2.UP
		3:
			return Vector2(-1.0, -1.0).normalized()
		4:
			return Vector2.LEFT
		5:
			return Vector2(-1.0, 1.0).normalized()
		6:
			return Vector2.DOWN
		_:
			return Vector2(1.0, 1.0).normalized()


static func _angle_sector_index(angle: float) -> int:
	var wrapped := _normalize_degrees(angle + 22.5)
	var idx := int(floor(wrapped / 45.0)) % 8
	return idx


static func _normalize_degrees(angle: float) -> float:
	var wrapped := fmod(angle, 360.0)
	if wrapped < 0.0:
		wrapped += 360.0
	return wrapped
