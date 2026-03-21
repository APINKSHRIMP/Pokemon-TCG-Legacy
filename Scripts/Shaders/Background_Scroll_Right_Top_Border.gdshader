shader_type canvas_item;
uniform float scroll_speed = -0.009;

void fragment() {
    COLOR = texture(TEXTURE, vec2(UV.x + TIME * scroll_speed, UV.y));
}