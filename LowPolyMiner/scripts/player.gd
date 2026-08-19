class_name MinerPlayer
extends CharacterBody3D

signal selected_slot_changed(slot: int)
signal inventory_toggled(is_open: bool)
signal cheat_menu_toggled(is_open: bool)
signal torch_placement_requested(surface_position: Vector3, surface_normal: Vector3)
signal dynamite_throw_requested(origin: Vector3, velocity: Vector3, fuse_left: float)
signal dynamite_spent_requested()
signal status_message_requested(text: String)
signal dynamite_state_changed()
signal admin_break_requested(block: MineableBlock)
signal admin_paint_menu_requested(block: MineableBlock)

const SPEED := 6.0
const JUMP_VELOCITY := 5.2
const MOUSE_SENSITIVITY := 0.0022
const REACH := 6.0
const MIN_MINE_INTERVAL := 0.05
const HELD_TORCH_BASE_ENERGY := PlacedTorch.BASE_ENERGY * 0.5
const BODY_RADIUS := 0.42
const BODY_HEIGHT := 1.8
const BODY_CENTER_Y := 0.9
const CAMERA_HEIGHT := 1.62
const LEDGE_CHECK_DISTANCE := 1.15
const LEDGE_MIN_HEIGHT := 1.55
const LEDGE_MAX_HEIGHT := 2.20
const LEDGE_LANDING_INSET := 0.66
const LEDGE_WALL_GAP := 0.08
const LEDGE_HANG_DROP := 0.62
const LEDGE_LANDING_GAP := 0.055
const LEDGE_CLIMB_DURATION := 0.76
const LEDGE_GRAB_PHASE := 0.28
const LEDGE_BRACE_PHASE := 0.42
const LEDGE_LIFT_PHASE := 0.82
const LEDGE_ATTEMPT_WINDOW := 0.28
const LEDGE_ATTEMPT_DELAY := 0.08
const HAMMER_SWING_DURATION := 0.36
const HAMMER_RAISE_END := 0.38
const HAMMER_STRIKE_END := 0.86
const HAMMER_SCENE := "res://assets/models/FieldHammer.glb"
const TABLET_SCENE := "res://assets/models/FieldTablet.glb"
const DYNAMITE_SCENE := "res://assets/models/FieldDynamite.glb"
const HAMMER_FACE_ROT := Vector3(-24, 90, -16)
const HAMMER_RAISE_ROT := Vector3(48, 10, 16)
const HAMMER_STRIKE_ROT := Vector3(-58, -4, -22)
const HAMMER_RAISE_POS := Vector3(0.05, 0.18, 0.08)
const HAMMER_STRIKE_POS := Vector3(-0.18, -0.08, -0.30)
const DYNAMITE_FUSE_TIME := 6.0
const DYNAMITE_MAX_CHARGE := 5.0
const DYNAMITE_STRENGTH_PER_SEC := 5.0
const DYNAMITE_BASE_SPEED := 3.6
const DYNAMITE_SPEED_PER_STRENGTH := 0.42
const DYNAMITE_LOFT := 0.22

var body_collision: CollisionShape3D
var camera: Camera3D
var hammer_arm: Node3D
var hammer: Node3D
var held_tablet: Node3D
var held_dynamite: Node3D
var held_torch: Node3D
var held_torch_light: OmniLight3D
var held_torch_flame: MeshInstance3D
var empty_hand: Node3D
var hammer_rest := Vector3(0.50, -0.36, -0.58)
var tablet_rest := Vector3(0.26, -0.18, -0.46)
var tablet_rest_rot := Vector3(-22, 12, -6)
var dynamite_rest := Vector3(0.56, -0.50, -0.86)
var dynamite_rest_rot := Vector3(-18, 10, -14)
# Same hand, raised and pulled toward the shoulder. Yaw stays near rest so
# the stick does not twist end-on.
var dynamite_windup_pos := Vector3(0.50, -0.28, -0.60)
var dynamite_windup_rot := Vector3(-42, 10, -20)
var dynamite_lit := false
var dynamite_fuse_left := 0.0
var dynamite_charging := false
var dynamite_charge_time := 0.0
var dynamite_spark: MeshInstance3D
var dynamite_spark_light: OmniLight3D
var dynamite_spark_time := 0.0
var swing_time := 0.0
var mine_cooldown := 0.0
var bob_time := 0.0
var held_torch_flicker_time := 0.0
var wood_material: StandardMaterial3D
var metal_material: StandardMaterial3D
var selected_slot := 0
var selected_item_id := "hammer"
var inventory_open := false
var cheat_menu_open := false
var admin_mode := false
var ledge_climbing := false
var ledge_attempt_time := 0.0
var ledge_attempt_elapsed := 0.0
var ledge_takeoff_y := 0.0
var ledge_climb_time := 0.0
var ledge_climb_start := Vector3.ZERO
var ledge_climb_hang := Vector3.ZERO
var ledge_climb_lift := Vector3.ZERO
var ledge_climb_target := Vector3.ZERO


