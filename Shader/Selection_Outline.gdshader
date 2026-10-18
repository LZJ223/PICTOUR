shader_type canvas_item;
render_mode unshaded;

// 描边作为独立副本绘制，不占用原物体材质，因此可与图层 CanvasGroup 滤镜并存。
global uniform vec4 render_selection_outline_color : source_color;
global uniform float render_selection_outline_width;

uniform bool selected = false;
uniform float cycle_opacity = 1.0;
uniform bool use_texture_alpha = false;
uniform bool rectangular_geometry = false;
// 子类已生成等距轮廓时，保留 Line2D 的几何与抗锯齿 Alpha。
uniform bool prepared_geometry = false;
uniform vec2 visual_center = vec2(0.0);
uniform vec2 outline_scale_compensation = vec2(1.0);
uniform vec4 source_uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform sampler2D source_texture : source_color, filter_linear, repeat_disable;
uniform vec2 source_texture_pixel_size = vec2(1.0);

const int OUTLINE_SAMPLE_COUNT = 16;
const float OUTLINE_TAU = 6.28318530718;

float source_alpha(vec2 uv) {
	vec2 uv_min = source_uv_rect.xy;
	vec2 uv_max = source_uv_rect.xy + source_uv_rect.zw;
	if (any(lessThan(uv, uv_min)) || any(greaterThan(uv, uv_max))) {
		return 0.0;
	}
	return texture(source_texture, uv).a;
}

void vertex() {
	if (!prepared_geometry && selected && render_selection_outline_width > 0.0) {
		vec2 delta = VERTEX - visual_center;
		vec2 direction = rectangular_geometry
			? sign(delta)
			: normalize(delta + vec2(0.00001));
		VERTEX += direction * render_selection_outline_width * outline_scale_compensation;
	}
}

void fragment() {
	if (!selected || render_selection_outline_width <= 0.0) {
		discard;
	}

	// 无贴图 Polygon2D 的副本本身就是扩张后的白色轮廓。
	if (prepared_geometry) {
		COLOR = vec4(render_selection_outline_color.rgb, render_selection_outline_color.a * COLOR.a);
	} else if (!use_texture_alpha) {
		COLOR = render_selection_outline_color;
	} else {
		// 扩张后的几何需要先把 UV 映射回原图，再从周围采样 Alpha。
		vec2 uv_margin = (
			render_selection_outline_width
			* outline_scale_compensation
			* source_texture_pixel_size
		);
		vec2 normalized_uv = (UV - source_uv_rect.xy) / source_uv_rect.zw;
		vec2 mapped_uv = (
			source_uv_rect.xy
			+ normalized_uv * (source_uv_rect.zw + uv_margin * 2.0)
			- uv_margin
		);
		float center_alpha = source_alpha(mapped_uv);
		float surrounding_alpha = 0.0;
		for (int index = 0; index < OUTLINE_SAMPLE_COUNT; index++) {
			float angle = OUTLINE_TAU * float(index) / float(OUTLINE_SAMPLE_COUNT);
			vec2 direction = vec2(cos(angle), sin(angle));
			surrounding_alpha = max(
				surrounding_alpha,
				source_alpha(mapped_uv + direction * uv_margin)
			);
		}
		float outline_alpha = max(surrounding_alpha - center_alpha, 0.0);
		if (outline_alpha <= 0.0001) {
			discard;
		}
		COLOR = vec4(
			render_selection_outline_color.rgb,
			render_selection_outline_color.a * outline_alpha
		);
	}
	COLOR.a *= cycle_opacity;
}
