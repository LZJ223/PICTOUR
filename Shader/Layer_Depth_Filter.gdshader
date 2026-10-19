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
uniform sampler2D shadow_projection : repeat_disable, filter_linear;
uniform bool shadow_projection_enabled = false;
global uniform float render_shadow_strength;
global uniform bool render_night_light_enabled;
global uniform vec2 render_night_light_uv;
global uniform vec4 render_night_world_per_uv;
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
global uniform bool render_night_foreground_enabled;
global uniform float render_night_foreground_surface_width;
global uniform float render_night_foreground_fade_width;
global uniform float render_night_foreground_max_brightness;
global uniform float render_night_foreground_near_distance;
global uniform float render_night_foreground_far_distance;
global uniform float render_night_foreground_darkness;

// 只比较 Alpha：不把纹理花纹当轮廓，不依赖物体类型或切割后的顶点数量。
float foreground_brightness(vec2 uv, vec2 pixel_size, float alpha, float blend) {
	float maximum_brightness = clamp(render_night_foreground_max_brightness, 0.0, 1.0);
	float minimum_brightness = min(maximum_brightness, clamp(1.0 - render_night_foreground_darkness, 0.0, 1.0));
	vec2 delta_uv = uv - render_night_light_uv;
	vec2 world_offset = delta_uv.x * render_night_world_per_uv.xy + delta_uv.y * render_night_world_per_uv.zw;
	float near_distance = max(render_night_foreground_near_distance, 0.0);
	float far_distance = max(render_night_foreground_far_distance, near_distance + 1.0);
	float edge_brightness = mix(maximum_brightness, minimum_brightness, smoothstep(near_distance, far_distance, length(world_offset)));
	float fade = max(render_night_foreground_fade_width, 1.0);
	float edge_lod = max(log2(fade * 2.0), 0.0);
	vec2 radius = pixel_size * render_night_foreground_surface_width;
	float nearest_alpha = textureLod(screen_texture, uv, max(log2(fade), 0.0)).a;
	// 原始 Alpha 低于邻域均值时处在抗锯齿/渐变外缘，不能把它归一化成内部。
	if (alpha + 0.0001 < nearest_alpha) {
		return mix(1.0, edge_brightness, blend);
	}
	for (int index = 0; index < 8; index++) {
		float angle = float(index) * 0.78539816339;
		vec2 direction = vec2(cos(angle), sin(angle));
		nearest_alpha = min(nearest_alpha, textureLod(screen_texture, uv + direction * radius, edge_lod).a);
	}
	// 以局部原始 Alpha 归一化，半透明物体不会整块被误认为轮廓。
	float interior = smoothstep(0.5, 0.98, nearest_alpha / max(alpha, 0.0001));
	return mix(1.0, mix(edge_brightness, minimum_brightness, interior), blend);
}

// 先处理表面亮度再卷积颜色；最终覆盖率继续沿用原 mipmap Alpha。
vec4 foreground_surface(vec2 uv, vec2 pixel_size, float blur_lod, vec4 filtered, float blend) {
	if (blur_lod <= 0.001) {
		return vec4(filtered.rgb / max(filtered.a, 0.0001),
			foreground_brightness(uv, pixel_size, filtered.a, blend));
	}
	float weights[3] = float[3](1.0, 2.0, 1.0);
	vec2 step_uv = pixel_size * sqrt((exp2(2.0 * blur_lod) - 1.0) / 3.0);
	vec4 lit = vec4(0.0);
	float coverage = 0.0;
	float minimum_brightness = 1.0;
	float maximum_brightness = 0.0;
	for (int y = 0; y < 3; y++) {
		for (int x = 0; x < 3; x++) {
			vec2 sample_uv = uv + vec2(float(x - 1), float(y - 1)) * step_uv;
			vec4 surface = textureLod(screen_texture, sample_uv, 0.0);
			float brightness = foreground_brightness(sample_uv, pixel_size, surface.a, blend);
			float weight = weights[x] * weights[y];
			lit += surface * (brightness * weight);
			coverage += surface.a * weight;
			minimum_brightness = min(minimum_brightness, brightness);
			maximum_brightness = max(maximum_brightness, brightness);
		}
	}
	if (maximum_brightness - minimum_brightness < 0.0001) {
		return vec4(filtered.rgb / max(filtered.a, 0.0001), maximum_brightness);
	}
	return vec4(lit.rgb / max(lit.a, 0.0001), lit.a / max(coverage, 0.0001));
}

