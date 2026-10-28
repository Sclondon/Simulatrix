extends SceneTree
## Screenshots of the Boids lab: every preset after it has settled, then one with the debug views
## on, and one while a finger chases them.
## godot --audio-driver Dummy --path . -s tests/boids_shots.gd -- --shots=C:/tmp/boids [--portrait] [--only=2] [--frames=240]

var main: Control
var out := "user://boids_shots"
var portrait := false
var only := -1
var frames := 240


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			out = arg.trim_prefix("--shots=")
		elif arg.begins_with("--only="):
			only = int(arg.trim_prefix("--only="))
		elif arg.begins_with("--frames="):
			frames = int(arg.trim_prefix("--frames="))
		elif arg == "--portrait":
			portrait = true
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_size(Vector2i(540, 1170) if portrait else Vector2i(1280, 720))
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var file := "%s/%s%s.png" % [out, name, "_p" if portrait else ""]
	root.get_texture().get_image().save_png(file)
	print("saved ", file)


func _touch(pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.position = pos
	e.pressed = pressed
	Input.parse_input_event(e)


func _run() -> void:
	main.SIMS.append({title = "Boids", blurb = "", color = Color("7aa2ff"), script = load("res://sims/vfx/boids.gd")})
	await _frames(5)
	main.open_sim(main.SIMS.size() - 1)
	await _frames(5)
	var sim = main.sim
	for i in FlockRules.PRESETS.size():
		if only >= 0 and i != only:
			continue
		sim.use_preset(i)
		sim.auto_orbit = 0.0
		await _frames(frames)
		var name := "boids_%d_%s" % [i, Exporter.slug(FlockRules.PRESETS[i])]
		print("%s: flock %.2f ms, %d thought about, %.1f neighbours" % [name, sim.flock.sim_ms, sim.flock.steered, sim.flock.mean_neighbours])
		await _snap(name)
		if only >= 0 or i == 0 or i == 5:
			sim.show_perception = true
			sim.show_neighbours = true
			sim.show_velocity = true
			sim.show_bounds = true
			await _frames(4)
			await _snap(name + "_debug")
			sim.show_perception = false
			sim.show_neighbours = false
			sim.show_velocity = false
			sim.show_bounds = false
			# a finger held on the middle of them, then dragged across
			sim.poke_mode = true
			sim.hawk_on = false
			var a: Rect2 = main.area
			var c := a.get_center()
			var at: Vector2 = c
			var p: Variant = sim.camera.unproject_position(sim.flock.centre()) if not sim.camera.is_position_behind(sim.flock.centre()) else null
			if p != null:
				at = a.position + (p as Vector2) * a.size / Vector2(sim.viewport.size)
			_touch(at, true)
			for k in 30:
				var e := InputEventScreenDrag.new()
				e.position = at + Vector2(k * 3, 0)
				Input.parse_input_event(e)
				await _frames(1)
			print("chaser shown %s at %s, flock centre %s, %.2f mean fright" % [sim._chaser.visible, sim._chaser.position, sim.flock.centre(), _fright(sim.flock)])
			await _snap(name + "_chased")
			_touch(at + Vector2(90, 0), false)
			sim.poke_mode = false
			sim.hawk_on = true
	print("BOIDS SHOTS OK")
	quit()


func _fright(flock: Flock) -> float:
	var sum := 0.0
	for i in flock.boid_count():
		sum += flock.fear_of(i)
	return sum / maxf(flock.boid_count(), 1)
