shader_type canvas_item;

// ============================================================
// PIXEL DISSOLVE — the screen breaks into pixels that pop out and vanish
// ============================================================
// Used by PixelDissolve.gd for the jump from the overworld into a match.
//
//   progress 0 -> 1. For the first `pixelate_share` of it the picture coarsens into
//   bigger and bigger square pixels; for the rest those pixels pop out one by one in
//   a random order (each cell has its own moment): over `edge` of the run a cell swells
//   to `pop_scale` of its size, then shrinks about its centre to nothing.
//
//   A swelling cell spills a little over its neighbours, so every fragment checks the
//   3x3 cells around it; where several cover it the biggest one draws on top.
//
//   use_screen true:  the rect reads the LIVE screen under it (no snapshot, so no
//                     GPU read-back stall), pixelates it and pops the cells out to black.
//                     The rect itself is opaque: what shows is the screen or black.
//   use_screen false: the rect is a flat COLOR (black) MASK whose cells pop away,
//                     revealing what is underneath -- the match intro's way in.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec2 screen_px = vec2(1920.0, 1080.0);
uniform float max_cell = 32.0;          // pixel size at the end of the pixelate stage
uniform float pixelate_share = 0.35;    // share of `progress` spent coarsening
uniform float edge = 0.35;              // share of the dissolve one cell's pop takes
uniform float pop_scale = 1.25;         // how big a cell swells before it shrinks (keep <= 2)
uniform float pop_share = 0.3;          // share of a cell's pop spent swelling
uniform bool use_screen = true;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Size of a cell (1 = its normal size) at dissolve time `dis_t`.
float cell_scale(vec2 cell_id, float dis_t) {
	float r = hash(cell_id) * (1.0 - edge);
	float t = clamp((dis_t - r) / max(edge, 0.0001), 0.0, 1.0);
	float grow = clamp(pop_share, 0.01, 0.99);
	if (t < grow) {
		float g = t / grow;
		return mix(1.0, pop_scale, g * (2.0 - g));          // ease out into the swell
	}
	float s = (t - grow) / (1.0 - grow);
	return mix(pop_scale, 0.0, s * s);                      // ease in down to nothing
}

void fragment() {
	vec2 uv = use_screen ? SCREEN_UV : UV;
	vec2 px = uv * screen_px;
	float share = clamp(pixelate_share, 0.0, 0.95);
	float pix_t = share > 0.0 ? clamp(progress / share, 0.0, 1.0) : 1.0;
	float dis_t = clamp((progress - share) / (1.0 - share), 0.0, 1.0);

	if (dis_t <= 0.0) {
		// Still coarsening: every cell is whole.
		if (use_screen) {
			float cell = max(1.0, floor(mix(1.0, max_cell, pix_t * pix_t)));
			vec2 sample_px = (floor(px / cell) + 0.5) * cell;
			COLOR = vec4(texture(screen_tex, sample_px / screen_px).rgb, 1.0);
		}
		// Mask mode: COLOR is left as the rect's own colour.
	} else {
		// The cells that pop are always the final, largest size, so a block goes whole
		// rather than a fine pixel inside one.
		vec2 home = floor(px / max_cell);
		float best = 0.0;
		vec2 best_id = home;
		for (int dy = -1; dy <= 1; dy++) {
			for (int dx = -1; dx <= 1; dx++) {
				vec2 id = home + vec2(float(dx), float(dy));
				float sc = cell_scale(id, dis_t);
				vec2 off = abs(px - (id + 0.5) * max_cell);
				float half_size = 0.5 * max_cell * sc;
				if (sc > best && off.x <= half_size && off.y <= half_size) {
					best = sc;
					best_id = id;
				}
			}
		}
		bool covered = best > 0.0;
		if (use_screen) {
			vec2 sample_px = (best_id + 0.5) * max_cell;
			vec3 c = texture(screen_tex, sample_px / screen_px).rgb;
			COLOR = vec4(covered ? c : vec3(0.0), 1.0);
		} else {
			COLOR = vec4(COLOR.rgb, covered ? COLOR.a : 0.0);
		}
	}
}
