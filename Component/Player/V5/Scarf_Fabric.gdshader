shader_type canvas_item;
render_mode unshaded;

uniform sampler2D paper_ink : repeat_enable, filter_linear;

void fragment() {
	vec4 cloth = COLOR;
	float print_grain = texture(paper_ink, vec2(UV.x * 0.34 + 0.23, UV.y * 0.035 + 0.45)).r;
	float pigment = mix(0.87, 1.06, print_grain);
	COLOR = vec4(cloth.rgb * pigment, cloth.a);
}