func setup(wood: StandardMaterial3D, metal: StandardMaterial3D) -> void:
	wood_material = wood
	metal_material = metal

	body_collision = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = BODY_RADIUS
	capsule.height = BODY_HEIGHT
	body_collision.shape = capsule
	body_collision.position.y = BODY_CENTER_Y
	add_child(body_collision)

	camera = Camera3D.new()
	camera.position.y = CAMERA_HEIGHT
	camera.near = 0.04
	camera.current = true
	add_child(camera)

	hammer_arm = Node3D.new()
	hammer_arm.name = "HammerArm"
	hammer_arm.position = hammer_rest
	camera.add_child(hammer_arm)
	hammer = _create_held_prop(
		HAMMER_SCENE,
		1.9,
		Vector3.ZERO,
		Vector3(0.02, -0.16, 0.02),
		Vector3.ZERO,
		HAMMER_FACE_ROT,
		hammer_arm
	)
	held_tablet = _create_held_prop(
		TABLET_SCENE,
		1.35,
		Vector3(0, 0, 0),
		Vector3(0.0, -0.10, 0.02),
		tablet_rest,
		tablet_rest_rot
	)
	held_dynamite = _create_held_prop(
		DYNAMITE_SCENE,
		2.15,
		Vector3(10, 18, 8),
		Vector3(0.0, -0.06, 0.0),
		dynamite_rest,
		dynamite_rest_rot
	)
	_create_held_dynamite_fuse()
	_create_held_torch()
	_create_empty_hand()
	_update_held_item()

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	# Once the ledge is caught, the staged pull-up commits until the player has
	# safely settled. Modal menus still cancel it cleanly.
	if ledge_climbing:
		if event.is_action_pressed("cheat_menu"):
			_cancel_ledge_climb()
			_set_cheat_menu_open(true)
		elif event.is_action_pressed("inventory"):
			_cancel_ledge_climb()
			_set_inventory_open(true)
		return
	if event.is_action_pressed("cheat_menu"):
		_cancel_dynamite_charge()
		_set_cheat_menu_open(not cheat_menu_open)
		return
	if event.is_action_pressed("inventory"):
		_cancel_dynamite_charge()
		_set_inventory_open(not inventory_open)
		return
	for slot in range(4):
		if event.is_action_pressed("slot_%d" % (slot + 1)):
			_select_slot(slot)
			return
	if event.is_action_pressed("ui_cancel"):
		if cheat_menu_open:
			_set_cheat_menu_open(false)
		elif inventory_open:
			_set_inventory_open(false)
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if inventory_open or cheat_menu_open:
		_cancel_dynamite_charge()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x - event.relative.y * MOUSE_SENSITIVITY, -1.45, 1.45)
	elif event is InputEventMouseButton:
		if event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if selected_item_id == "dynamite" and not admin_mode:
					_begin_dynamite_charge()
				else:
					_try_primary_action()
			elif dynamite_charging:
				_release_dynamite_throw()
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			if admin_mode:
				_try_admin_paint_menu()
			elif selected_item_id == "torch":
				_try_place_torch()
			elif selected_item_id == "dynamite":
				_light_dynamite()


