extends SceneTree
## Drives a ~16 s tour of every sim for the arcade attract video.
## godot --path . --fixed-fps 30 --write-movie out.avi -s tests/attract.gd
## (drop an override.cfg with a 960x540 window first; Movie Maker uses the window size)

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
	e.position = main.area.position + pos
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = main.area.position + pos
	Input.parse_input_event(e)


## Drags along points (in sim coordinates) over n frames.
func _swipe(points: Array, n: int) -> void:
	_touch(0, points[0], true)
	for f in n:
		var t := float(f) / (n - 1) * (points.size() - 1)
		var k := mini(int(t), points.size() - 2)
		_drag(0, (points[k] as Vector2).lerp(points[k + 1], t - k))
		await process_frame
	_touch(0, points[-1], false)


func _open(i: int) -> Vector2:
	main.open_sim(i)
	main.toast.hide()
	main.toast_time = 0.0
	return main.area.size


func _run() -> void:
	main.panel_open = false
	await _frames(2)
	# Playground: already raining, pour a stream then fling a shape
	var s := _open(0)
	await _frames(20)
	await _swipe([Vector2(s.x * 0.2, s.y * 0.2), Vector2(s.x * 0.8, s.y * 0.3)], 30)
	await _frames(40)
	# Chaos Pendulum
	s = _open(1)
	await _frames(95)
	# Cloth: blow it about, then slice it
	s = _open(2)
	main.sim.wind = 900.0
	await _frames(40)
	main.sim.mode = 1
	await _swipe([Vector2(s.x * 0.3, s.y * 0.35), Vector2(s.x * 0.7, s.y * 0.6)], 18)
	await _frames(47)
	# Gravity Well: fling two extra planets
	s = _open(3)
	await _frames(15)
	await _swipe([Vector2(s.x * 0.8, s.y * 0.2), Vector2(s.x * 0.95, s.y * 0.1)], 15)
	await _frames(20)
	await _swipe([Vector2(s.x * 0.2, s.y * 0.8), Vector2(s.x * 0.1, s.y * 0.95)], 15)
	await _frames(40)
	# Ripple Tank: add a third source and drag it
	s = _open(4)
	await _frames(20)
	await _swipe([Vector2(s.x * 0.5, s.y * 0.2), Vector2(s.x * 0.5, s.y * 0.3), Vector2(s.x * 0.7, s.y * 0.25)], 45)
	await _frames(40)
	quit()
