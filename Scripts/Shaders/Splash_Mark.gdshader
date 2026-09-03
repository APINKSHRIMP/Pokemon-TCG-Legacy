shader_type canvas_item;

// ============================================================
// SPLASH MARK — the two-armed chevron on the boot splash
// ============================================================
// Drawn analytically rather than as a sprite so it stays crisp at any scale.
// The mark grows from 0.52 to 1.0 over the six-second load; a bitmap would be
// resampled the whole way, and the arms are flat gradients with hard edges,
// which is exactly the case an SDF wins.
//
// ── THE DESIGN SPACE IS 100 WIDE x 200 TALL ──────────────────
// Every constant below is in that space and UV is mapped onto it, so the
// numbers here read the same as the ones in the spec. The node's own rect
// (346 x 691 at full growth) does the scaling.
//
//   Upper arm:  (0, 0)   -> (100, 92)  -> (INNER, 92)  -> (0, 60)
//   Lower arm:  (0, 200) -> (100, 108) -> (INNER, 108) -> (0, 140)
//
// The lower arm is the upper one mirrored about y = 100, so it is drawn by
// flipping the sample point rather than by a second set of vertices.
//
// ── INNER IS DERIVED, NOT EYEBALLED ──────────────────────────
// INNER = 100 * (tip - thickness) / tip keeps each arm's inner edge PARALLEL
// to its outer edge, which is what makes the bar an even thickness along its
// whole length. Change gap_half or thickness and it recomputes; hand-set it
// and the arms taper into triangles.
// ============================================================

uniform vec4 upper_a : source_color = vec4(0.482, 0.247, 0.831, 1.0);  // 7B3FD4
uniform vec4 upper_b : source_color = vec4(0.910, 0.271, 0.608, 1.0);  // E8459B
uniform vec4 lower_a : source_color = vec4(0.910, 0.271, 0.608, 1.0);  // E8459B
uniform vec4 lower_b : source_color = vec4(0.961, 0.475, 0.231, 1.0);  // F5793B

// TWEAKABLE — the gap between the two tips is 2 x gap_half; thickness is the
// arm's vertical depth at the left edge. Both in design units.
uniform float gap_half  = 8.0;
uniform float thickness = 60.0;

const vec2 DESIGN = vec2(100.0, 200.0);

// Signed distance from a point to the line through v0 -> v1. Positive on the
// left of the edge, which is the inside for this winding.
float edge_dist(vec2 p, vec2 v0, vec2 v1) {
	vec2 e = v1 - v0;
	return (e.x * (p.y - v0.y) - e.y * (p.x - v0.x)) / length(e);
}

// Coverage of the convex quad A-B-C-D at p, antialiased by the screen-space
// derivative so the edge stays one pixel wide whatever the node is scaled to.
float arm_alpha(vec2 p, vec2 A, vec2 B, vec2 C, vec2 D) {
	float d = min(min(edge_dist(p, A, B), edge_dist(p, B, C)),
	              min(edge_dist(p, C, D), edge_dist(p, D, A)));
	float w = max(length(vec2(dFdx(d), dFdy(d))) * 0.5, 0.0001);
	return smoothstep(-w, w, d);
}

// Alpha-over: s composited on top of d.
vec4 over(vec4 s, vec4 d) {
	float a = s.a + d.a * (1.0 - s.a);
	if (a <= 0.0) {
		return vec4(0.0);
	}
	return vec4((s.rgb * s.a + d.rgb * d.a * (1.0 - s.a)) / a, a);
}

void fragment() {
	vec2 p = UV * DESIGN;
	vec2 q = vec2(p.x, DESIGN.y - p.y);   // the lower arm, mirrored into the upper one's space

	float tip   = DESIGN.y * 0.5 - gap_half;
	float inner = DESIGN.x * (tip - thickness) / tip;

	vec2 A = vec2(0.0, 0.0);
	vec2 B = vec2(DESIGN.x, tip);
	vec2 C = vec2(inner, tip);
	vec2 D = vec2(0.0, thickness);

	// Gradient axis runs A -> B: the arm's top-left corner to its outer tip.
	vec2  ax  = B - A;
	float len = dot(ax, ax);
	float tu  = clamp(dot(p - A, ax) / len, 0.0, 1.0);
	float tl  = clamp(dot(q - A, ax) / len, 0.0, 1.0);

	// Lower arm reads top-RIGHT to bottom-LEFT, which is B -> A in mirrored space.
	vec4 cu = vec4(mix(upper_a.rgb, upper_b.rgb, tu), arm_alpha(p, A, B, C, D));
	vec4 cl = vec4(mix(lower_a.rgb, lower_b.rgb, 1.0 - tl), arm_alpha(q, A, B, C, D));

	COLOR = over(cu, cl);
}