func _physics_process(delta: float) -> void:
	mine_cooldown = maxf(0.0, mine_cooldown - delta)
	_tick_dynamite(delta)
	if ledge_climbing:
		_cancel_dynamite_charge()
		_process_ledge_climb(delta)
		_update_held_props(delta, 0.0)
		return

	if not is_on_floor():
		velocity += get_gravity() * delta
	var controls_locked := inventory_open or cheat_menu_open
	var input_dir := Vector2.ZERO if controls_locked else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if controls_locked:
		ledge_attempt_time = 0.0
		ledge_attempt_elapsed = 0.0
	elif Input.is_action_just_pressed("jump") and is_on_floor():
		ledge_takeoff_y = global_position.y
		velocity.y = JUMP_VELOCITY
		ledge_attempt_time = LEDGE_ATTEMPT_WINDOW
		ledge_attempt_elapsed = 0.0
	elif ledge_attempt_time > 0.0:
		# Releasing Space makes this jump permanently ordinary. Since assist setup
		# only happens on the grounded just-pressed frame, pressing again in midair
		# cannot accidentally re-arm the climb.
		if not Input.is_action_pressed("jump"):
			ledge_attempt_time = 0.0
			ledge_attempt_elapsed = 0.0
		else:
			ledge_attempt_time = maxf(0.0, ledge_attempt_time - delta)
			ledge_attempt_elapsed += delta
			if (
				ledge_attempt_elapsed >= LEDGE_ATTEMPT_DELAY
				and velocity.y > 0.0
				and not direction.is_zero_approx()
				and _try_start_ledge_climb(direction, ledge_takeoff_y)
			):
				_process_ledge_climb(delta)
				_update_held_props(delta, 0.0)
				return

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
		bob_time += delta * 10.0
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED * 7.0 * delta)
		velocity.z = move_toward(velocity.z, 0, SPEED * 7.0 * delta)
		bob_time += delta * 3.0
	move_and_slide()
	_update_held_props(delta, input_dir.length())


func _try_start_ledge_climb(move_direction: Vector3, reference_y: float) -> bool:
	var ledge := _find_ledge_climb(move_direction, reference_y)
	if ledge.is_empty():
		return false
	ledge_climbing = true
	ledge_attempt_time = 0.0
	ledge_attempt_elapsed = 0.0
	ledge_climb_time = 0.0
	ledge_climb_start = global_position
	ledge_climb_hang = ledge.hang
	ledge_climb_lift = ledge.lift
	ledge_climb_target = ledge.target
	velocity = Vector3.ZERO
	return true


func _find_ledge_climb(move_direction: Vector3, reference_y: float) -> Dictionary:
	var horizontal := Vector3(move_direction.x, 0.0, move_direction.z).normalized()
	if horizontal.is_zero_approx():
		return {}
	var space := get_world_3d().direct_space_state
	var wall_from := global_position + Vector3.UP * 0.82
	var wall_query := PhysicsRayQueryParameters3D.create(
		wall_from,
		wall_from + horizontal * LEDGE_CHECK_DISTANCE,
		collision_mask,
		[get_rid()]
	)
	wall_query.collide_with_areas = false
	var wall_hit := space.intersect_ray(wall_query)
	if wall_hit.is_empty():
		return {}
	if not wall_hit.collider is StaticBody3D or wall_hit.collider is PlacedTorch:
		return {}
	var wall_normal: Vector3 = wall_hit.normal
	if absf(wall_normal.y) > 0.20 or horizontal.dot(-wall_normal) < 0.55:
		return {}

	var landing_xz: Vector3 = wall_hit.position - wall_normal * LEDGE_LANDING_INSET
	var top_from := Vector3(
		landing_xz.x,
		reference_y + LEDGE_MAX_HEIGHT + 0.45,
		landing_xz.z
	)
	var top_to := Vector3(
		landing_xz.x,
		reference_y + LEDGE_MIN_HEIGHT - 0.25,
		landing_xz.z
	)
	var top_query := PhysicsRayQueryParameters3D.create(
		top_from,
		top_to,
		collision_mask,
		[get_rid()]
	)
	top_query.collide_with_areas = false
	top_query.hit_from_inside = true
	var top_hit := space.intersect_ray(top_query)
	if top_hit.is_empty() or Vector3(top_hit.normal).y < 0.75:
		return {}
	var ledge_height: float = top_hit.position.y - reference_y
	if ledge_height < LEDGE_MIN_HEIGHT or ledge_height > LEDGE_MAX_HEIGHT:
		return {}
	var tangent := Vector3(-wall_normal.z, 0.0, wall_normal.x).normalized()
	for side in [-BODY_RADIUS * 0.72, BODY_RADIUS * 0.72]:
		var support_offset: Vector3 = tangent * side
		var support_query := PhysicsRayQueryParameters3D.create(
			top_from + support_offset,
			top_to + support_offset,
			collision_mask,
			[get_rid()]
		)
		support_query.collide_with_areas = false
		support_query.hit_from_inside = true
		var support_hit := space.intersect_ray(support_query)
		if (
			support_hit.is_empty()
			or Vector3(support_hit.normal).y < 0.75
			or absf(support_hit.position.y - top_hit.position.y) > 0.12
		):
			return {}

	var target_root := Vector3(landing_xz.x, top_hit.position.y + LEDGE_LANDING_GAP, landing_xz.z)
	var outside_xz: Vector3 = wall_hit.position + wall_normal * (BODY_RADIUS + LEDGE_WALL_GAP)
	var hang_root := Vector3(outside_xz.x, top_hit.position.y - LEDGE_HANG_DROP, outside_xz.z)
	var lift_root := Vector3(outside_xz.x, target_root.y, outside_xz.z)
	if not _body_fits_at(hang_root) or not _body_fits_at(lift_root) or not _body_fits_at(target_root):
		return {}
	return {"hang": hang_root, "lift": lift_root, "target": target_root}


