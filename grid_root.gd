extends Node3D

@export var columns := 5
@export var visible_rows := 3
@export var spacing := 2.0
@export var cube_size := 1.0
@export var selected_scale := 1.2
@export var selected_spin_speed := 0.6
@export var deselect_return_time := 0.2
@export var model_fit_ratio := 0.8
@export var fade_duration: float = 0.35
@export var game_box_size: Vector3 = Vector3(0.9, 1.2, 0.2)
@export var systems_path := "res://systems.xml"
@export var camera_path := NodePath("Camera3D")
@export var camera_margin := 0.4
@export var selected_label_path := NodePath("UILayer/SelectedLabel")

@onready var grid_container: Node3D = $GridContainer
@onready var game_grid_container: Node3D = $GameGridContainer
@onready var grid_camera: Camera3D = get_node_or_null(camera_path)
@onready var selected_label: Label = get_node_or_null(selected_label_path)

var grid_cubes: Array[Node3D] = []
var grid_base_rotations: Array[Vector3] = []
var grid_base_scales: Array[Vector3] = []
var game_nodes: Array[Node3D] = []
var game_base_rotations: Array[Vector3] = []
var game_base_scales: Array[Vector3] = []
var selected_index: int = -1
var game_selected_index: int = -1
var total_systems: int = 0
var grid_columns: int = 1
var grid_rows: int = 0
var grid_systems: Array[Dictionary] = []
var game_total: int = 0
var game_rows: int = 0
var game_columns: int = 1
var game_list: Array[Dictionary] = []
var showing_games: bool = false
var is_transitioning: bool = false
var current_system: Dictionary = {}
var rom_root: String = ""
var grid_top_row: int = 0
var game_top_row: int = 0

func _ready() -> void:
	_load_config()
	_build_grid()

func _build_grid() -> void:
	_clear_grid()
	_clear_game_grid()
	grid_container.visible = true
	game_grid_container.visible = false
	showing_games = false
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
	grid_top_row = 0

	for i in range(systems.size()):
		var row: int = int(i / safe_columns)
		var col: int = i % safe_columns
		var pos := Vector3(start_x + float(col) * spacing, start_y - float(row) * spacing, 0.0)
		var system_node: Node3D = _spawn_system_node(systems[i], pos)
		grid_cubes.append(system_node)

	if total_systems > 0:
		_set_selected(0)
	_update_system_scroll_position()
	var window_rows: int = int(min(grid_rows, max(visible_rows, 1)))
	var window_height: float = float(window_rows - 1) * spacing
	_frame_camera(total_width, window_height)

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
	grid_top_row = 0
	if selected_label != null:
		selected_label.text = ""

func _clear_game_grid() -> void:
	for child in game_grid_container.get_children():
		child.queue_free()
	game_nodes.clear()
	game_base_rotations.clear()
	game_base_scales.clear()
	game_list.clear()
	game_selected_index = -1
	game_total = 0
	game_rows = 0
	game_top_row = 0

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

func _build_game_grid(system: Dictionary) -> void:
	_clear_game_grid()
	var system_name: String = str(system.get("name", ""))
	var system_path: String = _get_system_path(system)
	var box_size: Vector3 = _get_game_box_size(system)
	var extensions: Array[String] = _parse_extensions(str(system.get("extensions", "")))
	var games: Array[Dictionary] = _load_games(system_path, extensions)
	if games.is_empty():
		push_warning("No games found in %s" % system_path)
		return
	game_list = games

	var safe_columns: int = int(max(columns, 1))
	var rows: int = int(ceil(float(games.size()) / float(safe_columns)))
	var total_width: float = float(safe_columns - 1) * spacing
	var total_height: float = float(rows - 1) * spacing
	var start_x: float = -total_width / 2.0
	var start_y: float = total_height / 2.0

	game_columns = safe_columns
	game_rows = rows
	game_total = games.size()
	game_top_row = 0

	for i in range(games.size()):
		var row: int = int(i / safe_columns)
		var col: int = i % safe_columns
		var pos := Vector3(start_x + float(col) * spacing, start_y - float(row) * spacing, 0.0)
		var game_node: Node3D = _spawn_game_node(games[i], system_name, pos, box_size)
		game_nodes.append(game_node)

	if game_total > 0:
		_set_game_selected(0)

	_update_game_scroll_position()
	var window_rows: int = int(min(game_rows, max(visible_rows, 1)))
	var window_height: float = float(window_rows - 1) * spacing
	_frame_camera(total_width, window_height)

