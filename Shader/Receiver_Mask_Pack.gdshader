shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D receiver_0 : repeat_disable, filter_linear;
uniform sampler2D receiver_1 : repeat_disable, filter_linear;
uniform sampler2D receiver_2 : repeat_disable, filter_linear;
uniform sampler2D receiver_3 : repeat_disable, filter_linear;
uniform vec4 active_layers = vec4(0.0);
uniform vec4 layer_opacity = vec4(1.0);

void fragment() {
	vec4 coverage = vec4(textureLod(receiver_0, UV, 0.0).a,
		textureLod(receiver_1, UV, 0.0).a,
		textureLod(receiver_2, UV, 0.0).a,
		textureLod(receiver_3, UV, 0.0).a);
	// 原影子已经包含换层透明度；这里仅保留实体自身的视觉覆盖。
	COLOR = clamp(coverage / max(layer_opacity, vec4(0.0001)), vec4(0.0), vec4(1.0)) * active_layers;
}
