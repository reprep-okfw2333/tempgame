class_name BlockVolume
extends Node3D

## Solid sculptable cube. Nearby surface voxels become MineableBlock bodies,
## distant surface voxels are batched visuals, and the interior remains bytes.

const AIR := 0
const STONE := 1
const COAL := 2
const COPPER := 3

# 80 x 320 x 80 = 2,048,000 cells. The landing floor stays at world Y -1;
# the extra height is almost all downward (~304 cells / 608 units).
const SIZE := Vector3i(80, 320, 80)
const CELL := 2.0
const LANDING_FLOOR_Y := -1.0
const LAYERS_ABOVE_LANDING := 15
const INTERACTION_RADIUS := 14
const STREAM_RADIUS := 28
const DESPAWN_RADIUS := 36
const STREAM_UPDATE_DISTANCE := 4
const STREAM_CHUNK_SIZE := 8
const STREAM_WORK_BUDGET_USEC := 4000
const SAVE_PATH := "user://sculpted_volume.bin"
const SAVE_MAGIC := "LPM1"
const _CHUNK_MODE_NEAR := 1
const _CHUNK_MODE_FAR := 2

const _NEIGHBORS := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1)
]

signal block_spawned(block: MineableBlock)

var origin := Vector3(-19.0, -1.0, -32.0)
var cells := PackedByteArray()
var dirty := false
var _nodes: Dictionary = {}
var _loaded_chunks: Dictionary = {}
var _chunk_visuals: Dictionary = {}
var _pending_chunk_modes: Dictionary = {}
var _pending_near_chunks: Array[Vector3i] = []
var _pending_far_chunks: Array[Vector3i] = []
var _pending_unloads: Array[Vector3i] = []
var _stream_initialized := false
var _stream_center := Vector3i(99999, 99999, 99999)
var _stream_box_mesh: BoxMesh
var _stone_material: StandardMaterial3D
var _coal_material: StandardMaterial3D
var _copper_material: StandardMaterial3D
var _crack_textures: Array = []


func setup(
	stone_material: StandardMaterial3D,
	coal_material: StandardMaterial3D,
	copper_material: StandardMaterial3D,
	cracks: Array
) -> void:
	_stone_material = stone_material
	_coal_material = coal_material
	_copper_material = copper_material
	_crack_textures = cracks
	# Front face at z = 6. Bottom extends far below the landing; the
	# landing-floor layer and 15 layers above it stay at the old heights.
	var landing_layer := SIZE.y - 1 - LAYERS_ABOVE_LANDING
	origin = Vector3(
		-float(SIZE.x - 1),
		LANDING_FLOOR_Y - float(landing_layer) * CELL,
		6.0 - float(SIZE.z - 1) * CELL
	)
	if not _load():
		_fill_stone()
	_stream_box_mesh = BoxMesh.new()
	_stream_box_mesh.size = Vector3.ONE * MineableBlock.BLOCK_VISUAL_SIZE
	sync_around(Vector3(0.0, 1.0, 14.0))


func world_position(grid: Vector3i) -> Vector3:
	return origin + Vector3(grid) * CELL


func get_visual_aabb() -> AABB:
	# Includes the deliberate 0.01-unit visual overlap around the outermost
	# voxel centers. Presentation systems can therefore respect the exact rock
	# silhouette without duplicating the volume's dimensional assumptions.
	var visual_size := MineableBlock.BLOCK_VISUAL_SIZE
	var bounds_size := Vector3(
		float(SIZE.x - 1) * CELL + visual_size,
		float(SIZE.y - 1) * CELL + visual_size,
		float(SIZE.z - 1) * CELL + visual_size
	)
	return AABB(origin - Vector3.ONE * visual_size * 0.5, bounds_size)


func world_to_grid(world: Vector3) -> Vector3i:
	var local := (world - origin) / CELL
	return Vector3i(roundi(local.x), roundi(local.y), roundi(local.z))


