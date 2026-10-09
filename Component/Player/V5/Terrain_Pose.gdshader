shader_type canvas_item;
render_mode unshaded;

uniform vec4 previous_shape = vec4(0.0);
uniform vec4 current_shape = vec4(0.0);
uniform vec2 foot_x = vec2(-12.0, 12.0);
uniform float facing = 1.0;
uniform float interpolation = 1.0;

void vertex() {
	vec4 shape = mix(previous_shape, current_shape, interpolation);
	vec2 p = VERTEX;
	p.x *= facing;
	float gap = max(foot_x.y - foot_x.x, 1.0);
	float side = clamp((p.x - foot_x.x) / gap, 0.0, 1.0);
	float lower_leg = smoothstep(-37.0, -2.0, p.y);
	p.y += mix(shape.x, shape.y, side) * lower_leg + shape.z;
	// 倾身只作用于腰以上，双脚与腿不会绕整个人物根节点旋转。
	p.x += shape.w * max(-VERTEX.y - 36.0, 0.0);
	VERTEX = p;
}
