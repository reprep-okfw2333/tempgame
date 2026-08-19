extends Node3D

func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(960, 540))
	get_tree().create_timer(4.0).timeout.connect(func() -> void: get_tree().quit())
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#8a8a8a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#c8c2b8")
	environment.ambient_light_energy = 0.7
	env.environment = environment
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)

	var camera := Camera3D.new()
	camera.current = true
	add_child(camera)

	var hammer: Node3D = _make_prop(
		"res://assets/models/FieldHammer.glb",
		1.9,
		Vector3.ZERO,
		Vector3(0.02, -0.16, 0.02),
		Vector3(0.50, -0.36, -0.58),
		Vector3(-24, 90, -16)
	)
	var tablet: Node3D = _make_prop(
		"res://assets/models/FieldTablet.glb",
		1.35,
		Vector3.ZERO,
		Vector3(0.0, -0.10, 0.02),
		Vector3(0.26, -0.18, -0.46),
		Vector3(-22, 12, -6)
	)
	var dynamite: Node3D = _make_prop(
		"res://assets/models/FieldDynamite.glb",
		2.15,
		Vector3(10, 18, 8),
		Vector3(0.0, -0.06, 0.0),
		Vector3(0.56, -0.50, -0.86),
		Vector3(-18, 10, -14)
	)
	add_child(hammer)
	add_child(tablet)
	add_child(dynamite)

	await _shot(hammer, tablet, dynamite, "res://tests/pickaxe_fps.png")
	hammer.visible = true
	hammer.position = Vector3.ZERO
	hammer.rotation_degrees = Vector3(-8, 40, 12)
	tablet.visible = false
	dynamite.visible = false
	camera.position = Vector3(0.55, 0.18, 1.15)
	camera.look_at(Vector3(0.0, 0.18, 0.0))
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/pickaxe_preview.png")
	get_tree().quit()


func _make_prop(
	scene_path: String,
	visual_scale: float,
	visual_rotation_deg: Vector3,
	visual_offset: Vector3,
	rest: Vector3,
	rest_rot: Vector3
) -> Node3D:
	var prop = load("res://scripts/held_prop.gd").new()
	prop.setup(scene_path, visual_scale, visual_rotation_deg, visual_offset)
	prop.position = rest
	prop.rotation_degrees = rest_rot
	return prop


func _shot(hammer: Node3D, tablet: Node3D, dynamite: Node3D, path: String) -> void:
	hammer.visible = true
	tablet.visible = false
	dynamite.visible = false
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	tablet.visible = true
	hammer.visible = false
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/tablet_fps.png")
	tablet.visible = false
	dynamite.visible = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/dynamite_fps.png")
