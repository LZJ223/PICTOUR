shader_type canvas_item;
render_mode unshaded;

global uniform sampler2D render_receiver_mask : repeat_disable, filter_nearest;
uniform int layer_id = 3;

void fragment() {
	float coverage = textureLod(render_receiver_mask, UV, 0.0)[layer_id];
	COLOR = vec4(vec3(coverage), 1.0);
}
