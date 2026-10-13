shader_type canvas_item;

// Every world CanvasItem on an outdoor map wears this (Time_Of_Day_Grade.grade_node). The
// grade runs before Godot adds PointLight2D light, so street lights stay at full strength.
//
// TileMapLayers also get the sheet's "_Lights.png" overlay: same size and layout as the
// sheet, transparent except lit windows / lamps. Those pixels are drawn on top UNGRADED,
// scaled by tod_curve.w, so every placed tile lights up without any extra tile painting.

#include "res://Scripts/Shaders/Time_Of_Day_Grade.gdshaderinc"

uniform bool has_lights = false;
uniform sampler2D lights_texture : filter_nearest, repeat_disable;
// Godot draws TileSet atlases from a padded copy (1px border round every tile, on by
// default), so UV is in padded space. These undo it; tile_px is the atlas cell size.
uniform bool atlas_padded = true;
uniform float tile_px = 16.0;

// The colour BEFORE grading, handed to light(): a lamp reveals what is really there (its
// daytime colour, tinted by the light) instead of brightening the night-tinted colour,
// which turned warm lamps pink on purple paving and mint on grass.
varying vec3 day_albedo;

void fragment() {
	vec4 c = COLOR;  // already texture * modulate in 4.6 -- multiplying by TEXTURE again squares it
	day_albedo = c.rgb;
	c.rgb = tod_grade(c.rgb);
	if (has_lights && tod_curve.w > 0.0) {
		vec2 px = UV / TEXTURE_PIXEL_SIZE;
		if (atlas_padded) {
			px -= floor(px / (tile_px + 2.0)) * 2.0 + 1.0;
		}
		vec4 lit = texture(lights_texture, px / vec2(textureSize(lights_texture, 0)));
		float k = lit.a * tod_curve.w * COLOR.a;  // COLOR.a: still honours modulate fades
		float a = k + c.a * (1.0 - k);
		if (a > 0.0) {
			c.rgb = (lit.rgb * k + c.rgb * c.a * (1.0 - k)) / a;
		}
		c.a = a;
	}
	COLOR = c;
}

// Godot's default light() with day_albedo in place of the graded COLOR.
void light() {
	LIGHT = vec4(day_albedo * LIGHT_COLOR.rgb * LIGHT_ENERGY, LIGHT_COLOR.a);
}
