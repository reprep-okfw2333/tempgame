class_name CloudLayers
extends Node3D

## Two exterior, world-anchored cloud strata built from opaque low-poly
## geometry. Six whole-cloud silhouettes per layer, independent wind bands,
## broad deterministic scattering, and a distant dithered cutoff keep the
## field varied without particles, textures, or transparent-card overdraw.

const SHAPE_VARIANT_COUNT := 6
const TILE_PERIOD := 360.0
const TILE_RADIUS := 2
const TILE_COPY_COUNT := TILE_RADIUS * 2 + 1
const DISTANCE_FADE_BEGIN := 340.0
const DISTANCE_FADE_END := 520.0

const LOWER_BASE_COUNTS := [14, 12, 8, 6, 5, 3]
const UPPER_BASE_COUNTS := [7, 6, 4, 3, 2, 2]
const LOWER_MAX_Y := -10.5
const MOUNTAIN_CLEARANCE_ABOVE := 4.0

const LOWER_SPEEDS := [0.16, 0.23, 0.32, 0.43, 0.57, 0.74]
const UPPER_SPEEDS := [-0.29, -0.39, -0.51, -0.66, -0.84, -1.05]
const LOWER_PHASES := [-164.0, -107.0, -48.0, 29.0, 101.0, 158.0]
const UPPER_PHASES := [-151.0, -91.0, -17.0, 53.0, 117.0, 169.0]

const LOWER_COLOR := Color("#d0d4c5")
const UPPER_COLOR := Color("#c3c0ca")
const LOWER_SEED := 0x10C10D
const UPPER_SEED := 0xA80CE

var mine_visual_bounds := AABB(Vector3(-80.01, -610.01, -153.01), Vector3(160.02, 640.02, 160.02))
var lower_root: Node3D
var upper_root: Node3D
var lower_material: ShaderMaterial
var upper_material: ShaderMaterial
var cloud_meshes: Array[ArrayMesh] = []
var lower_drift_roots: Array[Node3D] = []
var upper_drift_roots: Array[Node3D] = []
var lower_batches: Array[MultiMeshInstance3D] = []
var upper_batches: Array[MultiMeshInstance3D] = []
var wind_time := 0.0


func _ready() -> void:
	set_process(false)


func setup(mountain_bounds: AABB) -> void:
	mine_visual_bounds = mountain_bounds
	lower_material = _cloud_material(LOWER_COLOR)
	upper_material = _cloud_material(UPPER_COLOR)

	for variant_index in range(SHAPE_VARIANT_COUNT):
		cloud_meshes.append(_create_cloud_mesh(variant_index))

	lower_root = Node3D.new()
	lower_root.name = "LowerCloudDeck"
	lower_root.set_meta("cloud_layer", "lower")
	add_child(lower_root)

	upper_root = Node3D.new()
	upper_root.name = "UpperCloudScatter"
	upper_root.set_meta("cloud_layer", "upper")
	add_child(upper_root)

	for variant_index in range(SHAPE_VARIANT_COUNT):
		_build_batch(
			lower_root,
			lower_material,
			cloud_meshes[variant_index],
			variant_index,
			LOWER_BASE_COUNTS[variant_index],
			false,
			LOWER_SPEEDS[variant_index],
			LOWER_SEED + variant_index * 7919
		)
		_build_batch(
			upper_root,
			upper_material,
			cloud_meshes[variant_index],
			variant_index,
			UPPER_BASE_COUNTS[variant_index],
			true,
			UPPER_SPEEDS[variant_index],
			UPPER_SEED + variant_index * 6151
		)

	set_wind_time(0.0)
	set_process(true)


func _process(delta: float) -> void:
	set_wind_time(wind_time + delta)


func set_wind_time(seconds: float) -> void:
	wind_time = seconds
	for index in range(lower_drift_roots.size()):
		lower_drift_roots[index].position.x = _wrap_wind(
			LOWER_PHASES[index] + LOWER_SPEEDS[index] * wind_time
		)
	for index in range(upper_drift_roots.size()):
		upper_drift_roots[index].position.x = _wrap_wind(
			UPPER_PHASES[index] + UPPER_SPEEDS[index] * wind_time
		)


func get_lower_instance_count() -> int:
	return _instance_total(lower_batches)


func get_upper_instance_count() -> int:
	return _instance_total(upper_batches)


