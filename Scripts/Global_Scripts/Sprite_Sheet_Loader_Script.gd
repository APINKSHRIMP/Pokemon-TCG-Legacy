class_name SpriteSheetLoader

const FRAME_MAP = {
	"idle_down":  [[0, 0], [2, 0]],
	"idle_left":  [[0, 1], [2, 1]],
	"idle_right": [[0, 2], [2, 2]],
	"idle_up":    [[0, 3], [2, 3]],
	"walk_down":  [[0, 0], [1, 0], [2, 0], [3, 0]],
	"walk_left":  [[0, 1], [1, 1], [2, 1], [3, 1]],
	"walk_right": [[0, 2], [1, 2], [2, 2], [3, 2]],
	"walk_up":    [[0, 3], [1, 3], [2, 3], [3, 3]],
}

const COLOR_TOLERANCE = 0.02

static func load_sprite_frames(sprite_name: String) -> SpriteFrames:
	var path = "res://Image_Assets/Character_Sprites/Overworld_Sprites/" + sprite_name + ".png"
	var sheet_texture = load(path) as Texture2D
	
	if sheet_texture == null:
		push_error("Could not load sprite sheet: " + path)
		return null
	
	var clean_texture = sheet_texture
	
	var sheet_width = clean_texture.get_width()
	var sheet_height = clean_texture.get_height()
	var frame_width = sheet_width / 4.0
	var frame_height = sheet_height / 4.0
	
	var sprite_frames = SpriteFrames.new()
	sprite_frames.remove_animation("default")
	
	for anim_name in FRAME_MAP.keys():
		sprite_frames.add_animation(anim_name)
		sprite_frames.set_animation_speed(anim_name, 6.0)
		
		var is_idle = anim_name.begins_with("idle")
		sprite_frames.set_animation_loop(anim_name, !is_idle)
		
		for grid_pos in FRAME_MAP[anim_name]:
			var atlas = AtlasTexture.new()
			atlas.atlas = clean_texture
			atlas.region = Rect2(
				grid_pos[0] * frame_width,
				grid_pos[1] * frame_height,
				frame_width,
				frame_height
			)
			sprite_frames.add_frame(anim_name, atlas)
	
	return sprite_frames

static func _colors_match(a: Color, b: Color) -> bool:
	return (
		absf(a.r - b.r) < COLOR_TOLERANCE
		and absf(a.g - b.g) < COLOR_TOLERANCE
		and absf(a.b - b.b) < COLOR_TOLERANCE
	)
