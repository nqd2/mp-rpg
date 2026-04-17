@tool
extends Node

@export var gesture_controller_path: NodePath = NodePath("../GestureController")
@export var auto_start_camera: bool = true
@export var preferred_feed_index: int = -1
@export var preferred_feed_name_contains: String = ""
@export var debug_enabled: bool = true
@export var startup_retry_interval_sec: float = 0.5
@export var startup_retry_count: int = 8
@export var preview_enabled: bool = true
@export var preview_size: Vector2 = Vector2(240, 135)
@export var preview_margin: Vector2 = Vector2(16, 16)
@export var preview_panel_color: Color = Color(0.0, 0.0, 0.0, 0.55)

var _gesture_controller: Node
var _active_feed
var _debug_label: Label
var _camera_monitoring_enabled: bool = false
var _startup_retry_timer: float = 0.0
var _startup_retries_left: int = 0
var _no_feed_warning_emitted: bool = false
var _preview_layer: CanvasLayer
var _preview_panel: Panel
var _preview_rect: TextureRect


func _ready() -> void:
	_gesture_controller = get_node_or_null(gesture_controller_path)
	_ensure_camera_monitoring()
	# Avoid noisy warnings while the script runs in editor (@tool).
	if auto_start_camera and not Engine.is_editor_hint():
		_startup_retries_left = max(startup_retry_count, 0)
		if not start_camera(false):
			_startup_retry_timer = max(startup_retry_interval_sec, 0.05)
	if debug_enabled:
		_ensure_debug_label()
	if preview_enabled:
		_ensure_preview_ui()


func _process(_delta: float) -> void:
	if not debug_enabled and _debug_label != null:
		_debug_label.queue_free()
		_debug_label = null
	elif debug_enabled and _debug_label == null:
		_ensure_debug_label()

	if _debug_label != null:
		_debug_label.text = _build_debug_text()

	_update_preview_layout()
	_update_preview_visibility()
	_retry_start_camera(_delta)


func start_camera(emit_warnings: bool = true) -> bool:
	_ensure_camera_monitoring()
	if _active_feed != null and _feed_is_active(_active_feed):
		return true

	var feed: Variant = _select_feed()
	if feed == null:
		if emit_warnings and not _no_feed_warning_emitted:
			push_warning("No CameraServer feed available.")
			_no_feed_warning_emitted = true
		return false

	if not _set_feed_active(feed, true):
		push_warning("Could not activate camera feed.")
		return false

	_active_feed = feed
	_no_feed_warning_emitted = false
	_apply_feed_to_preview(feed)
	return true


func stop_camera() -> void:
	if _active_feed == null:
		return
	_set_feed_active(_active_feed, false)
	_active_feed = null
	if _gesture_controller != null and _gesture_controller.has_method("clear_tracking"):
		_gesture_controller.call("clear_tracking")


# Native plugin can call this when landmarks are produced from current camera frame.
func submit_landmarks(landmarks: Array, hand_label: String = "dominant") -> void:
	if _gesture_controller == null:
		_gesture_controller = get_node_or_null(gesture_controller_path)
	if _gesture_controller != null and _gesture_controller.has_method("set_mediapipe_landmarks"):
		_gesture_controller.call("set_mediapipe_landmarks", landmarks, hand_label)


# Native plugin can call this when it already classifies the gesture.
func submit_classified_state(is_closed: bool, is_fully_open: bool, angle_deg: float, is_valid: bool = true) -> void:
	if _gesture_controller == null:
		_gesture_controller = get_node_or_null(gesture_controller_path)
	if _gesture_controller != null and _gesture_controller.has_method("set_hand_state_from_native"):
		_gesture_controller.call("set_hand_state_from_native", is_closed, is_fully_open, angle_deg, is_valid)


