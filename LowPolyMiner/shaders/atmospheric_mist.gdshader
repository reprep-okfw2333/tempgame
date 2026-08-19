shader_type canvas_item;
render_mode unshaded, blend_mix;

// After all 3D, including RetroFog. Soften and dirty the frame in large slow
// fields so it reads as air, not a stamped gray slab.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform mat4 inv_projection_matrix;
uniform mat4 inv_view_matrix;

uniform vec4 mist_color = vec4(0.29, 0.27, 0.32, 1.0);
uniform vec4 cave_mist_color = vec4(0.055, 0.059, 0.047, 1.0);
uniform vec3 mine_min = vec3(-100.0, -400.0, -200.0);
uniform vec3 mine_max = vec3(100.0, 40.0, 8.0);
uniform float cave_shell = 3.0;
uniform float cave_fade = 8.0;
uniform float mist_density = 0.95;
uniform float mist_opacity = 0.36;
uniform float mist_ambient = 0.10;
uniform float mist_scale = 13.0;
uniform float mist_speed = 0.16;
uniform vec2 mist_direction = vec2(1.0, 0.22);
uniform float mist_contrast = 0.55;
uniform float mist_depth_falloff = 18.0;
uniform float mist_near_amount = 0.24;
uniform float mist_far_amount = 0.85;
uniform float mist_begin = 2.6;
uniform float speckle_density = 0.22;
uniform float speckle_size = 1.3;
uniform float speckle_brightness = 0.40;
uniform float speckle_speed = 0.07;
uniform vec4 speckle_color = vec4(0.361, 0.400, 0.251, 1.0);


float hash13(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}


float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	return mix(mix(nx00, nx10, f.y), mix(nx01, nx11, f.y), f.z);
}


float mist_field(vec3 p) {
	float a = 0.55;
	float s = 0.0;
	s += value_noise(p) * a;
	p = p * 2.07 + vec3(17.2, 9.1, 3.4);
	a *= 0.5;
	s += value_noise(p) * a;
	p = p * 2.11 + vec3(5.8, 21.6, 11.0);
	a *= 0.5;
	s += value_noise(p) * a;
	return s;
}


vec3 view_ray(vec2 screen_uv) {
	vec3 ndc = vec3(screen_uv, 1.0) * 2.0 - 1.0;
	vec4 view = inv_projection_matrix * vec4(ndc, 1.0);
	view /= max(view.w, 0.0001);
	return normalize(view.xyz);
}


float cave_weight(vec3 world_pos) {
	vec3 inset_min = mine_min + vec3(cave_shell);
	vec3 inset_max = mine_max - vec3(cave_shell);
	vec3 to_face = min(world_pos - inset_min, inset_max - world_pos);
	float inward = min(to_face.x, min(to_face.y, to_face.z));
	return smoothstep(0.0, max(cave_fade, 0.001), inward);
}


float layer_sample(vec3 world_pos, vec2 wind, float warp, float scale_mul, float wind_mul, vec2 shift) {
	float quant = max(mist_scale * 0.18, 0.30);
	vec3 domain = mix(world_pos, floor(world_pos / quant + 0.5) * quant, 0.38);
	vec3 p = vec3(domain.xz * (scale_mul / mist_scale) - wind * wind_mul + shift, domain.y * 0.06 + warp);
	float hinge = clamp(mist_contrast, 0.05, 1.0);
	float lo = mix(0.22, 0.38, hinge);
	float hi = mix(0.82, 0.64, hinge);
	return smoothstep(lo, hi, mist_field(p));
}


void fragment() {
	vec3 origin = (inv_view_matrix * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 ray = mat3(inv_view_matrix) * view_ray(SCREEN_UV);
	vec2 wind = normalize(mist_direction + vec2(0.0001, 0.0)) * TIME * mist_speed;

	float near_dist = max(mist_begin + 3.5, 5.5);
	float mid_dist = near_dist + max(mist_depth_falloff * 0.55, 8.0);
	float far_dist = mid_dist + max(mist_depth_falloff * 0.85, 12.0);
	vec3 near_pos = origin + ray * near_dist;
	vec3 mid_pos = origin + ray * mid_dist;
	vec3 far_pos = origin + ray * far_dist;
	float warp_n = sin(near_pos.x * 0.035 + TIME * 0.07) * 0.55;
	float warp_m = cos(mid_pos.z * 0.028 - TIME * 0.05) * 0.32;

	float near_n = layer_sample(near_pos, wind, warp_n, 1.55, 1.35, vec2(0.0, 0.0));
	float mid_n = layer_sample(mid_pos, wind, warp_m, 1.00, 1.00, vec2(19.0, 7.0));
	float far_n = layer_sample(far_pos, wind, warp_m * 0.5, 0.52, 0.42, vec2(4.0, 23.0));

	float banks = near_n * mist_near_amount + mid_n * 1.25 + far_n * mist_far_amount;
	float mist = clamp(banks * mist_density, 0.0, 1.0);
	float tool = smoothstep(0.56, 0.82, SCREEN_UV.x) * smoothstep(0.58, 0.90, SCREEN_UV.y);
	mist *= 1.0 - tool * 0.80;

	vec3 speckle_pos = mid_pos + vec3(wind.x, 0.0, wind.y) * speckle_speed * 2.4;
	float cell = max(speckle_size, 0.15);
	vec3 cell_id = floor(speckle_pos / cell);
	float seed = hash13(cell_id);
	float seed_b = hash13(cell_id + vec3(3.7, 8.1, 1.9));
	vec3 local = fract(speckle_pos / cell) - 0.5;
	local.y *= 1.35;
	float radius = mix(0.08, 0.22, seed_b);
	float spot = 1.0 - smoothstep(radius * 0.30, radius, length(local));
	float present = step(1.0 - speckle_density * 0.12, seed);
	float pulse = smoothstep(0.10, 0.58, 0.5 + 0.5 * sin(TIME * speckle_speed * (0.7 + seed_b) + seed * 51.0));
	float speckle = spot * present * pulse * smoothstep(0.12, 0.42, mist) * speckle_brightness * (1.0 - tool);

	vec3 scene = texture(screen_texture, SCREEN_UV).rgb;
	float luma = dot(scene, vec3(0.299, 0.587, 0.114));
	float cave_w = (
		cave_weight(near_pos) + cave_weight(mid_pos) + cave_weight(far_pos)
	) / 3.0;
	vec3 stain = mix(mist_color.rgb, cave_mist_color.rgb, cave_w);
	// Crush detail and dirty the air. Dark cave pixels stain toward a color
	// below the rock so the haze is depth, not a lift.
	vec3 smothered = mix(scene, vec3(luma), 0.42) * 0.84;
	smothered = mix(smothered, stain, 0.28);
	float veil = mix(mist_ambient, mist_opacity, mist);
	vec3 out_c = mix(scene, smothered, clamp(veil, 0.0, 0.42));
	out_c = mix(out_c, mix(out_c, speckle_color.rgb, 0.28), clamp(speckle, 0.0, 1.0));
	COLOR = vec4(out_c, 1.0);
}
