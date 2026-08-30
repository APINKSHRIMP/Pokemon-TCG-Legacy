shader_type canvas_item;

// ============================================================
// UI FIELD — the play area / content background
// ============================================================
// The dark ground every screen sits on: a base fill, four soft radial glows
// that keep it from reading as flat black, and the counter-scrolling chevron
// texture. Replaces the white and light-blue-dot backgrounds.
//
// One node, one draw. The glows are ellipses in UV space (they are meant to
// stretch with the screen, unlike the stripes, which are pixel-locked) and are
// composited in the order the design layers them:
//
//     base  ->  left wash  ->  right wash  ->  top tint  ->  bottom tint
//
// The two washes are OPAQUE colours fading to nothing, so they recolour large
// areas; the two tints are low-alpha accent colours that only warm the edges.
// Getting that order wrong makes the field muddy rather than deep.
//
// Counter-scrolling is deliberate: this scrolls LEFT while the chrome bars
// scroll RIGHT, which is what stops a static board feeling dead. Set
// scroll_speed to 0.0 for reduced motion.
// ============================================================

uniform vec4 base_color : source_color = vec4(0.090, 0.067, 0.149, 1.0);   // 171126

// Washes — opaque at the centre, gone by the edge of their ellipse.
uniform vec4  wash_left        : source_color = vec4(0.141, 0.090, 0.251, 1.0);  // 241740
uniform vec2  wash_left_centre  = vec2(0.20, 0.30);
uniform vec2  wash_left_radius  = vec2(0.95, 0.80);
uniform vec4  wash_right       : source_color = vec4(0.227, 0.082, 0.200, 1.0);  // 3A1533
uniform vec2  wash_right_centre = vec2(0.88, 0.80);
uniform vec2  wash_right_radius = vec2(0.95, 0.80);

// Tints — carry their own low alpha, and sit mostly OFF-SCREEN (centre y of
// -0.10 and 1.12) so only the falloff is visible along the top and bottom.
uniform vec4  tint_top        : source_color = vec4(0.910, 0.271, 0.608, 0.18);  // E8459B 18%
uniform vec2  tint_top_centre  = vec2(0.50, -0.10);
uniform vec2  tint_top_radius  = vec2(1.05, 0.80);
uniform vec4  tint_bottom     : source_color = vec4(0.961, 0.475, 0.231, 0.16);  // F5793B 16%
uniform vec2  tint_bottom_centre = vec2(0.50, 1.12);
uniform vec2  tint_bottom_radius = vec2(1.05, 0.80);

// Chevrons — larger and slower than the bars' so the two layers read as
// separate planes rather than one moving surface.
uniform vec4  stripe_color : source_color = vec4(1.0, 1.0, 1.0, 0.026);
uniform float angle_deg    = 115.0;
uniform float stripe_width = 18.0;
uniform float period       = 74.0;
uniform float scroll_speed = -5.3;   // px/s along +X; negative scrolls LEFT

uniform vec2 rect_size = vec2(1920.0, 1080.0);

// Falloff of a radial in UV space. 1.0 at the centre, 0.0 at the ellipse edge,
// smoothstepped so there is no visible ring.
float radial(vec2 uv, vec2 centre, vec2 radius) {
	vec2 d = (uv - centre) / max(radius, vec2(0.0001));
	return 1.0 - smoothstep(0.0, 1.0, length(d));
}

void fragment() {
	vec3 col = base_color.rgb;

	// Washes: opaque colour, so mix by the falloff alone.
	col = mix(col, wash_left.rgb,  radial(UV, wash_left_centre,  wash_left_radius)  * wash_left.a);
	col = mix(col, wash_right.rgb, radial(UV, wash_right_centre, wash_right_radius) * wash_right.a);

	// Tints: alpha-over, so the falloff multiplies the colour's own alpha.
	col = mix(col, tint_top.rgb,    radial(UV, tint_top_centre,    tint_top_radius)    * tint_top.a);
	col = mix(col, tint_bottom.rgb, radial(UV, tint_bottom_centre, tint_bottom_radius) * tint_bottom.a);

	// Chevrons, in pixel space so they never stretch with the rect.
	vec2  p = UV * rect_size;
	float a = radians(angle_deg);
	vec2  n = vec2(-sin(a), cos(a));
	float d = mod(dot(p - vec2(TIME * scroll_speed, 0.0), n), period);
	float edge = 1.0;
	float ink = smoothstep(-edge, edge, d) - smoothstep(stripe_width - edge, stripe_width + edge, d);
	col = mix(col, stripe_color.rgb, ink * stripe_color.a);

	COLOR = vec4(col, 1.0);
}
