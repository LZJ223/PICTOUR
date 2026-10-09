shader_type canvas_item;

uniform sampler2D grain : source_color, filter_linear, repeat_enable;
uniform float depth_fog : hint_range(0.0, 1.0) = 0.0;
uniform float wear : hint_range(0.0, 1.0) = 0.46;
uniform vec2 grain_offset = vec2(0.0);
varying vec2 paper_position;
varying vec4 ink_color;

void vertex() {
	paper_position = VERTEX;
	ink_color = COLOR;
}

void fragment() {
	vec3 sampled_ink = texture(grain, paper_position / 1000.0 + grain_offset).rgb;
	float fine = dot(sampled_ink, vec3(0.299, 0.587, 0.114));
	float broad = dot(texture(grain, paper_position / 1800.0 + grain_offset + vec2(0.27, 0.11)).rgb, vec3(0.299, 0.587, 0.114));
	vec3 paper = vec3(0.91, 0.86, 0.73);
	vec3 printed = mix(ink_color.rgb, sampled_ink, wear);
	printed *= mix(0.90, 1.14, smoothstep(0.18, 0.50, broad));
	vec3 distant = mix(vec3(0.58, 0.65, 0.55), paper, 0.22 + fine * 0.22);
	COLOR = vec4(mix(printed, distant, depth_fog), ink_color.a);
}
