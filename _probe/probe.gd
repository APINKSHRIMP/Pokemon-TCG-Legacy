extends SceneTree
func _rect(tl: TileMapLayer) -> Rect2:
	var used: Rect2i = tl.get_used_rect()
	if used.size == Vector2i.ZERO or tl.tile_set == null: return Rect2()
	var half: Vector2 = Vector2(tl.tile_set.tile_size) * 0.5
	var xf := tl.get_global_transform()
	var a: Vector2 = xf * (tl.map_to_local(used.position) - half)
	var b: Vector2 = xf * (tl.map_to_local(used.end - Vector2i.ONE) + half)
	return Rect2(a, b - a).abs()
func _initialize():
	for p in ["Celeste_Harbour","Verdant_Forest","Gym_Plaza"]:
		var ps: PackedScene = load("res://Scenes/Map_Scenes/%s.tscn" % p)
		var root: Node = ps.instantiate()
		print("== ", p)
		var all := Rect2()
		var lst := []
		for tl in root.find_children("*", "TileMapLayer", true, false):
			var r := _rect(tl)
			if r.size == Vector2.ZERO: continue
			all = r if all.size == Vector2.ZERO else all.merge(r)
			lst.append([r.get_area(), str(root.get_path_to(tl)), r])
		lst.sort_custom(func(a, b): return a[0] > b[0])
		for i in min(8, lst.size()): print("  ", lst[i][1], " ", lst[i][2])
		print(" UNION ", all)
		var doors = root.get_node_or_null("Door Areas")
		if doors:
			for d in doors.get_children():
				if d is CollisionShape2D:
					print("  DOOR ", d.name, " ", d.get_global_transform().origin, " -> ", d.get_meta("target_scene", ""), " disabled=", d.disabled)
		var pl = root.get_node_or_null("Player")
		if pl: print("  PLAYER parent xf ", pl.get_parent().get_global_transform().origin, " scale ", pl.get_global_transform().get_scale())
		root.free()
func _process(_d): return true
