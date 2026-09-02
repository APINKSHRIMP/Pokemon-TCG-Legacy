shader_type canvas_item;

// ============================================================
// UI DIALOGUE PANEL — the message box, both variants, in one node
// ============================================================
// Replaces the old Rounded_Message_Panel edge-glow look for the PANEL only.
// Chips still use that shader; this one draws the box itself.
//
// ── THE RECT IS BIGGER THAN THE BOX ──────────────────────────
// The drop shadow and the outer glow fall OUTSIDE the panel, and a canvas_item
// shader cannot draw past its own rect. So the ColorRect is inflated by `pad`
// on all four sides and the panel body is inset by that much. If you move the
// box, move the inflated rect and leave `pad` alone.
//
// ── THE TWO VARIANTS ─────────────────────────────────────────
// Character (an NPC or opponent is speaking):
//     spine_w  = 8, spine_col = that speaker's colour
//     glow_col = the same colour, very low alpha
//     border   = flat white at 15%, skipped where the spine sits
// System (the game is speaking — every in-match message, gift notices):
//     spine_w  = 0
//     border_grad = 1, so all four edges take the theme gradient
//     top_strip_w = 5, a thicker gradient hairline along the top edge
//
// Everything else — fill, radius, shadow, padding — is shared. That is the
// whole point of one component with a speaker flag.
// ============================================================

uniform vec2  rect_size      = vec2(1828.0, 240.0);
uniform float pad            = 60.0;   // rect edge -> panel edge, room for shadow + glow
uniform float corner_radius  = 18.0;

uniform vec4  fill           : source_color = vec4(0.082, 0.055, 0.137, 0.94);

// Flat border. Ignored when border_grad is 1.
uniform vec4  border_col     : source_color = vec4(1.0, 1.0, 1.0, 0.15);
uniform float border_w       = 1.0;
uniform float border_grad    = 0.0;    // 1 = sample the three stops across the width

// The three theme stops, used by both the gradient border and the top strip.
uniform vec4  grad_a         : source_color = vec4(0.482, 0.247, 0.831, 1.0);
uniform vec4  grad_b         : source_color = vec4(0.910, 0.271, 0.608, 1.0);
uniform vec4  grad_c         : source_color = vec4(0.961, 0.475, 0.231, 1.0);
uniform float grad_b_pos     = 0.52;

uniform float top_strip_w    = 0.0;    // gradient hairline along the top edge

uniform float spine_w        = 0.0;    // solid colour bar down the left edge
uniform vec4  spine_col      : source_color = vec4(1.0, 0.5, 0.77, 1.0);

// Outer glow. `glow_spread` SHRINKS the glow shape before blurring, exactly as a
// negative CSS spread does — it is what keeps the halo tight enough to read as a
// suggestion of colour rather than an outline.
uniform vec4  glow_col       : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float glow_blur      = 42.0;
uniform float glow_spread    = 13.0;

uniform vec4  shadow_col     : source_color = vec4(0.0, 0.0, 0.0, 0.60);
uniform float shadow_dy      = 11.0;
uniform float shadow_blur    = 36.0;

// Signed distance to a rounded rect. 0 on the border, negative inside.
float rr(vec2 p, vec2 b, float r) {
	vec2 d = abs(p) - b + r;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - r;
}

// Straight source-over. Everything here composites back to front onto nothing,
// so the panel can sit over the overworld without punching a hole in it.
vec4 over(vec4 dst, vec4 src) {
	float a = src.a + dst.a * (1.0 - src.a);
	if (a <= 0.0001) {
		return vec4(0.0);
	}
	return vec4((src.rgb * src.a + dst.rgb * dst.a * (1.0 - src.a)) / a, a);
}

vec3 three_stop(float t) {
	return t < grad_b_pos
		? mix(grad_a.rgb, grad_b.rgb, t / max(grad_b_pos, 0.0001))
		: mix(grad_b.rgb, grad_c.rgb, (t - grad_b_pos) / max(1.0 - grad_b_pos, 0.0001));
}

void fragment() {
	vec2  p    = UV * rect_size;
	vec2  half = rect_size * 0.5;
	vec2  b    = max(half - vec2(pad), vec2(0.001));
	float r    = min(corner_radius, min(b.x, b.y));
	float sd   = rr(p - half, b, r);

	vec4 out_col = vec4(0.0);

	// ── Drop shadow, offset down ──
	float sd_sh = rr(p - half - vec2(0.0, shadow_dy), b, r);
	float a_sh  = shadow_col.a * (1.0 - smoothstep(-shadow_blur * 0.5, shadow_blur * 0.5, sd_sh));
	out_col = over(out_col, vec4(shadow_col.rgb, a_sh));

	// ── Outer glow in the speaker's colour ──
	float a_gl = glow_col.a * (1.0 - smoothstep(
		-glow_spread - glow_blur * 0.5, -glow_spread + glow_blur * 0.5, sd));
	out_col = over(out_col, vec4(glow_col.rgb, a_gl));

	// ── Panel body ──
	float cov = 1.0 - smoothstep(-0.75, 0.75, sd);
	out_col = over(out_col, vec4(fill.rgb, fill.a * cov));

	// The gradient runs across the PANEL, not the inflated rect, so the stops
	// land where the design put them regardless of how much padding is in play.
	float grad_t = clamp((p.x - pad) / max(rect_size.x - pad * 2.0, 1.0), 0.0, 1.0);
	vec3  edge_rgb = border_grad > 0.5 ? three_stop(grad_t) : border_col.rgb;
	float edge_a   = border_grad > 0.5 ? 1.0 : border_col.a;

	// ── Border ring, one width all the way round ──
	float ring = cov * smoothstep(-border_w - 0.75, -border_w + 0.75, sd);
	// The spine replaces the left border rather than sitting under it.
	if (spine_w > 0.0) {
		ring *= smoothstep(pad + spine_w - 0.75, pad + spine_w + 0.75, p.x);
	}
	out_col = over(out_col, vec4(edge_rgb, edge_a * ring));

	// ── Thicker gradient hairline along the top ──
	if (top_strip_w > 0.0) {
		float strip = cov * (1.0 - smoothstep(
			pad + top_strip_w - 0.75, pad + top_strip_w + 0.75, p.y));
		out_col = over(out_col, vec4(three_stop(grad_t), strip));
	}

	// ── Left spine ──
	if (spine_w > 0.0) {
		float sp = cov * (1.0 - smoothstep(pad + spine_w - 0.75, pad + spine_w + 0.75, p.x));
		out_col = over(out_col, vec4(spine_col.rgb, spine_col.a * sp));
	}

	COLOR = out_col;
}
