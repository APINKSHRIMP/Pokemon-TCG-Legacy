extends Node

func _ready() -> void:
	var files: Array = []
	_walk("res://Scripts", files)
	_walk("res://Scenes", files)
	var bad := 0
	for f in files:
		var s = ResourceLoader.load(f, "", ResourceLoader.CACHE_MODE_REUSE)
		if s == null:
			print("COMPILE FAIL (null): ", f)
			bad += 1
		elif s is GDScript and not (s as GDScript).can_instantiate():
			print("COMPILE FAIL: ", f)
			bad += 1
	print("COMPILE ALL DONE: ", files.size(), " scripts, ", bad, " failed")
	get_tree().quit()


func _walk(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_walk(dir.path_join(d), out)
