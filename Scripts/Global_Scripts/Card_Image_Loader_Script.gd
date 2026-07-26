extends TextureRect

# Create a custom signal that will be emitted when this card is clicked to set this card as the "selected" card
signal card_clicked(clicked_card: card_object)

# Declare the card ID as a variable
var card_uid
var card_ref: card_object

# Animation and selection variables
var tween: Tween
var is_selected: bool = false
var original_modulate: Color

# Function to load the card image based on the UID (e.g Base1-1)
func load_card_image(card_passed_uid: String, card_target_size, card_object_ref: card_object = null, face_down: bool = false, sleeve_path: String = ""):
	# Store reference to the card object so we can emit it when clicked
	self.card_ref = card_object_ref

	# Store the card UID so we can access it later when clicked
	self.card_uid = card_passed_uid

	# Check the card_passed_uid to make sure it's valid and if not error out
	var split_uid = card_passed_uid.split("-")
	if split_uid.size() != 2:
		print("Invalid UID provided, card_uid:", card_passed_uid)
		return

	# Card details will be for example "Base1-1" "EX2-2"
	var card_set = split_uid[0]

	# Set the image to a null card in case there's any errors
	var card_image_path="res://Image_Assets/null.png"

	# Now find the image based on the card card_uid and size
	# If the image is only being displayed small then no point wasting resources loading large card images and shrinking them down.

	if card_target_size.x < 250 or card_target_size.y < 350:
		if face_down:
			card_image_path = sleeve_path if sleeve_path != "" else "res://Image_Assets/Sleeves/1_Default_English.png"
		else:
			card_image_path="res://Image_Assets/Card_Image_Library/"+card_set+"/Small/"+card_passed_uid+".png"
	else:
		if face_down:
			card_image_path = sleeve_path if sleeve_path != "" else "res://Image_Assets/Sleeves/1_Default_English.png"
		else:
			card_image_path="res://Image_Assets/Card_Image_Library/"+card_set+"/Large/"+card_passed_uid+".png"
	
	# Now find the image from the path provided
	var card_texture = load(card_image_path)
	
	# check that the file could be found and if so load the image
	if card_texture != null:
		
		# We want to resize the image to always be the correct dimensions
		# Therefore we start by gettting the original image dimensions
		var original_card_dimension_width = card_texture.get_width()
		var original_card_dimension_height = card_texture.get_height()
		
		# Calculate scale factor (use the smaller ratio to maintain aspect ratio)
		var scale_x = float(card_target_size.x) / float(original_card_dimension_width)
		var scale_y = float(card_target_size.y) / float(original_card_dimension_height)
		var scale_factor = min(scale_x, scale_y)
		
		# Calculate final size maintaining aspect ratio
		var final_width = int(original_card_dimension_width * scale_factor)
		var final_height = int(original_card_dimension_height * scale_factor)
		
		# Set the texture
		self.texture = card_texture
		
		# Set size
		self.custom_minimum_size = Vector2(final_width, final_height)
		
		# NEW: Set pivot point to center so scaling happens from center
		self.pivot_offset = Vector2(final_width / 2, final_height / 2)
		
		# Set stretch mode to scale proportionally
		self.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		
		# Set stretch mode to scale proportionally
		self.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		self.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		
	else:
		print("Error: Could not load card image at path: ", card_image_path)

# Apply animation and colour effects to show selected card
# Apply visual effect when card is selected
func set_selected(selected: bool) -> void:
	is_selected = selected
	
	if selected:
		# Kill any existing tween to prevent conflicts
		if tween:
			tween.kill()
		
		# Store original color BEFORE starting animation if not already stored
		if original_modulate == Color(0, 0, 0, 0):
			original_modulate = Color.WHITE
		
		# Create new tween for smooth animation
		tween = create_tween()
		tween.set_loops()  # Loop the animation
		
		# Glow and scale happen simultaneously
		tween.tween_property(self, "modulate", Color.WHITE * 1.4, 0.5)
		tween.parallel().tween_property(self, "scale", Vector2(1.03, 1.03), 0.5)
		
		# Return to normal - glow and scale happen simultaneously
		tween.tween_property(self, "modulate", Color.WHITE * 1.0, 0.5)
		tween.parallel().tween_property(self, "scale", Vector2(1.0, 1.0), 0.5)
		
	else:
		# Kill the tween animation
		if tween:
			tween.kill()
			tween = null
		
		# Restore original appearance immediately
		modulate = Color.WHITE
		scale = Vector2(1.0, 1.0)
		
# This function script is used to determine when a card is clicked			
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		# ISSUE #89 FIX: the mouse wheel is delivered as an InputEventMouseButton with pressed == true,
		# so scrolling with the cursor over a card counted as clicking that card and emitted
		# card_clicked — scrolling a hand of 8+ cards kept selecting whichever card was under the
		# cursor. Scrolling is not a click.
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			return
		# Check if the click is actually on this card
		if get_global_rect().has_point(event.position):
			
			# Check the whole ancestor chain, not just the immediate parent — a hidden
			# container further up the tree (e.g. show_enlarged_array_selection_mode hiding
			# the prize-card containers) still leaves this card's own get_global_rect() at its
			# last on-screen position, so a stale card here would otherwise silently eat clicks
			# meant for whatever new array is now drawn over that same screen area.
			if not is_visible_in_tree():
				print("ISSUE #12 FIX ACTIVE (Card_Image_Loader): ignored click on a card hidden via an ancestor, card_ref=", card_ref.metadata.get("name", "") if card_ref else "null")
				return
			
			card_clicked.emit(card_ref)
			
			# Get reference to the main script to check if we're in selection mode
			var main_node = get_tree().root.get_child(0)
			if main_node == null:
				print("Error: Could not find main script node")
				return

			var messagebox = main_node.get_node_or_null("messagebox_container")
			if messagebox and messagebox.visible:
				return
				
			# If in selection mode, consume the input so it doesn't propagate to other cards
			if main_node.has_method("card_selection_mode_enabled") and main_node.card_selection_mode_enabled:
				get_tree().get_root().set_input_as_handled()

# On card load...
func _ready() -> void:
	# Allow mouse input to pass through to this TextureRect
	mouse_filter = MOUSE_FILTER_PASS
