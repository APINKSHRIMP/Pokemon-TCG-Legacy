shader_type canvas_item;

// ============================================================
// UI SLOT — an empty position: outline plus a faint fill
// ============================================================
// Empty bench positions, empty deck-builder cells, empty discard piles and
// unowned collection tiles. A slot the player can see is progress; the black
// rectangles this replaces just looked like a bug.
//
// ── WHY THIS IS A SHADER AND NOT A StyleBoxFlat ──────────────
// StyleBoxFlat draws its rounded corners as four arcs of real geometry. At a
// FULL-PILL radius — which a circular coin slot needs — those arcs meet exactly
// at the midpoint of each edge, and the antialiasing of the two arcs meeting
// there blends twice over the same pixels. The result was four bright white
// dots at dead north, east, south and west of every empty coin.
//
// The project also sets `2d/snap/snap_2d_vertices_to_pixel = true` for the
// pixel-art overworld, which snaps those arc vertices to whole pixels and
// facets the curve on top of it. Both problems are geometry problems, so the
// slot stops being geometry: one quad, one signed-distance field, no seams and
// no vertices to snap. Same reasoning as the baked button faces.
//
// corner_radius is clamped to half the short edge, so passing anything large
// (or just 9999) gives a perfect circle on a square rect.
// ============================================================

uniform vec4  fill_color    : source_color = vec4(1.0, 1.0, 1.0, 0.03);
uniform vec4  outline_color : source_color = vec4(1.0, 1.0, 1.0, 0.16);
uniform vec2  rect_size     = vec2(100.0, 100.0);
uniform float corner_radius = 7.0;
uniform float outline_px    = 3.0;

// Signed distance to a rounded rect. 0 on the border, negative inside.
// Matches the rr() in UI_Selection_Ring.gdshader and the GDScript copy in
// Build_UI_Themes, so every rounded shape in the UI agrees.
float rr(vec2 p, vec2 b, float r) {
	vec2 d = abs(p) - b + r;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - r;
}

void fragment() {
	vec2  p  = UV * rect_size;
	vec2  hs = rect_size * 0.5;
	float r  = min(corner_radius, min(hs.x, hs.y));
	float sd = rr(p - hs, hs, r);

	// 1 inside the shape, 0 outside, one pixel of falloff across the border.
	float inside = 1.0 - smoothstep(-0.5, 0.5, sd);

	// The outline is the band from `outline_px` inside the border to the border
	// itself. Feathered on the inner edge only — the outer edge is already
	// feathered by `inside`, and feathering both would halve the ink.
	float ring = smoothstep(-outline_px - 0.5, -outline_px + 0.5, sd);

	vec3  col = mix(fill_color.rgb, outline_color.rgb, ring);
	float a   = mix(fill_color.a, outline_color.a, ring) * inside;

	COLOR = vec4(col, a);
}
