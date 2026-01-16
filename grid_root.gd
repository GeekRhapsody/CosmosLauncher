extends Node3D

@export var columns := 4
@export var spacing := 2.0
@export var cube_size := 1.0
@export var selected_scale := 1.2
@export var selected_spin_speed := 0.6
@export var deselect_return_time := 0.2
@export var model_fit_ratio := 0.8
@export var systems_path := "res://systems.xml"
@export var camera_path := NodePath("Camera3D")
@export var camera_margin := 0.4
@export var selected_label_path := NodePath("UILayer/SelectedLabel")

@onready var grid_container: Node3D = $GridContainer
@onready var grid_camera: Camera3D = get_node_or_null(camera_path)
@onready var selected_label: Label = get_node_or_null(selected_label_path)

var grid_cubes: Array[Node3D] = []
var grid_base_rotations: Array[Vector3] = []
var grid_base_scales: Array[Vector3] = []
var selected_index: int = -1
var total_systems: int = 0
var grid_columns: int = 1
var grid_rows: int = 0
var grid_systems: Array[Dictionary] = []

func _ready() -> void:
	_build_grid()

func _build_grid() -> void:
	_clear_grid()
	var resolved_path := _resolve_systems_path()
	var systems: Array[Dictionary] = _load_systems(resolved_path)
	var had_systems := not systems.is_empty()
	_append_settings_system(systems)
	if not had_systems:
		push_warning("No systems found in %s" % systems_path)
	if systems.is_empty():
		return
	grid_systems = systems

	var safe_columns: int = int(max(columns, 1))
	var rows: int = int(ceil(float(systems.size()) / float(safe_columns)))
	var total_width := float(safe_columns - 1) * spacing
	var total_height := float(rows - 1) * spacing
	var start_x := -total_width / 2.0
	var start_y := total_height / 2.0

	grid_columns = safe_columns
	grid_rows = rows
	total_systems = systems.size()

	for i in range(systems.size()):
		var row: int = int(i / safe_columns)
		var col: int = i % safe_columns
		var pos := Vector3(start_x + float(col) * spacing, start_y - float(row) * spacing, 0.0)
		var system_node: Node3D = _spawn_system_node(systems[i], pos)
		grid_cubes.append(system_node)

	if total_systems > 0:
		_set_selected(0)
	_frame_camera(total_width, total_height)

func _clear_grid() -> void:
	for child in grid_container.get_children():
		child.queue_free()
	grid_cubes.clear()
	grid_base_rotations.clear()
	grid_base_scales.clear()
	grid_systems.clear()
	selected_index = -1
	total_systems = 0
	grid_rows = 0
	if selected_label != null:
		selected_label.text = ""

