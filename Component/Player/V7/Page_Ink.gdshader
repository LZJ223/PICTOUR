shader_type canvas_item;
uniform sampler2D paper_ink : repeat_enable, filter_linear;
varying vec2 local_uv;
void vertex() { local_uv = VERTEX * 0.015; }
void fragment() {
	vec4 base = COLOR;
	float dry = texture(paper_ink, local_uv).r;
	base.rgb *= 0.955 + 0.045 * dry;
	COLOR = base;
}
