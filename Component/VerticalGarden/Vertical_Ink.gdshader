shader_type canvas_item;
uniform sampler2D grain : source_color, filter_linear, repeat_enable;
uniform vec2 grain_offset = vec2(0.0);
uniform float bottom_fade = 0.0;
varying vec2 paper_position;
varying vec4 ink_color;

void vertex() {
	paper_position = VERTEX;
	ink_color = COLOR;
}

void fragment() {
	vec3 g = texture(grain, paper_position / 1050.0 + grain_offset).rgb;
	float broad = dot(texture(grain, paper_position / 2130.0 + grain_offset.yx).rgb, vec3(0.299,0.587,0.114));
	float light_ink = smoothstep(0.44,0.66,dot(ink_color.rgb,vec3(0.299,0.587,0.114)));
	vec3 printed = mix(ink_color.rgb,g,0.24*(1.0-light_ink));
	printed *= mix(0.96,1.05,smoothstep(0.12,0.54,broad));
	float fade = 1.0-bottom_fade*smoothstep(0.30,1.0,UV.y+(broad-0.35)*0.10);
	COLOR = vec4(printed,ink_color.a*fade);
}