func _spawn_system_node(system: Dictionary, position: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = position
	root.scale = Vector3.ONE
	root.name = "System_%s" % str(system.get("name", "System"))
	grid_container.add_child(root)

	var model_path: String = str(system.get("model", ""))
	if model_path == "":
		model_path = str(system.get("model_path", ""))
	var model_added := false
	if model_path != "":
		var loaded: Resource = load(model_path)
		if loaded is PackedScene:
			var inst: Node = (loaded as PackedScene).instantiate()
			root.add_child(inst)
			model_added = true
		else:
			push_warning("Model is not a PackedScene: %s" % model_path)

	if not model_added:
		_add_fallback_cube(root)

	_fit_model_to_cell(root)
	grid_base_rotations.append(root.rotation)
	grid_base_scales.append(root.scale)
	return root

func _add_fallback_cube(root: Node3D) -> void:
	var cube := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(cube_size, cube_size, cube_size)
	cube.mesh = mesh
	root.add_child(cube)

func _set_selected(index: int) -> void:
	if total_systems <= 0:
		return

	var clamped_index: int = int(clamp(index, 0, total_systems - 1))
	if selected_index >= 0 and selected_index < grid_cubes.size():
		grid_cubes[selected_index].scale = _get_base_scale(selected_index)
		_reset_rotation(selected_index)

	selected_index = clamped_index
	if selected_index < grid_cubes.size():
		grid_cubes[selected_index].scale = _get_base_scale(selected_index) * selected_scale
		_update_selected_label(selected_index)

func _move_selection(delta_col: int, delta_row: int) -> void:
	if total_systems <= 0:
		return
	if selected_index < 0:
		_set_selected(0)
		return

	var row: int = int(selected_index / grid_columns)
	var col: int = selected_index % grid_columns
	var new_row: int = int(clamp(row + delta_row, 0, max(grid_rows - 1, 0)))
	var new_col: int = int(clamp(col + delta_col, 0, grid_columns - 1))
	var new_index: int = int(new_row * grid_columns + new_col)
	if new_index >= total_systems:
		new_index = total_systems - 1

	_set_selected(new_index)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		_move_selection(-1, 0)
	elif event.is_action_pressed("ui_right"):
		_move_selection(1, 0)
	elif event.is_action_pressed("ui_up"):
		_move_selection(0, -1)
	elif event.is_action_pressed("ui_down"):
		_move_selection(0, 1)

func _process(delta: float) -> void:
	if selected_index >= 0 and selected_index < grid_cubes.size():
		grid_cubes[selected_index].rotate_y(selected_spin_speed * delta)

func _reset_rotation(index: int) -> void:
	if index < 0 or index >= grid_cubes.size() or index >= grid_base_rotations.size():
		return

	var node := grid_cubes[index]
	if not is_instance_valid(node):
		return

	var base_rot := grid_base_rotations[index]
	if deselect_return_time <= 0.0:
		node.rotation = base_rot
		return

	var tween := node.create_tween()
	tween.tween_property(node, "rotation", base_rot, deselect_return_time)

func _fit_model_to_cell(root: Node3D) -> void:
	var bounds := _get_model_aabb(root)
	if bounds.size.length() <= 0.0:
		return

	var max_dim: float = bounds.size.x
	if bounds.size.y > max_dim:
		max_dim = bounds.size.y
	if bounds.size.z > max_dim:
		max_dim = bounds.size.z
	if max_dim <= 0.0:
		return

	var ratio: float = clamp(model_fit_ratio, 0.2, 1.0)
	var target := spacing * ratio
	var scale_factor: float = float(target / max_dim)
	root.scale = Vector3.ONE * scale_factor

func _get_model_aabb(root: Node3D) -> AABB:
	var root_inverse: Transform3D = root.global_transform.affine_inverse()
	var combined: AABB = AABB()
	var has_aabb: bool = false
	var stack: Array[Node3D] = [root]

	while not stack.is_empty():
		var node: Node3D = stack.pop_back()
		if node is MeshInstance3D:
			var mesh_node := node as MeshInstance3D
			var local_aabb: AABB = mesh_node.get_aabb()
			var to_root: Transform3D = root_inverse * mesh_node.global_transform
			var transformed: AABB = _transform_aabb(local_aabb, to_root)
			if not has_aabb:
				combined = transformed
				has_aabb = true
			else:
				combined = combined.merge(transformed)

		for child in node.get_children():
			if child is Node3D:
				stack.append(child as Node3D)

	if not has_aabb:
		return AABB()
	return combined

func _transform_aabb(aabb: AABB, transform: Transform3D) -> AABB:
	var min_point := aabb.position
	var max_point := aabb.position + aabb.size
	var corners := [
		Vector3(min_point.x, min_point.y, min_point.z),
		Vector3(max_point.x, min_point.y, min_point.z),
		Vector3(min_point.x, max_point.y, min_point.z),
		Vector3(max_point.x, max_point.y, min_point.z),
		Vector3(min_point.x, min_point.y, max_point.z),
		Vector3(max_point.x, min_point.y, max_point.z),
		Vector3(min_point.x, max_point.y, max_point.z),
		Vector3(max_point.x, max_point.y, max_point.z)
	]

	var first: Vector3 = transform * corners[0]
	var result := AABB(first, Vector3.ZERO)
	for corner in corners:
		var point: Vector3 = transform * corner
		result = result.expand(point)

	return result

func _get_base_scale(index: int) -> Vector3:
	if index < 0 or index >= grid_base_scales.size():
		return Vector3.ONE
	return grid_base_scales[index]

func _update_selected_label(index: int) -> void:
	if selected_label == null:
		return
	if index < 0 or index >= grid_systems.size():
		selected_label.text = ""
		return
	selected_label.text = str(grid_systems[index].get("name", ""))

func _frame_camera(total_width: float, total_height: float) -> void:
	if grid_camera == null:
		return

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.y <= 0.0:
		return

	var aspect: float = viewport_size.x / viewport_size.y
	var half_height: float = max(total_height * 0.5, 0.1)
	var half_width: float = max(total_width * 0.5, 0.1)
	var v_fov_rad: float = deg_to_rad(grid_camera.fov)
	var tan_half_fov: float = tan(v_fov_rad * 0.5)
	var dist_height: float = half_height / tan_half_fov
	var dist_width: float = half_width / (aspect * tan_half_fov)
	var required: float = max(dist_height, dist_width)
	var margin: float = clamp(camera_margin, 0.5, 0.98)
	var distance: float = required / margin
	grid_camera.position = Vector3(0.0, 0.0, distance)
	grid_camera.look_at(Vector3.ZERO, Vector3.UP)

func _append_settings_system(systems: Array[Dictionary]) -> void:
	for system in systems:
		var system_name := str(system.get("name", "")).strip_edges().to_lower()
		if system_name == "settings":
			return

	var settings: Dictionary = {
		"name": "Settings",
		"emulator": "",
		"path": "",
		"model": "res://models/settings_cogs.tscn"
	}
	systems.append(settings)

func _load_systems(path: String) -> Array[Dictionary]:
	if not FileAccess.file_exists(path):
		push_error("systems.xml not found at %s" % path)
		return []

	var parser := XMLParser.new()
	var open_err := parser.open(path)
	if open_err != OK:
		push_error("Failed to open %s (err %s)" % [path, open_err])
		return []

	var systems: Array[Dictionary] = []
	var current: Dictionary = {}
	var current_key: String = ""
	var in_system: bool = false

	while true:
		var read_err := parser.read()
		if read_err != OK:
			break

		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var name := parser.get_node_name()
				if name == "system":
					in_system = true
					current = {}
				elif in_system and name in ["name", "emulator", "path", "folder", "folder_path", "model", "model_path"]:
					current_key = name
			XMLParser.NODE_TEXT:
				if in_system and current_key != "":
					current[current_key] = parser.get_node_data().strip_edges()
			XMLParser.NODE_ELEMENT_END:
				var end_name := parser.get_node_name()
				if end_name == "system":
					in_system = false
					if not current.is_empty():
						systems.append(current)
				elif in_system and end_name == current_key:
					current_key = ""

	return systems

func _resolve_systems_path() -> String:
	var exe_dir := OS.get_executable_path().get_base_dir()
	var external_path := exe_dir.path_join("systems.xml")
	if FileAccess.file_exists(external_path):
		return external_path

	return systems_path
