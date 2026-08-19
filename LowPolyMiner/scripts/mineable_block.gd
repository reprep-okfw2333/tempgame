class_name MineableBlock
extends StaticBody3D

signal break_requested(block: MineableBlock)

const DAMAGE_BLEND_DURATION := 0.08
const BLOCK_VISUAL_SIZE := 2.02
const BLOCK_COLLISION_SIZE := 2.0
const CRACK_OVERLAY_SIZE := 2.035
const DAMAGE_STATE_STRENGTH := [0.0, 1.0, 0.65, 1.0]
# Cutout, not blend: RetroFog copies the screen before transparent objects and
# then covers the view, so a blended overlay would never appear.
# High enough that dusty mask fill is discarded and only the stroke remains.
const CRACK_ALPHA_SCISSOR := 0.28

static var shared_crack_shader: Shader
static var _pigment_cache: Dictionary = {}

var block_type := "stone"
var grid_pos := Vector3i.ZERO
var health := 10
var max_health := 10
var awaiting_break := false
var mesh_instance: MeshInstance3D
var crack_mesh: MeshInstance3D
var base_material: StandardMaterial3D
var crack_textures: Array
var crack_shader_material: ShaderMaterial
var hit_flash := 0.0
var damage_state := 0
var visual_damage_state := 0
var damage_blend_time := 0.0


func _ready() -> void:
	set_process(false)


func setup(type: String, block_material: StandardMaterial3D, cracks: Array) -> void:
	block_type = type
	base_material = block_material
	crack_textures = cracks
	_set_health_for_type(type)
	max_health = health

	mesh_instance = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * BLOCK_VISUAL_SIZE
	mesh_instance.mesh = box
	mesh_instance.material_override = base_material
	add_child(mesh_instance)

	# Slightly larger than the base cube so the reusable crack filter sits on
	# top of present and future block textures without z-fighting.
	crack_mesh = MeshInstance3D.new()
	var crack_box := BoxMesh.new()
	crack_box.size = Vector3.ONE * CRACK_OVERLAY_SIZE
	crack_mesh.mesh = crack_box
	crack_mesh.visible = false
	crack_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	crack_shader_material = ShaderMaterial.new()
	crack_shader_material.shader = _get_crack_shader()
	crack_shader_material.set_shader_parameter("cracks_77", crack_textures[0])
	crack_shader_material.set_shader_parameter("cracks_33", crack_textures[1])
	crack_shader_material.set_shader_parameter("cracks_01", crack_textures[2])
	crack_shader_material.set_shader_parameter("strength_77", DAMAGE_STATE_STRENGTH[1])
	crack_shader_material.set_shader_parameter("strength_33", DAMAGE_STATE_STRENGTH[2])
	crack_shader_material.set_shader_parameter("strength_01", DAMAGE_STATE_STRENGTH[3])
	crack_shader_material.set_shader_parameter("state_from", 0.0)
	crack_shader_material.set_shader_parameter("state_to", 0.0)
	crack_shader_material.set_shader_parameter("blend_amount", 0.0)
	crack_shader_material.set_shader_parameter("alpha_scissor", CRACK_ALPHA_SCISSOR)
	crack_shader_material.set_shader_parameter("overlay_size", CRACK_OVERLAY_SIZE)
	_bind_crack_pigment()
	crack_mesh.material_override = crack_shader_material
	add_child(crack_mesh)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3.ONE * BLOCK_COLLISION_SIZE
	collision.shape = shape
	add_child(collision)
	# Hundreds of streamed blocks are idle almost all the time. Only opt into
	# per-frame work while a hit response or crack transition is active.
	set_process(false)


