shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_disabled;

group_uniforms general;
	uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
	uniform sampler2D action: filter_linear;
	uniform float position_scale: hint_range(1.0, 10.0, 0.1) = 0.0;

group_uniforms effect;
	varying float gray_flick;

void vertex() {
	vec2 _action_size = vec2(textureSize(action, 0));
	float _i_pixel_size = 1.0 / _action_size.x;
	float _f_pixel_size = 1.0 / _action_size.y;

	float _action_frame = INSTANCE_CUSTOM.r;
	vec2 _uv_p = vec2(UV2.x + _i_pixel_size * 0.5, -((_action_frame + 0.5) * _f_pixel_size));
	vec2 _uv_n = vec2(_uv_p.x, _uv_p.y - _action_size.y * 0.5 * _f_pixel_size);
	vec3 _position = texture(action, _uv_p).xyz;
	vec3 _normal = texture(action, _uv_n).xyz;

	vec3 _position_new = vec3(
		position_scale * (_position.x * 2.0 - 1.0),
		position_scale * (_position.z * 2.0 - 1.0),
		position_scale * (_position.y * -2.0 + 1.0)
	);
	vec3 _normal_new = vec3(
		_normal.x * 2.0 - 1.0,
		_normal.z * 2.0 - 1.0,
		_normal.y * -2.0 + 1.0
	);
	VERTEX = _position_new;
	NORMAL = _normal_new;
	UV.x += INSTANCE_CUSTOM.g;
	gray_flick = INSTANCE_CUSTOM.b;
}

void fragment() {
	vec4 _albedo_tex = texture(texture_albedo, UV);
	vec3 _gray_color = vec3(0.299 * _albedo_tex.r + 0.587 * _albedo_tex.g + 0.114 * _albedo_tex.b);
	// combine grayscale toggle and hit flick value into 1 float
	float _gray = trunc(gray_flick);
	float _flick = fract(gray_flick);
	vec3 _color = mix(_albedo_tex.rgb, _gray_color, _gray);
	ALBEDO = _color + _flick;
}