func _spawn_game_node(game: Dictionary, system_name: String, position: Vector3, box_size: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = position
	root.scale = Vector3.ONE
	root.name = "Game_%s" % str(game.get("name", "Game"))
	game_grid_container.add_child(root)

	var game_name: String = str(game.get("name", ""))
	var box := _create_game_box(system_name, game_name, box_size)
	root.add_child(box)

	_fit_model_to_cell(root)
	game_base_rotations.append(root.rotation)
	game_base_scales.append(root.scale)
	return root

func _create_game_box(system_name: String, game_name: String, size: Vector3) -> Node3D:
	var root := Node3D.new()
	var half_w: float = size.x * 0.5
	var half_h: float = size.y * 0.5
	var half_d: float = size.z * 0.5

	var front_tex: Texture2D = _load_game_texture(system_name, "Front", game_name)
	var spine_tex: Texture2D = _load_game_texture(system_name, "Spine", game_name)
	var back_tex: Texture2D = _load_game_texture(system_name, "Back", game_name)

	var front_mat: StandardMaterial3D = _create_box_material(front_tex)
	var spine_mat: StandardMaterial3D = _create_box_material(spine_tex)
	var back_mat: StandardMaterial3D = _create_box_material(back_tex)
	var gray_mat: StandardMaterial3D = _create_box_material(null)

	_add_game_face(root, Vector2(size.x, size.y), Vector3(0, 0, half_d), Vector3(0, 0, 0), front_mat)
	_add_game_face(root, Vector2(size.x, size.y), Vector3(0, 0, -half_d), Vector3(0, 180, 0), back_mat)
	_add_game_face(root, Vector2(size.z, size.y), Vector3(-half_w, 0, 0), Vector3(0, -90, 0), spine_mat)
	_add_game_face(root, Vector2(size.z, size.y), Vector3(half_w, 0, 0), Vector3(0, 90, 0), gray_mat)
	_add_game_face(root, Vector2(size.x, size.z), Vector3(0, half_h, 0), Vector3(-90, 0, 0), gray_mat)
	_add_game_face(root, Vector2(size.x, size.z), Vector3(0, -half_h, 0), Vector3(90, 0, 0), gray_mat)

	return root

func _get_game_box_size(system: Dictionary) -> Vector3:
	var height: float = game_box_size.y
	var width: float = game_box_size.x
	var depth: float = game_box_size.z
	var aspect_raw: String = str(system.get("box_aspect", "")).strip_edges()
	if aspect_raw != "":
		var ratio: float = _parse_aspect_ratio(aspect_raw)
		if ratio > 0.0:
			width = height * ratio

	var thickness_raw: String = str(system.get("box_thickness", "")).strip_edges()
	if thickness_raw != "":
		var thickness: float = float(thickness_raw)
		if thickness > 0.0:
			depth = thickness

	return Vector3(width, height, depth)

func _parse_aspect_ratio(raw: String) -> float:
	var trimmed: String = raw.strip_edges().to_lower()
	if trimmed == "":
		return 0.0
	var parts: PackedStringArray = trimmed.split(":", false)
	if parts.size() != 2:
		parts = trimmed.split("x", false)
	if parts.size() != 2:
		return 0.0
	var width: float = float(parts[0])
	var height: float = float(parts[1])
	if width <= 0.0 or height <= 0.0:
		return 0.0
	return width / height

func _add_game_face(root: Node3D, size: Vector2, position: Vector3, rotation_deg: Vector3, material: Material) -> void:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = size
	var face: MeshInstance3D = MeshInstance3D.new()
	face.mesh = quad
	face.material_override = material
	face.position = position
	face.rotation_degrees = rotation_deg
	root.add_child(face)

func _create_box_material(texture: Texture2D) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	if texture != null:
		material.albedo_texture = texture
		material.albedo_color = Color(1, 1, 1, 1)
	else:
		material.albedo_color = Color(0.4, 0.4, 0.4, 1)
	return material

func _load_game_texture(system_name: String, face: String, game_name: String) -> Texture2D:
	var assets_root: String = _resolve_assets_root()
	var system_folder: String = assets_root.path_join(system_name)
	var face_folder: String = system_folder.path_join(face)
	var file_name: String = "%s.png" % game_name
	var texture_path: String = face_folder.path_join(file_name)
	return _load_texture(texture_path)

func _load_texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var image: Image = Image.new()
	var err: int = image.load(path)
	if err != OK:
		return null
	var texture: Texture2D = ImageTexture.create_from_image(image)
	return texture

func _resolve_assets_root() -> String:
	var exe_dir: String = OS.get_executable_path().get_base_dir()
	var external_assets: String = exe_dir.path_join("assets")
	if DirAccess.dir_exists_absolute(external_assets):
		return external_assets
	return "res://assets"

func _get_system_path(system: Dictionary) -> String:
	if system.has("path"):
		return _expand_path(_apply_root_folder(str(system.get("path", ""))))
	if system.has("folder"):
		return _expand_path(_apply_root_folder(str(system.get("folder", ""))))
	if system.has("folder_path"):
		return _expand_path(_apply_root_folder(str(system.get("folder_path", ""))))
	return ""

func _parse_extensions(raw: String) -> Array[String]:
	var items: Array[String] = []
	if raw == "":
		return items

	var parts: PackedStringArray = raw.split(",", false)
	for part in parts:
		var ext: String = part.strip_edges().to_lower()
		if ext == "":
			continue
		if ext.begins_with("."):
			ext = ext.substr(1)
		items.append(ext)
	return items

func _load_games(path: String, extensions: Array[String]) -> Array[Dictionary]:
	if path == "":
		return []
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		push_warning("Unable to open game path: %s" % path)
		return []

	var games: Array[Dictionary] = []
	var filter_extensions: bool = not extensions.is_empty()
	dir.list_dir_begin()
	while true:
		var file: String = dir.get_next()
		if file == "":
			break
		if dir.current_is_dir():
			continue
		if file.begins_with("."):
			continue
		if filter_extensions:
			var ext: String = file.get_extension().to_lower()
			if ext == "" or not extensions.has(ext):
				continue
		var name: String = file.get_basename()
		games.append({"name": name, "file": path.path_join(file)})
	dir.list_dir_end()

	games.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var name_a: String = str(a.get("name", "")).to_lower()
		var name_b: String = str(b.get("name", "")).to_lower()
		return name_a < name_b
	)

	return games

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
		_update_system_label(selected_index)
	_ensure_system_row_visible(int(selected_index / grid_columns))

