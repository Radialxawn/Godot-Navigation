shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_disabled;

varying vec4 instance_custom;

void vertex() {
	instance_custom = INSTANCE_CUSTOM;
}

void fragment() {
	ALBEDO = COLOR.rgb;
}
