shader_type canvas_item;
render_mode unshaded;

// 单位与背景原图一致；正常镜头中 2 个原图像素对应 1 个设计像素。
uniform float cell_size : hint_range(24.0, 256.0, 1.0) = 80.0;
uniform float density : hint_range(0.0, 1.0, 0.01) = 0.6;
uniform float min_radius : hint_range(0.5, 8.0, 0.1) = 1.2;
uniform float max_radius : hint_range(0.5, 8.0, 0.1) = 3.0;
uniform vec4 star_color : source_color = vec4(0.96, 0.98, 1.0, 1.0);
uniform float star_seed : hint_range(0.0, 1000.0, 1.0) = 17.0;
uniform vec2 region_origin = vec2(0.0);

varying vec2 sky_position;
varying vec4 vertex_modulate;

vec4 cell_random(vec2 cell) {
	vec4 random = fract(cell.xyxy * vec4(0.1031, 0.1030, 0.0973, 0.1099) + star_seed * 0.013);
	random += dot(random, random.wzxy + 33.33);
	return fract((random.xxyz + random.yzzw) * random.zywx);
}

void vertex() {
	sky_position = VERTEX + region_origin;
	vertex_modulate = COLOR;
}

void fragment() {
	vec4 random = cell_random(floor(sky_position / cell_size));
	vec2 point = fract(sky_position / cell_size) * cell_size;
	// 星点不接触网格边界，因此不需要扫描相邻网格，也不会在边界被切开。
	float padding = max(min_radius, max_radius) + 1.0;
	vec2 center = mix(vec2(padding), vec2(cell_size - padding), random.xy);
	float radius = mix(min(min_radius, max_radius), max(min_radius, max_radius), random.z);
	vec2 footprint = fwidth(sky_position);
	float edge = max(max(footprint.x, footprint.y), 0.001) * 0.5;
	float alpha = 1.0 - smoothstep(radius - edge, radius + edge, length(point - center));
	alpha *= 1.0 - step(density, fract(random.z * 7.31 + random.w * 0.61));
	COLOR = vec4(star_color.rgb * mix(0.75, 1.0, random.w), star_color.a * alpha) * vertex_modulate;
}