func _body_fits_at(root_position: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = body_collision.shape
	query.transform = Transform3D(Basis.IDENTITY, root_position + Vector3.UP * BODY_CENTER_Y)
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _process_ledge_climb(delta: float) -> void:
	ledge_climb_time = minf(ledge_climb_time + delta, LEDGE_CLIMB_DURATION)
	var progress := ledge_climb_time / LEDGE_CLIMB_DURATION
	var next_position := ledge_climb_target
	if progress < LEDGE_GRAB_PHASE:
		var phase := smoothstep(0.0, 1.0, progress / LEDGE_GRAB_PHASE)
		next_position = ledge_climb_start.lerp(ledge_climb_hang, phase)
		next_position.y += sin(phase * PI) * 0.06
	elif progress < LEDGE_BRACE_PHASE:
		var phase := (progress - LEDGE_GRAB_PHASE) / (LEDGE_BRACE_PHASE - LEDGE_GRAB_PHASE)
		next_position = ledge_climb_hang - Vector3.UP * sin(phase * PI) * 0.025
	elif progress < LEDGE_LIFT_PHASE:
		var phase := smoothstep(0.0, 1.0, (progress - LEDGE_BRACE_PHASE) / (LEDGE_LIFT_PHASE - LEDGE_BRACE_PHASE))
		next_position = ledge_climb_hang.lerp(ledge_climb_lift, phase)
	else:
		var phase := smoothstep(0.0, 1.0, (progress - LEDGE_LIFT_PHASE) / (1.0 - LEDGE_LIFT_PHASE))
		next_position = ledge_climb_lift.lerp(ledge_climb_target, phase)

	var collision := move_and_collide(next_position - global_position)
	if collision != null:
		_cancel_ledge_climb()
		return
	var effort_envelope := sin(progress * PI)
	var pull_progress := clampf(
		(progress - LEDGE_BRACE_PHASE) / (LEDGE_LIFT_PHASE - LEDGE_BRACE_PHASE),
		0.0,
		1.0
	)
	var effort_tug := sin(pull_progress * TAU * 2.0) * sin(pull_progress * PI)
	var side_bob := sin(progress * TAU) * effort_envelope
	camera.position = Vector3(
		side_bob * 0.018,
		CAMERA_HEIGHT - effort_envelope * 0.14 + effort_tug * 0.028,
		-effort_envelope * 0.085
	)
	camera.rotation.z = side_bob * deg_to_rad(1.1)
	if ledge_climb_time >= LEDGE_CLIMB_DURATION:
		_finish_ledge_climb()


func _finish_ledge_climb() -> void:
	ledge_climbing = false
	ledge_attempt_time = 0.0
	ledge_attempt_elapsed = 0.0
	ledge_climb_time = 0.0
	velocity = Vector3.ZERO
	camera.position = Vector3(0.0, CAMERA_HEIGHT, 0.0)
	camera.rotation.z = 0.0
	apply_floor_snap()


func _cancel_ledge_climb() -> void:
	ledge_climbing = false
	ledge_attempt_time = 0.0
	ledge_attempt_elapsed = 0.0
	ledge_climb_time = 0.0
	velocity = Vector3.ZERO
	camera.position = Vector3(0.0, CAMERA_HEIGHT, 0.0)
	camera.rotation.z = 0.0


func _try_admin_paint_menu() -> void:
	var result := _aim_ray()
	if result and result.collider is MineableBlock:
		admin_paint_menu_requested.emit(result.collider)


func _try_primary_action() -> void:
	if mine_cooldown > 0.0:
		return
	var result := _aim_ray()
	if admin_mode:
		if result and result.collider is MineableBlock:
			mine_cooldown = MIN_MINE_INTERVAL
			swing_time = HAMMER_SWING_DURATION
			admin_break_requested.emit(result.collider)
		return
	if result and result.collider is PlacedTorch:
		mine_cooldown = MIN_MINE_INTERVAL
		var placed_torch: PlacedTorch = result.collider
		placed_torch.break_apart()
		return
	if selected_item_id != "hammer":
		return
	# This only caps impossible event spam. Normal and very fast human clicking
	# is not slowed by the hammer animation or the block's visual transition.
	mine_cooldown = MIN_MINE_INTERVAL
	swing_time = HAMMER_SWING_DURATION
	if result and result.collider is MineableBlock:
		var block: MineableBlock = result.collider
		block.hit(1)


func _try_place_torch() -> void:
	if mine_cooldown > 0.0:
		return
	mine_cooldown = MIN_MINE_INTERVAL
	var result := _aim_ray()
	if result and result.collider is StaticBody3D and not result.collider is PlacedTorch:
		torch_placement_requested.emit(result.position, result.normal)


func _aim_ray() -> Dictionary:
	var from := camera.global_position
	var forward := -camera.global_basis.z
	# Start past the first-person mesh so a held tool cannot eat the click.
	var query := PhysicsRayQueryParameters3D.create(from + forward * 0.55, from + forward * REACH)
	query.exclude = [self]
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(query)


func _update_held_props(delta: float, movement_amount: float) -> void:
	_update_hammer(delta, movement_amount)
	_update_idle_held(held_tablet, tablet_rest, tablet_rest_rot, "tablet", delta, movement_amount)
	_update_dynamite_held(delta, movement_amount)
	_update_torch_bob(delta, movement_amount)
	_update_empty_hand_bob(delta, movement_amount)


func _update_hammer(delta: float, movement_amount: float) -> void:
	if selected_item_id != "hammer":
		return
	var bob := _held_bob(movement_amount)
	if swing_time > 0.0:
		swing_time = maxf(0.0, swing_time - delta)
		var progress := 1.0 - swing_time / HAMMER_SWING_DURATION
		var rot := Vector3.ZERO
		var pos := hammer_rest
		# The mesh keeps its facing on a child node. This arm swings in camera
		# space so the strike still chops toward the crosshair.
		if progress < HAMMER_RAISE_END:
			var t := progress / HAMMER_RAISE_END
			var ease := 1.0 - (1.0 - t) * (1.0 - t)
			rot = HAMMER_RAISE_ROT * ease
			pos = hammer_rest + HAMMER_RAISE_POS * ease
		elif progress < HAMMER_STRIKE_END:
			var t := (progress - HAMMER_RAISE_END) / (HAMMER_STRIKE_END - HAMMER_RAISE_END)
			var smash := t * t * t
			rot = HAMMER_RAISE_ROT.lerp(HAMMER_STRIKE_ROT, smash)
			pos = (hammer_rest + HAMMER_RAISE_POS).lerp(hammer_rest + HAMMER_STRIKE_POS, smash)
		else:
			var t := (progress - HAMMER_STRIKE_END) / (1.0 - HAMMER_STRIKE_END)
			rot = HAMMER_STRIKE_ROT.lerp(Vector3.ZERO, t * 0.35)
			pos = (hammer_rest + HAMMER_STRIKE_POS).lerp(hammer_rest, t * 0.25)
		hammer_arm.rotation_degrees = rot
		hammer_arm.position = pos + bob
	else:
		hammer_arm.rotation_degrees = hammer_arm.rotation_degrees.lerp(Vector3.ZERO, delta * 10.0)
		hammer_arm.position = hammer_arm.position.lerp(hammer_rest + bob, delta * 10.0)


func _update_dynamite_held(delta: float, movement_amount: float) -> void:
	if selected_item_id != "dynamite":
		return
	var bob := _held_bob(movement_amount)
	var charge := 0.0
	if dynamite_charging:
		var raw := clampf(dynamite_charge_time / DYNAMITE_MAX_CHARGE, 0.0, 1.0)
		charge = raw * raw * (3.0 - 2.0 * raw)
	var target_pos := dynamite_rest.lerp(dynamite_windup_pos, charge)
	var target_rot := dynamite_rest_rot.lerp(dynamite_windup_rot, charge)
	var follow := 22.0 if dynamite_charging else 14.0
	held_dynamite.position = held_dynamite.position.lerp(target_pos + bob, delta * follow)
	held_dynamite.rotation_degrees = held_dynamite.rotation_degrees.lerp(target_rot, delta * follow)


func _light_dynamite() -> void:
	if selected_item_id != "dynamite":
		return
	if dynamite_lit:
		return
	dynamite_lit = true
	dynamite_fuse_left = DYNAMITE_FUSE_TIME
	_update_dynamite_spark()
	status_message_requested.emit("FUSE LIT")
	dynamite_state_changed.emit()


func _begin_dynamite_charge() -> void:
	if selected_item_id != "dynamite" or admin_mode:
		return
	if not dynamite_lit:
		status_message_requested.emit("LIGHT IT FIRST")
		return
	dynamite_charging = true
	dynamite_charge_time = 0.0
	dynamite_state_changed.emit()


func _release_dynamite_throw() -> void:
	if not dynamite_charging:
		return
	dynamite_charging = false
	if selected_item_id != "dynamite" or not dynamite_lit:
		dynamite_charge_time = 0.0
		dynamite_state_changed.emit()
		return
	var strength := dynamite_charge_time * DYNAMITE_STRENGTH_PER_SEC
	var speed := DYNAMITE_BASE_SPEED + strength * DYNAMITE_SPEED_PER_STRENGTH
	var look := -camera.global_basis.z
	var throw_dir := (look + Vector3.UP * DYNAMITE_LOFT).normalized()
	var origin := _dynamite_throw_origin(look)
	var throw_velocity := throw_dir * speed
	throw_velocity += Vector3(velocity.x, 0.0, velocity.z) * 0.35
	var fuse := dynamite_fuse_left
	clear_dynamite_state()
	dynamite_throw_requested.emit(origin, throw_velocity, fuse)


func _dynamite_throw_origin(look: Vector3) -> Vector3:
	var desired := (
		camera.global_position
		+ look * 0.50
		+ camera.global_basis.x * 0.20
		- camera.global_basis.y * 0.16
	)
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		camera.global_position + look * 0.35,
		desired
	)
	query.exclude = [self]
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit:
		return hit.position - look * 0.16
	return desired


