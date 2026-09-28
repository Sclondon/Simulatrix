extends Sim
## Gravity well: fling planets around a star. Tap for a ready-made circular orbit.

const SUBSTEPS := 4
const TRAIL_MAX := 180
const PREDICT_STEPS := 300
const MAX_PLANETS := 60
const COLORS := [
	Color("7aa2ff"), Color("3de0c4"), Color("ff8a5b"), Color("ff5fa2"), Color("b98cff"), Color("9be564"),
]
const SIZES := [ # radius, mass relative to the star
	Vector2(5.0, 0.0005), Vector2(9.0, 0.004), Vector2(16.0, 0.03),
]

var star_pos := Vector2.ZERO
var star_mult := 1.0
var planet_size := 1
var mutual := true
var trails := true
var speed := 1.0

var planets: Array[Dictionary] = [] # {p, v, m, r, color, trail}
var stars_bg := PackedVector2Array()
var aims := {} # touch index -> {from, to}
var star_grab := -1
var flashes: Array[Dictionary] = [] # {p, t}
var time := 0.0


func help() -> String:
	return "A star with gravity that follows Newton's inverse-square law.\n\nTap anywhere to place a planet already moving at the right speed for a circular orbit. For your own launch, drag back like a slingshot and let go. The dotted line shows where it will go.\n\nWith Mutual gravity on, planets tug on each other too. When two collide they merge. Drag the star to shake up the whole system."


func hint() -> String:
	return "Tap for an orbit, or drag back and release to fling a planet"


func controls() -> Array:
	return [
		{type = "choice", label = "New planet", options = ["Moon", "Planet", "Giant"], value = planet_size,
			on = func(v: int) -> void: planet_size = v},
		{type = "slider", label = "Star mass", min = 0.2, max = 3.0, step = 0.05, value = star_mult, fmt = "%.2fx",
			on = func(v: float) -> void: star_mult = v},
		{type = "slider", label = "Time", min = 0.1, max = 3.0, step = 0.05, value = speed, fmt = "%.2fx",
			on = func(v: float) -> void: speed = v},
		{type = "toggle", label = "Mutual gravity", value = mutual, on = func(v: bool) -> void: mutual = v},
		{type = "toggle", label = "Trails", value = trails, on = func(v: bool) -> void:
			trails = v
			for pl in planets:
				pl.trail = PackedVector2Array()},
		{type = "button", label = "Solar system", on = _solar_system},
		{type = "button", label = "Clear", on = func() -> void: planets.clear()},
	]


func _ready() -> void:
	star_pos = size * 0.5
	_make_starfield()
	_solar_system()


func resize(new_size: Vector2) -> void:
	var old := size
	size = new_size
	star_pos += (size - old) * 0.5
	for pl in planets:
		pl.p += (size - old) * 0.5
		pl.trail = PackedVector2Array()
	_make_starfield()


func _make_starfield() -> void:
	stars_bg.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in int(size.x * size.y / 5000.0):
		stars_bg.append(Vector2(rng.randf() * size.x, rng.randf() * size.y))


func _unit() -> float:
	return clampf(minf(size.x, size.y) / 720.0, 0.4, 2.0)


func _gm() -> float:
	return 2.5e6 * star_mult * pow(_unit(), 3.0)


func _star_radius() -> float:
	return 26.0 * _unit() * pow(star_mult, 1.0 / 3.0)


func _circular_velocity(p: Vector2) -> Vector2:
	var to := p - star_pos
	var r := maxf(to.length(), 1.0)
	return to.orthogonal().normalized() * sqrt(_gm() / r) * -1.0


func _add_planet(p: Vector2, v: Vector2, size_index: int) -> void:
	if planets.size() >= MAX_PLANETS:
		planets.pop_front()
	var s: Vector2 = SIZES[size_index]
	planets.append({p = p, v = v, m = s.y, r = s.x * _unit(), color = COLORS.pick_random(),
		trail = PackedVector2Array()})


func _solar_system() -> void:
	planets.clear()
	var reach := minf(size.x, size.y) * 0.47
	var radii := [0.22, 0.36, 0.52, 0.72, 0.92]
	var kinds := [0, 1, 1, 2, 1]
	for i in radii.size():
		var p: Vector2 = star_pos + Vector2.from_angle(randf() * TAU) * reach * radii[i]
		_add_planet(p, _circular_velocity(p), kinds[i])


func _accel(p: Vector2, skip: int) -> Vector2:
	var to := star_pos - p
	var d2 := maxf(to.length_squared(), 100.0)
	var a := to * (_gm() / (d2 * sqrt(d2)))
	if mutual:
		for j in planets.size():
			if j == skip:
				continue
			var o: Vector2 = planets[j].p - p
			var od2 := o.length_squared() + 64.0
			a += o * (_gm() * planets[j].m / (od2 * sqrt(od2)))
	return a


