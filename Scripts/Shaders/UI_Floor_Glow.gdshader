shader_type canvas_item;

// ============================================================
// UI FLOOR GLOW - the soft pad each trainer stands on
// ============================================================
// A blurred ellipse in that side's accent colour, sitting under the sprite's
// feet. Drawn rather than baked so the two sides can differ by one uniform.
//
// THE NODE MUST BE A CHILD OF THE SPRITE'S DRIFT WRAPPER, not of the screen.
// The entrance moves each trainer twice, and a glow parented to the stage would
// stay put while the sprite slid off it - which makes the trainer look like they
// are skating rather than walking.
//
// The falloff is a smoothstep on the normalised radius rather than a true
// gaussian: at this size the two are indistinguishable and this one is cheap.
// `softness` is the fraction of the radius the fade occupies.
// ============================================================

uniform vec4  glow_col : source_color = vec4(0.780, 0.608, 1.0, 0.55);
uniform float softness : hint_range(0.05, 1.0) = 0.62;

void fragment() {
	// Distance from the centre in units where the ellipse's edge is 1.0.
	vec2 d = (UV - vec2(0.5)) * 2.0;
	float r = length(d);
	float a = 1.0 - smoothstep(1.0 - softness, 1.0, r);
	COLOR = vec4(glow_col.rgb, glow_col.a * a);
}
