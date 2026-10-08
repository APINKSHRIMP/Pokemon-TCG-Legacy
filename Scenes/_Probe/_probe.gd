extends Node
func _ready():
	var ae = load("res://Scripts/Main_Match_Gameplay_Scripts/Attack_Effects.gd").new()
	add_child(ae)
	ae._ensure_dispatch_ready()
	var out = FileAccess.open("C:/Users/Olly9/AppData/Local/Temp/claude/C--Pokemon-TCG-Legacy/e3648872-254c-4b99-8d4b-4e32c3238fcf/scratchpad/generic_parse.jsonl", FileAccess.WRITE)
	var dir = DirAccess.open("res://Card_Set_Data")
	for f in dir.get_files():
		if not f.ends_with(".json") or f.begins_with("pack"): continue
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://Card_Set_Data/" + f))
		var cards = data if data is Array else data.get("cards", data.get("data", []))
		for c in cards:
			for a in c.get("attacks", []):
				var nm = str(a.get("name", "")).to_lower()
				var dispatched = ae._attack_dispatch.has(nm)
				var eff = []
				if not dispatched and str(a.get("text", "")) != "":
					eff = ae.parse_card_text_effects(str(a.get("text", "")), str(c.get("name", "")))
				out.store_line(JSON.stringify({"uid": c["id"], "card": c["name"], "attack": a.get("name", ""), "damage": a.get("damage", ""), "text": a.get("text", ""), "dispatched": dispatched, "effects": eff}))
	out.close()
	print("PROBE DONE")
	get_tree().quit()