func _tick_dynamite(delta: float) -> void:
	if dynamite_charging:
		if selected_item_id != "dynamite" or not dynamite_lit:
			_cancel_dynamite_charge()
		else:
			dynamite_charge_time = minf(dynamite_charge_time + delta, DYNAMITE_MAX_CHARGE)
	if dynamite_lit:
		dynamite_fuse_left = maxf(0.0, dynamite_fuse_left - delta)
		dynamite_spark_time += delta
		_update_dynamite_spark()
		if dynamite_fuse_left <= 0.0:
			_cancel_dynamite_charge()
			clear_dynamite_state()
			# Blast comes later. The held stick just burns away.
			dynamite_spent_requested.emit()
			status_message_requested.emit("FUSE BURNED OUT")
			return
	if dynamite_charging:
		dynamite_state_changed.emit()


func _cancel_dynamite_charge() -> void:
	if not dynamite_charging:
		return
	dynamite_charging = false
	dynamite_charge_time = 0.0
	dynamite_state_changed.emit()


func clear_dynamite_state() -> void:
	dynamite_lit = false
	dynamite_fuse_left = 0.0
	dynamite_charging = false
	dynamite_charge_time = 0.0
	_update_dynamite_spark()
	dynamite_state_changed.emit()


func get_dynamite_action_hint() -> String:
	if dynamite_charging:
		var strength := dynamite_charge_time * DYNAMITE_STRENGTH_PER_SEC
		return "THROW  %.1fs  STR %d" % [dynamite_charge_time, int(round(strength))]
	if dynamite_lit:
		return "LIT  %.1fs    HOLD LEFT  THROW" % dynamite_fuse_left
	return "RIGHT CLICK  LIGHT    HOLD LEFT  THROW"


