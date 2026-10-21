shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D logo_texture : source_color, repeat_disable, filter_linear;
// 数据纹理不能使用 source_color / 有损压缩，RG 保存路径进度，B 保存向内距离 / 64。
uniform sampler2D stroke_texture : repeat_disable, filter_linear;
uniform vec4 background_color : source_color = vec4(0.105, 0.11, 0.125, 1.0);
uniform vec2 viewport_size = vec2(1920.0, 1080.0);
// Logo 的位置、尺寸共用一套坐标，白色剪影与原色不可能发生相对偏移。
uniform vec4 logo_rect = vec4(0.21875, 0.25, 0.5625, 0.5);
uniform float stroke_progress : hint_range(0.0, 1.0) = 0.0;
uniform float stroke_width_source = 13.333333;
uniform float fill_progress : hint_range(0.0, 1.0) = 0.0;
uniform float fill_wave_height = 0.005556;
uniform float logo_reveal_progress : hint_range(0.0, 1.0) = 0.0;
uniform float background_reveal_progress : hint_range(0.0, 1.0) = 0.0;
uniform float blur_lod : hint_range(0.0, 6.0) = 2.4;
uniform float logo_opacity : hint_range(0.0, 1.0) = 1.0;

float reveal_circle(vec2 point, float radius, float progress, float feather) {
	float edge = progress * (radius + feather * 2.0);
	return (1.0 - smoothstep(edge - feather, edge + feather, length(point)))
		* step(0.00001, progress);
}

void fragment() {
	vec2 logo_uv = (UV - logo_rect.xy) / max(logo_rect.zw, vec2(0.00001));
	float inside = step(0.0, logo_uv.x) * step(logo_uv.x, 1.0)
		* step(0.0, logo_uv.y) * step(logo_uv.y, 1.0);
	vec4 logo = texture(logo_texture, clamp(logo_uv, vec2(0.0), vec2(1.0)));
	logo.a *= inside;
	vec4 stroke_data = texture(stroke_texture, clamp(logo_uv, vec2(0.0), vec2(1.0)));
	float path_progress = dot(stroke_data.rg, vec2(65280.0, 255.0)) / 65535.0;
	float inward_distance = stroke_data.b * 64.0;
	float line_aa = max(fwidth(inward_distance), 0.25);
	float stroke = (1.0 - smoothstep(stroke_width_source - line_aa, stroke_width_source + line_aa, inward_distance))
		* stroke_data.a;
	float written = 1.0 - smoothstep(stroke_progress - 0.001, stroke_progress + 0.001, path_progress);
	written *= step(0.00001, stroke_progress);
	written = mix(written, 1.0, step(0.99999, stroke_progress));
	// 完整描边保留；内部由下往上填白，波幅在起止时归零，避免末尾留下缺口。
	float wave = (sin(logo_uv.x * TAU * 2.0 + TIME * 3.0)
		+ sin(logo_uv.x * TAU * 3.0 - TIME * 2.0) * 0.35)
		* fill_wave_height * sin(fill_progress * PI);
	float waterline = mix(1.01, -0.01, fill_progress) + wave;
	float water_aa = max(fwidth(logo_uv.y), 0.0001);
	float fill = smoothstep(waterline - water_aa, waterline + water_aa, logo_uv.y)
		* step(0.00001, fill_progress);
	float formed = max(stroke * written, fill);
	// 按像素距离生成圆，而不是直接使用 UV 距离，宽屏下也不会变成椭圆。
	float feather = max(1.0, min(viewport_size.x / 1920.0, viewport_size.y / 1080.0) * 2.0);
	vec2 logo_size = logo_rect.zw * viewport_size;
	float logo_circle = reveal_circle((logo_uv - vec2(0.5)) * logo_size,
		length(logo_size) * 0.5, logo_reveal_progress, feather);
	float background_circle = reveal_circle((UV - vec2(0.5)) * viewport_size,
		length(viewport_size) * 0.5, background_reveal_progress, feather);
	vec3 background = mix(background_color.rgb, textureLod(screen_texture, SCREEN_UV, blur_lod).rgb, background_circle);
	vec3 logo_color = mix(vec3(1.0), logo.rgb, logo_circle);
	COLOR = vec4(mix(background, logo_color, logo.a * formed * logo_opacity), 1.0);
}
