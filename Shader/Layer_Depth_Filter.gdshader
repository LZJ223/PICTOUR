shader_type canvas_item;
render_mode unshaded;

#include "res://Shader/Night_Light_Common.gdshaderinc"

// CanvasGroup 会先把整个图层绘制到后备缓冲，再执行本材质。
// 各类效果的强度由 Renderer 统一写入全局变量，本材质只接收图层 Z 值。
uniform sampler2D screen_texture :
	hint_screen_texture,
	repeat_disable,
	filter_linear_mipmap;

uniform float layer_z_index = 0.0;
uniform float cycle_opacity = 1.0;
uniform int layer_id = 0;
uniform bool is_night = false;
global uniform sampler2D render_shadow_mask : repeat_disable, filter_linear;
global uniform vec2 render_shadow_tile_size;
global uniform bool render_night_enabled;
global uniform vec2 render_night_light_uv;
global uniform vec4 render_night_light_color : source_color;
global uniform float render_night_light_radius;
global uniform float render_night_ambient;
global uniform float render_night_surface_width;
global uniform float render_night_surface_energy;
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

	if (is_night && render_night_enabled) {
		// 夜间明暗只作用于当前关卡平面；其余层保持原来的景深颜色。
		float focus = 1.0 - smoothstep(0.0, 0.5, layer_distance);
		if (focus > 0.001 && color.a > 0.0001) {
			vec2 point = screen_uv_to_sdf(SCREEN_UV);
			vec2 light = screen_uv_to_sdf(render_night_light_uv);
			float epsilon = length(screen_uv_to_sdf(SCREEN_UV + SCREEN_PIXEL_SIZE) - point);
			float width = length(screen_uv_to_sdf(SCREEN_UV + vec2(0.0, render_night_surface_width)) - point);
			float radius = length(screen_uv_to_sdf(render_night_light_uv + vec2(0.0, render_night_light_radius)) - light);
			float diffuse = 0.0;
			// 深处和光照范围外直接使用环境色，不执行射线步进。
			if (texture_sdf(point) > -width * 4.0 && length(light - point) < radius) {
				vec3 entry = night_entry_surface(point, light, epsilon, width * 4.0);
				if (entry.z >= 0.0) {
					vec2 surface = entry.xy;
					vec2 normal = texture_sdf_normal(surface);
					vec2 toward_light = light - surface;
					float facing = max(dot(normal, normalize(toward_light + vec2(0.000001))), 0.0);
					float falloff = pow(max(1.0 - length(toward_light) / max(radius, epsilon), 0.0), 1.3);
					if (facing > 0.001 && falloff > 0.001) {
						float visibility = night_visibility(surface + normal * epsilon * 2.0, light, epsilon);
						diffuse = falloff * facing * exp(-entry.z / max(width, epsilon)) * visibility;
					}
				}
			}
			vec3 illumination = vec3(render_night_ambient)
				+ render_night_light_color.rgb * render_night_surface_energy * diffuse;
			color.rgb *= mix(vec3(1.0), illumination, focus);
		}
		// 阴影在所有调色、受光之后置黑；目标图层的 Alpha 不变。
		vec2 tile = vec2(float(layer_id % 2), float(layer_id / 2));
		vec2 tile_pixel = clamp(SCREEN_UV * render_shadow_tile_size, vec2(0.5), render_shadow_tile_size - vec2(0.5));
		vec2 mask_uv = (tile * render_shadow_tile_size + tile_pixel) / (render_shadow_tile_size * 2.0);
		float coverage = textureLod(render_shadow_mask, mask_uv, 0.0).r;
		color.rgb *= 1.0 - coverage;
	}

	// 保留 CanvasGroup 原有的调制与透明度行为。
	COLOR *= color;
	COLOR.a *= cycle_opacity;
}
