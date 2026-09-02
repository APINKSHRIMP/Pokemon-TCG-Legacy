shader_type canvas_item;

// ============================================================
// UI BATTLE BAND — the slanted gradient bands on the intro / outro screens
// ============================================================
// One node per band. The gradient is the outcome's three stops (theme purple for
// the intro, green for a win, red for a loss); the slant is a straight cut across
// the rect, antialiased in pixels rather than UV so both bands cut at the same
// visual sharpness whatever height they are given.
//
// ── WHY THE BANDS OVERHANG THE SCREEN ────────────────────────
// Each band is authored TALLER than its 21.5% and pushed off the top or bottom
// edge, because the entrance animation slides it further in the direction it
// already travelled. Without the overhang the second, slow phase would drag the
// band's far edge into view and open a gap at the screen edge. The overhang is
// the caller's job (see Battle_Frame.gd BAND_OVERHANG); this shader only knows
// how to cut a slanted edge.
//
// ── THE CUT ──────────────────────────────────────────────────
// `cut_start` and `cut_end` are the cut's height as a fraction of the rect, at
// the LEFT and RIGHT edges. `keep_below` picks which side survives:
//     top band     cut_start 1.00, cut_end 0.66, keep_below 0  (keep above)
//     bottom band  cut_start 0.34, cut_end 0.00, keep_below 1  (keep below)
// ============================================================

uniform vec4  grad_a     : source_color = vec4(0.482, 0.247, 0.831, 1.0);
uniform vec4  grad_b     : source_color = vec4(0.910, 0.271, 0.608, 1.0);
uniform vec4  grad_c     : source_color = vec4(0.961, 0.475, 0.231, 1.0);
uniform float grad_b_pos = 0.52;

uniform vec2  rect_size  = vec2(1920.0, 270.0);
uniform float cut_start  = 1.0;
uniform float cut_end    = 0.66;
uniform float keep_below = 0.0;

void fragment() {
	float t = UV.x;
	vec3 grad = t < grad_b_pos
		? mix(grad_a.rgb, grad_b.rgb, t / max(grad_b_pos, 0.0001))
		: mix(grad_b.rgb, grad_c.rgb, (t - grad_b_pos) / max(1.0 - grad_b_pos, 0.0001));

	// The cut line, and this pixel's distance from it — in PIXELS, so a one-pixel
	// smoothstep is genuinely one pixel however tall the band is.
	float limit = mix(cut_start, cut_end, UV.x) * rect_size.y;
	float d = (UV.y * rect_size.y) - limit;
	float alpha = keep_below > 0.5
		? smoothstep(-1.0, 1.0, d)
		: 1.0 - smoothstep(-1.0, 1.0, d);

	COLOR = vec4(grad, alpha);
}
