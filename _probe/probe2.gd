extends SceneTree
const WANT := {
	"Celeste_Harbour": ["TILE_MAPS/TRAIN TRACKS/Rail", "TILE_MAPS/TERRAIN/Sea Rocks", "TILE_MAPS/TERRAIN/Hill"],
	"Verdant_Forest": ["TILE_MAPS/PONDS/PIKACHU_POND/Water", "TILE_MAPS/PONDS/MAGIKARP_POND_L/Hillsides", "TILE_MAPS/TRAIN TRACKS/Hill"],
	"Gym_Plaza": ["TILE_MAPS/BACKGROUND/road"],
}
func _initialize():
	var f := FileAccess.open("res://_probe/cells.txt", FileAccess.WRITE)
	for p in WANT:
		var root: Node = (load("res://Scenes/Map_Scenes/%s.tscn" % p) as PackedScene).instantiate()
		for lp in WANT[p]:
			var tl := root.get_node_or_null(lp) as TileMapLayer
			if tl == null:
				print("missing ", lp); continue
			var xf := tl.get_global_transform()
			for c in tl.get_used_cells():
				var w: Vector2 = xf * tl.map_to_local(c)
				f.store_line("%s|%s|%d|%d" % [p, lp, int(w.x), int(w.y)])
		root.free()
	f.close()
func _process(_d): return true