func sync_around(world_pos: Vector3) -> void:
	_process_stream_queue()
	var center := world_to_grid(world_pos)
	if _stream_initialized:
		var movement := center - _stream_center
		if (
			absi(movement.x) < STREAM_UPDATE_DISTANCE
			and absi(movement.y) < STREAM_UPDATE_DISTANCE
			and absi(movement.z) < STREAM_UPDATE_DISTANCE
		):
			return
	_stream_center = center

	# Work in cached 8-cell chunks. Near chunks use fully interactive bodies;
	# distant chunks render their exposed faces in a few lightweight MultiMeshes.
	# Whole-chunk activation pads both radii, keeping transitions out of view.
	var near_chunks := _chunks_intersecting_sphere(center, INTERACTION_RADIUS)
	var stream_chunks := _chunks_intersecting_sphere(center, STREAM_RADIUS)
	for chunk: Vector3i in stream_chunks:
		var next_mode := _CHUNK_MODE_NEAR if near_chunks.has(chunk) else _CHUNK_MODE_FAR
		if _stream_initialized:
			_queue_chunk_mode(chunk, next_mode)
		else:
			_set_chunk_mode(chunk, next_mode)

	var retained_chunks := _chunks_intersecting_sphere(center, DESPAWN_RADIUS)
	for chunk: Vector3i in _loaded_chunks.keys():
		if not retained_chunks.has(chunk):
			_queue_chunk_mode(chunk, 0)
		elif not near_chunks.has(chunk):
			_queue_chunk_mode(chunk, _CHUNK_MODE_FAR)
	for chunk: Vector3i in _pending_chunk_modes.keys():
		if not stream_chunks.has(chunk) and not _loaded_chunks.has(chunk):
			_pending_chunk_modes.erase(chunk)
	_stream_initialized = true


func type_at(grid: Vector3i) -> int:
	if not _in_bounds(grid):
		return AIR
	return int(cells[_index(grid)])


func remove_voxel(grid: Vector3i) -> void:
	if not _in_bounds(grid):
		return
	cells[_index(grid)] = AIR
	_nodes.erase(grid)
	for offset in _NEIGHBORS:
		var neighbor: Vector3i = grid + offset
		if type_at(neighbor) != AIR and not _nodes.has(neighbor) and _in_stream(neighbor):
			_spawn_block(neighbor)
	_refresh_far_visuals_around(grid)
	_mark_dirty()


func set_voxel_type(grid: Vector3i, type_name: String) -> String:
	var next := _type_id(type_name)
	if next == AIR or not _in_bounds(grid) or type_at(grid) == AIR:
		return ""
	cells[_index(grid)] = next
	var block: MineableBlock = _nodes.get(grid)
	if block != null:
		block.apply_type(_type_name(next), _material_for(next))
	else:
		_refresh_far_chunk(_chunk_for(grid))
	_mark_dirty()
	return _type_name(next)


func reset_to_solid_stone() -> void:
	for block: MineableBlock in _nodes.values():
		if is_instance_valid(block):
			block.queue_free()
	_nodes.clear()
	for visual: Node3D in _chunk_visuals.values():
		if is_instance_valid(visual):
			visual.visible = false
			visual.queue_free()
	_chunk_visuals.clear()
	_loaded_chunks.clear()
	_clear_stream_queue()
	_stream_initialized = false
	_fill_stone()
	_stream_center = Vector3i(99999, 99999, 99999)
	sync_around(origin + Vector3(_stream_fallback_center()) * CELL)
	_mark_dirty()


func save_to_disk() -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not save sculpted volume: %s" % SAVE_PATH)
		return false
	file.store_buffer(SAVE_MAGIC.to_ascii_buffer())
	file.store_16(SIZE.x)
	file.store_16(SIZE.y)
	file.store_16(SIZE.z)
	file.store_buffer(cells)
	dirty = false
	return true


func _mark_dirty() -> void:
	dirty = true


func _fill_stone() -> void:
	cells.resize(SIZE.x * SIZE.y * SIZE.z)
	cells.fill(STONE)


func _in_stream(grid: Vector3i) -> bool:
	return int(_loaded_chunks.get(_chunk_for(grid), 0)) == _CHUNK_MODE_NEAR


func _stream_fallback_center() -> Vector3i:
	return Vector3i(SIZE.x / 2, SIZE.y - 1 - LAYERS_ABOVE_LANDING, SIZE.z - 1)


func _chunk_for(grid: Vector3i) -> Vector3i:
	return Vector3i(
		floori(float(grid.x) / float(STREAM_CHUNK_SIZE)),
		floori(float(grid.y) / float(STREAM_CHUNK_SIZE)),
		floori(float(grid.z) / float(STREAM_CHUNK_SIZE))
	)


