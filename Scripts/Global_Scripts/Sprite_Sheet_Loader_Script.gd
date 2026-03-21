class_name SpriteSheetLoader

const FRAME_MAP = {
	"idle_up":    [[0, 0]],
	"idle_right": [[1, 0]],
	"idle_down":  [[2, 1]],
	"idle_left":  [[0, 2]],
	"walk_up":    [[0, 0], [2, 0], [0, 0], [1, 3]],
	"walk_right": [[1, 0], [1, 1], [1, 0], [1, 2]],
	"walk_down":  [[2, 1], [2, 2], [2, 1], [2, 3]],
	"walk_left":  [[0, 2], [0, 1], [0, 2], [0, 3]],
}

# How close a pixel colour must be to the background to be removed.
# 0.02 allows for slight compression artifacts around sprite edges.
const COLOR_TOLERANCE = 0.02

static func load_sprite_frames(sprite_name: String) -> SpriteFrames:
	var path = "res://Image_Assets/Character_Sprites/Overworld_Sprites/sprite_sheet_" + sprite_name + ".png"
	var sheet_texture = load(path) as Texture2D
	
	if sheet_texture == null:
		push_error("Could not load sprite sheet: " + path)
		return null
	
	# --- Background removal ---
	# Get the raw Image from the texture so we can edit pixels
	var image = sheet_texture.get_image()
	
	# Ensure the image has an alpha channel to support transparency
	# RGBA8 = Red, Green, Blue, Alpha - 8 bits each
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	
	# Read the top-left pixel as the background colour
	var bg_color = image.get_pixel(0, 0)
	
	# Replace every pixel matching the background with transparent
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel = image.get_pixel(x, y)
			if _colors_match(pixel, bg_color):
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	
	# Create a new texture from the modified image
	var clean_texture = ImageTexture.create_from_image(image)
	
	# --- Build SpriteFrames from the cleaned texture ---
	var sheet_width = clean_texture.get_width()
	var sheet_height = clean_texture.get_height()
	var frame_width = sheet_width / 3.0
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
	# Check if two colours are close enough to be considered the same.
	# This handles slight variations from image compression.
	return (
		absf(a.r - b.r) < COLOR_TOLERANCE
		and absf(a.g - b.g) < COLOR_TOLERANCE
		and absf(a.b - b.b) < COLOR_TOLERANCE
	)
