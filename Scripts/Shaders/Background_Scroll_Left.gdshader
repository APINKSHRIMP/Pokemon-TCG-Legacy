shader_type canvas_item;
uniform float scroll_speed = 0.002;
uniform vec4 tint = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
    COLOR = texture(TEXTURE, vec2(UV.x + TIME * scroll_speed, UV.y)) * tint;
}