func _chunks_intersecting_sphere(center: Vector3i, radius: int) -> Dictionary:
	var found: Dictionary = {}
	var radius_vector := Vector3i(radius, radius, radius)
	var minimum := _chunk_for(center - radius_vector)
	var maximum := _chunk_for(center + radius_vector)
	var last_chunk := _chunk_for(SIZE - Vector3i.ONE)
	minimum = Vector3i(
		clampi(minimum.x, 0, last_chunk.x),
		clampi(minimum.y, 0, last_chunk.y),
		clampi(minimum.z, 0, last_chunk.z)
	)
	maximum = Vector3i(
		clampi(maximum.x, 0, last_chunk.x),
		clampi(maximum.y, 0, last_chunk.y),
		clampi(maximum.z, 0, last_chunk.z)
	)
	var radius_squared := radius * radius
	for z in range(minimum.z, maximum.z + 1):
		for y in range(minimum.y, maximum.y + 1):
			for x in range(minimum.x, maximum.x + 1):
				var chunk := Vector3i(x, y, z)
				var first_cell := chunk * STREAM_CHUNK_SIZE
				var last_cell := Vector3i(
					mini(first_cell.x + STREAM_CHUNK_SIZE - 1, SIZE.x - 1),
					mini(first_cell.y + STREAM_CHUNK_SIZE - 1, SIZE.y - 1),
					mini(first_cell.z + STREAM_CHUNK_SIZE - 1, SIZE.z - 1)
				)
				var closest := Vector3i(
					clampi(center.x, first_cell.x, last_cell.x),
					clampi(center.y, first_cell.y, last_cell.y),
					clampi(center.z, first_cell.z, last_cell.z)
				)
				var delta := closest - center
				if delta.x * delta.x + delta.y * delta.y + delta.z * delta.z <= radius_squared:
					found[chunk] = true
	return found


func _set_chunk_mode(chunk: Vector3i, next_mode: int) -> void:
	var current_mode := int(_loaded_chunks.get(chunk, 0))
	if current_mode == next_mode:
		return
	_loaded_chunks[chunk] = next_mode
	if next_mode == _CHUNK_MODE_NEAR:
		_spawn_near_chunk(chunk)
		_free_far_chunk(chunk)
	else:
		_spawn_far_chunk(chunk)
		_free_near_chunk(chunk)


func _queue_chunk_mode(chunk: Vector3i, next_mode: int) -> void:
	var current_mode := int(_loaded_chunks.get(chunk, 0))
	if current_mode == next_mode:
		_pending_chunk_modes.erase(chunk)
		return
	if int(_pending_chunk_modes.get(chunk, -1)) == next_mode:
		return
	_pending_chunk_modes[chunk] = next_mode
	if next_mode == _CHUNK_MODE_NEAR:
		_pending_near_chunks.append(chunk)
	elif next_mode == _CHUNK_MODE_FAR:
		_pending_far_chunks.append(chunk)
	else:
		_pending_unloads.append(chunk)


func _process_stream_queue() -> void:
	if _pending_chunk_modes.is_empty():
		return
	var started := Time.get_ticks_usec()
	while not _pending_chunk_modes.is_empty():
		var chunk := Vector3i.ZERO
		var expected_mode := -1
		if not _pending_near_chunks.is_empty():
			chunk = _pending_near_chunks.pop_back()
			expected_mode = _CHUNK_MODE_NEAR
		elif not _pending_far_chunks.is_empty():
			chunk = _pending_far_chunks.pop_back()
			expected_mode = _CHUNK_MODE_FAR
		elif not _pending_unloads.is_empty():
			chunk = _pending_unloads.pop_back()
			expected_mode = 0
		else:
			_pending_chunk_modes.clear()
			break
		if int(_pending_chunk_modes.get(chunk, -1)) != expected_mode:
			continue
		_pending_chunk_modes.erase(chunk)
		if expected_mode == 0:
			_unload_chunk(chunk)
		else:
			_set_chunk_mode(chunk, expected_mode)
		if Time.get_ticks_usec() - started >= STREAM_WORK_BUDGET_USEC:
			break


func _clear_stream_queue() -> void:
	_pending_chunk_modes.clear()
	_pending_near_chunks.clear()
	_pending_far_chunks.clear()
	_pending_unloads.clear()


func _unload_chunk(chunk: Vector3i) -> void:
	var current_mode := int(_loaded_chunks.get(chunk, 0))
	_loaded_chunks.erase(chunk)
	if current_mode == _CHUNK_MODE_NEAR:
		_free_near_chunk(chunk)
	elif current_mode == _CHUNK_MODE_FAR:
		_free_far_chunk(chunk)


func _spawn_near_chunk(chunk: Vector3i) -> void:
	var first_cell := chunk * STREAM_CHUNK_SIZE
	var past_last := Vector3i(
		mini(first_cell.x + STREAM_CHUNK_SIZE, SIZE.x),
		mini(first_cell.y + STREAM_CHUNK_SIZE, SIZE.y),
		mini(first_cell.z + STREAM_CHUNK_SIZE, SIZE.z)
	)
	for z in range(first_cell.z, past_last.z):
		for y in range(first_cell.y, past_last.y):
			for x in range(first_cell.x, past_last.x):
				var grid := Vector3i(x, y, z)
				if type_at(grid) != AIR and _is_exposed(grid):
					_spawn_block(grid)


func _free_near_chunk(chunk: Vector3i) -> void:
	var stale: Array[Vector3i] = []
	for grid: Vector3i in _nodes.keys():
		if _chunk_for(grid) == chunk:
			stale.append(grid)
	for grid in stale:
		var block: MineableBlock = _nodes[grid]
		_nodes.erase(grid)
		if is_instance_valid(block):
			block.queue_free()