func get_all_cloud_visuals() -> Array[MultiMeshInstance3D]:
	var visuals: Array[MultiMeshInstance3D] = []
	visuals.append_array(lower_batches)
	visuals.append_array(upper_batches)
	return visuals


func _instance_total(batches: Array[MultiMeshInstance3D]) -> int:
	var total := 0
	for batch in batches:
		total += batch.multimesh.instance_count
	return total


func _wrap_wind(value: float) -> float:
	return fposmod(value + TILE_PERIOD * 0.5, TILE_PERIOD) - TILE_PERIOD * 0.5


func _cloud_material(tint: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/clouds.gdshader") as Shader
	material.set_shader_parameter("cloud_tint", tint)
	material.set_shader_parameter("mountain_aabb_min", mine_visual_bounds.position)
	material.set_shader_parameter("mountain_aabb_max", mine_visual_bounds.end)
	material.set_shader_parameter("distance_fade_begin", DISTANCE_FADE_BEGIN)
	material.set_shader_parameter("distance_fade_end", DISTANCE_FADE_END)
	return material


func _build_batch(
	layer_root: Node3D,
	material: ShaderMaterial,
	cloud_mesh: ArrayMesh,
	variant_index: int,
	base_instance_count: int,
	is_upper: bool,
	wind_speed: float,
	seed_value: int
) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var base_transforms: Array[Transform3D] = []
	var base_colors: Array[Color] = []
	var base_custom_data: Array[Color] = []
	var placed_centers: Array[Vector3] = []

	for _instance_index in range(base_instance_count):
		var transform := _random_cloud_transform(
			cloud_mesh.get_aabb(), rng, is_upper, placed_centers
		)
		base_transforms.append(transform)
		placed_centers.append(transform.origin)
		var value := rng.randf_range(0.82, 1.04)
		var warmth := rng.randf_range(0.96, 1.035)
		base_colors.append(Color(value * warmth, value, value / warmth, 1.0))
		base_custom_data.append(Color(rng.randf(), float(variant_index) / 5.0, rng.randf(), 1.0))

	var repeated_count := base_transforms.size() * TILE_COPY_COUNT * TILE_COPY_COUNT
	var cloud_multimesh := MultiMesh.new()
	cloud_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	cloud_multimesh.use_colors = true
	cloud_multimesh.use_custom_data = true
	cloud_multimesh.mesh = cloud_mesh
	cloud_multimesh.instance_count = repeated_count

	var combined_bounds := AABB()
	var has_bounds := false
	var write_index := 0
	for tile_z in range(-TILE_RADIUS, TILE_RADIUS + 1):
		for tile_x in range(-TILE_RADIUS, TILE_RADIUS + 1):
			var tile_offset := Vector3(
				float(tile_x) * TILE_PERIOD,
				0.0,
				float(tile_z) * TILE_PERIOD
			)
			for base_index in range(base_transforms.size()):
				var repeated_transform := base_transforms[base_index]
				repeated_transform.origin += tile_offset
				cloud_multimesh.set_instance_transform(write_index, repeated_transform)
				cloud_multimesh.set_instance_color(write_index, base_colors[base_index])
				cloud_multimesh.set_instance_custom_data(write_index, base_custom_data[base_index])
				var instance_bounds := _transform_aabb(cloud_mesh.get_aabb(), repeated_transform)
				if has_bounds:
					combined_bounds = combined_bounds.merge(instance_bounds)
				else:
					combined_bounds = instance_bounds
					has_bounds = true
				write_index += 1
	cloud_multimesh.custom_aabb = combined_bounds

	var drift_root := Node3D.new()
	drift_root.name = "%sWind%02d" % ["Upper" if is_upper else "Lower", variant_index]
	drift_root.set_meta("cloud_batch", true)
	drift_root.set_meta("cloud_layer", "upper" if is_upper else "lower")
	drift_root.set_meta("shape_variant", variant_index)
	drift_root.set_meta("wind_speed", wind_speed)
	drift_root.set_meta("tile_period", TILE_PERIOD)
	drift_root.set_meta("base_instance_count", base_transforms.size())
	drift_root.set_meta("tile_radius", TILE_RADIUS)
	layer_root.add_child(drift_root)

	var instances := MultiMeshInstance3D.new()
	instances.name = "CloudVariant%02d" % variant_index
	instances.multimesh = cloud_multimesh
	instances.material_override = material
	instances.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instances.set_meta("cloud_batch", true)
	instances.set_meta("cloud_layer", "upper" if is_upper else "lower")
	instances.set_meta("shape_variant", variant_index)
	instances.set_meta("wind_speed", wind_speed)
	instances.set_meta("tile_period", TILE_PERIOD)
	instances.set_meta("base_instance_count", base_transforms.size())
	instances.set_meta("tile_radius", TILE_RADIUS)
	drift_root.add_child(instances)

	if is_upper:
		upper_drift_roots.append(drift_root)
		upper_batches.append(instances)
	else:
		lower_drift_roots.append(drift_root)
		lower_batches.append(instances)


func _random_cloud_transform(
	mesh_bounds: AABB,
	rng: RandomNumberGenerator,
	is_upper: bool,
	placed_centers: Array[Vector3]
) -> Transform3D:
	var size_roll := rng.randf()
	var overall_size := 1.0
	if size_roll < 0.23:
		overall_size = rng.randf_range(0.42, 0.72)
	elif size_roll < 0.88:
		overall_size = rng.randf_range(0.76, 1.52)
	else:
		overall_size = rng.randf_range(1.72, 2.65)
	if is_upper:
		overall_size *= rng.randf_range(0.76, 1.12)

	var scale := Vector3(
		overall_size * rng.randf_range(0.68, 1.38),
		overall_size * rng.randf_range(0.62, 1.22),
		overall_size * rng.randf_range(0.66, 1.34)
	)
	var rotation := Vector3(
		rng.randf_range(-0.055, 0.055),
		rng.randf_range(0.0, TAU),
		rng.randf_range(-0.045, 0.045)
	)
	var basis := Basis.from_euler(rotation).scaled(scale)
	var bounds_at_origin := _transform_aabb(mesh_bounds, Transform3D(basis, Vector3.ZERO))
	var center_xz := _scatter_center(rng, placed_centers, overall_size)
	var origin := Vector3(center_xz.x, 0.0, center_xz.z)

	if is_upper:
		var altitude_roll := rng.randf()
		var desired_bottom := mine_visual_bounds.end.y + MOUNTAIN_CLEARANCE_ABOVE
		if altitude_roll < 0.56:
			desired_bottom += rng.randf_range(0.0, 34.0)
		elif altitude_roll < 0.88:
			desired_bottom += rng.randf_range(32.0, 92.0)
		else:
			desired_bottom += rng.randf_range(88.0, 178.0)
		origin.y = desired_bottom - bounds_at_origin.position.y
	else:
		var depth_roll := rng.randf()
		var desired_top := LOWER_MAX_Y
		if depth_roll < 0.68:
			desired_top -= rng.randf_range(0.0, 18.0)
		elif depth_roll < 0.94:
			desired_top -= rng.randf_range(18.0, 50.0)
		else:
			desired_top -= rng.randf_range(50.0, 105.0)
		origin.y = desired_top - bounds_at_origin.end.y

	return Transform3D(basis, origin)


func _scatter_center(
	rng: RandomNumberGenerator,
	placed_centers: Array[Vector3],
	overall_size: float
) -> Vector3:
	var candidate := Vector3.ZERO
	for attempt in range(24):
		candidate = Vector3(
			rng.randf_range(-TILE_PERIOD * 0.5, TILE_PERIOD * 0.5),
			0.0,
			rng.randf_range(-TILE_PERIOD * 0.5, TILE_PERIOD * 0.5)
		)
		var separated := true
		var minimum_spacing := 8.0 + overall_size * 7.0
		for other in placed_centers:
			var delta_xz := Vector2(candidate.x - other.x, candidate.z - other.z)
			if delta_xz.length() < minimum_spacing:
				separated = false
				break
		if separated:
			return candidate
	return candidate


func _transform_aabb(bounds: AABB, transform: Transform3D) -> AABB:
	var transformed := AABB()
	var initialized := false
	for corner_index in range(8):
		var corner := bounds.position + Vector3(
			bounds.size.x if (corner_index & 1) != 0 else 0.0,
			bounds.size.y if (corner_index & 2) != 0 else 0.0,
			bounds.size.z if (corner_index & 4) != 0 else 0.0
		)
		var point := transform * corner
		if initialized:
			transformed = transformed.expand(point)
		else:
			transformed = AABB(point, Vector3.ZERO)
			initialized = true
	return transformed


func _create_cloud_mesh(variant_index: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var lobes := _variant_lobes(variant_index)
	for lobe_index in range(lobes.size()):
		_append_lobe(vertices, normals, colors, lobes[lobe_index], variant_index, lobe_index)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _variant_lobes(variant_index: int) -> Array[Transform3D]:
	var lobes: Array[Transform3D] = []
	match variant_index:
		0: # Compact cauliflower mound.
			lobes.append(_lobe(Vector3(0.0, 0.0, 0.0), Vector3(5.8, 2.5, 4.5), 0.10))
			lobes.append(_lobe(Vector3(-4.2, -0.2, 0.8), Vector3(3.7, 1.8, 3.1), -0.18))
			lobes.append(_lobe(Vector3(4.3, 0.2, -0.6), Vector3(4.1, 2.0, 3.4), 0.22))
			lobes.append(_lobe(Vector3(-0.7, 1.8, -0.4), Vector3(4.0, 2.8, 3.5), -0.08))
			lobes.append(_lobe(Vector3(1.4, -0.5, 3.1), Vector3(3.4, 1.6, 2.5), 0.31))
		1: # Long, low shelf.
			lobes.append(_lobe(Vector3(-9.0, -0.3, 0.4), Vector3(5.0, 1.7, 3.0), 0.18))
			lobes.append(_lobe(Vector3(-5.4, 0.2, -0.8), Vector3(5.7, 2.0, 3.6), -0.12))
			lobes.append(_lobe(Vector3(-0.8, 0.5, 0.2), Vector3(6.1, 2.2, 3.9), 0.05))
			lobes.append(_lobe(Vector3(4.4, 0.0, 0.9), Vector3(5.4, 1.9, 3.2), 0.26))
			lobes.append(_lobe(Vector3(9.1, -0.4, -0.2), Vector3(4.4, 1.5, 2.8), -0.22))
			lobes.append(_lobe(Vector3(0.8, 1.7, -0.7), Vector3(4.2, 1.8, 3.0), 0.14))
		2: # Tall thunderhead.
			lobes.append(_lobe(Vector3(0.0, -1.7, 0.0), Vector3(5.4, 2.2, 4.7), 0.04))
			lobes.append(_lobe(Vector3(-2.8, 1.3, 0.7), Vector3(4.0, 2.8, 3.6), -0.17))
			lobes.append(_lobe(Vector3(2.3, 2.3, -0.5), Vector3(4.2, 3.2, 3.7), 0.19))
			lobes.append(_lobe(Vector3(-0.3, 5.4, 0.2), Vector3(3.8, 3.5, 3.3), -0.05))
			lobes.append(_lobe(Vector3(1.0, 8.1, -0.2), Vector3(2.8, 2.5, 2.7), 0.27))
		3: # Broken twin islands with an intentional gap.
			lobes.append(_lobe(Vector3(-7.0, -0.2, -0.2), Vector3(4.7, 2.2, 4.0), -0.16))
			lobes.append(_lobe(Vector3(-3.6, 1.4, 0.6), Vector3(3.4, 2.3, 3.0), 0.11))
			lobes.append(_lobe(Vector3(5.3, 0.1, -0.5), Vector3(4.3, 1.9, 3.6), 0.21))
			lobes.append(_lobe(Vector3(8.1, 1.0, 0.4), Vector3(3.2, 2.2, 2.7), -0.24))
		4: # Anvil cap and narrow stem.
			lobes.append(_lobe(Vector3(0.0, -2.3, 0.0), Vector3(3.2, 3.5, 3.0), 0.08))
			lobes.append(_lobe(Vector3(-1.0, 1.1, 0.3), Vector3(4.0, 3.0, 3.6), -0.13))
			lobes.append(_lobe(Vector3(-7.4, 3.0, 0.1), Vector3(5.4, 1.9, 3.3), 0.20))
			lobes.append(_lobe(Vector3(-3.3, 3.6, -0.6), Vector3(5.5, 2.2, 3.8), -0.08))
			lobes.append(_lobe(Vector3(1.8, 3.8, 0.4), Vector3(5.8, 2.3, 4.0), 0.16))
			lobes.append(_lobe(Vector3(7.0, 3.2, -0.2), Vector3(5.0, 1.8, 3.2), -0.19))
			lobes.append(_lobe(Vector3(10.1, 2.7, 0.5), Vector3(3.5, 1.4, 2.6), 0.28))
		5: # Thin diagonal wind streak.
			lobes.append(_lobe(Vector3(-10.0, -0.6, -3.4), Vector3(4.2, 1.3, 2.4), 0.31))
			lobes.append(_lobe(Vector3(-6.0, -0.1, -2.1), Vector3(5.0, 1.6, 2.8), -0.22))
			lobes.append(_lobe(Vector3(-1.5, 0.7, -0.7), Vector3(5.5, 1.9, 3.1), 0.14))
			lobes.append(_lobe(Vector3(3.3, 0.2, 1.0), Vector3(4.7, 1.5, 2.6), -0.10))
			lobes.append(_lobe(Vector3(7.4, -0.4, 2.5), Vector3(4.1, 1.3, 2.3), 0.24))
			lobes.append(_lobe(Vector3(10.8, -0.8, 3.7), Vector3(3.0, 1.0, 1.9), -0.29))
	return lobes


func _lobe(position: Vector3, scale: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(0.0, yaw, 0.0)).scaled(scale), position)


func _append_lobe(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	transform: Transform3D,
	variant_index: int,
	lobe_index: int
) -> void:
	var ratio := (1.0 + sqrt(5.0)) * 0.5
	var points: Array[Vector3] = [
		Vector3(-1.0, ratio, 0.0), Vector3(1.0, ratio, 0.0),
		Vector3(-1.0, -ratio, 0.0), Vector3(1.0, -ratio, 0.0),
		Vector3(0.0, -1.0, ratio), Vector3(0.0, 1.0, ratio),
		Vector3(0.0, -1.0, -ratio), Vector3(0.0, 1.0, -ratio),
		Vector3(ratio, 0.0, -1.0), Vector3(ratio, 0.0, 1.0),
		Vector3(-ratio, 0.0, -1.0), Vector3(-ratio, 0.0, 1.0)
	]
	for point_index in range(points.size()):
		points[point_index] = points[point_index].normalized()

	var faces := PackedInt32Array([
		0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
		1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
		4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1
	])
	for face_index in range(0, faces.size(), 3):
		var a := transform * _deform_point(points[faces[face_index]], variant_index, lobe_index)
		var b := transform * _deform_point(points[faces[face_index + 1]], variant_index, lobe_index)
		var c := transform * _deform_point(points[faces[face_index + 2]], variant_index, lobe_index)
		_append_flat_triangle(vertices, normals, colors, a, b, c, variant_index, lobe_index, face_index / 3)


func _deform_point(direction: Vector3, variant_index: int, lobe_index: int) -> Vector3:
	var phase := float(variant_index * 37 + lobe_index * 19) * 0.173
	var wave := (
		sin(direction.x * 8.7 + direction.y * 13.1 + direction.z * 17.3 + phase) * 0.62
		+ sin(direction.x * 21.7 - direction.y * 9.3 + direction.z * 5.9 + phase * 1.71) * 0.38
	)
	var amount := 0.055 + float((variant_index + lobe_index) % 4) * 0.018
	return direction * (1.0 + wave * amount)


func _append_flat_triangle(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	variant_index: int,
	lobe_index: int,
	face_index: int
) -> void:
	var normal := (b - a).cross(c - a).normalized()
	var upward := clampf(normal.y * 0.5 + 0.5, 0.0, 1.0)
	var step_value := floorf(upward * 3.0 + 0.5) / 3.0
	var face_phase := float(variant_index * 101 + lobe_index * 23 + face_index * 7)
	var face_noise := fposmod(sin(face_phase * 1.618) * 43758.5453, 1.0)
	var face_value := clampf(lerpf(0.76, 1.0, step_value) + (face_noise - 0.5) * 0.055, 0.72, 1.0)
	vertices.append(a)
	vertices.append(b)
	vertices.append(c)
	normals.append(normal)
	normals.append(normal)
	normals.append(normal)
	colors.append(Color(face_value, face_value, face_value, 1.0))
	colors.append(Color(face_value, face_value, face_value, 1.0))
	colors.append(Color(face_value, face_value, face_value, 1.0))
