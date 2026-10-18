shader_type canvas_item;
render_mode unshaded;

global uniform bool render_receiver_mask_enabled;
global uniform int render_receiver_mask_debug;
uniform int receiver_layer_id = 0;

void fragment() {
	// 正常模式由承影层自身合成黑色；原节点只在“完整影子”调试模式直接绘制。
	if (!render_receiver_mask_enabled || render_receiver_mask_debug != 1) { discard; }
	COLOR = vec4(0.0, 0.0, 0.0, COLOR.a);
}
