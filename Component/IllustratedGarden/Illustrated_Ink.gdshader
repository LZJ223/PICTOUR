shader_type canvas_item;
uniform sampler2D grain : source_color, filter_linear, repeat_enable;
uniform vec2 grain_offset = vec2(0.0);
uniform float bottom_fade = 0.0;
uniform sampler2D page_surface : source_color, filter_linear, repeat_enable;
uniform bool background_surface = false;
varying vec2 paper_position;
varying vec4 ink_color;
void vertex() {
	paper_position = VERTEX;
	ink_color = COLOR;
}
void fragment() {
	float coarse = dot(texture(grain,paper_position/1740.0+grain_offset).rgb,vec3(0.299,0.587,0.114));
	float speck = dot(texture(grain,paper_position/580.0+grain_offset.yx).rgb,vec3(0.299,0.587,0.114));
	vec2 page_uv = fract(paper_position / vec2(2140.0,1280.0)+grain_offset);
	vec3 surface = texture(page_surface,page_uv).rgb;
	float edge_distance = min(min(page_uv.x,1.0-page_uv.x),min(page_uv.y,1.0-page_uv.y));
	float continuity = smoothstep(0.015,0.10,edge_distance);
	float surface_ink = dot(surface,vec3(0.299,0.587,0.114));
	vec3 printed;
	if (background_surface) {
		printed = ink_color.rgb * mix(0.94,1.06,surface_ink*continuity+0.33*(1.0-continuity));
	} else {
		printed = mix(ink_color.rgb,surface,0.54*continuity);
		printed *= mix(0.95,1.04,smoothstep(0.12,0.68,coarse));
	}
	printed = mix(printed,vec3(0.95,0.88,0.73),smoothstep(0.62,0.89,speck)*0.04);
	float fade = 1.0-bottom_fade*smoothstep(0.42,1.0,UV.y);
	COLOR = vec4(printed,ink_color.a*fade);
}
