@tool
extends Node

const HandGestureStateScript = preload("res://scripts/mediapipe/hand_gesture_state.gd")

@export var debug_enabled: bool = true
@export var mirror_x: bool = true
@export var finger_straight_dot_threshold: float = 0.9
@export var finger_parallel_dot_threshold: float = 0.82
@export var closed_folded_finger_max_ratio: float = 0.82
@export var open_extended_finger_min_ratio: float = 1.12

var _last_state = HandGestureStateScript.make_invalid()
var _attack_pulse: bool = false
var _was_open_last_frame: bool = false
var _debug_label: Label


func _ready() -> void:
	if debug_enabled:
		_ensure_debug_label()


func _process(_delta: float) -> void:
	if not debug_enabled and _debug_label != null:
		_debug_label.queue_free()
		_debug_label = null
	elif debug_enabled and _debug_label == null:
		_ensure_debug_label()

	if _debug_label != null:
		_debug_label.text = _build_debug_text()


func consume_attack_pressed() -> bool:
	var pressed := _attack_pulse
	_attack_pulse = false
	return pressed


func get_movement_vector() -> Vector2:
	if _last_state == null:
		return Vector2.ZERO
	if not _last_state.is_valid:
		return Vector2.ZERO
	if _last_state.is_closed or _last_state.is_fully_open:
		return Vector2.ZERO
	return _last_state.movement_vector


func has_valid_state() -> bool:
	return _last_state != null and _last_state.is_valid


func get_state():
	if _last_state == null:
		return HandGestureStateScript.make_invalid()
	return _last_state


# Native-plugin entrypoint: accepts 21 hand landmarks as Vector2/Vector3 or dictionaries with x,y.
func set_mediapipe_landmarks(landmarks: Array, _hand_label: String = "dominant") -> void:
	var points := _parse_landmarks(landmarks)
	if points.size() < 21:
		_update_state(HandGestureStateScript.make_invalid())
		return
	_update_state(_classify_landmarks(points))


# Alternative native entrypoint if plugin pre-classifies hand state.
func set_hand_state_from_native(is_closed: bool, is_fully_open: bool, angle_deg: float, is_valid: bool = true) -> void:
	if not is_valid:
		_update_state(HandGestureStateScript.make_invalid())
	elif is_closed:
		_update_state(HandGestureStateScript.make_closed())
	elif is_fully_open:
		_update_state(HandGestureStateScript.make_fully_open())
	else:
		_update_state(HandGestureStateScript.make_directional(angle_deg))


func clear_tracking() -> void:
	_update_state(HandGestureStateScript.make_invalid())


func _update_state(next_state) -> void:
	_last_state = next_state
	var is_open_now: bool = next_state != null and next_state.is_fully_open
	_attack_pulse = is_open_now and not _was_open_last_frame
	_was_open_last_frame = is_open_now


func _classify_landmarks(points: Array[Vector2]):
	var fold_ratios := _compute_fold_ratios(points)

	var folded_count := 0
	var extended_count := 0
	for ratio in fold_ratios:
		if ratio <= closed_folded_finger_max_ratio:
			folded_count += 1
		if ratio >= open_extended_finger_min_ratio:
			extended_count += 1

	if folded_count >= 4:
		return HandGestureStateScript.make_closed()
	if extended_count >= 4:
		return HandGestureStateScript.make_fully_open()

	var straight := _fingers_straight_enough(points)
	var parallel := _fingers_parallel_enough(points)
	if not straight or not parallel:
		return HandGestureStateScript.make_invalid()

	var direction := _hand_direction_vector(points)
	if direction.length() < 0.001:
		return HandGestureStateScript.make_invalid()

	var angle := rad_to_deg(atan2(direction.y, direction.x))
	return HandGestureStateScript.make_directional(angle)


func _compute_fold_ratios(points: Array[Vector2]) -> Array[float]:
	var ratios: Array[float] = []
	var finger_defs := [
		[0, 2, 4], # thumb
		[0, 6, 8], # index
		[0, 10, 12], # middle
		[0, 14, 16], # ring
		[0, 18, 20] # pinky
	]
	for finger in finger_defs:
		var wrist: Vector2 = points[finger[0]]
		var mid: Vector2 = points[finger[1]]
		var tip: Vector2 = points[finger[2]]
		var base_len := wrist.distance_to(mid)
		if base_len <= 0.0001:
			ratios.append(0.0)
		else:
			ratios.append(wrist.distance_to(tip) / base_len)
	return ratios


func _fingers_straight_enough(points: Array[Vector2]) -> bool:
	var finger_triplets := [
		[5, 6, 8], # index
		[9, 10, 12], # middle
		[13, 14, 16], # ring
		[17, 18, 20] # pinky
	]
	var good := 0
	for triplet in finger_triplets:
		var a: Vector2 = (points[triplet[1]] - points[triplet[0]]).normalized()
		var b: Vector2 = (points[triplet[2]] - points[triplet[1]]).normalized()
		if a.length() <= 0.0 or b.length() <= 0.0:
			continue
		if a.dot(b) >= finger_straight_dot_threshold:
			good += 1
	return good >= 3


func _fingers_parallel_enough(points: Array[Vector2]) -> bool:
	var dirs := [
		(points[8] - points[5]).normalized(), # index
		(points[12] - points[9]).normalized(), # middle
		(points[16] - points[13]).normalized(), # ring
		(points[20] - points[17]).normalized() # pinky
	]
	var pairs_good := 0
	var pairs_total := 0
	for i in range(dirs.size()):
		for j in range(i + 1, dirs.size()):
			if dirs[i].length() <= 0.0 or dirs[j].length() <= 0.0:
				continue
			pairs_total += 1
			if dirs[i].dot(dirs[j]) >= finger_parallel_dot_threshold:
				pairs_good += 1
	return pairs_total > 0 and float(pairs_good) / float(pairs_total) >= 0.66


func _hand_direction_vector(points: Array[Vector2]) -> Vector2:
	var avg_tip := (
		points[8] +
		points[12] +
		points[16] +
		points[20]
	) / 4.0
	var wrist := points[0]
	var v := avg_tip - wrist
	if mirror_x:
		v.x = -v.x
	# Godot's positive Y points down; invert for intuitive up=90deg mapping.
	v.y = -v.y
	return v.normalized()


func _parse_landmarks(raw_landmarks: Array) -> Array[Vector2]:
	var parsed: Array[Vector2] = []
	for item in raw_landmarks:
		if item is Vector2:
			parsed.append(item)
		elif item is Vector3:
			parsed.append(Vector2(item.x, item.y))
		elif item is Dictionary and item.has("x") and item.has("y"):
			parsed.append(Vector2(float(item["x"]), float(item["y"])))
	return parsed


func _ensure_debug_label() -> void:
	_debug_label = Label.new()
	_debug_label.name = "GestureDebugLabel"
	_debug_label.position = Vector2(12, 12)
	add_child(_debug_label)


func _build_debug_text() -> String:
	if _last_state == null or not _last_state.is_valid:
		return "Gesture: invalid"
	if _last_state.is_closed:
		return "Gesture: closed (stop)"
	if _last_state.is_fully_open:
		return "Gesture: fully_open (attack)"
	return "Gesture: %s @ %.1f deg" % [_last_state.direction_name, _last_state.angle_deg]
