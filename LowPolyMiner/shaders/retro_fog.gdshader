shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_test_disabled, depth_draw_never;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 fog_color : source_color = vec4(0.443, 0.518, 0.318, 1.0);
uniform vec4 cave_fog_color : source_color = vec4(0.043, 0.047, 0.035, 1.0);
uniform float fog_begin = 5.0;
uniform float fog_end = 38.0;
uniform float fog_curve = 0.85;
uniform float fog_intensity = 0.88;
uniform float cave_fog_intensity = 0.58;
uniform float fog_band_count = 16.0;
uniform float retro_mix = 0.70;
uniform vec3 mine_min = vec3(-100.0, -400.0, -200.0);
uniform vec3 mine_max = vec3(100.0, 40.0, 8.0);
uniform float cave_shell = 3.0;
uniform float cave_fade = 8.0;


float cave_weight(vec3 world_pos) {
	// Exterior crust and anything outside the mountain keep outdoor fog.
	// Torch-lit walls deep inside still count as cave — luma must not decide.
	vec3 inset_min = mine_min + vec3(cave_shell);
	vec3 inset_max = mine_max - vec3(cave_shell);
	vec3 to_face = min(world_pos - inset_min, inset_max - world_pos);
	float inward = min(to_face.x, min(to_face.y, to_face.z));
	return smoothstep(0.0, max(cave_fade, 0.001), inward);
}


float bayer4(vec2 pixel) {
	int x = int(mod(floor(pixel.x), 4.0));
	int y = int(mod(floor(pixel.y), 4.0));
	float matrix[16] = float[16](
		0.0, 8.0, 2.0, 10.0,
		12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0,
		15.0, 7.0, 13.0, 5.0
	);
	return (matrix[y * 4 + x] + 0.5) / 16.0;
}


void vertex() {
	// Reversed-Z fullscreen quad. It remains a camera child, but this clip-space
	// position guarantees complete coverage without a large world mesh.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}


void fragment() {
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, raw_depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
#endif
	vec4 view_position = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_position /= max(view_position.w, 0.0001);
	float linear_depth = max(-view_position.z, 0.0);
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(view_position.xyz, 1.0)).xyz;
	float depth_span = max(fog_end - fog_begin, 0.001);
	float fog_coefficient = clamp((linear_depth - fog_begin) / depth_span, 0.0, 1.0);
	fog_coefficient = pow(smoothstep(0.0, 1.0, fog_coefficient), fog_curve);

	float band_count = max(fog_band_count, 1.0);
	float ordered = bayer4(FRAGCOORD.xy);
	float stepped = floor(fog_coefficient * band_count + ordered) / band_count;
	float styled_coefficient = mix(fog_coefficient, stepped, retro_mix);
	vec3 scene_color = texture(screen_texture, SCREEN_UV).rgb;
	float cave_w = cave_weight(world_pos);
	float amount = clamp(styled_coefficient * mix(fog_intensity, cave_fog_intensity, cave_w), 0.0, 1.0);
	vec3 target = mix(fog_color.rgb, cave_fog_color.rgb, cave_w);
	ALBEDO = mix(scene_color, target, amount);
}
