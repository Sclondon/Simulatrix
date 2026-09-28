extends Sim
## Double pendulum integrated with RK4. Chaos ghosts start a hair apart and drift.

const GHOST_OFFSET := 0.001 # radians
const TRAIL_MAX := 360
const GHOST_COLORS := [Color("ff5fa2"), Color("3de0c4"), Color("ffd166")]

var g := 9.81
var mass_ratio := 1.0 # m2 / m1
var length_ratio := 1.0 # l2 / l1, total length stays 2 m
var damping := 0.0
var ghosts := true
var trails := true
var speed := 1.0

var states: Array[PackedFloat64Array] = [] # [t1, t2, w1, w2] per pendulum
var trail_pts: Array[PackedVector2Array] = []
var grabbed := -1 # which bob (1 or 2) is held, -1 none
var grab_index := -1


func help() -> String:
	return "Two rods, two weights, and no way to predict where it goes.\n\nDrag either weight to pose the pendulum, then let go. With Chaos ghosts on, three copies start just 0.001 radians apart. Watch them move as one, then split up completely.\n\nSmall swings stay calm and regular. Big ones turn chaotic. Try making the lower weight much heavier or lighter."


func hint() -> String:
	return "Drag a weight to pose it, then let go"


func controls() -> Array:
	return [
		{type = "toggle", label = "Chaos ghosts", value = ghosts, on = _set_ghosts},
		{type = "toggle", label = "Trails", value = trails, on = func(v: bool) -> void:
			trails = v
			_clear_trails()},
		{type = "slider", label = "Gravity", min = 1.0, max = 30.0, step = 0.1, value = g, fmt = "%.1f m/s²",
			on = func(v: float) -> void: g = v},
		{type = "slider", label = "Lower mass", min = 0.2, max = 5.0, step = 0.05, value = mass_ratio, fmt = "%.2fx",
			on = func(v: float) -> void: mass_ratio = v},
		{type = "slider", label = "Lower rod", min = 0.3, max = 3.0, step = 0.05, value = length_ratio, fmt = "%.2fx",
			on = func(v: float) -> void:
				length_ratio = v
				_clear_trails()},
		{type = "slider", label = "Friction", min = 0.0, max = 1.0, step = 0.01, value = damping, fmt = "%.2f",
			on = func(v: float) -> void: damping = v},
		{type = "slider", label = "Time", min = 0.1, max = 2.0, step = 0.05, value = speed, fmt = "%.2fx",
			on = func(v: float) -> void: speed = v},
		{type = "button", label = "Big drop", on = func() -> void: _pose(PI * 0.75, PI * 0.9)},
		{type = "button", label = "Upside down", on = func() -> void: _pose(PI - 0.02, PI - 0.01)},
		{type = "button", label = "Gentle", on = func() -> void: _pose(0.35, 0.25)},
	]


func _ready() -> void:
	_pose(PI * 0.75, PI * 0.9)


func _lengths() -> Vector2:
	var l1 := 2.0 / (1.0 + length_ratio)
	return Vector2(l1, 2.0 - l1)


func _scale() -> float:
	return minf(size.x, size.y) * 0.44 / 2.0 # pixels per metre


func _pivot() -> Vector2:
	return size * 0.5


func _pose(t1: float, t2: float) -> void:
	var count := 3 if ghosts else 1
	states.clear()
	for i in count:
		states.append(PackedFloat64Array([t1 + GHOST_OFFSET * i, t2, 0.0, 0.0]))
	_clear_trails()


func _set_ghosts(v: bool) -> void:
	ghosts = v
	var s := states[0]
	_pose(s[0], s[1])
	for i in states.size():
		var st := states[i]
		st[2] = s[2]
		st[3] = s[3]
		states[i] = st


func _clear_trails() -> void:
	trail_pts.clear()
	for i in states.size():
		trail_pts.append(PackedVector2Array())


func _deriv(s: PackedFloat64Array) -> PackedFloat64Array:
	var l := _lengths()
	var m1 := 1.0
	var m2 := mass_ratio
	var t1 := s[0]
	var t2 := s[1]
	var w1 := s[2]
	var w2 := s[3]
	var d := t1 - t2
	var den := 2.0 * m1 + m2 - m2 * cos(2.0 * d)
	var a1 := (-g * (2.0 * m1 + m2) * sin(t1) - m2 * g * sin(t1 - 2.0 * t2)
		- 2.0 * sin(d) * m2 * (w2 * w2 * l.y + w1 * w1 * l.x * cos(d))) / (l.x * den)
	var a2 := (2.0 * sin(d) * (w1 * w1 * l.x * (m1 + m2) + g * (m1 + m2) * cos(t1)
		+ w2 * w2 * l.y * m2 * cos(d))) / (l.y * den)
	a1 -= damping * w1
	a2 -= damping * w2
	return PackedFloat64Array([w1, w2, a1, a2])