func _create_held_dynamite_fuse() -> void:
	dynamite_spark = MeshInstance3D.new()
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.018
	spark_mesh.height = 0.036
	spark_mesh.radial_segments = 6
	spark_mesh.rings = 3
	dynamite_spark.mesh = spark_mesh
	dynamite_spark.position = Vector3(0.0, 0.48, 0.0)
	dynamite_spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color("#ffb14a")
	dynamite_spark.material_override = spark_mat
	dynamite_spark.visible = false
	held_dynamite.add_child(dynamite_spark)
	dynamite_spark_light = OmniLight3D.new()
	dynamite_spark_light.position = Vector3(0.0, 0.48, 0.0)
	dynamite_spark_light.light_color = Color("#ff9a3a")
	dynamite_spark_light.light_energy = 0.18
	dynamite_spark_light.omni_range = 1.2
	dynamite_spark_light.omni_attenuation = 1.8
	dynamite_spark_light.shadow_enabled = false
	dynamite_spark_light.visible = false
	held_dynamite.add_child(dynamite_spark_light)


func _update_dynamite_spark() -> void:
	var show := dynamite_lit and selected_item_id == "dynamite"
	if dynamite_spark != null:
		dynamite_spark.visible = show
		if show:
			var flicker := 0.75 + sin(dynamite_spark_time * 28.0) * 0.18
			dynamite_spark.scale = Vector3.ONE * (0.85 + flicker * 0.25)
	if dynamite_spark_light != null:
		dynamite_spark_light.visible = show
		if show:
			dynamite_spark_light.light_energy = 0.18 * (0.75 + sin(dynamite_spark_time * 28.0) * 0.18)


