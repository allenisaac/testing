extends Camera3D

@export var pitch_degrees: float = 30.0
@export var orbit_speed: float = 90.0   # degrees per second
@export var zoom_padding: float = 1.25  # multiplier on bounding box extent

var _yaw: float = 45.0
var _center: Vector3 = Vector3.ZERO
var _distance: float = 15.0
var _initialized: bool = false


func _process(delta: float) -> void:
	if not _initialized:
		_initialize()
		return

	var input := Input.get_axis("ui_left", "ui_right")
	if input != 0.0:
		_yaw += input * orbit_speed * delta
		_update_transform()


func _initialize() -> void:
	var board := get_parent().get_node("HexBoard3D") as HexBoard3D
	if board == null or board.tiles.is_empty():
		return

	var min_x := INF;  var max_x := -INF
	var min_y := INF;  var max_y := -INF
	var min_z := INF;  var max_z := -INF

	for coord in board.tiles.keys():
		var tile_data: Dictionary = board.tiles[coord]
		var wp := HexCoord.axial_to_world(coord, HexCoord.RADIUS)
		var y  := HexCoord.elevation_to_height(tile_data["elevation"])
		if wp.x < min_x: min_x = wp.x
		if wp.x > max_x: max_x = wp.x
		if y  < min_y:  min_y = y
		if y  > max_y:  max_y = y
		if wp.z < min_z: min_z = wp.z
		if wp.z > max_z: max_z = wp.z

	_center = Vector3(
		(min_x + max_x) * 0.5,
		(min_y + max_y) * 0.5,
		(min_z + max_z) * 0.5
	)

	var extent_x := (max_x - min_x) + HexCoord.RADIUS * 2.0
	var extent_z := (max_z - min_z) + HexCoord.RADIUS * 2.0
	var extent   := maxf(extent_x, extent_z)

	# Orthographic size = half-height of the view in world units.
	# At 30° pitch the board's Z is foreshortened; boost size to compensate.
	var pitch_rad := deg_to_rad(pitch_degrees)
	size = (extent * zoom_padding) / (2.0 * cos(pitch_rad))
	_distance = extent * zoom_padding * 1.2

	_initialized = true
	_update_transform()


func _update_transform() -> void:
	var pitch_rad := deg_to_rad(pitch_degrees)
	var yaw_rad   := deg_to_rad(_yaw)

	var offset := Vector3(
		sin(yaw_rad) * cos(pitch_rad),
		sin(pitch_rad),
		cos(yaw_rad) * cos(pitch_rad)
	) * _distance

	look_at_from_position(_center + offset, _center, Vector3.UP)
