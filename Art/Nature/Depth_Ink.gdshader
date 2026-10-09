shader_type canvas_item;

uniform float depth_fog : hint_range(0.0, 1.0) = 0.0;
uniform vec4 sage : source_color = vec4(0.68, 0.73, 0.62, 1.0);
uniform sampler2D dry_ink : source_color, filter_linear;
uniform float texture_strength : hint_range(0.0, 1.0) = 0.7;
varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
}

void fragment() {
	vec4 ink = texture(TEXTURE, UV);
	float wear = dot(texture(dry_ink, UV).rgb, vec3(0.299, 0.587, 0.114));
	ink.rgb *= mix(1.0, clamp(0.67 + wear * 1.25, 0.8, 1.45), texture_strength);
	float density = dot(ink.rgb, vec3(0.299, 0.587, 0.114));
	vec3 distant = mix(sage.rgb, vec3(0.90, 0.87, 0.77), density * 0.3);
	COLOR = vec4(mix(ink.rgb, distant, depth_fog), ink.a) * vertex_tint;
}
