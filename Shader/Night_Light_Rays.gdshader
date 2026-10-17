shader_type canvas_item;
render_mode unshaded;

#include "res://Shader/Night_Light_Common.gdshaderinc"

global uniform bool render_night_enabled;
global uniform vec2 render_night_light_uv;
global uniform vec4 render_night_light_color : source_color;
global uniform float render_night_light_radius;
global uniform float render_night_ray_energy;
global uniform float render_night_focus;
global uniform float render_night_time;

void fragment() {
	if (!render_night_enabled) { discard; }
	vec2 delta = (render_night_light_uv - SCREEN_UV) / SCREEN_PIXEL_SIZE;
	float radius = max(render_night_light_radius / SCREEN_PIXEL_SIZE.y, 1.0);
	float falloff = pow(max(1.0 - length(delta) / radius, 0.0), 0.7);
	if (falloff < 0.001) { discard; }
	vec2 origin = screen_uv_to_sdf(SCREEN_UV);
	vec2 light = screen_uv_to_sdf(render_night_light_uv);
	float epsilon = length(screen_uv_to_sdf(SCREEN_UV + SCREEN_PIXEL_SIZE) - origin);
	if (texture_sdf(origin) < -epsilon) { discard; }
	float visibility = night_visibility(origin, light, epsilon);
	float angle = atan(delta.y, delta.x);
	float streaks = 0.90 + 0.06 * sin(angle * 23.0 + render_night_time * 0.05)
		+ 0.04 * sin(angle * 41.0 - render_night_time * 0.03);
	// 被挡住的空气有明显暗区，照通的空气呈暖色；边界来自真实轮廓。
	// 此平面仍放在所有实体之后，既不会压暗其他层，也不会把黑影照灰。
	float strength = falloff * render_night_ray_energy * render_night_focus;
	COLOR = vec4(render_night_light_color.rgb * visibility * streaks,
		strength * mix(1.0, 0.65, visibility));
}