func _move_selection(delta_col: int, delta_row: int) -> void:
	if total_systems <= 0:
		return
	if selected_index < 0:
		_set_selected(0)
		return

	var row: int = int(selected_index / grid_columns)
	var col: int = selected_index % grid_columns
	var new_row: int = row
	var new_col: int = col

	if delta_row != 0:
		if delta_row > 0:
			if row >= grid_rows - 1:
				new_row = 0
				grid_top_row = 0
			else:
				new_row = row + 1
		else:
			if row <= 0:
				new_row = int(max(grid_rows - 1, 0))
				grid_top_row = int(max(grid_rows - max(visible_rows, 1), 0))
			else:
				new_row = row - 1
	else:
		new_col = int(clamp(col + delta_col, 0, grid_columns - 1))

	var new_index: int = int(new_row * grid_columns + new_col)
	if new_index >= total_systems:
		new_index = total_systems - 1

	_set_selected(new_index)
	_ensure_system_row_visible(new_row)

func _set_game_selected(index: int) -> void:
	if game_total <= 0:
		return

	var clamped_index: int = int(clamp(index, 0, game_total - 1))
	if game_selected_index >= 0 and game_selected_index < game_nodes.size():
		game_nodes[game_selected_index].scale = _get_game_base_scale(game_selected_index)
		_reset_game_rotation(game_selected_index)

	game_selected_index = clamped_index
	if game_selected_index < game_nodes.size():
		game_nodes[game_selected_index].scale = _get_game_base_scale(game_selected_index) * selected_scale
		_update_game_label(game_selected_index)
	_ensure_game_row_visible(int(game_selected_index / game_columns))