func _spawn_far_chunk(chunk: Vector3i) -> void:
	var transforms_by_type: Dictionary = {
		STONE: [] as Array[Transform3D],
		COAL: [] as Array[Transform3D],
		COPPER: [] as Array[Transform3D],
	}
	var first_cell := chunk * STREAM_CHUNK_SIZE
	var past_last := Vector3i(
		mini(first_cell.x + STREAM_CHUNK_SIZE, SIZE.x),
		mini(first_cell.y + STREAM_CHUNK_SIZE, SIZE.y),
		mini(first_cell.z + STREAM_CHUNK_SIZE, SIZE.z)
	)
	for z in range(first_cell.z, past_last.z):
		for y in range(first_cell.y, past_last.y):
			for x in range(first_cell.x, past_last.x):
				var grid := Vector3i(x, y, z)
				var kind := type_at(grid)
				if kind != AIR and _is_exposed(grid):
					var transforms: Array = transforms_by_type[kind]
					transforms.append(Transform3D(Basis.IDENTITY, world_position(grid)))

	var container := Node3D.new()
	container.name = "FarChunk_%d_%d_%d" % [chunk.x, chunk.y, chunk.z]
	for kind in [STONE, COAL, COPPER]:
		var transforms: Array = transforms_by_type[kind]
		if transforms.is_empty():
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = _stream_box_mesh
		multimesh.instance_count = transforms.size()
		for index in range(transforms.size()):
			multimesh.set_instance_transform(index, transforms[index])
		var visual := MultiMeshInstance3D.new()
		visual.multimesh = multimesh
		visual.material_override = _material_for(kind)
		# Exposed faces are the only geometry the mountain has. If they do not
		# cast, the sun shines through the hollow interior as if the rock were air.
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		container.add_child(visual)
	_chunk_visuals[chunk] = container
	add_child(container)


func _free_far_chunk(chunk: Vector3i) -> void:
	var visual: Node3D = _chunk_visuals.get(chunk)
	_chunk_visuals.erase(chunk)
	if is_instance_valid(visual):
		visual.visible = false
		visual.queue_free()


func _refresh_far_chunk(chunk: Vector3i) -> void:
	if int(_loaded_chunks.get(chunk, 0)) != _CHUNK_MODE_FAR:
		return
	_free_far_chunk(chunk)
	_spawn_far_chunk(chunk)


func _refresh_far_visuals_around(grid: Vector3i) -> void:
	var affected: Dictionary = {_chunk_for(grid): true}
	for offset in _NEIGHBORS:
		affected[_chunk_for(grid + offset)] = true
	for chunk: Vector3i in affected:
		_refresh_far_chunk(chunk)


func _spawn_block(grid: Vector3i) -> void:
	if _nodes.has(grid):
		return
	var kind := type_at(grid)
	if kind == AIR:
		return
	var block := MineableBlock.new()
	block.position = world_position(grid)
	block.grid_pos = grid
	block.setup(_type_name(kind), _material_for(kind), _crack_textures)
	_nodes[grid] = block
	add_child(block)
	block_spawned.emit(block)


func _is_exposed(grid: Vector3i) -> bool:
	for offset in _NEIGHBORS:
		if type_at(grid + offset) == AIR:
			return true
	return false


func _in_bounds(grid: Vector3i) -> bool:
	return (
		grid.x >= 0 and grid.x < SIZE.x
		and grid.y >= 0 and grid.y < SIZE.y
		and grid.z >= 0 and grid.z < SIZE.z
	)


func _index(grid: Vector3i) -> int:
	return grid.x + SIZE.x * (grid.y + SIZE.y * grid.z)


func _type_id(type_name: String) -> int:
	if type_name == "coal":
		return COAL
	if type_name == "copper":
		return COPPER
	if type_name == "stone":
		return STONE
	return AIR


func _type_name(kind: int) -> String:
	if kind == COAL:
		return "coal"
	if kind == COPPER:
		return "copper"
	return "stone"


func _material_for(kind: int) -> StandardMaterial3D:
	if kind == COAL:
		return _coal_material
	if kind == COPPER:
		return _copper_material
	return _stone_material


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE and dirty:
		save_to_disk()


func _load() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	if file.get_buffer(4).get_string_from_ascii() != SAVE_MAGIC:
		return false
	var sx := file.get_16()
	var sy := file.get_16()
	var sz := file.get_16()
	if Vector3i(sx, sy, sz) != SIZE:
		return false
	var data := file.get_buffer(sx * sy * sz)
	if data.size() != sx * sy * sz:
		return false
	cells = data
	return true
