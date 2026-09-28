extends SceneTree
## Headless smoke test: opens every sim, pokes it with touches, flips between
## landscape and portrait, and presses every control.
## godot --headless --path . -s tests/smoke.gd

var main: Control


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	Input.parse_input_event(e)


func _gesture(from: Vector2, to: Vector2) -> void:
	_touch(0, from, true)
	await _frames(2)
	for k in 10:
		_drag(0, from.lerp(to, k / 9.0))
		await _frames(1)
	_touch(0, to, false)
	await _frames(2)


func _run() -> void:
	await _frames(5)
	for size in [Vector2(1280, 720), Vector2(720, 1500)]:
		root.size = Vector2i(size)
		await _frames(3)
		for i in main.SIMS.size():
			main.open_sim(i)
			await _frames(10)
			var a: Rect2 = main.area
			print("%s @ %s area %s" % [main.SIMS[i].title, size, a.size])
			var c := a.get_center()
			await _gesture(c + Vector2(-80, -60), c + Vector2(90, 70))
			await _gesture(c + Vector2(0, 40), c + Vector2(0, 40))
			await _gesture(a.position + Vector2(40, 40), c)
			# press every button and toggle, pick the last option of every choice
			for spec in main.sim.controls():
				match spec.type:
					"button": spec.on.call()
					"toggle":
						spec.on.call(not spec.value)
						spec.on.call(spec.value)
					"choice": spec.on.call(spec.options.size() - 1)
					"slider": spec.on.call(spec.max)
				await _frames(2)
			await _gesture(c, c + Vector2(50, -50))
			await _frames(60)
			main.show_help()
			await _frames(2)
	main.show_menu()
	await _frames(5)
	print("SMOKE OK")
	quit()
