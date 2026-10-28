extends SceneTree
## Boids: GameCommon's flock under load, and the Boids lab's export.
##   godot --audio-driver Dummy --path . -s tests/boids_check.gd -- --perf [--count=500]
##       every preset at --count boids for 3 s each: thinking ms a frame, how many thought about a
##       frame, mean neighbours. Fails (BOIDS PERF SLOW) if a preset's flock takes over 8 ms.
##   godot --audio-driver Dummy --path . -s tests/boids_check.gd -- --export=C:/tmp/lib
##       the Boids lab exports into a scratch library and sends the asset to a fresh empty
##       project at <dir>/fresh (open it, or run its check.tscn, to try it).

var main: Control


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var count := 500
	for a in args:
		if a.begins_with("--count="):
			count = int(a.trim_prefix("--count="))
	for a in args:
		if a == "--perf":
			_perf.call_deferred(count)
			return
		if a.begins_with("--export="):
			_export.call_deferred(a.trim_prefix("--export="))
			return
	print("--perf or --export=<dir>")
	quit(1)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _perf(count: int) -> void:
	var slow := false
	for name: String in FlockRules.PRESETS:
		var flock := Flock.new()
		flock.rules = FlockRules.preset(name)
		flock.rules.count = count
		flock.target = Vector3(0, 0, 0)
		root.add_child(flock)
		await _frames(30)
		var worst := 0.0
		var sum := 0.0
		var steer := 0
		var near := 0.0
		for k in 180:
			await process_frame
			sum += flock.sim_ms
			worst = maxf(worst, flock.sim_ms)
			steer += flock.steered
			near += flock.mean_neighbours
		var mean := sum / 180.0
		print("%-15s %4d boids: %.2f ms a frame (worst %.2f), %d of them thought about a frame, %.1f neighbours" % [
			name, flock.boid_count(), mean, worst, steer / 180, near / 180.0])
		if mean > 8.0:
			slow = true
		flock.queue_free()
		await _frames(2)
	print("BOIDS PERF SLOW" if slow else "BOIDS PERF OK")
	quit(1 if slow else 0)


func _export(dir: String) -> void:
	Exporter.root_override = dir
	DisplayServer.window_set_size(Vector2i(1280, 720))
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main.SIMS.append({title = "Boids", blurb = "", color = Color("7aa2ff"), script = load("res://sims/vfx/boids.gd")})
	main.open_sim(main.SIMS.size() - 1)
	await _frames(10)
	var project := dir + "/fresh"
	DirAccess.make_dir_recursive_absolute(project)
	var f := FileAccess.open(project + "/project.godot", FileAccess.WRITE)
	f.store_string("config_version=5\n\n[application]\nconfig/name=\"Fresh\"\nconfig/features=PackedStringArray(\"4.7\", \"GL Compatibility\")\n\n[rendering]\nrenderer/rendering_method=\"gl_compatibility\"\n")
	f.close()
	# each preset's flock, as the lab exports it
	for i in FlockRules.PRESETS.size():
		main.sim.use_preset(i)
		await _frames(5)
		var name: String = "Test " + FlockRules.PRESETS[i]
		main.sim._export(name)
		print(Exporter.send_to_project("flocks", name, project))
	# a scene in the fresh project that instances every exported flock and runs them
	var check := "extends Node3D\n\nfunc _ready() -> void:\n"
	for i in FlockRules.PRESETS.size():
		var slug: String = Exporter.slug("Test " + str(FlockRules.PRESETS[i]))
		check += "\tvar f%d: Flock = load(\"res://assets/flocks/%s.tscn\").instantiate()\n\tadd_child(f%d)\n" % [i, slug, i]
		check += "\tvar r%d := load(\"res://assets/flocks/%s.tres\") as FlockRules\n\tassert(r%d != null)\n" % [i, slug, i]
	check += "\tvar cam := Camera3D.new()\n\tadd_child(cam)\n\tcam.look_at_from_position(Vector3(0, 20, 60), Vector3(0, 10, 0))\n"
	check += "\nvar _t := 0\n\nfunc _process(_d: float) -> void:\n\t_t += 1\n\tif _t == 120:\n"
	check += "\t\tfor c in get_children():\n\t\t\tif c is Flock:\n\t\t\t\tprint(c.name, \" \", c.boid_count(), \" boids round \", c.centre())\n"
	check += "\t\tprint(\"FRESH FLOCKS OK\")\n\t\tget_tree().quit()\n"
	var g := FileAccess.open(project + "/check.gd", FileAccess.WRITE)
	g.store_string(check)
	g.close()
	var s := FileAccess.open(project + "/check.tscn", FileAccess.WRITE)
	s.store_string("[gd_scene format=3]\n\n[ext_resource type=\"Script\" path=\"res://check.gd\" id=\"1\"]\n\n[node name=\"Check\" type=\"Node3D\"]\nscript = ExtResource(\"1\")\n")
	s.close()
	print("EXPORTED")
	quit()
