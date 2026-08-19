class_name PlacedTorch
extends StaticBody3D

const BASE_ENERGY := 2.35
const LIGHT_RANGE := 25.12
const LIGHT_ATTENUATION := 1.08
const SHADOW_OPACITY := 0.66
const SHADOW_BLUR := 2.6

var torch_light: OmniLight3D
var flame: MeshInstance3D
var flicker_time := 0.0
var flicker_phase := 0.0


func setup(surface_position: Vector3, surface_normal: Vector3, wood_material: StandardMaterial3D) -> void:
	# The torch remains ray-pickable without snagging the player, whose default
	# collision mask only includes layer 1.
	collision_layer = 2
	collision_mask = 0
	var normal := surface_normal.normalized()
	global_position = surface_position + normal * 0.35
	quaternion = Quaternion(Vector3.UP, normal)
	flicker_phase = randf() * TAU

	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.055
	shaft_mesh.bottom_radius = 0.075
	shaft_mesh.height = 0.68
	shaft_mesh.radial_segments = 6
	shaft.mesh = shaft_mesh
	shaft.material_override = wood_material
	add_child(shaft)

	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.14
	shape.height = 0.85
	collision.shape = shape
	collision.position.y = 0.15
	add_child(collision)

	flame = MeshInstance3D.new()
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.095
	flame_mesh.height = 0.19
	flame_mesh.radial_segments = 6
	flame_mesh.rings = 3
	flame.mesh = flame_mesh
	flame.position.y = 0.43
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flame_material := StandardMaterial3D.new()
	flame_material.albedo_color = Color("#ff9b3d")
	flame_material.emission_enabled = true
	flame_material.emission = Color("#ff5c18")
	flame_material.emission_energy_multiplier = 2.6
	flame.material_override = flame_material
	add_child(flame)

	torch_light = OmniLight3D.new()
	torch_light.position.y = 0.43
	torch_light.light_color = Color("#ff9a52")
	torch_light.light_energy = BASE_ENERGY
	torch_light.omni_range = LIGHT_RANGE
	torch_light.omni_attenuation = LIGHT_ATTENUATION
	torch_light.shadow_enabled = true
	torch_light.shadow_bias = 0.08
	torch_light.shadow_normal_bias = 1.1
	torch_light.shadow_opacity = SHADOW_OPACITY
	torch_light.shadow_blur = SHADOW_BLUR
	add_child(torch_light)


func _process(delta: float) -> void:
	flicker_time += delta
	var slow_wave := sin(flicker_time * 7.3 + flicker_phase) * 0.07
	var fast_wave := sin(flicker_time * 17.1 + flicker_phase * 1.7) * 0.035
	var flicker := 0.92 + slow_wave + fast_wave
	torch_light.light_energy = BASE_ENERGY * flicker
	flame.scale = Vector3(0.94, 1.0 + fast_wave * 2.2, 0.94)


func break_apart() -> void:
	queue_free()
