extends Node

const OUT := "C:/Users/Olly9/AppData/Local/Temp/claude/C--Pokemon-TCG-Legacy/52cd3292-9a6a-4ea0-afba-a6926237e381/scratchpad/"

var _t := 0.0
var _placed := false
var _p := Vector2.ZERO
var _next_shot := 1.6
var _n := 0

func _process(delta: float) -> void:
	_t += delta
	var player = get_tree().get_first_node_in_group("player")
	var spawner = get_tree().get_first_node_in_group("pokemon_spawner")
	if player == null or spawner == null:
		return
	if not _placed and _t > 1.0:
		_placed = true
		player.lock_movement()
		player.camera.zoom = Vector2(9, 9)
		_p = player.global_position.round()
		spawner.apply_doc({
			"flyers": {"interval": 1, "chance": 100, "min": 1, "max": 2, "table": [{"species": "187_Hoppip", "percent": 100}]},
			"spawn_points": [
			{"id": "b", "template": "burying", "at": [_p.x - 30, _p.y + 30], "chance": 100, "interval": 0.3, "up_time": 1.2, "table": [{"species": "050_Diglett", "percent": 100}]},
			{"id": "s", "template": "surfacing", "at": [_p.x + 30, _p.y + 30], "chance": 100, "interval": 0.3, "table": [{"species": "129_Magikarp", "percent": 100}]},
			{"id": "sw", "template": "swinging_bug", "at": [_p.x, _p.y - 35], "chance": 100, "table": [{"species": "167_Spinarak", "percent": 100}]},
			{"id": "t", "template": "bug_tree", "at": [_p.x - 60, _p.y - 25], "chance": 100, "table": [{"species": "010_Caterpie", "percent": 100}]},
			{"id": "r", "template": "rodent", "at": [_p.x + 60, _p.y - 25], "chance": 100, "table": [{"species": "019_Rattata", "percent": 100}]},
		]})
	if _placed and _t >= _next_shot and _n < 16:
		_next_shot += 0.2
		_n += 1
		var vp := get_viewport()
		var view: Rect2 = vp.get_canvas_transform().affine_inverse() * Rect2(Vector2.ZERO, vp.get_visible_rect().size)
		var info := "player=%s view=%s" % [_p, view]
		for ch in spawner.get_children():
			if ch is PokemonBurrower or ch is PokemonSurfacer or ch is PokemonFlyer:
				info += "\n     %s %s clip=%d screen=%s" % [ch.get_script().get_global_name(), ch.species, ch.clip_rows,
						(vp.get_canvas_transform() * ch.global_position).round()]
		vp.get_texture().get_image().save_png(OUT + "vf_%02d.png" % _n)
		print("VF %02d t=%.1f %s" % [_n, _t, info])
	if _n >= 16:
		get_tree().quit()