func _physics_process(delta: float) -> void:
	time += delta
	var h := delta * speed / SUBSTEPS
	for step in SUBSTEPS:
		# semi-implicit Euler: stable enough for orbits and cheap
		for i in planets.size():
			planets[i].v += _accel(planets[i].p, i) * h
		for pl in planets:
			pl.p += pl.v * h
		_collide()
	var far := maxf(size.x, size.y) * 3.0
	for i in range(planets.size() - 1, -1, -1):
		if planets[i].p.distance_to(star_pos) > far:
			planets.remove_at(i)
	if trails:
		for pl in planets:
			var t: PackedVector2Array = pl.trail
			t.append(pl.p)
			if t.size() > TRAIL_MAX:
				t = t.slice(t.size() - TRAIL_MAX)
			pl.trail = t
	for i in range(flashes.size() - 1, -1, -1):
		flashes[i].t += delta
		if flashes[i].t > 0.6:
			flashes.remove_at(i)
	queue_redraw()


func _collide() -> void:
	var star_r := _star_radius()
	for i in range(planets.size() - 1, -1, -1):
		if planets[i].p.distance_to(star_pos) < star_r + planets[i].r * 0.5:
			flashes.append({p = planets[i].p, t = 0.0, r = planets[i].r * 3.0})
			planets.remove_at(i)
	var i := 0
	while i < planets.size():
		var j := i + 1
		while j < planets.size():
			var a := planets[i]
			var b := planets[j]
			if a.p.distance_to(b.p) < (a.r + b.r) * 0.8:
				var m: float = a.m + b.m
				a.v = (a.v * a.m + b.v * b.m) / m
				a.p = (a.p * a.m + b.p * b.m) / m
				a.r = pow(pow(a.r, 3.0) + pow(b.r, 3.0), 1.0 / 3.0)
				if b.m > a.m:
					a.color = b.color
				a.m = m
				flashes.append({p = a.p, t = 0.0, r = a.r * 2.0})
				planets.remove_at(j)
			else:
				j += 1
		i += 1


func _launch_velocity(aim: Dictionary) -> Vector2:
	return (aim.from - aim.to) * 3.0


func touch_down(index: int, p: Vector2) -> void:
	if star_grab == -1 and p.distance_to(star_pos) < _star_radius() + 30.0:
		star_grab = index
		return
	aims[index] = {from = p, to = p}


func touch_move(index: int, p: Vector2) -> void:
	if index == star_grab:
		star_pos = p
	elif aims.has(index):
		aims[index].to = p


func touch_up(index: int, p: Vector2) -> void:
	if index == star_grab:
		star_grab = -1
		return
	if not aims.has(index):
		return
	var aim: Dictionary = aims[index]
	aims.erase(index)
	aim.to = p
	if aim.from.distance_to(aim.to) < 14.0:
		_add_planet(aim.from, _circular_velocity(aim.from), planet_size)
	else:
		_add_planet(aim.from, _launch_velocity(aim), planet_size)


func _predict(aim: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	var p: Vector2 = aim.from
	var v := _launch_velocity(aim)
	var h := 1.0 / 60.0 * speed / 2.0
	var star_r := _star_radius()
	for i in PREDICT_STEPS * 2:
		var to := star_pos - p
		var d2 := maxf(to.length_squared(), 100.0)
		v += to * (_gm() / (d2 * sqrt(d2))) * h
		p += v * h
		if i % 4 == 0:
			out.append(p)
		if to.length() < star_r:
			break
	return out


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("07080f"))
	for i in stars_bg.size():
		var twinkle := 0.35 + 0.25 * sin(time * 1.7 + i * 12.9)
		draw_rect(Rect2(stars_bg[i], Vector2(2, 2)), Color(1, 1, 1, twinkle))
	for pl in planets:
		var t: PackedVector2Array = pl.trail
		if trails and t.size() > 1:
			var cols := PackedColorArray()
			cols.resize(t.size())
			for j in t.size():
				cols[j] = Color(pl.color, float(j) / t.size() * 0.6)
			draw_polyline_colors(t, cols, 2.0, true)
	var star_r := _star_radius()
	for k in 6:
		draw_circle(star_pos, star_r * (1.0 + k * 0.35), Color(1.0, 0.75, 0.3, 0.07))
	draw_circle(star_pos, star_r, Color("ffd166"))
	draw_circle(star_pos, star_r * 0.7, Color("fff1c1"))
	for pl in planets:
		draw_circle(pl.p, pl.r, pl.color)
		draw_circle(pl.p - Vector2(pl.r, pl.r) * 0.3, pl.r * 0.35, Color(1, 1, 1, 0.35))
	for f in flashes:
		var k: float = f.t / 0.6
		draw_arc(f.p, f.r * (1.0 + k * 2.0), 0, TAU, 32, Color(1, 0.9, 0.6, 1.0 - k), 3.0, true)
	var radius: float = SIZES[planet_size].x * _unit()
	for aim in aims.values():
		draw_circle(aim.from, radius, Color(1, 1, 1, 0.7))
		if aim.from.distance_to(aim.to) >= 14.0:
			draw_line(aim.from, aim.to, Color(1, 1, 1, 0.35), 2.0, true)
			for p in _predict(aim):
				draw_circle(p, 2.0, Color(1, 1, 1, 0.55))
