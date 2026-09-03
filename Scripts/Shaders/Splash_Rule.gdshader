shader_type canvas_item;

// ============================================================
// SPLASH RULE — one half of the horizontal line through the mark's gap
// ============================================================
// Two of these make the rule: a left segment and a right segment, each running
// OUTWARD from the TCG cap at the centre of the screen. `from_right` flips
// which end is the near one, so both segments share this shader.
//
// Three stops along the segment, measured from the near (TCG) end:
//   0%    col_near   fully opaque
//   45%   col_mid    the segment's own accent at 35% alpha
//   100%  col_mid    at zero alpha
//
// The gradient is in the node's LOCAL space, so it scales with the segment
// during the six-second growth rather than sliding through it. That is what
// makes the rule read as being drawn outward from the centre.
// ============================================================

uniform vec4  col_near : source_color = vec4(1.0, 0.435, 0.745, 1.0);
uniform vec4  col_mid  : source_color = vec4(0.910, 0.271, 0.608, 0.35);
uniform float mid_stop = 0.45;
uniform float radius   = 2.0;
uniform bool  from_right = false;
uniform vec2  rect_size  = vec2(700.0, 6.5);

void fragment() {
	vec2 p = UV * rect_size;

	// Distance along the segment from its near end, 0..1.
	float t = from_right ? (1.0 - UV.x) : UV.x;

	vec4 c;
	if (t < mid_stop) {
		c = mix(col_near, col_mid, t / mid_stop);
	} else {
		c = mix(col_mid, vec4(col_mid.rgb, 0.0), (t - mid_stop) / (1.0 - mid_stop));
	}

	// Rounded-rect coverage. Cheaper than a texture and it cannot be faceted by
	// the project's snap_2d_vertices_to_pixel, which is what rules StyleBoxFlat
	// out for small radii here.
	vec2  h  = rect_size * 0.5;
	vec2  d  = abs(p - h) - (h - vec2(radius));
	float sd = length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - radius;
	float w  = max(fwidth(sd) * 0.5, 0.0001);
	float mask = 1.0 - smoothstep(-w, w, sd);

	COLOR = vec4(c.rgb, c.a * mask);
}
