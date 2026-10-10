shader_type canvas_item;

uniform float gray_amount : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 color = texture(TEXTURE, UV) * COLOR;
	float luma = dot(color.rgb, vec3(0.299, 0.587, 0.114));
	color.rgb = mix(color.rgb, vec3(luma), gray_amount);
	COLOR = color;
}
