shader_type spatial;
render_mode vertex_lighting, specular_disabled, cull_back, depth_draw_opaque;

uniform vec4 cloud_tint : source_color = vec4(0.81, 0.83, 0.77, 1.0);
uniform vec3 mountain_aabb_min = vec3(-80.01, -610.01, -153.01);
uniform vec3 mountain_aabb_max = vec3(80.01, 30.01, 7.01);
uniform float distance_fade_begin = 340.0;
uniform float distance_fade_end = 520.0;

varying vec3 world_position;
varying vec3 cloud_local_position;
varying float cloud_instance_seed;


float cloud_hash(vec3 value) {
	return fract(sin(dot(value, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	cloud_local_position = VERTEX;
	cloud_instance_seed = INSTANCE_CUSTOM.x;
}


void fragment() {
	bool inside_mountain = (
		world_position.x >= mountain_aabb_min.x
		&& world_position.x <= mountain_aabb_max.x
		&& world_position.y >= mountain_aabb_min.y
		&& world_position.y <= mountain_aabb_max.y
		&& world_position.z >= mountain_aabb_min.z
		&& world_position.z <= mountain_aabb_max.z
	);
	if (inside_mountain) {
		discard;
	}

	float camera_distance = distance(world_position, CAMERA_POSITION_WORLD);
	float distance_fade = smoothstep(distance_fade_begin, distance_fade_end, camera_distance);
	// Coarse cells peel away small facet groups rather than turning distant
	// silhouettes into fine sparkling noise. The coordinates remain mesh-local,
	// so the pattern travels with each drifting cloud and never swims in world space.
	vec3 pattern_cell = floor(cloud_local_position * 0.45 + vec3(
		cloud_instance_seed * 29.0,
		cloud_instance_seed * 47.0,
		cloud_instance_seed * 71.0
	));
	float threshold = cloud_hash(pattern_cell);
	if (distance_fade > threshold) {
		discard;
	}

	ALBEDO = cloud_tint.rgb * COLOR.rgb;
	ROUGHNESS = 1.0;
}