func _process(delta: float) -> void:
	if hit_flash > 0.0:
		hit_flash -= delta
		var flash_scale: Vector3 = Vector3.ONE * lerpf(1.0, 0.88, hit_flash / 0.10)
		mesh_instance.scale = flash_scale
		crack_mesh.scale = flash_scale
		if hit_flash <= 0.0:
			mesh_instance.scale = Vector3.ONE
			crack_mesh.scale = Vector3.ONE

	if damage_blend_time > 0.0:
		damage_blend_time = maxf(0.0, damage_blend_time - delta)
		var progress := 1.0 - damage_blend_time / DAMAGE_BLEND_DURATION
		crack_shader_material.set_shader_parameter("blend_amount", smoothstep(0.0, 1.0, progress))
		if damage_blend_time <= 0.0:
			_finish_damage_transition()

	if hit_flash <= 0.0 and damage_blend_time <= 0.0:
		set_process(false)


func hit(damage: int = 1) -> void:
	if awaiting_break:
		return
	set_process(true)
	health -= damage
	hit_flash = 0.10
	if health <= 0:
		# Main owns the inventory and decides whether the block can be stored.
		# Keep the block at its final damage state until that request succeeds.
		health = 1
		awaiting_break = true
		break_requested.emit(self)
	else:
		_update_damage_state()


func apply_type(type: String, block_material: StandardMaterial3D) -> void:
	block_type = type
	base_material = block_material
	if mesh_instance != null:
		mesh_instance.material_override = block_material
	_set_health_for_type(type)
	max_health = health
	awaiting_break = false
	damage_state = 0
	visual_damage_state = 0
	damage_blend_time = 0.0
	hit_flash = 0.0
	set_process(false)
	if mesh_instance != null:
		mesh_instance.scale = Vector3.ONE
	if crack_mesh != null:
		crack_mesh.visible = false
		crack_mesh.scale = Vector3.ONE
	if crack_shader_material != null:
		crack_shader_material.set_shader_parameter("state_from", 0.0)
		crack_shader_material.set_shader_parameter("state_to", 0.0)
		crack_shader_material.set_shader_parameter("blend_amount", 0.0)
		_bind_crack_pigment()


func _bind_crack_pigment() -> void:
	if crack_shader_material == null:
		return
	var pigments := _pigments_for(base_material)
	var body: Color = pigments["body"]
	var vein: Color = pigments["vein"]
	var albedo: Texture2D = pigments["albedo"]
	if albedo == null:
		albedo = _solid_texture(body)
	crack_shader_material.set_shader_parameter("pigment_body", body)
	crack_shader_material.set_shader_parameter("pigment_vein", vein)
	crack_shader_material.set_shader_parameter("block_uv_scale", pigments["uv_scale"])
	crack_shader_material.set_shader_parameter("block_albedo", albedo)


static func _solid_texture(color: Color) -> Texture2D:
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, color)
	return ImageTexture.create_from_image(image)


static func _pigments_for(material: StandardMaterial3D) -> Dictionary:
	var uv_scale := 0.25
	var tex: Texture2D = null
	if material != null:
		uv_scale = material.uv1_scale.x
		tex = material.albedo_texture
	var path := tex.resource_path if tex != null else ""
	if path != "" and _pigment_cache.has(path):
		var cached: Dictionary = (_pigment_cache[path] as Dictionary).duplicate()
		cached["uv_scale"] = uv_scale
		cached["albedo"] = tex
		return cached
	# Measured fallbacks if the imported image cannot be read at runtime.
	var body := Color("#423d32")
	var vein := Color("#3b3527")
	if path.ends_with("coal.png"):
		body = Color("#33302a")
		vein = Color("#332f27")
	elif path.ends_with("copper.png"):
		body = Color("#594334")
		vein = Color("#944016")
	if tex != null:
		var sampled := _sample_pigments(tex)
		if not sampled.is_empty():
			body = sampled["body"]
			vein = sampled["vein"]
	if path != "":
		_pigment_cache[path] = {"body": body, "vein": vein}
	return {
		"body": body,
		"vein": vein,
		"uv_scale": uv_scale,
		"albedo": tex
	}


