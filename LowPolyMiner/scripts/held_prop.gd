class_name HeldProp
extends Node3D

## First-person wrapper for a field-tool GLB. The player owns camera-space
## rest/swing poses; this node only instances the mesh and applies a local
## visual offset so each prop can be scaled and aimed independently.

var _scene_path := ""
var _visual_scale := Vector3.ONE
var _visual_rotation_deg := Vector3.ZERO
var _visual_offset := Vector3.ZERO


func setup(
	scene_path: String,
	visual_scale: float = 1.0,
	visual_rotation_deg: Vector3 = Vector3.ZERO,
	visual_offset: Vector3 = Vector3.ZERO
) -> void:
	_scene_path = scene_path
	_visual_scale = Vector3.ONE * visual_scale
	_visual_rotation_deg = visual_rotation_deg
	_visual_offset = visual_offset
	if is_inside_tree() and not has_node("Visual"):
		_build()


func _ready() -> void:
	if not _scene_path.is_empty() and not has_node("Visual"):
		_build()


func _build() -> void:
	var packed := load(_scene_path) as PackedScene
	if packed == null:
		push_error("Missing held model: %s" % _scene_path)
		return
	var visual := Node3D.new()
	visual.name = "Visual"
	visual.scale = _visual_scale
	visual.rotation_degrees = _visual_rotation_deg
	visual.position = _visual_offset
	visual.add_child(packed.instantiate())
	add_child(visual)
	_style_meshes(visual)


func _style_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mesh_instance.material_override is BaseMaterial3D:
			_style_material(mesh_instance.material_override)
		for surface in mesh_instance.get_surface_override_material_count():
			var override_material := mesh_instance.get_surface_override_material(surface)
			if override_material is BaseMaterial3D:
				_style_material(override_material)
		var mesh := mesh_instance.mesh
		if mesh != null:
			for surface in mesh.get_surface_count():
				var material := mesh.surface_get_material(surface)
				if material is BaseMaterial3D:
					_style_material(material)
	for child in node.get_children():
		_style_meshes(child)


func _style_material(material: BaseMaterial3D) -> void:
	# The source GLBs are nearest-filtered PS1 atlases. Keep that look in
	# Compatibility so the held tools do not pick up bilinear smear.
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# Unshaded so the atlas reads at authored brightness. Lighting the
	# first-person mesh with extra lights made visible blobs in the cave.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color.WHITE
