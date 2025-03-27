shader_type spatial;
render_mode depth_draw_never;

void fragment() {
	ALBEDO = COLOR.rgb;
}