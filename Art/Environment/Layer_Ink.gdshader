shader_type canvas_item;

uniform vec4 fog_color : source_color = vec4(0.659, 0.722, 0.643, 1.0);
uniform float fog_strength : hint_range(0.0, 1.0) = 0.0;
varying vec4 item_tint;

void vertex() {
	item_tint = COLOR;
}

void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	COLOR = vec4(mix(texel.rgb, fog_color.rgb, fog_strength), texel.a) * item_tint;
}
