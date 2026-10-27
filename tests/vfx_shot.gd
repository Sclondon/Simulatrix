extends SceneTree
## Opens one sim script by path inside the real shell and saves screenshots of it.
## godot --audio-driver Dummy --path . -s tests/vfx_shot.gd -- --sim=res://sims/vfx/ocean.gd --shots=C:/tmp/shots [--portrait] [--frames=120] [--poke]
## Prints the frame time and "VFX SHOT OK". --poke drags a finger across the scene in Poke mode before the second shot.

var main: Control
var out := "user://shots"
var portrait := false
var path := ""
var frames := 120
var poke := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			out = arg.trim_prefix("--shots=")
		elif arg.begins_with("--sim="):
			path = arg.trim_prefix("--sim=")
		elif arg.begins_with("--frames="):
			frames = int(arg.trim_prefix("--frames="))
		elif arg == "--portrait":
			portrait = true
		elif arg == "--poke":
			poke = true
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
	var script: Script = load(path)
	main.SIMS.append({title = path.get_file().get_basename().capitalize(), blurb = "", group = "VFX",
		color = Color("7aa2ff"), script = script})
	await _frames(5)
	main.open_sim(main.SIMS.size() - 1)
	await _frames(frames)
	var t0 := Time.get_ticks_usec()
	await _frames(60)
	print("%s: %.1f ms a frame" % [path, (Time.get_ticks_usec() - t0) / 60000.0])
	var name := path.get_file().get_basename()
	await _snap(name)
	if poke and main.sim is Sim3D:
		main.sim.poke_mode = true
		var a: Rect2 = main.area
		var c := a.get_center()
		_touch(c - Vector2(120, 0), true)
		for k in 30:
			var e := InputEventScreenDrag.new()
			e.position = c.lerp(c + Vector2(120, 40), k / 29.0) - Vector2(120, 0) + Vector2(k * 8, 0)
			Input.parse_input_event(e)
			await _frames(1)
		_touch(c + Vector2(120, 40), false)
		await _frames(30)
		await _snap(name + "_poked")
	# press every control once
	for spec in main.sim.controls():
		match spec.type:
			"button": spec.on.call()
			"toggle":
				spec.on.call(not spec.value)
				spec.on.call(spec.value)
			"choice":
				spec.on.call(spec.options.size() - 1)
				spec.on.call(spec.value)
			"slider":
				spec.on.call(spec.max)
				spec.on.call(spec.value)
		await _frames(2)
	await _frames(20)
	print("VFX SHOT OK")
	quit()
