extends VBoxContainer
## A colour-over-life gradient editable by touch: tap a stop to pick it, drag it along,
## tap the bar to add a stop, hold a stop (or right-click it) to delete it. The picked
## stop takes a colour from the palette and an alpha from the slider. Presets below.
## Emits changed(stops) as [[offset, "rrggbbaa"], ...].

signal changed(stops: Array)

const C_INSET := Color("1f1f22")
const C_EDGE := Color("111113")
const C_ACCENT_HI := Color("6fa3de")
const PALETTE := ["ffffff", "c8c8c8", "808080", "3c3c3c", "000000", "fff3b0", "ffd040", "ff9020",
	"ff3c10", "8a0010", "ff70b0", "e040ff", "8040ff", "3050ff", "60b0ff", "60fff0", "20c090", "60ff60",
	"d0ff60", "8a6a4a"]
const PRESETS := {
	"Fire": [[0, "fff3b0ff"], [0.25, "ffb030ff"], [0.6, "ff4010c0"], [1, "40100000"]],
	"Smoke": [[0, "40404000"], [0.15, "505050a0"], [1, "80808000"]],
	"Spark": [[0, "ffffe0ff"], [0.3, "ffc040ff"], [1, "ff400000"]],
	"Magic": [[0, "ffffffff"], [0.4, "c080ffff"], [1, "4040ff00"]],
	"Ice": [[0, "ffffffff"], [0.5, "90e0ffc0"], [1, "3070ff00"]],
	"Toxic": [[0, "e0ff80ff"], [0.5, "40ff60c0"], [1, "10602000"]],
	"Fade": [[0, "ffffffff"], [1, "ffffff00"]],
	"Pop in": [[0, "ffffff00"], [0.15, "ffffffff"], [0.7, "ffffffff"], [1, "ffffff00"]],
}

var stops: Array = []
var selected := 0
var bar := Control.new()
var alpha := HSlider.new()
var _drag := -1
var _press_pos := Vector2.ZERO
var _press_time := 0.0
var _moved := false


func _init(start: Array) -> void:
	stops = _copy(start)
	add_theme_constant_override("separation", 6)
	bar.custom_minimum_size = Vector2(0, 64)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.draw.connect(_draw_bar)
	bar.gui_input.connect(_bar_input)
	bar.add_to_group("keeps_drags")
	add_child(bar)
	# palette for the picked stop
	var grid := GridContainer.new()
	grid.columns = 10
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	add_child(grid)
	for hex: String in PALETTE:
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(0, 30)
		sw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var s := StyleBoxFlat.new()
		s.bg_color = Color(hex)
		s.border_color = C_EDGE
		s.set_border_width_all(1)
		sw.add_theme_stylebox_override("normal", s)
		var h := s.duplicate()
		h.border_color = Color.WHITE
		h.set_border_width_all(2)
		sw.add_theme_stylebox_override("hover", h)
		sw.add_theme_stylebox_override("pressed", h)
		sw.pressed.connect(func() -> void: _set_color(Color(hex)))
		grid.add_child(sw)
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 8)
	add_child(arow)
	var al := Label.new()
	al.text = "Stop alpha"
	al.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arow.add_child(al)
	alpha.min_value = 0.0
	alpha.max_value = 1.0
	alpha.step = 0.01
	alpha.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alpha.custom_minimum_size.y = 36
	alpha.value_changed.connect(func(v: float) -> void:
		var c := Color(stops[selected][1])
		c.a = v
		stops[selected][1] = c.to_html(true)
		bar.queue_redraw()
		changed.emit(_copy(stops)))
	arow.add_child(alpha)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	add_child(row)
	for key: String in PRESETS:
		var b := Button.new()
		b.text = key
		b.custom_minimum_size = Vector2(0, 32)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(func() -> void:
			stops = _copy(PRESETS[key])
			selected = 0
			_sync_alpha()
			bar.queue_redraw()
			changed.emit(_copy(stops)))
		row.add_child(b)
	_sync_alpha()


func _set_color(c: Color) -> void:
	c.a = Color(stops[selected][1]).a
	stops[selected][1] = c.to_html(true)
	bar.queue_redraw()
	changed.emit(_copy(stops))


func _sync_alpha() -> void:
	alpha.set_value_no_signal(Color(stops[selected][1]).a)


func _process(delta: float) -> void:
	if _drag != -1 and not _moved and stops.size() > 2:
		_press_time += delta
		bar.queue_redraw()
		if _press_time > 0.6:
			stops.remove_at(_drag)
			selected = clampi(selected, 0, stops.size() - 1)
			_drag = -1
			_sync_alpha()
			changed.emit(_copy(stops))
			bar.queue_redraw()


