// TIME-OF-DAY COLOUR GRADE -- shared by every overworld shader (World_Time_Grade.gdshader,
// PokemonSurfacer's water shader). The four globals are declared in project.godot
// [shader_globals] and written by Time_Of_Day_Grade.gd; nothing else should set them.
//
// Each output channel is a weighted mix of the input red/green/blue plus an offset, plus a
// brightness-curve term (luma squared) that bends highlights -- Evening's sunset glow lives
// almost entirely in that curve. Afternoon is the identity: every sprite is drawn for it.
global uniform vec4 tod_red;    // xyz: weights of input r,g,b in output red;   w: offset
global uniform vec4 tod_green;  // xyz: weights of input r,g,b in output green; w: offset
global uniform vec4 tod_blue;   // xyz: weights of input r,g,b in output blue;  w: offset
global uniform vec4 tod_curve;  // xyz: luma^2 weight per output channel;       w: lights strength 0..1 (above 1 = brighter lit pixels)

vec3 tod_grade(vec3 c) {
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec4 x = vec4(c, 1.0);
	vec3 o = vec3(dot(x, tod_red), dot(x, tod_green), dot(x, tod_blue)) + tod_curve.xyz * (l * l);
	return clamp(o, 0.0, 1.0);
}