func _move_game_selection(delta_col: int, delta_row: int) -> void:
	if game_total <= 0:
		return
	if game_selected_index < 0:
		_set_game_selected(0)
		return

	var row: int = int(game_selected_index / game_columns)
	var col: int = game_selected_index % game_columns
	var new_row: int = row
	var new_col: int = col

	if delta_row != 0:
		if delta_row > 0:
			if row >= game_rows - 1:
				new_row = 0
				game_top_row = 0
			else:
				new_row = row + 1
		else:
			if row <= 0:
				new_row = int(max(game_rows - 1, 0))
				game_top_row = int(max(game_rows - max(visible_rows, 1), 0))
			else:
				new_row = row - 1
	else:
		new_col = int(clamp(col + delta_col, 0, game_columns - 1))

	var new_index: int = int(new_row * game_columns + new_col)
	if new_index >= game_total:
		new_index = game_total - 1

	_set_game_selected(new_index)
	_ensure_game_row_visible(new_row)

func _launch_selected_game() -> void:
	if game_selected_index < 0 or game_selected_index >= game_list.size():
		return

	var rom_path: String = str(game_list[game_selected_index].get("file", ""))
	if rom_path == "":
		push_warning("Selected game has no file path.")
		return

	var launch_cmd: String = str(current_system.get("launch", ""))
	if launch_cmd.strip_edges() == "":
		push_warning("No launch command configured for this system.")
		return

	var tokens: Array[String] = _split_command(launch_cmd)
	if tokens.is_empty():
		push_warning("Launch command is empty or invalid.")
		return

	var expanded_rom: String = _expand_path(rom_path)
	var has_rom: bool = false
	for i in range(tokens.size()):
		var token: String = tokens[i]
		if token.find("%ROM%") != -1:
			tokens[i] = token.replace("%ROM%", expanded_rom)
			has_rom = true

	if not has_rom:
		push_warning("Launch command must include %ROM% placeholder.")
		return

	for i in range(tokens.size()):
		tokens[i] = _expand_path(_apply_root_folder(tokens[i]))

	var exec_path: String = tokens[0]
	if _looks_like_path(exec_path) and not FileAccess.file_exists(exec_path):
		push_error("Executable not found: %s" % exec_path)
		return
	var args: Array[String] = []
	for i in range(1, tokens.size()):
		args.append(tokens[i])

	print("Launching:", exec_path, "Args:", args)
	var pid: int = OS.create_process(exec_path, args)
	if pid == -1:
		push_error("Failed to launch: %s" % exec_path)

func _split_command(command: String) -> Array[String]:
	var tokens: Array[String] = []
	var current: String = ""
	var in_quotes: bool = false
	var quote_char: String = ""
	var escape: bool = false

	for i in range(command.length()):
		var ch: String = command.substr(i, 1)
		if escape:
			current += ch
			escape = false
			continue
		if ch == "\\":
			escape = true
			continue
		if in_quotes:
			if ch == quote_char:
				in_quotes = false
			else:
				current += ch
			continue
		if ch == "\"" or ch == "'":
			in_quotes = true
			quote_char = ch
			continue
		if _is_whitespace(ch):
			if current != "":
				tokens.append(current)
				current = ""
			continue
		current += ch

	if current != "":
		tokens.append(current)

	return tokens

func _is_whitespace(ch: String) -> bool:
	return ch == " " or ch == "\t" or ch == "\n" or ch == "\r"

func _expand_path(path: String) -> String:
	var expanded: String = path
	if expanded.begins_with("res://") or expanded.begins_with("user://"):
		return ProjectSettings.globalize_path(expanded)
	if expanded.begins_with("~"):
		var home: String = OS.get_environment("HOME")
		if home != "":
			expanded = home + expanded.substr(1)
	if expanded.find("$HOME") != -1:
		var home_env: String = OS.get_environment("HOME")
		if home_env != "":
			expanded = expanded.replace("$HOME", home_env)
	return expanded

func _looks_like_path(value: String) -> bool:
	return value.find("/") != -1 or value.find("\\") != -1

