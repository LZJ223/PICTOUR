shader_type canvas_item;
render_mode unshaded, skip_vertex_transform;

global uniform vec2 render_shadow_anchor;
global uniform vec4 render_shadow_layer_scales;
global uniform vec3 render_shadow_screen_x;
global uniform vec3 render_shadow_screen_y;
global uniform vec2 render_shadow_view_size;
global uniform vec2 render_shadow_tile_size;

uniform int receiver_id = 0;
uniform vec2 receiver_offset = vec2(0.0);
varying flat vec2 tile_origin;

void vertex() {
	vec2 physical = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	vec2 projected = render_shadow_anchor
		+ (physical - render_shadow_anchor) * render_shadow_layer_scales[receiver_id];
	vec2 screen = vec2(dot(render_shadow_screen_x, vec3(projected, 1.0)),
		dot(render_shadow_screen_y, vec3(projected, 1.0))) + receiver_offset;
	tile_origin = vec2(float(receiver_id % 2), float(receiver_id / 2)) * render_shadow_tile_size;
	VERTEX = screen / render_shadow_view_size * render_shadow_tile_size + tile_origin;
}

void fragment() {
	vec2 local_pixel = FRAGCOORD.xy - tile_origin;
	if (any(lessThan(local_pixel, vec2(0.0))) || any(greaterThanEqual(local_pixel, render_shadow_tile_size))) {
		discard;
	}
	COLOR = vec4(1.0);
}
