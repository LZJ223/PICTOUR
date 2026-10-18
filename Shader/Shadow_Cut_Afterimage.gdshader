shader_type canvas_item;
render_mode unshaded;

uniform sampler2D retained_appearance : repeat_disable, filter_linear;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 old = texture(TEXTURE, UV);
	float retained = texture(retained_appearance, UV).a;
	// 反解 Alpha 叠加：残影 + 碎片在首帧保持旧覆盖率，半透明保留区域不重复叠加。
	float removed = clamp((old.a - retained) / max(1.0 - retained, 0.0001), 0.0, 1.0);
	vec3 color = old.rgb / max(old.a, 0.0001);
	COLOR = vec4(color, removed * (1.0 - smoothstep(0.0, 1.0, progress))) * tint;
}
