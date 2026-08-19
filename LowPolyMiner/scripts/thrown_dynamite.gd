class_name ThrownDynamite
extends RigidBody3D

## Lit stick in the world. Flies and bounces under gravity. Also resolves
## against BlockVolume cells so it cannot ghost through far, collision-less
## mountain faces. The fuse still runs; this object only despawns when it ends.

const MODEL_PATH := "res://assets/models/FieldDynamite.glb"
const VISUAL_SCALE := 2.1
const FUSE_TIP := Vector3(0.0, 0.50, 0.0)
const STICK_RADIUS := 0.055
const STICK_HEIGHT := 0.50

var fuse_left := 6.0
var _volume: Node = null
var _last_free := Vector3.ZERO
var _spark: MeshInstance3D
var _spark_light: OmniLight3D
var _spark_time := 0.0


func setup(
	origin: Vector3,
	linear_vel: Vector3,
	remaining_fuse: float,
	volume: Node = null
) -> void:
	global_position = origin
	_last_free = origin
	_volume = volume
	fuse_left = remaining_fuse
	collision_layer = 2
	collision_mask = 1
	mass = 2.4
	gravity_scale = 1.55
	linear_damp = 0.18
	angular_damp = 1.35
	continuous_cd = true
	can_sleep = true
	var phys := PhysicsMaterial.new()
	phys.bounce = 0.08
	phys.friction = 1.0
	physics_material_override = phys

	var visual: Node3D = load(MODEL_PATH).instantiate()
	visual.scale = Vector3.ONE * VISUAL_SCALE
	add_child(visual)

	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = STICK_RADIUS
	capsule.height = STICK_HEIGHT
	collision.shape = capsule
	add_child(collision)

	_spark = MeshInstance3D.new()
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.024
	spark_mesh.height = 0.048
	spark_mesh.radial_segments = 6
	spark_mesh.rings = 3
	_spark.mesh = spark_mesh
	_spark.position = FUSE_TIP
	_spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color("#ffb14a")
	_spark.material_override = spark_mat
	add_child(_spark)

	_spark_light = OmniLight3D.new()
	_spark_light.position = FUSE_TIP
	_spark_light.light_color = Color("#ff9a3a")
	_spark_light.light_energy = 0.18
	_spark_light.omni_range = 1.4
	_spark_light.omni_attenuation = 1.8
	_spark_light.shadow_enabled = false
	add_child(_spark_light)

	linear_velocity = linear_vel
	angular_velocity = Vector3(
		randf_range(-3.5, 3.5),
		randf_range(-1.8, 1.8),
		randf_range(-3.5, 3.5)
	)


func _physics_process(delta: float) -> void:
	fuse_left -= delta
	_spark_time += delta
	var flicker := 0.75 + sin(_spark_time * 28.0) * 0.18 + sin(_spark_time * 51.0) * 0.07
	if _spark_light != null:
		_spark_light.light_energy = 0.18 * flicker
	if _spark != null:
		_spark.scale = Vector3.ONE * (0.85 + flicker * 0.25)
	_resolve_volume_hit()
	if linear_velocity.length() < 0.35 and absf(linear_velocity.y) < 0.25:
		linear_damp = 2.4
		angular_damp = 4.0
	if fuse_left <= 0.0:
		queue_free()


func _resolve_volume_hit() -> void:
	if _volume == null or not _volume.has_method("type_at"):
		return
	var grid: Vector3i = _volume.world_to_grid(global_position)
	if int(_volume.type_at(grid)) == 0:
		_last_free = global_position
		return
	global_position = _last_free
	var center: Vector3 = _volume.world_position(grid)
	var away := global_position - center
	var normal := away.normalized() if away.length_squared() > 0.0001 else -linear_velocity.normalized()
	if normal.length_squared() < 0.0001:
		normal = Vector3.UP
	linear_velocity = linear_velocity.bounce(normal) * 0.32
	angular_velocity *= 0.45
