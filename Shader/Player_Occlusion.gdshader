shader_type canvas_item;
render_mode unshaded;

uniform sampler2D player_mask : repeat_disable, filter_linear;
uniform sampler2D player_front : repeat_disable, filter_linear;
uniform sampler2D body_mask : repeat_disable, filter_linear;
uniform sampler2D body_front : repeat_disable, filter_linear;
uniform sampler2D body_same_layer : repeat_disable, filter_linear;
uniform vec4 xray_color : source_color = vec4(0.48, 0.56, 0.64, 0.6);
uniform bool player_active = false;
uniform bool body_active = false;
uniform bool has_player = false;
uniform bool has_body = false;
uniform bool has_body_front = false;
uniform bool has_same_layer = false;
uniform bool body_in_front = false;
uniform float body_opacity = 1.0;

void fragment() {
	float player = has_player ? texture(player_mask, SCREEN_UV).a : 0.0;
	float body = has_body ? texture(body_mask, SCREEN_UV).a : 0.0;
	float player_covered = player_active ? player * texture(player_front, SCREEN_UV).a : 0.0;
	float body_covered = 0.0;
	if (body_active) {
		float front = has_body_front ? texture(body_front, SCREEN_UV).a : 0.0;
		// 同层只应用一次统一淡出系数，避免身体和遮挡物分别淡出造成透明度平方。
		float same_layer = has_same_layer
			? clamp(texture(body_same_layer, SCREEN_UV).a / max(body_opacity, 0.0001), 0.0, 1.0)
			: 0.0;
		body_covered = body * (1.0 - (1.0 - front) * (1.0 - same_layer));
	}
	if (body_in_front) {
		player_covered *= 1.0 - body;
	} else {
		body_covered *= 1.0 - player;
	}
	float coverage = 1.0 - (1.0 - player_covered) * (1.0 - body_covered);
	COLOR = vec4(xray_color.rgb, coverage * xray_color.a);
}
