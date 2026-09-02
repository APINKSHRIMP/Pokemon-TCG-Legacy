shader_type canvas_item;

// ============================================================
// UI GRADIENT TEXT — "VS", "WIN", "LOSS" filled left to right
// ============================================================
// Godot cannot gradient-fill a Label, and a Label's UV is per-GLYPH-ATLAS, not
// per-control, so the usual `UV.x` trick paints each letter its own full ramp.
// The fix is a varying: VERTEX is in the control's own local space, so carrying
// it into fragment() gives a position across the WHOLE label to ramp against.
//
// `rect_w` must be the label's actual width in pixels. Set it after the label has
// been sized, not before — a zero width clamps every glyph to the first stop.
// ============================================================

uniform vec4  grad_a     : source_color = vec4(0.780, 0.608, 1.0, 1.0);
uniform vec4  grad_b     : source_color = vec4(1.0, 0.608, 0.839, 1.0);
uniform vec4  grad_c     : source_color = vec4(1.0, 0.753, 0.541, 1.0);
uniform float grad_b_pos = 0.5;
uniform float rect_w     = 200.0;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float t = clamp(local_pos.x / max(rect_w, 1.0), 0.0, 1.0);
	vec3 col = t < grad_b_pos
		? mix(grad_a.rgb, grad_b.rgb, t / max(grad_b_pos, 0.0001))
		: mix(grad_b.rgb, grad_c.rgb, (t - grad_b_pos) / max(1.0 - grad_b_pos, 0.0001));

	// The glyph's own alpha is all that is kept from the font atlas.
	COLOR = vec4(col, texture(TEXTURE, UV).a * COLOR.a);
}
