shader_type canvas_item;

// ============================================================
// ROUNDED MESSAGE PANEL
// ============================================================
// One shader drives every piece of the dynamic message box:
//
//   Main panel — white fill with a coloured band hugging the border that
//                drops off sharply to white, so body text never sits on
//                colour.
//
//   Chip       — a solid pill. Same shader with the bands set huge, so the
//                falloff never begins and the whole rect is edge colour.
//
// edge_solid / edge_fade are vec2 and DELIBERATELY not square: .x governs the
// left and right edges, .y the top and bottom. The reference design has a wide
// colour band down each side but only a hairline along the top and bottom —
// a uniform inset would eat most of a short, wide panel and leave barely any
// white for the text to sit on.
//
// color_left / color_right give every rect a subtle horizontal gradient.
// Chips use it to shade a little toward the neighbour on each side; the main
// panel normally passes the same colour twice.
//
// rect_size MUST be kept in sync with the node's pixel size — the maths works
// in pixels so the radius and bands stay resolution-honest instead of
// stretching with the rect.
// ============================================================

uniform vec4  color_left    : source_color = vec4(0.459, 0.596, 0.984, 1.0);
uniform vec4  color_right   : source_color = vec4(0.459, 0.596, 0.984, 1.0);
uniform vec4  fill_color    : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec2  rect_size     = vec2(100.0, 100.0);
uniform float corner_radius = 24.0;
uniform vec2  edge_solid    = vec2(26.0, 2.0);   // px of pure colour: x = sides, y = top/bottom
uniform vec2  edge_fade     = vec2(12.0, 4.0);   // px each band takes to reach fill_color

void fragment() {
	vec2 p  = UV * rect_size;
	vec2 hs = rect_size * 0.5;

	// Signed distance to a rounded rect: 0 on the border, negative inside.
	// The radius is clamped so a short rect degrades to a pill rather than
	// folding in on itself. Used for the silhouette and its antialiasing.
	float r = min(corner_radius, min(hs.x, hs.y));
	vec2  d = abs(p - hs) - (hs - r);
	float sd = length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - r;
	float inside = 1.0 - smoothstep(-0.75, 0.75, sd);

	// How far in from the nearest edge we are, per axis.
	vec2 inset = min(p, rect_size - p);
	float tx = 1.0 - smoothstep(edge_solid.x, edge_solid.x + edge_fade.x, inset.x);
	float ty = 1.0 - smoothstep(edge_solid.y, edge_solid.y + edge_fade.y, inset.y);
	// max() so the corners, which are inside both bands, stay fully coloured.
	float t = max(tx, ty);

	vec4 edge = mix(color_left, color_right, UV.x);
	vec4 col  = mix(fill_color, edge, t);

	COLOR = vec4(col.rgb, col.a * inside);
}
