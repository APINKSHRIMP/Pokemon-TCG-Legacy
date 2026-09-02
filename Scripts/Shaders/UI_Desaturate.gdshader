shader_type canvas_item;

// ============================================================
// UI DESATURATE — the defeated trainer on the win / loss screen
// ============================================================
// Greys and dims a sprite so the outcome reads before the word does. Applied to
// the LOSER only: the opponent on a win, the player on a loss.
//
// Deliberately NOT used on the best-of-three screen. Desaturation is how the
// final screen says "this is settled"; using it between rounds would tell the
// player the match is over when it is not.
//
// Rec. 601 luma, the same weighting the message box uses to pick chip text
// colour — green carries most of the perceived brightness.
// ============================================================

uniform float grey_amount  : hint_range(0.0, 1.0) = 0.80;
uniform float brightness   : hint_range(0.0, 2.0) = 0.55;

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	float luma = dot(src.rgb, vec3(0.299, 0.587, 0.114));
	vec3 col = mix(src.rgb, vec3(luma), grey_amount) * brightness;
	COLOR = vec4(col, src.a) * COLOR;
}
