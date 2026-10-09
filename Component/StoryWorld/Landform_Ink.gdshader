shader_type canvas_item;

uniform sampler2D grain : source_color, filter_linear, repeat_enable;
uniform vec2 grain_offset = vec2(0.0);
uniform float bottom_fade : hint_range(0.0, 1.0) = 0.0;
varying vec2 local_position;
varying vec4 land_color;

void vertex() {
	local_position = VERTEX;
	land_color = COLOR;
}

void fragment() {
	vec3 g = texture(grain, local_position / 850.0 + grain_offset).rgb;
	float fine = dot(g, vec3(0.299, 0.587, 0.114));
	float broad = dot(texture(grain, local_position / 1730.0 + grain_offset.yx).rgb, vec3(0.299, 0.587, 0.114));
	float light_land = smoothstep(0.44, 0.62, dot(land_color.rgb, vec3(0.299, 0.587, 0.114)));
	vec3 dark_print = mix(land_color.rgb, g, 0.80);
	vec3 light_print = land_color.rgb * mix(0.85, 1.14, smoothstep(0.12, 0.55, fine));
	vec3 printed = mix(dark_print, light_print, light_land);
	printed *= mix(0.94, 1.07, smoothstep(0.14, 0.52, broad));
	float fade = 1.0 - bottom_fade * smoothstep(0.36, 1.0, UV.y + (broad - 0.35) * 0.18);
	COLOR = vec4(printed, land_color.a * fade);
}
