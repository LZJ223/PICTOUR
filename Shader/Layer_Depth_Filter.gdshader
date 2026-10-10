shader_type canvas_item;
render_mode unshaded;

// CanvasGroup 会先把整个图层绘制到后备缓冲，再执行本材质。
// mipmap LOD 用于低成本的前景模糊。
uniform sampler2D screen_texture :
	hint_screen_texture,
	repeat_disable,
	filter_linear_mipmap;

uniform float blur_lod = 0.0;
uniform float darkness = 0.0;
uniform vec4 fog_color : source_color = vec4(0.75, 0.82, 0.78, 0.8);
uniform float fog_strength = 0.0;
uniform vec4 outline_color : source_color = vec4(1.0);
uniform float outline_width_px : hint_range(0.0, 8.0, 0.5) = 3.0;

const int OUTLINE_SAMPLE_COUNT = 16;
const float OUTLINE_TAU = 6.28318530718;

// 在完成模糊后的整层 Alpha 外围采样，得到最终画面的外描边遮罩。
float get_outline_alpha(vec2 uv, float center_alpha, float sample_lod) {
	if (outline_width_px <= 0.0 || center_alpha >= 0.9999) {
		return 0.0;
	}

	float surrounding_alpha = 0.0;
	vec2 screen_pixel_size = 1.0 / vec2(textureSize(screen_texture, 0));
	for (int index = 0; index < OUTLINE_SAMPLE_COUNT; index++) {
		float angle = OUTLINE_TAU * float(index) / float(OUTLINE_SAMPLE_COUNT);
		vec2 direction = vec2(cos(angle), sin(angle));
		vec2 offset = direction * outline_width_px * screen_pixel_size;
		float sample_alpha = textureLod(screen_texture, uv + offset, sample_lod).a;
		surrounding_alpha = max(surrounding_alpha, sample_alpha);
	}

	// 减去当前像素的 Alpha，确保描边只出现在图层外部。
	return max(surrounding_alpha - center_alpha, 0.0);
}

void fragment() {
	vec4 color = textureLod(screen_texture, SCREEN_UV, blur_lod);

	// CanvasGroup 使用预乘 Alpha；混色前恢复原始 RGB，避免透明边缘发黑。
	if (color.a > 0.0001) {
		color.rgb /= color.a;
	}

	// 前景以模糊为主，并附带少量压暗。
	color.rgb *= 1.0 - darkness;

	// SCREEN_UV.y 从画面顶部的 0 线性增加到底部的 1。
	float fog_gradient = SCREEN_UV.y;
	float fog_amount = clamp(
		fog_gradient * fog_strength * fog_color.a,
		0.0,
		1.0
	);
	color.rgb = mix(color.rgb, fog_color.rgb, fog_amount);

	// 使用滤镜处理后的轮廓生成白边，再将其合成到最终图层下方。
	float outline_alpha = get_outline_alpha(SCREEN_UV, color.a, blur_lod) * outline_color.a;
	float combined_alpha = color.a + outline_alpha * (1.0 - color.a);
	vec3 combined_rgb = vec3(0.0);
	if (combined_alpha > 0.0001) {
		combined_rgb = (
			color.rgb * color.a
			+ outline_color.rgb * outline_alpha * (1.0 - color.a)
		) / combined_alpha;
	}

	// 保留 CanvasGroup 原有的调制与透明度行为。
	COLOR *= vec4(combined_rgb, combined_alpha);
}
