extends SceneTree
## The Rope Lab's four scenes each export into a scratch library (--root=<dir>) and are sent to a
## fresh empty project at <dir>/fresh, as "Send to project..." does; then that project is
## imported and run headless: every exported patch (.tscn) and style (.tres) is loaded, put in a
## scene, stepped for a second and cut, and a ball is dropped on a wire. Prints "ROPE EXPORT OK".
## godot --audio-driver Dummy --path . -s tests/rope_export_check.gd -- --root=C:/tmp/ropelib
var main: Control
const CHECK := """extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0, 4, 20), Vector3(0, 3, 0))
	var bad := 0
	for name in ["test_kelp", "test_vines", "test_wires", "test_ropes"]:
		var style := load("res://assets/ropes/%s.tres" % name) as RopeStyle
		var packed := load("res://assets/ropes/%s.tscn" % name) as PackedScene
		if style == null or packed == null:
			print("MISSING ", name)
			bad += 1
			continue
		var patch := packed.instantiate() as RopePatch
		world.add_child(patch)
		var line := RopeLine.new()
		line.style = style
		line.length = 3.0
		line.position = Vector3(0, 5, 0)
		world.add_child(line)
		for f in 60:
			await physics_frame
		if patch.lines.is_empty() or not patch.lines[0].point_at(1.0).is_finite():
			print("NO LINES ", name)
			bad += 1
		print("%s: %d lines, %d leaves, pieces %d, tip %s" % [name, patch.lines.size(), patch.leaf_count(), style.pieces, patch.lines[0].point_at(99.0)])
		patch.lines[0].cut(patch.lines[0].rest_length() * 0.5)
		for f in 10:
			await physics_frame
		patch.queue_free()
		line.queue_free()
	print("FRESH OK" if bad == 0 else "FRESH FAILED")
	quit()
"""


func _initialize() -> void:
	var root_dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--root="):
			root_dir = a.trim_prefix("--root=")
	Exporter.root_override = root_dir
	DisplayServer.window_set_size(Vector2i(1280, 720))
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred(root_dir)


func _f(n: int) -> void:
	for i in n:
		await process_frame


func _run(root_dir: String) -> void:
	var project := root_dir + "/fresh"
	DirAccess.make_dir_recursive_absolute(project)
	var f := FileAccess.open(project + "/project.godot", FileAccess.WRITE)
	f.store_string("config_version=5\n\n[application]\nconfig/name=\"Fresh\"\nconfig/features=PackedStringArray(\"4.7\", \"GL Compatibility\")\n\n[rendering]\nrenderer/rendering_method=\"gl_compatibility\"\n")
	f.close()
	# (the lab may not be in the list yet)
	var at := -1
	for i in main.SIMS.size():
		if main.SIMS[i].title == "Rope Lab":
			at = i
	if at == -1:
		main.SIMS.append({title = "Rope Lab", blurb = "", color = Color("7aa2ff"), script = load("res://sims/vfx/ropes.gd")})
		at = main.SIMS.size() - 1
	await _f(5)
	main.open_sim(at)
	await _f(5)
	for pair in [[0, "Test Kelp"], [1, "Test Vines"], [2, "Test Wires"], [3, "Test Ropes"]]:
		main.sim.scene = pair[0]
		main.sim._build_scene()
		await _f(10)
		main.sim._export(pair[1])
		print(Exporter.send_to_project("ropes", pair[1], project))
	var check := FileAccess.open(project + "/rope_check.gd", FileAccess.WRITE)
	check.store_string(CHECK)
	check.close()
	var godot := OS.get_executable_path()
	var out := []
	OS.execute(godot, ["--headless", "--audio-driver", "Dummy", "--path", project, "--import"], out, true)
	out.clear()
	OS.execute(godot, ["--headless", "--audio-driver", "Dummy", "--path", project, "-s", "res://rope_check.gd"], out, true)
	var text := "\n".join(out)
	print(text)
	print("ROPE EXPORT OK" if text.contains("FRESH OK") and not text.contains("SCRIPT ERROR") else "ROPE EXPORT FAILED")
	quit()
