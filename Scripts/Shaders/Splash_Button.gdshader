shader_type canvas_item;

// ============================================================
// SPLASH BUTTON FACE — the two menu buttons on the boot splash
// ============================================================
// The splash buttons are NOT the game's standard buttons: the spec gives them
// their own radius (12 against the game's 22), their own type size (29 against
// 17) and their own fills, so they cannot take the baked ui_*.tres faces.
//
// They are drawn instead of baked because a baked 9-patch would have to be
// regenerated for this one screen's radius, and instead of StyleBoxFlat because
// the project sets snap_2d_vertices_to_pixel, which facets a small rounded
// corner (see the note at the top of Build_UI_Themes.gd).
//
// The Button itself sits on top of this rect with an empty stylebox and does
// nothing but take the click and draw its label. `state_tint` is how hover and
// press reach the face — composited OVER the fill rather than multiplied into
// it, so it moves the alpha too and therefore works on the New Game button's
// 8%-white fill as well as on Continue Game's opaque gradient.
// ============================================================

uniform vec4  fill_top   : source_color = vec4(1.0, 1.0, 1.0, 0.08);
uniform vec4  fill_bot   : source_color = vec4(1.0, 1.0, 1.0, 0.08);
uniform vec4  edge_col   : source_color = vec4(0.0, 0.0, 0.0, 0.30);
uniform vec4  state_tint : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float radius = 12.0;
uniform float edge_h = 4.6;
uniform vec2  rect_size = vec2(300.0, 73.0);

vec4 over(vec4 s, vec4 d) {
	float a = s.a + d.a * (1.0 - s.a);
	if (a <= 0.0) {
		return vec4(0.0);
	}
	return vec4((s.rgb * s.a + d.rgb * d.a * (1.0 - s.a)) / a, a);
}

void fragment() {
	vec2 p = UV * rect_size;

	vec4 c = mix(fill_top, fill_bot, UV.y);

	// The inset bottom edge. Half a pixel of feather so it does not crawl.
	float e = smoothstep(rect_size.y - edge_h - 0.5, rect_size.y - edge_h + 0.5, p.y);
	c = mix(c, over(edge_col, c), e);

	c = over(state_tint, c);

	vec2  h  = rect_size * 0.5;
	vec2  d  = abs(p - h) - (h - vec2(radius));
	float sd = length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - radius;
	float w  = max(fwidth(sd) * 0.5, 0.0001);
	float mask = 1.0 - smoothstep(-w, w, sd);

	COLOR = vec4(c.rgb, c.a * mask);
}
