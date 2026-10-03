extends Node
func _ready() -> void:
	var ae = load("res://Scripts/Main_Match_Gameplay_Scripts/Attack_Effects.gd").new()
	add_child(ae)
	ae._ensure_dispatch_ready()
	var out = FileAccess.open("user://attack_audit.json", FileAccess.WRITE)
	var res := {"dispatch": ae._attack_dispatch.keys(), "attacks": []}
	for st in ["neo1", "neo2", "neo3", "neo4", "ecard1", "ecard2", "ecard3"]:
		var f = FileAccess.open("res://Card_Set_Data/" + st + ".json", FileAccess.READ)
		var data = JSON.parse_string(f.get_as_text())
		for c in data:
			for a in c.get("attacks", []):
				var fx = ae.parse_card_text_effects(a.get("text", ""), c.get("name", ""))
				res["attacks"].append({"id": c["id"], "card": c["name"], "name": a["name"], "damage": a.get("damage", ""), "cost": a.get("cost", []), "text": a.get("text", ""), "fx": fx})
	out.store_string(JSON.stringify(res))
	out.close()
	print("AUDIT DONE ", res["attacks"].size(), " dispatch keys ", res["dispatch"].size())
	get_tree().quit()
