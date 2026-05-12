extends Camera3D

@export var pitch_degrees: float = 30.0
@export var start_yaw_degrees: float = 43.5
@export var rotation_step_degrees: float = 60.0

@export var pixels_per_unit: float = 50.0
@export var reference_viewport_size: Vector2 = Vector2(640.0, 360.0)

@export var pan_speed: float = 8.0
@export var camera_distance: float = 15.0

var _yaw: float = 43.5
var _center: Vector3 = Vector3.ZERO
var _distance: float = 15.0
var _initialized: bool = false


func _ready() -> void:
	_yaw = start_yaw_degrees
	_distance = camera_distance


func _process(delta: float) -> void:
	if not _initialized:
		_initialize()
		return

	_handle_rotation()
	_handle_pan(delta)
	_update_transform()


func _handle_rotation() -> void:
	if Input.is_action_just_pressed("ui_left"):
		_yaw -= rotation_step_degrees

	if Input.is_action_just_pressed("ui_right"):
		_yaw += rotation_step_degrees

	_yaw = wrapf(_yaw, 0.0, 360.0)


func _handle_pan(delta: float) -> void:
	var input_dir := Vector2.ZERO

	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1.0
	if Input.is_key_pressed(KEY_W):
		input_dir.y += 1.0
	if Input.is_key_pressed(KEY_S):
		input_dir.y -= 1.0

	if input_dir == Vector2.ZERO:
		return

	input_dir = input_dir.normalized()

	var yaw_rad := deg_to_rad(_yaw)

	# Ground-plane directions relative to current camera yaw
	var forward := Vector3(sin(yaw_rad), 0.0, cos(yaw_rad)).normalized()
	var right := Vector3(forward.z, 0.0, -forward.x).normalized()

	_center += (right * input_dir.x + forward * input_dir.y) * pan_speed * delta


func _initialize() -> void:
	var board := get_parent().get_node("HexBoard3D") as HexBoard3D
	if board == null or board.tiles.is_empty():
		return

	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	var min_z := INF
	var max_z := -INF

	for coord in board.tiles.keys():
		var tile_data: Dictionary = board.tiles[coord]
		var wp := HexCoord.axial_to_world(coord, HexCoord.RADIUS)
		var y := HexCoord.elevation_to_height(tile_data["elevation"])

		if wp.x < min_x: min_x = wp.x
		if wp.x > max_x: max_x = wp.x
		if y < min_y: min_y = y
		if y > max_y: max_y = y
		if wp.z < min_z: min_z = wp.z
		if wp.z > max_z: max_z = wp.z

	_center = Vector3(
		(min_x + max_x) * 0.5,
		(min_y + max_y) * 0.5,
		(min_z + max_z) * 0.5
	)

	# Fixed orthographic zoom:
	# 1 world unit = 50 pixels in a 640x360 viewport
	# Visible vertical world units = 360 / 50 = 7.2
	# Camera3D.size = half of visible vertical span
	size = reference_viewport_size.y / pixels_per_unit

	_initialized = true
	_update_transform()


func _update_transform() -> void:
	var pitch_rad := deg_to_rad(pitch_degrees)
	var yaw_rad := deg_to_rad(_yaw)

	var offset := Vector3(
		sin(yaw_rad) * cos(pitch_rad),
		sin(pitch_rad),
		cos(yaw_rad) * cos(pitch_rad)
	) * _distance

	look_at_from_position(_center + offset, _center, Vector3.UP)