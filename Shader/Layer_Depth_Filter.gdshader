shader_type canvas_item;

#include "res://Shader/Night_Surface.gdshaderinc"

// CanvasGroup 会先把整个图层绘制到后备缓冲，再执行本材质。
// 各类效果的强度由 Renderer 统一写入全局变量，本材质只接收图层 Z 值。
uniform sampler2D screen_texture :
	hint_screen_texture,
	repeat_disable,
	filter_linear_mipmap;

uniform float layer_z_index = 0.0;
uniform float cycle_opacity = 1.0;
uniform bool is_night = false;
global uniform bool render_night_light_enabled;
global uniform vec2 render_night_light_uv;
global uniform float render_night_surface_width;
global uniform float render_night_ambient;
varying vec3 surface_albedo;
varying float surface_response;
const float LAYER_Z_INDEX_STEP = 100.0;

global uniform float render_foreground_blur_step;
global uniform float render_background_blur_step;
global uniform float render_maximum_blur_lod;
global uniform float render_foreground_darkness_step;
global uniform vec4 render_foreground_tint_color : source_color;
global uniform float render_foreground_tint_step;
global uniform float render_contrast_falloff;
global uniform vec4 render_background_tint_color : source_color;
global uniform float render_background_tint_step;

void fragment() {
	float front_distance = max(layer_z_index, 0.0) / LAYER_Z_INDEX_STEP;
	float back_distance = max(-layer_z_index, 0.0) / LAYER_Z_INDEX_STEP;
	float layer_distance = abs(layer_z_index) / LAYER_Z_INDEX_STEP;
	float blur_lod = min(
		front_distance * render_foreground_blur_step
			+ back_distance * render_background_blur_step,
		render_maximum_blur_lod
	);
	vec4 color = textureLod(screen_texture, SCREEN_UV, blur_lod);

	// CanvasGroup 使用预乘 Alpha；混色前恢复原始 RGB，避免透明边缘发黑。
	if (color.a > 0.0001) {
		color.rgb /= color.a;
	}

	// 离关卡层越远，对比度越低，逐步压缩图像细节。
	float contrast = clamp(
		1.0 - layer_distance * render_contrast_falloff,
		0.0,
		1.0
	);
	color.rgb = (color.rgb - vec3(0.5)) * contrast + vec3(0.5);

	// 前景优先压暗，随着距离增加形成接近剪影的效果。
	float darkness = clamp(
		front_distance * render_foreground_darkness_step,
		0.0,
		1.0
	);
	color.rgb *= 1.0 - darkness;

	// 前景与后景分别向独立基准色偏移；强度为 0 时不会改变颜色。
	float foreground_tint = clamp(
		front_distance * render_foreground_tint_step,
		0.0,
		1.0
	);
	float background_tint = clamp(
		back_distance * render_background_tint_step,
		0.0,
		1.0
	);
	color.rgb = mix(color.rgb, render_foreground_tint_color.rgb, foreground_tint);
	color.rgb = mix(color.rgb, render_background_tint_color.rgb, background_tint);

	surface_albedo = COLOR.rgb * color.rgb;
	surface_response = 0.0;
	if (is_night && render_night_light_enabled) {
		float focus = 1.0 - smoothstep(0.0, 0.5, layer_distance);
		if (focus > 0.001 && color.a > 0.0001) {
			color.rgb *= mix(1.0, render_night_ambient, focus);
			vec2 point = screen_uv_to_sdf(SCREEN_UV);
			vec2 light_position = screen_uv_to_sdf(render_night_light_uv);
			float epsilon = length(screen_uv_to_sdf(SCREEN_UV + SCREEN_PIXEL_SIZE) - point);
			float width = length(screen_uv_to_sdf(SCREEN_UV + vec2(0.0, render_night_surface_width)) - point);
			if (texture_sdf(point) > -width * 4.0) {
				vec3 entry = night_entry_surface(point, light_position, epsilon, width * 4.0);
				if (entry.z >= 0.0) {
					vec2 normal = texture_sdf_normal(entry.xy);
					vec2 toward_light = normalize(light_position - entry.xy + vec2(0.000001));
					surface_response = max(dot(normal, toward_light), 0.0) * exp(-entry.z / max(width, epsilon)) * focus;
					// 用表面外侧查询原生 Light2D 阴影，避免物体内部被自身完全遮黑。
					SHADOW_VERTEX = sdf_to_screen_uv(entry.xy + normal * epsilon * 2.5) / SCREEN_PIXEL_SIZE;
				}
			}
		}
	}

	// 保留 CanvasGroup 原有的调制与透明度行为。
	COLOR *= color;
	COLOR.a *= cycle_opacity;
}

void light() {
	// 非关卡层 response 为零，保留原有景深亮度。
	LIGHT = vec4(surface_albedo * LIGHT_COLOR.rgb * LIGHT_ENERGY * surface_response, LIGHT_COLOR.a);
}
