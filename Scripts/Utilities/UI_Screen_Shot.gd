extends SceneTree

# ============================================================
# UI SCREEN SHOT — load one real screen, render it, save a PNG
# ============================================================
# The counterpart to UI_Theme_Preview: that one draws a specimen sheet of
# components, this one loads an ACTUAL scene so a converted screen can be
# checked without playing to it.
#
#   "C:\Godot\Godot_v4.6.1-stable_win64_console.exe" --path "C:\Pokemon TCG Legacy" \
#       --script Scripts/Utilities/UI_Screen_Shot.gd -- <scene-path> [out-name]
#
# e.g.  -- res://Scenes/Main_Menu_Scenes/Options_Scene.tscn options
#
# NOT --headless: there is no rendering without a window, so the capture comes
# back blank. It opens, waits for the screen to settle, grabs a frame and quits.
#
# It also prints the rect of every direct child of the scene root, because a
# screenshot cannot tell you that a container has silently collapsed to zero
# height or run off the bottom of the screen.
# ============================================================

const SETTLE_FRAMES := 12

# How long to hold after an optional method call, for a grid rebuild to settle.
const CALL_SETTLE_SECONDS := 12.0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("UI_Screen_Shot: pass a scene path after --")
		quit(1)
		return

	var scene_path: String = args[0]
	var out_name: String = args[1] if args.size() > 1 else "screen"

	var packed: PackedScene = load(scene_path)
	if packed == null:
		printerr("UI_Screen_Shot: could not load ", scene_path)
		quit(1)
		return

	var screen := packed.instantiate()
	root.add_child(screen)
	current_scene = screen

	for _i in SETTLE_FRAMES:
		await process_frame

	# Optional third arg: a no-argument method to call on the scene root before
	# capturing, so a screen can be photographed in a state that normally needs a
	# click to reach (an owned-only filter toggled off, a tab switched).
	# A coroutine returns a signal here rather than completing, and there is no
	# clean way to await an unknown one — so the wait is a flat hold long enough
	# for a grid rebuild to finish.
	if args.size() > 2 and screen.has_method(args[2]):
		# A fourth arg is passed to the method as an int, for the handlers that
		# take one (e.g. a sell band index).
		if args.size() > 3:
			screen.call(args[2], int(args[3]))
		else:
			screen.call(args[2])
		await screen.get_tree().create_timer(CALL_SETTLE_SECONDS).timeout
		for _j in SETTLE_FRAMES:
			await process_frame

	if screen is Control:
		print("root rect ", (screen as Control).get_global_rect())
		for child in screen.get_children():
			if child is Control:
				print("  %-22s %s  visible=%s" % [
					child.name, str((child as Control).get_global_rect()),
					str((child as Control).visible)])

	var out := "user://%s.png" % out_name
	var err := root.get_texture().get_image().save_png(out)
	if err == OK:
		print("wrote ", ProjectSettings.globalize_path(out))
	else:
		printerr("save failed ", err)
	quit()
