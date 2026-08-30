shader_type canvas_item;

// ============================================================
// UI SELECTION RING — the rotating gradient outline on a selected item
// ============================================================
// Applies to every selectable thing in the game: cards in a strip, collection
// tiles, shop items, deck cells, bench Pokemon.
//
// This is an ADDITION to the existing grow/shrink, not a replacement. The
// scale tween is how selection has always read in this game and it stays.
//
// ── HOW IT IS MOUNTED ────────────────────────────────────────
// A ColorRect sized a little LARGER than the item, sitting BEHIND it, so the
// ring straddles the item's edge and the item itself is never tinted. Crucially
// the ring must NOT be a child of the item — the selection tween scales the
// item, and a child ring would scale with it and grow thicker as it pulses.
// Mount it as a sibling on the same flat layer the shop price pills use.
//
// ── THE GRADIENT IS ANGULAR AND CYCLIC ───────────────────────
// The chrome gradient (purple -> pink -> orange) is mapped around the shape by
// angle rather than across it, and wraps back to purple, so there is no seam
// where the ramp restarts. angle_offset advances with TIME to spin it.
//
// ── REDUCED MOTION ───────────────────────────────────────────
// Set spin_speed to 0.0. The ring stays, it just holds still — the spec calls
// for a static gradient, not a missing outline.
// ============================================================

uniform vec4 grad_a : source_color = vec4(0.482, 0.247, 0.831, 1.0);  // 7B3FD4
uniform vec4 grad_b : source_color = vec4(0.910, 0.271, 0.608, 1.0);  // E8459B
uniform vec4 grad_c : source_color = vec4(0.961, 0.475, 0.231, 1.0);  // F5793B

uniform vec2  rect_size     = vec2(120.0, 160.0);
uniform float ring_width    = 4.0;    // px of ink
uniform float inset         = 4.0;    // px from the rect edge to the ring's centreline
uniform float corner_radius = 11.0;

// Radians per second. One revolution every 3s is TAU / 3 = 2.0944.
uniform float spin_speed = 2.0944;

// Signed distance to a rounded rect. 0 on the border, negative inside.
float rr(vec2 p, vec2 b, float r) {
	vec2 d = abs(p) - b + r;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - r;
}

void fragment() {
	vec2 p  = UV * rect_size;
	vec2 hs = rect_size * 0.5;

	// The ring's centreline sits `inset` in from the rect edge, so the rect
	// must be authored that much larger than the item on every side.
	vec2  b = max(hs - vec2(inset), vec2(0.001));
	float r = min(corner_radius, min(b.x, b.y));
	float sd = rr(p - hs, b, r);

	// Band of ink around sd == 0, antialiased by one pixel on each side.
	float half_w = ring_width * 0.5;
	float ink = 1.0 - smoothstep(half_w - 1.0, half_w + 1.0, abs(sd));

	// Angular position, normalised to 0..1 and advanced by TIME.
	vec2  v = p - hs;
	float ang = atan(v.y, v.x) + TIME * spin_speed;
	float t = fract(ang / 6.2831853);

	// Three-stop CYCLIC ramp: a -> b -> c -> a, one third each, so the wrap
	// point is the same colour on both sides and never shows as a hard edge.
	vec3 col;
	if (t < 0.3333333) {
		col = mix(grad_a.rgb, grad_b.rgb, t * 3.0);
	} else if (t < 0.6666667) {
		col = mix(grad_b.rgb, grad_c.rgb, (t - 0.3333333) * 3.0);
	} else {
		col = mix(grad_c.rgb, grad_a.rgb, (t - 0.6666667) * 3.0);
	}

	COLOR = vec4(col, ink);
}
