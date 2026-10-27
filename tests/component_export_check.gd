extends SceneTree
## Ocean, Weather Lab and Wind each export into a scratch library (--root=<dir>), and each asset is
## sent to a fresh empty project at <dir>/fresh, as "Send to project..." does. Open that project to
## try them. godot --audio-driver Dummy --path . -s tests/component_export_check.gd -- --root=C:/tmp/lib
var main: Control
func _initialize() -> void:
	var root := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--root="):
			root = a.trim_prefix("--root=")
	Exporter.root_override = root
	DisplayServer.window_set_size(Vector2i(1280, 720))
	main = load("res://main.tscn").instantiate()
	root_node(main)
	_run.call_deferred(root)
func root_node(n: Node) -> void:
	get_root().add_child(n)
func _f(n: int) -> void:
	for i in n:
		await process_frame
func _run(root: String) -> void:
	var project := root + "/fresh"
	DirAccess.make_dir_recursive_absolute(project)
	var f := FileAccess.open(project + "/project.godot", FileAccess.WRITE)
	f.store_string("config_version=5\n\n[application]\nconfig/name=\"Fresh\"\nconfig/features=PackedStringArray(\"4.7\", \"GL Compatibility\")\n\n[rendering]\nrenderer/rendering_method=\"gl_compatibility\"\n")
	f.close()
	for pair in [["Ocean", "ocean", "Test Sea"], ["Weather Lab", "weather", "Test Storm"], ["Wind", "wind", "Test Breeze"]]:
		for i in main.SIMS.size():
			if main.SIMS[i].title == pair[0]:
				main.open_sim(i)
		await _f(10)
		main.sim._export(pair[2])
		print(Exporter.send_to_project(pair[1], pair[2], project))
	print("EXPORTED")
	quit()