func _add(s: PackedFloat64Array, k: PackedFloat64Array, h: float) -> PackedFloat64Array:
	var out := s.duplicate()
	for i in 4:
		out[i] += k[i] * h
	return out


func _rk4(s: PackedFloat64Array, h: float) -> PackedFloat64Array:
	var k1 := _deriv(s)
	var k2 := _deriv(_add(s, k1, h * 0.5))
	var k3 := _deriv(_add(s, k2, h * 0.5))
	var k4 := _deriv(_add(s, k3, h))
	var out := s.duplicate()
	for i in 4:
		out[i] += h / 6.0 * (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i])
	return out


func _bobs(s: PackedFloat64Array) -> Array[Vector2]:
	var l := _lengths() * _scale()
	var p1 := _pivot() + Vector2(sin(s[0]), cos(s[0])) * l.x
	var p2 := p1 + Vector2(sin(s[1]), cos(s[1])) * l.y
	return [p1, p2]


func _physics_process(delta: float) -> void:
	if grabbed == -1:
		const STEPS := 8
		var h := delta * speed / STEPS
		for i in states.size():
			var s := states[i]
			for step in STEPS:
				s = _rk4(s, h)
			states[i] = s
	if trails:
		for i in states.size():
			var pts := trail_pts[i]
			pts.append(_bobs(states[i])[1])
			if pts.size() > TRAIL_MAX:
				pts = pts.slice(pts.size() - TRAIL_MAX)
			trail_pts[i] = pts
	queue_redraw()


func touch_down(index: int, pos: Vector2) -> void:
	if grabbed != -1:
		return
	var b := _bobs(states[0])
	var reach := 60.0
	if pos.distance_to(b[1]) < reach:
		grabbed = 2
	elif pos.distance_to(b[0]) < reach:
		grabbed = 1
	else:
		return
	grab_index = index
	touch_move(index, pos)


func touch_move(index: int, pos: Vector2) -> void:
	if index != grab_index:
		return
	var s := states[0]
	if grabbed == 1:
		var to := pos - _pivot()
		s[0] = atan2(to.x, to.y)
	else:
		var p1 := _bobs(s)[0]
		var to := pos - p1
		s[1] = atan2(to.x, to.y)
	_pose(s[0], s[1])


func touch_up(index: int, _pos: Vector2) -> void:
	if index == grab_index:
		grabbed = -1
		grab_index = -1


func _draw() -> void:
	draw_backdrop(Color("10131f"))
	var pivot := _pivot()
	var reach := _scale() * 2.0
	draw_arc(pivot, reach, 0, TAU, 96, Color(1, 1, 1, 0.05), 2.0, true)
	var multi := states.size() > 1
	if trails:
		for i in trail_pts.size():
			var pts := trail_pts[i]
			if pts.size() < 2:
				continue
			var base: Color = GHOST_COLORS[i] if multi else Color("7aa2ff")
			var cols := PackedColorArray()
			cols.resize(pts.size())
			for j in pts.size():
				cols[j] = Color(base, float(j) / pts.size() * 0.8)
			draw_polyline_colors(pts, cols, 2.5, true)
	var m_scale := clampf(minf(size.x, size.y) / 720.0, 0.6, 1.4)
	var r1 := 18.0 * m_scale
	var r2 := 18.0 * pow(mass_ratio, 1.0 / 3.0) * m_scale
	for i in range(states.size() - 1, -1, -1):
		var b := _bobs(states[i])
		var c: Color = GHOST_COLORS[i] if multi else Color("e8ecf8")
		var rod := Color(c, 0.9 if i == 0 else 0.55)
		draw_line(pivot, b[0], rod, 5.0, true)
		draw_line(b[0], b[1], rod, 5.0, true)
		draw_circle(b[0], r1, Color(c, 1.0 if i == 0 else 0.7))
		draw_circle(b[1], r2, Color(c, 1.0 if i == 0 else 0.7))
	draw_circle(pivot, 8.0, Color("aab4cf"))
	if grabbed != -1:
		var b := _bobs(states[0])[grabbed - 1]
		draw_arc(b, 34.0 * m_scale, 0, TAU, 32, Color(1, 1, 1, 0.5), 3.0, true)
