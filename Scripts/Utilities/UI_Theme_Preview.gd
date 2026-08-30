extends SceneTree

# ============================================================
# UI THEME PREVIEW — one frame of every component, to a PNG
# ============================================================
# A specimen sheet for the Spectrum Night theme: the chrome bars, the field,
# all six button variants plus disabled, chips, status chips, damage counters
# at both sizes, meters, empty slots, a panel and the whole type scale, laid
# out on one screen and saved as an image.
#
# Run it after changing anything in UI_Theme.gd or re-running Build_UI_Themes,
# so a token change is judged by looking at it rather than by guessing:
#
#   "C:\Godot\Godot_v4.6.1-stable_win64_console.exe" --path "C:\Pokemon TCG Legacy" \
#       --script Scripts/Utilities/UI_Theme_Preview.gd
#
# NOT --headless: there is no rendering without a window, so the capture comes
# back blank. It opens, grabs a frame and quits on its own.
#
# It also prints the measured rect of every button and both header side slots.
# That is deliberate — eyeballing a screenshot said the primary button was
# taller than the others when all seven were 49px, and missed that the header
# chips were sitting flush against x = 0. Read the numbers, not the picture.
#
# Output: user://ui_preview.png
#   C:\Users\<you>\AppData\Roaming\Godot\app_userdata\Pokemon_TCG_Legacy\

const OUT := "user://ui_preview.png"


func _init() -> void:
	_build.call_deferred()


func _build() -> void:
	var page := Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(page)

	UIKit.add_field(page)

	var header := UIKit.add_header(page)
	var title := Label.new()
	UIKit.set_label(title, "title", "Card search", "chrome_fg")
	header.centre.add_child(title)
	header.left.add_child(UIKit.make_chip("60 / 60", "on_chrome"))
	var reset := Button.new()
	reset.text = "Reset"
	UIKit.style_button(reset, "secondary")
	header.right.add_child(reset)

	var footer := UIKit.add_footer(page)
	var cancel := Button.new()
	cancel.text = "Cancel"
	UIKit.style_button(cancel, "secondary")
	footer.centre.add_child(cancel)
	var confirm := Button.new()
	confirm.text = "Search"
	UIKit.style_button(confirm, "primary")
	footer.centre.add_child(confirm)

	# A column of every component, so one image answers "does this all agree".
	var col := VBoxContainer.new()
	col.position = Vector2(120, 170)
	col.add_theme_constant_override("separation", 26)
	page.add_child(col)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	for variant in ["primary", "secondary", "selected", "good", "danger", "warn"]:
		var b := Button.new()
		b.text = variant
		UIKit.style_button(b, variant)
		buttons.add_child(b)
	var disabled := Button.new()
	disabled.text = "disabled"
	UIKit.style_button(disabled, "secondary")
	disabled.disabled = true
	buttons.add_child(disabled)
	col.add_child(buttons)

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 14)
	chips.add_child(UIKit.make_chip("Turn 6"))
	chips.add_child(UIKit.make_chip("Hand 7"))
	chips.add_child(UIKit.make_chip("PSN", "status", "PSN"))
	chips.add_child(UIKit.make_chip("CNF", "status", "CNF"))
	chips.add_child(UIKit.make_chip("PAR", "status", "PAR"))
	chips.add_child(UIKit.make_chip("ASL", "status", "ASL"))
	col.add_child(chips)

	# Damage counters at the two sizes, plus the HP figure they always pair with.
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 16)
	var hp_num := Label.new()
	UIKit.set_label(hp_num, "hp", "30 / 50")
	hp_row.add_child(hp_num)
	hp_row.add_child(UIKit.make_damage_counters(30, 50))
	hp_row.add_child(UIKit.make_damage_counters(90, 120))
	hp_row.add_child(UIKit.make_damage_counters(10, 40, true))
	col.add_child(hp_row)

	var meters := VBoxContainer.new()
	meters.add_theme_constant_override("separation", 10)
	var m1 := HBoxContainer.new()
	m1.add_theme_constant_override("separation", 18)
	var m1l := Label.new()
	UIKit.set_label(m1l, "small_label", "Unique cards", "field_mute")
	m1l.custom_minimum_size.x = 220
	m1.add_child(m1l)
	m1.add_child(UIKit.make_meter(134, 3285, 520))
	var m1v := Label.new()
	UIKit.set_label(m1v, "hp", "134 / 3285")
	m1.add_child(m1v)
	meters.add_child(m1)
	var m2 := HBoxContainer.new()
	m2.add_theme_constant_override("separation", 18)
	var m2l := Label.new()
	UIKit.set_label(m2l, "small_label", "Sets unlocked", "field_mute")
	m2l.custom_minimum_size.x = 220
	m2.add_child(m2l)
	m2.add_child(UIKit.make_meter(8, 37, 520))
	var m2v := Label.new()
	UIKit.set_label(m2v, "hp", "8 / 37")
	m2.add_child(m2v)
	meters.add_child(m2)
	col.add_child(meters)

	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 18)
	slots.add_child(UIKit.make_slot(Vector2(119, 165)))
	slots.add_child(UIKit.make_slot(Vector2(100, 100), true))
	var panel := UIKit.make_panel()
	panel.custom_minimum_size = Vector2(320, 165)
	var pl := Label.new()
	UIKit.set_label(pl, "body", "Pikachu used Thundershock and the Defending Pokemon is now Paralyzed.")
	pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(pl)
	slots.add_child(panel)
	col.add_child(slots)

	# Type-scale specimen, so the sizes can be judged against each other.
	var specimen := VBoxContainer.new()
	specimen.add_theme_constant_override("separation", 6)
	for role in ["title", "subtitle", "name", "button", "chip", "attack_name", "hp", "small_label", "body"]:
		var l := Label.new()
		UIKit.set_label(l, role, "%s — Dark Gloom used Poisonpowder" % role)
		specimen.add_child(l)
	col.add_child(specimen)

	# A selection ring on the empty bench slot, on its own flat layer.
	var ring_layer := Control.new()
	ring_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(ring_layer)

	await process_frame
	await process_frame
	await process_frame
	UIKit.add_selection_ring(ring_layer, slots.get_child(0), 7.0)
	await process_frame
	await process_frame

	for b in buttons.get_children():
		print("btn %-10s size=%s pos=%s" % [(b as Button).text, str(b.size), str(b.position)])
	print("header bar  size=", header.size)
	print("header left child rect=", header.left.get_child(0).get_global_rect())
	print("header right child rect=", header.right.get_child(0).get_global_rect())

	var img := root.get_texture().get_image()
	var err := img.save_png(OUT)
	if err == OK:
		print("wrote ", ProjectSettings.globalize_path(OUT))
	else:
		printerr("save failed ", err)
	quit()
