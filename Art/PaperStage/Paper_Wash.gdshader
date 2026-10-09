shader_type canvas_item;

uniform sampler2D grain : source_color, filter_linear, repeat_enable;
uniform vec2 grain_offset = vec2(0.0);
uniform vec2 shape_size = vec2(1.0);
varying vec4 wash_color;
varying vec2 local_position;

void vertex() {
	wash_color = COLOR;
	local_position = VERTEX;
}

void fragment() {
	vec2 wash_uv = local_position / shape_size;
	float broad = dot(texture(grain, wash_uv * 0.9 + grain_offset).rgb, vec3(0.299, 0.587, 0.114));
	float fine = dot(texture(grain, wash_uv * 2.1 + grain_offset.yx).rgb, vec3(0.299, 0.587, 0.114));
	vec2 p = wash_uv * 2.0 - vec2(1.0);
	p.x += sin(p.y * 4.7 + grain_offset.x * 8.0) * 0.18;
	p.y += sin(p.x * 5.3 + grain_offset.y * 7.0) * 0.07;
	float outline = length(p) + (broad - 0.4) * 0.34;
	float feather = 1.0 - smoothstep(0.45, 1.0, outline);
	float printed = clamp(0.55 + fine * 0.6, 0.5, 0.95);
	COLOR = vec4(wash_color.rgb, wash_color.a * feather * printed);
}