func _apply_root_folder(path: String) -> String:
	var token: String = "%rootfolder%"
	var lower: String = path.to_lower()
	if lower.begins_with(token):
		if rom_root == "":
			push_warning("Root folder is not set in config.cfg.")
			return path.replace("%rootfolder%", "").replace("%ROOTFOLDER%", "")
		var remainder: String = path.substr(token.length())
		if remainder.begins_with("/") or remainder.begins_with("\\"):
			remainder = remainder.substr(1)
		return rom_root.path_join(remainder)
	if path.find("%rootfolder%") != -1 or path.find("%ROOTFOLDER%") != -1:
		if rom_root != "":
			return path.replace("%rootfolder%", rom_root).replace("%ROOTFOLDER%", rom_root)
		push_warning("Root folder is not set in config.cfg.")
	return path

func _load_config() -> void:
	var config_path: String = _resolve_config_path()
	var config: ConfigFile = ConfigFile.new()
	if not FileAccess.file_exists(config_path):
		_write_default_config(config_path)
	var err: int = config.load(config_path)
	if err != OK:
		push_error("Failed to load config: %s (err %s)" % [config_path, err])
		return
	var root_value: String = str(config.get_value("paths", "root_folder", ""))
	rom_root = _expand_path(root_value.strip_edges())

func _resolve_config_path() -> String:
	var exe_dir: String = OS.get_executable_path().get_base_dir()
	var external: String = exe_dir.path_join("config.cfg")
	if FileAccess.file_exists(external):
		return external
	if FileAccess.file_exists("user://config.cfg"):
		return "user://config.cfg"
	if FileAccess.file_exists("res://config.cfg"):
		return "res://config.cfg"
	return "user://config.cfg"

func _write_default_config(path: String) -> void:
	if path.begins_with("res://"):
		return
	var config: ConfigFile = ConfigFile.new()
	config.set_value("paths", "root_folder", "/path/to/roms")
	config.save(path)

func _unhandled_input(event: InputEvent) -> void:
	if is_transitioning:
		return

	if event.is_action_pressed("ui_cancel"):
		if showing_games:
			_return_to_systems()
		return

	if event.is_action_pressed("ui_accept"):
		if showing_games:
			_launch_selected_game()
		else:
			_enter_selected_system()
		return

	if showing_games:
		if event.is_action_pressed("ui_left"):
			_move_game_selection(-1, 0)
		elif event.is_action_pressed("ui_right"):
			_move_game_selection(1, 0)
		elif event.is_action_pressed("ui_up"):
			_move_game_selection(0, -1)
		elif event.is_action_pressed("ui_down"):
			_move_game_selection(0, 1)
		return

	if event.is_action_pressed("ui_left"):
		_move_selection(-1, 0)
	elif event.is_action_pressed("ui_right"):
		_move_selection(1, 0)
	elif event.is_action_pressed("ui_up"):
		_move_selection(0, -1)
	elif event.is_action_pressed("ui_down"):
		_move_selection(0, 1)

func _enter_selected_system() -> void:
	if selected_index < 0 or selected_index >= grid_systems.size():
		return
	if is_transitioning:
		return

	var system: Dictionary = grid_systems[selected_index]
	_transition_to_games(system)

func _transition_to_games(system: Dictionary) -> void:
	is_transitioning = true
	showing_games = true
	current_system = system
	_fade_grid(grid_container, 1.0, fade_duration)
	await get_tree().create_timer(fade_duration).timeout
	grid_container.visible = false

	_build_game_grid(system)
	game_grid_container.visible = true
	_set_grid_transparency(game_grid_container, 1.0)
	_fade_grid(game_grid_container, 0.0, fade_duration)
	await get_tree().create_timer(fade_duration).timeout
	is_transitioning = false

func _return_to_systems() -> void:
	if is_transitioning:
		return
	_transition_to_systems()

func _transition_to_systems() -> void:
	is_transitioning = true
	_fade_grid(game_grid_container, 1.0, fade_duration)
	await get_tree().create_timer(fade_duration).timeout
	game_grid_container.visible = false
	showing_games = false
	current_system = {}
	_clear_game_grid()

	grid_container.visible = true
	_set_grid_transparency(grid_container, 1.0)
	_fade_grid(grid_container, 0.0, fade_duration)
	_update_system_label(selected_index)
	await get_tree().create_timer(fade_duration).timeout
	is_transitioning = false

