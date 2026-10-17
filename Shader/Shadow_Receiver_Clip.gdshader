shader_type canvas_item;
render_mode unshaded;

global uniform sampler2D render_receiver_mask : repeat_disable, filter_linear;
global uniform bool render_receiver_mask_enabled;
global uniform int render_receiver_mask_debug;
uniform int receiver_layer_id = 0;

void fragment() {
	if (!render_receiver_mask_enabled) { discard; }
	float coverage = 1.0;
	if (render_receiver_mask_debug != 1) {
		coverage = textureLod(render_receiver_mask, SCREEN_UV, 0.0)[receiver_layer_id];
	}
	// 保留原来的影子透明度与换层动画，覆盖内部输出纯黑。
	COLOR = vec4(0.0, 0.0, 0.0, COLOR.a * coverage);
}
