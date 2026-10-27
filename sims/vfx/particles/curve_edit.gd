extends VBoxContainer
## A curve over a particle's life (x 0..1, y 0..1), editable by touch:
## drag a point; tap empty space to add one; hold a point (or right-click it) to delete it.
## The end points stay at x 0 and 1. Presets below. Emits changed(points) as [[x, y], ...].

signal changed(points: Array)

const C_INSET := Color("1f1f22")
const C_EDGE := Color("111113")
const C_LINE := Color("2e2e33")
const C_ACCENT := Color("4f86c6")
const C_ACCENT_HI := Color("6fa3de")
const PRESETS := {
	"Flat": [[0, 1], [1, 1]],
	"Grow": [[0, 0.2], [1, 1]],
	"Shrink": [[0, 1], [1, 0]],
	"Pop": [[0, 0], [0.2, 1], [1, 0]],
	"Swell": [[0, 0.3], [0.6, 1], [1, 0.8]],
	"Pulse": [[0, 0.3], [0.25, 1], [0.5, 0.3], [0.75, 1], [1, 0.3]],
}

var points: Array = []
var area := Control.new()
var _drag := -1
var _press_pos := Vector2.ZERO
var _press_time := 0.0
var _moved := false


func _init(start: Array = [[0, 1], [1, 1]]) -> void:
	points = _copy(start)
	add_theme_constant_override("separation", 4)
	area.custom_minimum_size = Vector2(0, 120)
	area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.draw.connect(_draw_area)
	area.gui_input.connect(_area_input)
	area.add_to_group("keeps_drags") # the panel must not scroll when a point is dragged
	area.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(area)
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
			points = _copy(PRESETS[key])
			area.queue_redraw()
			changed.emit(_copy(points)))
		row.add_child(b)


func _process(delta: float) -> void:
	# hold a point still to delete it
	if _drag > 0 and _drag < points.size() - 1 and not _moved:
		_press_time += delta
		area.queue_redraw()
		if _press_time > 0.6:
			points.remove_at(_drag)
			_drag = -1
			changed.emit(_copy(points))
			area.queue_redraw()


func _to_px(p: Array) -> Vector2:
	var r := _inner()
	return r.position + Vector2(p[0] * r.size.x, (1.0 - p[1]) * r.size.y)


func _from_px(v: Vector2) -> Vector2:
	var r := _inner()
	return Vector2(clampf((v.x - r.position.x) / r.size.x, 0, 1), clampf(1.0 - (v.y - r.position.y) / r.size.y, 0, 1))


func _inner() -> Rect2:
	return Rect2(Vector2(10, 10), area.size - Vector2(20, 20))


func _area_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		area.accept_event()
		if e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
			var i := _hit(e.position)
			if i > 0 and i < points.size() - 1:
				points.remove_at(i)
				changed.emit(_copy(points))
				area.queue_redraw()
			return
		if e.button_index != MOUSE_BUTTON_LEFT:
			return
		if e.pressed:
			_drag = _hit(e.position)
			_press_pos = e.position
			_press_time = 0.0
			_moved = false
		else:
			if _drag == -1 and _press_pos.distance_to(e.position) < 8.0:
				_add(_from_px(e.position))
			elif _drag != -1 and _moved:
				changed.emit(_copy(points))
			_drag = -1
			area.queue_redraw()
	elif e is InputEventMouseMotion and _drag != -1:
		area.accept_event()
		if not _moved and _press_pos.distance_to(e.position) < 6.0:
			return
		_moved = true
		var v := _from_px(e.position)
		if _drag == 0:
			v.x = 0.0
		elif _drag == points.size() - 1:
			v.x = 1.0
		else:
			v.x = clampf(v.x, points[_drag - 1][0] + 0.01, points[_drag + 1][0] - 0.01)
		points[_drag] = [v.x, v.y]
		area.queue_redraw()
		changed.emit(_copy(points))


func _hit(pos: Vector2) -> int:
	var best := -1
	var best_d := 26.0
	for i in points.size():
		var d := _to_px(points[i]).distance_to(pos)
		if d < best_d:
			best_d = d
			best = i
	return best


func _add(v: Vector2) -> void:
	for i in points.size() - 1:
		if v.x > points[i][0] and v.x < points[i + 1][0]:
			points.insert(i + 1, [v.x, v.y])
			changed.emit(_copy(points))
			return


func _draw_area() -> void:
	var full := Rect2(Vector2.ZERO, area.size)
	area.draw_rect(full, C_INSET)
	area.draw_rect(full, C_EDGE, false, 1.0)
	var r := _inner()
	for k in 5:
		var x := r.position.x + r.size.x * k / 4.0
		var y := r.position.y + r.size.y * k / 4.0
		area.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), C_LINE)
		area.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), C_LINE)
	var curve := build(points)
	var line := PackedVector2Array()
	for k in 65:
		var t := k / 64.0
		line.append(r.position + Vector2(t * r.size.x, (1.0 - curve.sample(t)) * r.size.y))
	area.draw_polyline(line, C_ACCENT_HI, 2.0)
	for i in points.size():
		var c := _to_px(points[i])
		var hot := i == _drag
		area.draw_rect(Rect2(c - Vector2(7, 7), Vector2(14, 14)), C_EDGE)
		area.draw_rect(Rect2(c - Vector2(5, 5), Vector2(10, 10)), Color.WHITE if hot else C_ACCENT)
		if hot and not _moved and i > 0 and i < points.size() - 1 and _press_time > 0.15:
			# the hold-to-delete ring fills up
			area.draw_arc(c, 14, -PI / 2, -PI / 2 + TAU * clampf(_press_time / 0.6, 0, 1), 24, Color("ff6b6b"), 2.0)


## A Curve through the points, with smooth tangents.
static func build(pts: Array) -> Curve:
	var c := Curve.new()
	for i in pts.size():
		var a: Array = pts[maxi(i - 1, 0)]
		var b: Array = pts[mini(i + 1, pts.size() - 1)]
		var dx: float = b[0] - a[0]
		var slope: float = (b[1] - a[1]) / dx if dx > 0.0001 else 0.0
		c.add_point(Vector2(pts[i][0], pts[i][1]), slope, slope)
	return c


static func _copy(pts: Array) -> Array:
	var out := []
	for p: Array in pts:
		out.append([float(p[0]), float(p[1])])
	return out
