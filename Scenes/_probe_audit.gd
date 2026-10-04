extends Node
func _ready() -> void:
	var ae = load("res://Scripts/Main_Match_Gameplay_Scripts/Attack_Effects.gd").new()
	add_child(ae)
	ae._ensure_dispatch_ready()
	var out = FileAccess.open("user://attack_audit_ex.json", FileAccess.WRITE)
	var res := {"attacks": []}
	var sets = []
	for i in range(1, 17): sets.append("ex" + str(i))
	for i in range(1, 6): sets.append("pop" + str(i))
	for st in sets:
		var f = FileAccess.open("res://Card_Set_Data/" + st + ".json", FileAccess.READ)
		var data = JSON.parse_string(f.get_as_text())
		for c in data:
			for a in c.get("attacks", []):
				if ae._attack_dispatch.has(a.get("name","").to_lower()): continue
				var fx = ae.parse_card_text_effects(a.get("text", ""), c.get("name", ""))
				res["attacks"].append({"id": c["id"], "card": c["name"], "name": a["name"], "damage": a.get("damage", ""), "text": a.get("text", ""), "fx": fx})
	out.store_string(JSON.stringify(res))
	out.close()
	print("AUDIT DONE ", res["attacks"].size())
	get_tree().quit()
