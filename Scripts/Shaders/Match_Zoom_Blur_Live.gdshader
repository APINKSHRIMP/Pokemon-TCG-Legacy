shader_type canvas_item;

// ============================================================
// MATCH ZOOM BLUR (LIVE) — the same blur over the live screen underneath
// ============================================================
// Twin of Match_Zoom_Blur.gdshader that reads the LIVE screen under it instead of
// the frozen screenshot. The way back to the overworld uses it: the real map (new
// time-of-day colours and all) blurred and zoomed exactly like the screenshot, so
// the old picture can cross-fade into it while both come back into focus together.
// Keep the two shaders numerically identical apart from where they sample.
//
//   progress 0.0  the overworld exactly as it is
//   progress 1.0  zoomed in on the player, soft, darkened: the match backdrop
//
// Three effects ramp together:
//   * zoom       - UVs pulled in toward `focus` (the player on screen)
//   * streaks    - a radial blur: each pixel averages samples along the line
//                  toward `focus`, which is the "motion" in motion blur
//   * softness   - samples are read from a lower mip level as progress rises, so
//                  the streaks melt into an even soft blur by the end
// and the colour darkens and desaturates slightly on top.
// ============================================================

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec2  focus     = vec2(0.5, 0.5);   // UV of the point the zoom heads for
uniform float progress  : hint_range(0.0, 1.0) = 0.0;
uniform float zoom_max  = 1.7;     // how far in the zoom ends
uniform float streak    = 0.35;    // share of the way to `focus` the radial blur reaches
uniform float soft_lod  = 4.5;     // mip level of the final soft blur
uniform float darken    = 0.42;    // brightness left at progress 1.0
uniform float desat     = 0.15;    // share of colour removed at progress 1.0

const int SAMPLES = 20;

vec3 samp(vec2 uv, float lod) {
	vec2 c = clamp(uv, vec2(0.001), vec2(0.999));
	return textureLod(screen_tex, c, lod).rgb;
}

void fragment() {
	float p = clamp(progress, 0.0, 1.0);
	float z = mix(1.0, zoom_max, p);
	vec2 base_uv = SCREEN_UV;
	vec2 uv = focus + (base_uv - focus) / z;

	float reach = streak * p;
	float lod = soft_lod * p * p;
	vec3 acc = vec3(0.0);
	for (int i = 0; i < SAMPLES; i++) {
		float t = float(i) / float(SAMPLES - 1);
		acc += samp(mix(uv, focus, t * reach), lod);
	}
	acc /= float(SAMPLES);

	float grey = dot(acc, vec3(0.299, 0.587, 0.114));
	acc = mix(acc, vec3(grey), desat * p);
	acc *= mix(1.0, darken, p);

	// COLOR.a carries the node's modulate (and its parents'): writing 1.0 here would make
	// every fade on this rect - and on the overlay stage above it - do nothing.
	COLOR = vec4(acc, COLOR.a);
}
