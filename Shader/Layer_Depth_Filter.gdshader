shader_type canvas_item;
render_mode unshaded;

// CanvasGroup 会先把整个图层绘制到后备缓冲，再执行本材质。
// 各类效果的强度由 Renderer 统一写入全局变量，本材质只接收图层 Z 值。
uniform sampler2D screen_texture :
	hint_screen_texture,
	repeat_disable,
	filter_linear_mipmap;

uniform float layer_z_index = 0.0;
uniform float cycle_opacity = 1.0;
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

	// 保留 CanvasGroup 原有的调制与透明度行为。
	COLOR *= color;
	COLOR.a *= cycle_opacity;
}