static func _sample_pigments(tex: Texture2D) -> Dictionary:
	var img := tex.get_image()
	if img == null:
		return {}
	if img.is_compressed():
		img = img.duplicate()
		img.decompress()
	var width := img.get_width()
	var height := img.get_height()
	if width <= 0 or height <= 0:
		return {}
	var step := maxi(1, mini(width, height) / 128)
	var count := 0
	var rgb_sum := Vector3.ZERO
	var sat_sum := 0.0
	var x := 0
	while x < width:
		var y := 0
		while y < height:
			var pixel := img.get_pixel(x, y)
			rgb_sum += Vector3(pixel.r, pixel.g, pixel.b)
			sat_sum += pixel.s
			count += 1
			y += step
		x += step
	if count == 0:
		return {}
	var mean := rgb_sum / float(count)
	var mean_sat := sat_sum / float(count)
	var vein_sum := Vector3.ZERO
	var vein_count := 0
	x = 0
	while x < width:
		var y := 0
		while y < height:
			var pixel := img.get_pixel(x, y)
			if pixel.s > mean_sat * 1.25:
				vein_sum += Vector3(pixel.r, pixel.g, pixel.b)
				vein_count += 1
			y += step
		x += step
	var vein := mean
	if vein_count > 0:
		vein = vein_sum / float(vein_count)
	return {
		"body": Color(mean.x, mean.y, mean.z),
		"vein": Color(vein.x, vein.y, vein.z)
	}


func _set_health_for_type(type: String) -> void:
	if type == "coal":
		health = 20
	elif type == "copper":
		health = 15
	else:
		health = 10


func complete_break() -> void:
	queue_free()


func reject_break() -> void:
	awaiting_break = false


func _update_damage_state() -> void:
	var hits_taken := max_health - health
	var non_breaking_hits := max_health - 1
	# Three visual phases are spread over however many non-breaking hits the
	# block has. roundi() keeps arbitrary durability values aligned cleanly.
	var light_hit := maxi(1, roundi(non_breaking_hits / 3.0))
	var medium_hit := maxi(light_hit + 1, roundi(non_breaking_hits * 2.0 / 3.0))
	var severe_hit := non_breaking_hits
	var new_state := 0
	if hits_taken >= severe_hit:
		new_state = 3 # 1% condition
	elif hits_taken >= medium_hit:
		new_state = 2 # 33% condition
	elif hits_taken >= light_hit:
		new_state = 1 # 77% condition
	_begin_damage_transition(new_state)


func _begin_damage_transition(new_state: int) -> void:
	if new_state == damage_state:
		return
	# Hits can arrive faster than the 0.08-second blend. Resolve the current
	# visual target before beginning the next one so presentation never blocks
	# damage and the cumulative crack history always remains valid.
	if damage_blend_time > 0.0:
		_finish_damage_transition()
	damage_state = new_state
	crack_shader_material.set_shader_parameter("state_from", float(visual_damage_state))
	crack_shader_material.set_shader_parameter("state_to", float(damage_state))
	crack_shader_material.set_shader_parameter("blend_amount", 0.0)
	crack_mesh.visible = visual_damage_state > 0 or damage_state > 0
	damage_blend_time = DAMAGE_BLEND_DURATION


func _finish_damage_transition() -> void:
	visual_damage_state = damage_state
	damage_blend_time = 0.0
	crack_shader_material.set_shader_parameter("state_from", float(visual_damage_state))
	crack_shader_material.set_shader_parameter("state_to", float(visual_damage_state))
	crack_shader_material.set_shader_parameter("blend_amount", 0.0)
	crack_mesh.visible = visual_damage_state > 0