func _update_idle_held(
	node: Node3D,
	rest: Vector3,
	rest_rot: Vector3,
	item_id: String,
	delta: float,
	movement_amount: float
) -> void:
	if selected_item_id != item_id:
		return
	var bob := _held_bob(movement_amount)
	node.position = node.position.lerp(rest + bob, delta * 12.0)
	node.rotation_degrees = node.rotation_degrees.lerp(rest_rot, delta * 14.0)


func _held_bob(movement_amount: float) -> Vector3:
	return Vector3(sin(bob_time) * 0.012, abs(cos(bob_time)) * 0.012, 0) * movement_amount


func _update_torch_bob(delta: float, movement_amount: float) -> void:
	if selected_item_id != "torch":
		return
	var target := Vector3(0.58, -0.48, -0.92)
	var bob := _held_bob(movement_amount)
	held_torch.position = held_torch.position.lerp(target + bob, delta * 12.0)
	held_torch_flicker_time += delta
	var slow_wave := sin(held_torch_flicker_time * 7.3) * 0.07
	var fast_wave := sin(held_torch_flicker_time * 17.1 + 1.4) * 0.035
	var flicker := 0.92 + slow_wave + fast_wave
	held_torch_light.light_energy = HELD_TORCH_BASE_ENERGY * flicker
	held_torch_flame.scale = Vector3(0.94, 1.0 + fast_wave * 2.2, 0.94)


func _update_empty_hand_bob(delta: float, movement_amount: float) -> void:
	if not selected_item_id.is_empty():
		return
	var target := Vector3(0.56, -0.55, -0.82)
	var bob := _held_bob(movement_amount)
	empty_hand.position = empty_hand.position.lerp(target + bob, delta * 12.0)


func _select_slot(slot: int) -> void:
	selected_slot = clampi(slot, 0, 3)
	selected_slot_changed.emit(selected_slot)


func set_selected_item(item_id: String) -> void:
	if item_id != "dynamite":
		_cancel_dynamite_charge()
	selected_item_id = item_id
	_update_held_item()
	_update_dynamite_spark()


func _set_inventory_open(is_open: bool) -> void:
	if is_open and cheat_menu_open:
		cheat_menu_open = false
		cheat_menu_toggled.emit(false)
	inventory_open = is_open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if inventory_open else Input.MOUSE_MODE_CAPTURED
	inventory_toggled.emit(inventory_open)


func _set_cheat_menu_open(is_open: bool) -> void:
	if is_open and inventory_open:
		inventory_open = false
		inventory_toggled.emit(false)
	cheat_menu_open = is_open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if cheat_menu_open else Input.MOUSE_MODE_CAPTURED
	cheat_menu_toggled.emit(cheat_menu_open)