func _select_feed():
	_ensure_camera_monitoring()
	var feed_count := int(CameraServer.get_feed_count())
	if feed_count <= 0:
		return null

	if preferred_feed_index >= 0 and preferred_feed_index < feed_count:
		return CameraServer.get_feed(preferred_feed_index)

	if preferred_feed_name_contains != "":
		var needle := preferred_feed_name_contains.to_lower()
		for i in range(feed_count):
			var feed = CameraServer.get_feed(i)
			var feed_name := ""
			if feed != null:
				if feed.has_method("get_name"):
					feed_name = String(feed.call("get_name"))
				elif "name" in feed:
					feed_name = String(feed.name)
			if feed_name.to_lower().contains(needle):
				return feed

	return CameraServer.get_feed(0)


func _set_feed_active(feed, enabled: bool) -> bool:
	if feed == null:
		return false
	if feed.has_method("set_active"):
		feed.call("set_active", enabled)
		return true
	if feed.has_method("set_is_active"):
		feed.call("set_is_active", enabled)
		return true
	return false


func _feed_is_active(feed) -> bool:
	if feed == null:
		return false
	if feed.has_method("is_active"):
		return bool(feed.call("is_active"))
	if feed.has_method("get_is_active"):
		return bool(feed.call("get_is_active"))
	return false


func _ensure_debug_label() -> void:
	_debug_label = Label.new()
	_debug_label.name = "CameraBridgeDebugLabel"
	_debug_label.position = Vector2(12, 34)
	add_child(_debug_label)


func _build_debug_text() -> String:
	_ensure_camera_monitoring()
	var count := int(CameraServer.get_feed_count())
	var active := _active_feed != null and _feed_is_active(_active_feed)
	if count <= 0:
		return "Camera: no feeds"
	if not active:
		if _startup_retries_left > 0:
			return "Camera: feed found, waiting to activate"
		return "Camera: feed found, not active"
	return "Camera: active (%d feed(s))" % count


func _ensure_camera_monitoring() -> void:
	if _camera_monitoring_enabled:
		return
	CameraServer.set_monitoring_feeds(true)
	_camera_monitoring_enabled = true


func _retry_start_camera(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not auto_start_camera:
		return
	if _active_feed != null and _feed_is_active(_active_feed):
		return
	if _startup_retries_left <= 0:
		return

	_startup_retry_timer -= delta
	if _startup_retry_timer > 0.0:
		return

	_startup_retry_timer = max(startup_retry_interval_sec, 0.05)
	_startup_retries_left -= 1
	if start_camera(false):
		return
	if _startup_retries_left <= 0:
		start_camera(true)


func _ensure_preview_ui() -> void:
	if _preview_layer != null:
		return
	_preview_layer = CanvasLayer.new()
	_preview_layer.name = "CameraPreviewLayer"
	add_child(_preview_layer)

	_preview_panel = Panel.new()
	_preview_panel.name = "CameraPreviewPanel"
	_preview_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_layer.add_child(_preview_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = preview_panel_color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	_preview_panel.add_theme_stylebox_override("panel", style)

	_preview_rect = TextureRect.new()
	_preview_rect.name = "CameraPreviewRect"
	_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_panel.add_child(_preview_rect)

	_update_preview_layout()
	_update_preview_visibility()
	if _active_feed != null:
		_apply_feed_to_preview(_active_feed)


func _update_preview_layout() -> void:
	if _preview_panel == null or _preview_rect == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var clamped_size := Vector2(max(preview_size.x, 96.0), max(preview_size.y, 54.0))
	var panel_size := clamped_size + Vector2(8.0, 8.0)
	_preview_panel.size = panel_size
	_preview_panel.position = Vector2(
		max(viewport_size.x - panel_size.x - preview_margin.x, 0.0),
		max(preview_margin.y, 0.0)
	)
	_preview_rect.position = Vector2(4, 4)
	_preview_rect.size = clamped_size


func _update_preview_visibility() -> void:
	if _preview_panel == null:
		return
	_preview_panel.visible = preview_enabled


func _apply_feed_to_preview(feed) -> void:
	if not preview_enabled:
		return
	if _preview_rect == null:
		_ensure_preview_ui()
	if _preview_rect == null or feed == null:
		return

	if ClassDB.class_exists("CameraTexture") and feed.has_method("get_id"):
		var cam_tex := CameraTexture.new()
		cam_tex.camera_feed_id = int(feed.call("get_id"))
		_preview_rect.texture = cam_tex