// 联合采样预乘实体颜色与投影，先合影、后模糊；透明区域不参与颜色归一化。
// Alpha 仍沿用 CanvasGroup 的原始 mipmap 覆盖率，避免改变实体边缘与背景混合。
vec4 shadowed_surface(vec2 uv, vec2 pixel_size, float blur_lod, vec4 filtered) {
	if (blur_lod <= 0.001) {
		float visibility = 1.0 - textureLod(shadow_projection, uv, 0.0).a * render_shadow_strength;
		return vec4(filtered.rgb / max(filtered.a, 0.0001), visibility);
	}
	float weights[5] = float[5](1.0, 4.0, 6.0, 4.0, 1.0);
	float shadows[25];
	// 与 LOD 的采样范围一起增长，并在关闭模糊时连续收敛到单点。
	vec2 step_uv = pixel_size * sqrt((exp2(2.0 * blur_lod) - 1.0) / 6.0);
	float minimum_shadow = 1.0;
	float maximum_shadow = 0.0;
	for (int y = 0; y < 5; y++) {
		for (int x = 0; x < 5; x++) {
			vec2 sample_uv = uv + vec2(float(x - 2), float(y - 2)) * step_uv;
			float shadow = textureLod(shadow_projection, sample_uv, 0.0).a * render_shadow_strength;
			shadows[y * 5 + x] = shadow;
			minimum_shadow = min(minimum_shadow, shadow);
			maximum_shadow = max(maximum_shadow, shadow);
		}
	}
	// 遮罩恒定时保留原景深采样，且不用额外读取 25 次实体纹理。
	if (maximum_shadow - minimum_shadow < 0.0001) {
		return vec4(filtered.rgb / max(filtered.a, 0.0001), 1.0 - maximum_shadow);
	}
	vec4 lit = vec4(0.0);
	float coverage = 0.0;
	for (int y = 0; y < 5; y++) {
		for (int x = 0; x < 5; x++) {
			vec2 sample_uv = uv + vec2(float(x - 2), float(y - 2)) * step_uv;
			vec4 surface = textureLod(screen_texture, sample_uv, 0.0);
			float weight = weights[x] * weights[y];
			lit += surface * ((1.0 - shadows[y * 5 + x]) * weight);
			coverage += surface.a * weight;
		}
	}
	// 返回未受影部分的平均颜色与占比。调色是线性变换，可在平均后执行一次，
	// 再乘该占比，等价于每个采样点先调色、染黑，最后模糊。
	return vec4(lit.rgb / max(lit.a, 0.0001), lit.a / max(coverage, 0.0001));
}

void fragment() {
	float front_distance = max(layer_z_index, 0.0) / LAYER_Z_INDEX_STEP;
	float back_distance = max(-layer_z_index, 0.0) / LAYER_Z_INDEX_STEP;
	float layer_distance = abs(layer_z_index) / LAYER_Z_INDEX_STEP;
	float blur_lod = min(
		front_distance * render_foreground_blur_step
			+ back_distance * render_background_blur_step,
		render_maximum_blur_lod
	);
	vec4 filtered = textureLod(screen_texture, SCREEN_UV, blur_lod);
	vec4 color = filtered;

	// CanvasGroup 使用预乘 Alpha；混色前恢复原始 RGB，避免透明边缘发黑。
	if (color.a > 0.0001) {
		color.rgb /= color.a;
	}
	float lit_fraction = 1.0;
	float foreground_blend = 0.0;
	if (is_night && render_night_foreground_enabled) {
		foreground_blend = smoothstep(0.0, 1.0, front_distance);
	}
	if (foreground_blend > 0.0001 && color.a > 0.0001) {
		vec4 surface = foreground_surface(SCREEN_UV, SCREEN_PIXEL_SIZE, blur_lod, filtered, foreground_blend);
		color.rgb = surface.rgb;
		lit_fraction = surface.a;
	} else if (shadow_projection_enabled && color.a > 0.0001) {
		vec4 surface = shadowed_surface(
			SCREEN_UV, SCREEN_PIXEL_SIZE, blur_lod,
			filtered
		);
		color.rgb = surface.rgb;
		lit_fraction = surface.a;
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
	// 黑夜前景使用表面规则替代统一压暗；跨越关卡层时平滑过渡。
	darkness *= 1.0 - foreground_blend;
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
	// 联合模糊后的受光占比；覆盖强度达到 100% 时完整阴影保持纯黑，实体 Alpha 只合成一次。
	color.rgb *= lit_fraction;

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