func _fade_grid(root: Node3D, target_alpha: float, duration: float) -> void:
	var meshes: Array[GeometryInstance3D] = _collect_geometry(root)
	for mesh in meshes:
		var tween: Tween = mesh.create_tween()
		tween.tween_property(mesh, "transparency", target_alpha, duration)

func _set_grid_transparency(root: Node3D, alpha: float) -> void:
	var meshes: Array[GeometryInstance3D] = _collect_geometry(root)
	for mesh in meshes:
		mesh.transparency = alpha

func _collect_geometry(root: Node) -> Array[GeometryInstance3D]:
	var result: Array[GeometryInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is GeometryInstance3D:
			result.append(node as GeometryInstance3D)
		for child in node.get_children():
			var child_node: Node = child
			stack.append(child_node)
	return result

func _process(delta: float) -> void:
	if showing_games:
		if game_selected_index >= 0 and game_selected_index < game_nodes.size():
			game_nodes[game_selected_index].rotate_y(selected_spin_speed * delta)
		return
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

func _reset_game_rotation(index: int) -> void:
	if index < 0 or index >= game_nodes.size() or index >= game_base_rotations.size():
		return

	var node := game_nodes[index]
	if not is_instance_valid(node):
		return

	var base_rot := game_base_rotations[index]
	if deselect_return_time <= 0.0:
		node.rotation = base_rot
		return

	var tween := node.create_tween()
	tween.tween_property(node, "rotation", base_rot, deselect_return_time)

func _ensure_system_row_visible(row: int) -> void:
	if grid_rows <= 0:
		return
	var visible: int = int(max(visible_rows, 1))
	if grid_rows <= visible:
		grid_top_row = 0
		_update_system_scroll_position()
		return
	if row < grid_top_row:
		grid_top_row = row
	elif row >= grid_top_row + visible:
		grid_top_row = row - visible + 1
	grid_top_row = int(clamp(grid_top_row, 0, grid_rows - visible))
	_update_system_scroll_position()

func _ensure_game_row_visible(row: int) -> void:
	if game_rows <= 0:
		return
	var visible: int = int(max(visible_rows, 1))
	if game_rows <= visible:
		game_top_row = 0
		_update_game_scroll_position()
		return
	if row < game_top_row:
		game_top_row = row
	elif row >= game_top_row + visible:
		game_top_row = row - visible + 1
	game_top_row = int(clamp(game_top_row, 0, game_rows - visible))
	_update_game_scroll_position()

func _update_system_scroll_position() -> void:
	if grid_rows <= 0:
		return
	var visible: int = int(min(grid_rows, max(visible_rows, 1)))
	var total_height: float = float(grid_rows - 1) * spacing
	var start_y: float = total_height / 2.0
	var center_row: float = float(grid_top_row) + float(visible - 1) * 0.5
	var center_y: float = start_y - center_row * spacing
	grid_container.position = Vector3(0.0, -center_y, 0.0)

func _update_game_scroll_position() -> void:
	if game_rows <= 0:
		return
	var visible: int = int(min(game_rows, max(visible_rows, 1)))
	var total_height: float = float(game_rows - 1) * spacing
	var start_y: float = total_height / 2.0
	var center_row: float = float(game_top_row) + float(visible - 1) * 0.5
	var center_y: float = start_y - center_row * spacing
	game_grid_container.position = Vector3(0.0, -center_y, 0.0)

func _fit_model_to_cell(root: Node3D) -> void:
	var bounds: AABB = _get_model_aabb(root)
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

func _get_game_base_scale(index: int) -> Vector3:
	if index < 0 or index >= game_base_scales.size():
		return Vector3.ONE
	return game_base_scales[index]

func _update_system_label(index: int) -> void:
	if selected_label == null:
		return
	if index < 0 or index >= grid_systems.size():
		selected_label.text = ""
		return
	selected_label.text = str(grid_systems[index].get("name", ""))

func _update_game_label(index: int) -> void:
	if selected_label == null:
		return
	if index < 0 or index >= game_list.size():
		selected_label.text = ""
		return
	selected_label.text = str(game_list[index].get("name", ""))

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
				elif in_system and name in ["name", "emulator", "path", "folder", "folder_path", "model", "model_path", "extensions", "launch", "box_aspect", "box_thickness"]:
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
