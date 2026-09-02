shader_type canvas_item;

// ============================================================
// UI ROUND DISC - the filled chip inside a best-of-three round slot
// ============================================================
// A circle carrying a three-stop diagonal gradient with a soft highlight in its
// upper left, so a Win or Loss chip reads as an object with a light on it rather
// than a flat coloured dot.
//
// Sits INSIDE the slot's ring, inset by DISC_INSET, which is why this draws only
// the disc and knows nothing about the ring around it.
// ============================================================

uniform vec4  grad_a     : source_color = vec4(0.090, 0.655, 0.576, 1.0);
uniform vec4  grad_b     : source_color = vec4(0.125, 0.624, 0.298, 1.0);
uniform vec4  grad_c     : source_color = vec4(0.431, 0.620, 0.071, 1.0);
uniform float grad_b_pos = 0.55;
// The gradient's direction, in degrees clockwise from straight down.
uniform float angle_deg  = 160.0;

// The highlight: a soft radial wash centred toward the upper left.
uniform vec4  sheen_col  : source_color = vec4(1.0, 1.0, 1.0, 0.22);
uniform vec2  sheen_at   = vec2(0.34, 0.28);
uniform float sheen_r    = 0.58;

void fragment() {
	vec2 p = UV - vec2(0.5);
	float r = length(p) * 2.0;

	// Projection onto the gradient's axis, remapped to 0..1 across the disc.
	float a = radians(angle_deg);
	vec2  dir = vec2(sin(a), cos(a));
	float t = clamp(dot(UV - vec2(0.5), dir) + 0.5, 0.0, 1.0);

	vec3 col = t < grad_b_pos
		? mix(grad_a.rgb, grad_b.rgb, t / max(grad_b_pos, 0.0001))
		: mix(grad_b.rgb, grad_c.rgb, (t - grad_b_pos) / max(1.0 - grad_b_pos, 0.0001));

	float sheen = 1.0 - smoothstep(0.0, sheen_r, distance(UV, sheen_at));
	col = mix(col, sheen_col.rgb, sheen * sheen_col.a);

	// Circular silhouette, antialiased by one pixel of the normalised radius.
	float aa = fwidth(r) * 1.5;
	float alpha = 1.0 - smoothstep(1.0 - aa, 1.0, r);

	COLOR = vec4(col, alpha);
}
