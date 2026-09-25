shader_type spatial;
render_mode cull_back;

// Procedural building facade: concrete base colour with a grid of windows.
// Windows are computed from world position so every box mesh gets a coherent grid
// without any texture. At night "window_emission" lights a pseudo-random subset.

uniform vec4 base_color : source_color = vec4(0.62, 0.62, 0.66, 1.0);
uniform vec4 window_color : source_color = vec4(0.12, 0.17, 0.24, 1.0);
uniform vec4 lit_color : source_color = vec4(1.0, 0.86, 0.55, 1.0);
uniform float window_emission : hint_range(0.0, 6.0) = 0.0;
uniform vec2 window_density = vec2(0.45, 0.33);
uniform float lit_ratio : hint_range(0.0, 1.0) = 0.55;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.9;

varying vec3 world_pos;
varying vec3 world_normal;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv;
	bool is_roof = abs(world_normal.y) > 0.5;
	if (is_roof) {
		uv = world_pos.xz;
	} else if (abs(world_normal.x) > 0.5) {
		uv = vec2(world_pos.z, world_pos.y);
	} else {
		uv = vec2(world_pos.x, world_pos.y);
	}
	vec2 scaled = uv * window_density;
	vec2 cell = fract(scaled);
	vec2 id = floor(scaled);
	float is_window = step(0.22, cell.x) * step(cell.x, 0.78) * step(0.3, cell.y) * step(cell.y, 0.8);
	// Ground floor and roof have no windows.
	if (is_roof || world_pos.y < 1.2) {
		is_window = 0.0;
	}
	float rnd = hash21(id + floor(world_pos.xz * 0.01));
	float lit = step(1.0 - lit_ratio, rnd) * window_emission;
	vec3 albedo = mix(base_color.rgb, window_color.rgb, is_window);
	// Subtle horizontal floor bands to break up flat walls.
	float band = smoothstep(0.02, 0.0, abs(cell.y - 0.05)) * (1.0 - is_window);
	albedo *= 1.0 - band * 0.12;
	if (is_roof) {
		albedo = base_color.rgb * 0.55;
	}
	ALBEDO = albedo;
	EMISSION = lit_color.rgb * is_window * lit;
	ROUGHNESS = mix(roughness_base, 0.25, is_window);
	METALLIC = 0.0;
	SPECULAR = mix(0.3, 0.6, is_window);
}
