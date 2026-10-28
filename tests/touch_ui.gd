extends SceneTree
## Phone touch checks on the Properties panel, at an iPhone's CSS size:
## a vertical drag that starts on a button scrolls the panel and does not press the button;
## a sideways drag on a value bar changes it; a vertical drag on a value bar scrolls instead.
## godot --audio-driver Dummy --path . -s tests/touch_ui.gd

var main: Control
var failures := 0


func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(390, 844))
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _touch(pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.position = root.get_final_transform() * pos # canvas -> window pixels
	e.pressed = pressed
	Input.parse_input_event(e)


func _swipe(from: Vector2, to: Vector2) -> void:
	_touch(from, true)
	await _frames(2)
	for k in 12:
		var e := InputEventScreenDrag.new()
		var p := from.lerp(to, (k + 1) / 12.0)
		e.position = root.get_final_transform() * p
		e.relative = root.get_final_transform().basis_xform((to - from) / 12.0)
		e.velocity = (to - from) * 5.0
		Input.parse_input_event(e)
		await _frames(1)
	_touch(to, false)
	await _frames(3)


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		failures += 1


func _first(node: Node, test: Callable) -> Control:
	for c in node.get_children():
		if c is Control and c.is_visible_in_tree() and test.call(c):
			return c
		var found := _first(c, test)
		if found:
			return found
	return null


func _run() -> void:
	await _frames(5)
	_check(main.compact, "phone size turns on compact mode (scale %.2f)" % main.get_window().content_scale_factor)
	# Cloud Lab: a long panel of choices and value bars
	for i in main.SIMS.size():
		if main.SIMS[i].title == "Cloud Lab":
			main.open_sim(i)
	await _frames(20)
	var scroll: ScrollContainer = main.panel_scroll
	var panel_rect: Rect2 = scroll.get_global_rect()

	# 1. vertical drag starting on an unpressed choice button
	var button: Button = _first(main.panel_box, func(c: Control) -> bool:
		return c is Button and c.toggle_mode and not c.button_pressed and not c is CheckBox \
			and panel_rect.encloses(c.get_global_rect()))
	var fired := [0]
	button.pressed.connect(func() -> void: fired[0] += 1)
	var before := scroll.scroll_vertical
	var at := button.get_global_rect().get_center()
	await _swipe(at, at - Vector2(0, 160))
	_check(scroll.scroll_vertical > before + 60, "drag from a button scrolls the panel (%d -> %d)" % [before, scroll.scroll_vertical])
	_check(fired[0] == 0, "the button under the drag did not fire")

	# 2. a tap on that button still works
	await _frames(30) # let any fling settle
	scroll.scroll_vertical = 0
	await _frames(3)
	at = button.get_global_rect().get_center()
	if panel_rect.has_point(at):
		_touch(at, true)
		await _frames(2)
		_touch(at, false)
		await _frames(3)
		_check(fired[0] == 1, "a tap presses the button")

	# 3. value bars: sideways drag changes, vertical drag scrolls
	scroll.scroll_vertical = 0
	await _frames(3)
	var bar: ValueBar = _first(main.panel_box, func(c: Control) -> bool:
		return c is ValueBar and panel_rect.encloses(c.get_global_rect()))
	var v0 := bar.value
	var r := bar.get_global_rect()
	await _swipe(r.get_center() - Vector2(r.size.x * 0.3, 0), r.get_center() + Vector2(r.size.x * 0.4, 0))
	_check(not is_equal_approx(bar.value, v0), "sideways drag on a value bar changes it (%.2f -> %.2f)" % [v0, bar.value])
	var v1 := bar.value
	before = scroll.scroll_vertical
	r = bar.get_global_rect()
	await _swipe(r.get_center(), r.get_center() - Vector2(0, 150))
	_check(is_equal_approx(bar.value, v1), "vertical drag on a value bar leaves it alone")
	_check(scroll.scroll_vertical > before + 50, "vertical drag on a value bar scrolls the panel")

	# 4. the sheet handle
	var tall: bool = main.sheet_tall
	var head_at: Vector2 = main.panel.get_global_rect().position + Vector2(100, 10)
	_touch(head_at, true)
	await _frames(2)
	_touch(head_at, false)
	await _frames(3)
	_check(main.sheet_tall != tall, "tapping the Properties header pulls the sheet taller")

	print("TOUCH UI %s" % ("OK" if failures == 0 else "FAILED (%d)" % failures))
	quit(failures)
