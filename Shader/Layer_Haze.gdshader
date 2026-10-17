shader_type canvas_item;
render_mode unshaded;

global uniform sampler2D render_haze_texture : source_color, repeat_disable, filter_linear_mipmap;
global uniform float render_haze_opacity;
global uniform float render_haze_world_scale;
global uniform float render_haze_bottom_y;
global uniform float render_haze_speed;
global uniform float render_haze_layer_offset;
global uniform float render_haze_blur_step;
global uniform float render_haze_maximum_blur_lod;

uniform float layer_z_index = 0.0;
uniform bool is_night = false;
uniform float cycle_opacity = 1.0;
uniform float layer_id = 0.0;
uniform float layer_scale = 0.8;
uniform vec2 anchor_position = vec2(0.0);
uniform vec2 visual_offset = vec2(0.0);
uniform mat3 world_to_space = mat3(1.0);
uniform float scroll_offset = 0.0;

const float LAYER_Z_INDEX_STEP = 100.0;
const float MINIMUM_SCALE = 0.0001;

varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float depth = max(-layer_z_index / LAYER_Z_INDEX_STEP, 0.0);
	float blur_lod = min(
		depth * render_haze_blur_step,
		render_haze_maximum_blur_lod
	);
	float perspective_scale = pow(max(layer_scale, MINIMUM_SCALE), depth);
	vec2 space_position = (world_to_space * vec3(world_position, 1.0)).xy;
	vec2 space_anchor = (world_to_space * vec3(anchor_position, 1.0)).xy;
	vec2 space_offset = (world_to_space * vec3(visual_offset, 0.0)).xy;
	vec2 physical_position = space_anchor
		+ (space_position - space_offset - space_anchor) / perspective_scale;
	physical_position.x += scroll_offset;
	vec2 texture_world_size = vec2(textureSize(render_haze_texture, 0))
		* max(render_haze_world_scale, MINIMUM_SCALE);
	float texture_top = render_haze_bottom_y - texture_world_size.y;
	vec2 haze_uv = vec2(
		fract(
			(
				physical_position.x
				- TIME * render_haze_speed
				+ layer_id * render_haze_layer_offset
			) / texture_world_size.x
		),
		clamp(
			(physical_position.y - texture_top) / texture_world_size.y,
			0.0,
			1.0
		)
	);
	vec4 haze = textureLod(render_haze_texture, haze_uv, blur_lod);
	if (is_night) { haze.rgb = vec3(0.0); }
	haze.a *= render_haze_opacity * clamp(depth, 0.0, 1.0) * cycle_opacity;
	COLOR = haze;
}
