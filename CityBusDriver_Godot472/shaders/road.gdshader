shader_type spatial;
render_mode cull_back;

// Procedural asphalt with lane markings for a straight road segment rendered on a
// PlaneMesh. UV.x runs across the road, UV.y runs along it.

uniform float road_length = 50.0;
uniform float road_width = 14.0;
uniform float lane_width = 3.5;
uniform vec4 asphalt : source_color = vec4(0.16, 0.16, 0.17, 1.0);
uniform vec4 line_white : source_color = vec4(0.9, 0.9, 0.88, 1.0);
uniform vec4 line_yellow : source_color = vec4(0.93, 0.75, 0.2, 1.0);
uniform bool crosswalks = true;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float line_mask(float d, float half_w) {
	return 1.0 - smoothstep(half_w, half_w + 0.03, abs(d));
}

void fragment() {
	float across = (UV.x - 0.5) * road_width;
	float along = UV.y * road_length;
	float a = abs(across);
	vec3 col = asphalt.rgb;
	// Asphalt speckle.
	float speck = hash21(floor(vec2(across, along) * 6.0));
	col *= 0.9 + speck * 0.2;
	// Centre double yellow line.
	float yellow = line_mask(a - 0.22, 0.07);
	// Dashed white lane dividers.
	float dash = step(fract(along / 6.0), 0.5);
	float divider = line_mask(a - lane_width, 0.06) * dash;
	// Solid edge lines.
	float edge = line_mask(a - (road_width * 0.5 - 0.35), 0.06);
	// Crosswalks near both ends of the segment.
	float cw = 0.0;
	if (crosswalks) {
		float from_end = min(along, road_length - along);
		float in_band = step(1.0, from_end) * step(from_end, 3.6);
		float stripes = step(fract(across / 1.2), 0.5);
		cw = in_band * stripes * step(a, road_width * 0.5 - 0.6);
		float stop_line = step(0.5, from_end) * step(from_end, 0.85);
		cw = max(cw, stop_line);
	}
	col = mix(col, line_yellow.rgb, yellow);
	col = mix(col, line_white.rgb, max(max(divider, edge), cw));
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
