extends SceneTree
## Saves a screenshot of the menu and every sim to the folder given by --shots=<dir>.
## godot --path . -s tests/shots.gd -- --shots=C:/tmp/shots [--portrait]

var main: Control
var out := "user://shots"
var portrait := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			out = arg.trim_prefix("--shots=")
		if arg == "--portrait":
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
	root.get_texture().get_image().save_png("%s/%s%s.png" % [out, name, "_p" if portrait else ""])


func _run() -> void:
	await _frames(30)
	await _snap("menu")
	for i in main.SIMS.size():
		main.open_sim(i)
		await _frames(90)
		var t0 := Time.get_ticks_usec()
		await _frames(60)
		print("%s: %.1f ms a frame" % [main.SIMS[i].title, (Time.get_ticks_usec() - t0) / 60000.0])
		await _snap("sim%d" % i)
	quit()
