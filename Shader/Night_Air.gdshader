shader_type canvas_item;

global uniform bool render_night_light_enabled;
global uniform vec2 render_night_light_uv;
global uniform float render_night_light_radius;
uniform float opacity = 0.16;
uniform float focus = 1.0;

void fragment() {
	if (!render_night_light_enabled) { discard; }
	vec2 delta = (SCREEN_UV - render_night_light_uv) / SCREEN_PIXEL_SIZE;
	float radius = max(render_night_light_radius / SCREEN_PIXEL_SIZE.y, 1.0);
	float falloff = 1.0 - smoothstep(0.7, 1.0, length(delta) / radius);
	COLOR = vec4(0.0, 0.0, 0.0, opacity * falloff * focus);
}

void light() {
	// 同一个 PointLight2D 的原生阴影区不接收此亮色。无角度条纹、射线或时间动画。
	LIGHT = vec4(LIGHT_COLOR.rgb * LIGHT_ENERGY * 3.0, LIGHT_COLOR.a);
}