func _get_crack_shader() -> Shader:
	if shared_crack_shader == null:
		shared_crack_shader = Shader.new()
		shared_crack_shader.code = """
shader_type spatial;
render_mode fog_disabled, cull_back, depth_draw_opaque, specular_disabled, vertex_lighting;

uniform sampler2D cracks_77 : source_color, filter_nearest, repeat_disable;
uniform sampler2D cracks_33 : source_color, filter_nearest, repeat_disable;
uniform sampler2D cracks_01 : source_color, filter_nearest, repeat_disable;
uniform sampler2D block_albedo : source_color, filter_linear, repeat_enable;
uniform float strength_77 : hint_range(0.0, 1.0) = 1.0;
uniform float strength_33 : hint_range(0.0, 1.0) = 0.65;
uniform float strength_01 : hint_range(0.0, 1.0) = 1.0;
uniform float state_from : hint_range(0.0, 3.0) = 0.0;
uniform float state_to : hint_range(0.0, 3.0) = 0.0;
uniform float blend_amount : hint_range(0.0, 1.0) = 0.0;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.28;
uniform float overlay_size = 2.035;
uniform float block_uv_scale = 0.25;
uniform vec4 pigment_body : source_color = vec4(0.259, 0.239, 0.196, 1.0);
uniform vec4 pigment_vein : source_color = vec4(0.580, 0.251, 0.086, 1.0);

varying vec2 face_uv;
varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	vec3 n = abs(NORMAL);
	vec2 uv;
	if (n.x >= n.y && n.x >= n.z) {
		uv = vec2(-sign(NORMAL.x) * VERTEX.z, VERTEX.y);
	} else if (n.y >= n.z) {
		uv = vec2(VERTEX.x, -sign(NORMAL.y) * VERTEX.z);
	} else {
		uv = vec2(sign(NORMAL.z) * VERTEX.x, VERTEX.y);
	}
	face_uv = uv / overlay_size + 0.5;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float cumulative_alpha(float state, float alpha_77, float alpha_33, float alpha_01) {
	float result = 0.0;
	if (state >= 0.5) {
		result = max(result, alpha_77 * strength_77);
	}
	if (state >= 1.5) {
		result = max(result, alpha_33 * strength_33);
	}
	if (state >= 2.5) {
		result = max(result, alpha_01 * strength_01);
	}
	return result;
}

float crack_mask(vec2 uv) {
	float alpha_77 = texture(cracks_77, uv).a;
	float alpha_33 = texture(cracks_33, uv).a;
	float alpha_01 = texture(cracks_01, uv).a;
	float old_alpha = cumulative_alpha(state_from, alpha_77, alpha_33, alpha_01);
	float new_alpha = cumulative_alpha(state_to, alpha_77, alpha_33, alpha_01);
	return mix(old_alpha, new_alpha, blend_amount);
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 rock_color(vec3 sample_pos) {
	vec3 weights = abs(normalize(world_normal));
	weights = pow(weights, vec3(4.0));
	weights /= max(weights.x + weights.y + weights.z, 0.001);
	vec2 scale = vec2(block_uv_scale);
	vec3 tx = texture(block_albedo, sample_pos.zy * scale).rgb;
	vec3 ty = texture(block_albedo, sample_pos.xz * scale).rgb;
	vec3 tz = texture(block_albedo, sample_pos.xy * scale).rgb;
	return tx * weights.x + ty * weights.y + tz * weights.z;
}

void fragment() {
	float mask = crack_mask(face_uv);
	if (mask < alpha_scissor) {
		discard;
	}

	float depth = smoothstep(alpha_scissor, 1.0, mask);
	vec3 n = normalize(world_normal);
	vec3 rock = rock_color(world_pos - n * 0.008);
	vec3 body = pigment_body.rgb;
	vec3 vein = pigment_vein.rgb;
	float vein_luma = max(dot(vein, vec3(0.299, 0.587, 0.114)), 0.08);
	vec3 vein_hue = vein / vein_luma;
	float grain = hash21(face_uv * 22.0);

	// Stain the existing rock; never replace it with a flat fill.
	float stain_amt = mix(0.18, 0.42, depth) * mix(0.85, 1.15, grain);
	vec3 stained = mix(rock, rock * vein_hue, stain_amt);
	stained = mix(stained, mix(stained, body, 0.20), (1.0 - depth) * 0.25);

	// Shallow groove. Floor keeps the core from collapsing to black.
	float groove = mix(0.86, 0.62, depth);
	stained *= groove;

	float mask_y = crack_mask(face_uv + vec2(0.0, 0.003));
	float rim = clamp(mask - mask_y, 0.0, 1.0);
	stained += rock * rim * 0.22;

	ALBEDO = stained;
	ROUGHNESS = 0.93;
}
"""
	return shared_crack_shader