func _update_held_item() -> void:
	hammer_arm.visible = selected_item_id == "hammer"
	held_tablet.visible = selected_item_id == "tablet"
	held_dynamite.visible = selected_item_id == "dynamite"
	held_torch.visible = selected_item_id == "torch"
	empty_hand.visible = selected_item_id.is_empty()


func _create_held_prop(
	scene_path: String,
	visual_scale: float,
	visual_rotation_deg: Vector3,
	visual_offset: Vector3,
	rest: Vector3,
	rest_rot: Vector3,
	parent: Node3D = null
) -> Node3D:
	var prop = load("res://scripts/held_prop.gd").new()
	prop.setup(scene_path, visual_scale, visual_rotation_deg, visual_offset)
	prop.position = rest
	prop.rotation_degrees = rest_rot
	(parent if parent != null else camera).add_child(prop)
	return prop


func _create_held_torch() -> void:
	held_torch = Node3D.new()
	held_torch.position = Vector3(0.58, -0.48, -0.92)
	held_torch.rotation_degrees = Vector3(-12, 0, -18)
	camera.add_child(held_torch)
	var shaft := MeshInstance3D.new()
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.055
	shaft_mesh.bottom_radius = 0.07
	shaft_mesh.height = 0.72
	shaft_mesh.radial_segments = 6
	shaft.mesh = shaft_mesh
	var held_wood: StandardMaterial3D = wood_material.duplicate()
	held_wood.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shaft.material_override = held_wood
	held_torch.add_child(shaft)
	held_torch_flame = MeshInstance3D.new()
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.10
	flame_mesh.height = 0.20
	flame_mesh.radial_segments = 6
	flame_mesh.rings = 3
	held_torch_flame.mesh = flame_mesh
	held_torch_flame.position.y = 0.45
	held_torch_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flame_material := StandardMaterial3D.new()
	flame_material.albedo_color = Color("#ff9b3d")
	flame_material.emission_enabled = true
	flame_material.emission = Color("#ff6b21")
	flame_material.emission_energy_multiplier = 2.0
	held_torch_flame.material_override = flame_material
	held_torch.add_child(held_torch_flame)

	held_torch_light = OmniLight3D.new()
	held_torch_light.position.y = 0.45
	held_torch_light.light_color = Color("#ff9a52")
	held_torch_light.light_energy = HELD_TORCH_BASE_ENERGY
	held_torch_light.omni_range = PlacedTorch.LIGHT_RANGE
	held_torch_light.omni_attenuation = PlacedTorch.LIGHT_ATTENUATION
	held_torch_light.shadow_enabled = true
	held_torch_light.shadow_bias = 0.08
	held_torch_light.shadow_normal_bias = 1.1
	held_torch_light.shadow_opacity = PlacedTorch.SHADOW_OPACITY
	held_torch_light.shadow_blur = PlacedTorch.SHADOW_BLUR
	held_torch.add_child(held_torch_light)


func _create_empty_hand() -> void:
	empty_hand = Node3D.new()
	empty_hand.position = Vector3(0.56, -0.55, -0.82)
	empty_hand.rotation_degrees = Vector3(-18, -8, -12)
	camera.add_child(empty_hand)
	var hand_material := StandardMaterial3D.new()
	hand_material.albedo_color = Color("#b97955")
	hand_material.roughness = 0.92
	hand_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var palm := MeshInstance3D.new()
	var palm_mesh := BoxMesh.new()
	palm_mesh.size = Vector3(0.22, 0.28, 0.12)
	palm.mesh = palm_mesh
	palm.material_override = hand_material
	empty_hand.add_child(palm)
	var fingers := MeshInstance3D.new()
	var fingers_mesh := BoxMesh.new()
	fingers_mesh.size = Vector3(0.20, 0.15, 0.105)
	fingers.mesh = fingers_mesh
	fingers.position.y = 0.20
	fingers.material_override = hand_material
	empty_hand.add_child(fingers)
	var thumb := MeshInstance3D.new()
	var thumb_mesh := BoxMesh.new()
	thumb_mesh.size = Vector3(0.08, 0.18, 0.10)
	thumb.mesh = thumb_mesh
	thumb.position = Vector3(-0.13, 0.0, 0.0)
	thumb.rotation_degrees.z = 28.0
	thumb.material_override = hand_material
	empty_hand.add_child(thumb)