func _strip() -> Rect2:
	return Rect2(Vector2(12, 4), Vector2(bar.size.x - 24, 32))


func _stop_x(i: int) -> float:
	var r := _strip()
	return r.position.x + float(stops[i][0]) * r.size.x


func _hit(pos: Vector2) -> int:
	var best := -1
	var best_d := 22.0
	for i in stops.size():
		var d := absf(_stop_x(i) - pos.x)
		if d < best_d and pos.y > 30:
			best_d = d
			best = i
	return best


func _bar_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		bar.accept_event()
		if e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
			var i := _hit(e.position)
			if i != -1 and stops.size() > 2:
				stops.remove_at(i)
				selected = clampi(selected, 0, stops.size() - 1)
				_sync_alpha()
				changed.emit(_copy(stops))
				bar.queue_redraw()
			return
		if e.button_index != MOUSE_BUTTON_LEFT:
			return
		if e.pressed:
			_drag = _hit(e.position)
			_press_pos = e.position
			_press_time = 0.0
			_moved = false
			if _drag != -1:
				selected = _drag
				_sync_alpha()
		else:
			if _drag == -1 and _press_pos.distance_to(e.position) < 8.0:
				_add(e.position.x)
			_drag = -1
		bar.queue_redraw()
	elif e is InputEventMouseMotion and _drag != -1:
		bar.accept_event()
		if not _moved and _press_pos.distance_to(e.position) < 6.0:
			return
		_moved = true
		var r := _strip()
		stops[_drag][0] = clampf((e.position.x - r.position.x) / r.size.x, 0.0, 1.0)
		# keep the list in order as a stop passes another
		var picked: Array = stops[_drag]
		stops.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		_drag = stops.find(picked)
		selected = _drag
		bar.queue_redraw()
		changed.emit(_copy(stops))


func _add(x: float) -> void:
	var r := _strip()
	var t := clampf((x - r.position.x) / r.size.x, 0.0, 1.0)
	var c := build(stops).sample(t)
	stops.append([t, c.to_html(true)])
	stops.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in stops.size():
		if is_equal_approx(stops[i][0], t):
			selected = i
	_sync_alpha()
	changed.emit(_copy(stops))


func _draw_bar() -> void:
	var r := _strip()
	bar.draw_rect(Rect2(Vector2.ZERO, bar.size), C_INSET)
	# checkerboard under the strip, so alpha shows
	var cell := 8.0
	var x := 0
	while x * cell < r.size.x:
		for y in 4:
			var col := Color("9a9aa3") if (x + y) % 2 == 0 else Color("5c5c63")
			bar.draw_rect(Rect2(r.position + Vector2(x * cell, y * cell), Vector2(minf(cell, r.size.x - x * cell), cell)), col)
		x += 1
	var g := build(stops)
	var steps := 96
	for k in steps:
		var t := (k + 0.5) / steps
		bar.draw_rect(Rect2(r.position + Vector2(r.size.x * k / steps, 0), Vector2(r.size.x / steps + 1, r.size.y)), g.sample(t))
	bar.draw_rect(r, C_EDGE, false, 1.0)
	# the stops: a little house under the strip
	for i in stops.size():
		var sx := _stop_x(i)
		var c := Color(stops[i][1])
		c.a = 1.0
		var top := r.end.y + 3
		var pts := PackedVector2Array([Vector2(sx, top), Vector2(sx + 10, top + 9), Vector2(sx + 10, top + 24),
			Vector2(sx - 10, top + 24), Vector2(sx - 10, top + 9)])
		bar.draw_colored_polygon(pts, C_ACCENT_HI if i == selected else C_EDGE)
		bar.draw_rect(Rect2(Vector2(sx - 7, top + 10), Vector2(14, 11)), c)
		if i == _drag and not _moved and _press_time > 0.15 and stops.size() > 2:
			bar.draw_arc(Vector2(sx, top + 15), 15, -PI / 2, -PI / 2 + TAU * clampf(_press_time / 0.6, 0, 1), 24, Color("ff6b6b"), 2.0)


static func build(st: Array) -> Gradient:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for s: Array in st:
		offsets.append(float(s[0]))
		colors.append(Color(s[1]))
	g.offsets = offsets
	g.colors = colors
	return g


static func _copy(st: Array) -> Array:
	var out := []
	for s: Array in st:
		out.append([float(s[0]), String(s[1])])
	return out
