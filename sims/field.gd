extends Sim
## Electric charges and their field. The background shades the electric
## potential (red high, blue low, with contour lines), field lines run from
## positive charges to negative ones, and probes (small positive test charges)
## can be flung through it all and pushed around by Coulomb's law.

const MAX_CHARGES := 12
const LINES_PER_CHARGE := 14
const K := 4.0e6                     # force scale, px units
const SOFT := 400.0                  # softening (px^2) so nothing blows up at a charge

var charges: Array[Dictionary] = []  # {p, q}
var probes: Array[Dictionary] = []   # {p, v, trail}
var mode := 0                        # 0 add +, 1 add -, 2 fling probe
var strength := 1.0                  # magnitude of new charges
var show_lines := true
var show_arrows := false
var lines: Array[PackedVector2Array] = []
var dirty := true
var drags := {}                      # touch index -> {what, i, from}
var view := ColorRect.new()


func help() -> String:
	return "Like charges push each other apart and opposite charges pull together. The strength falls off with the square of the distance (Coulomb's law).\n\nField lines show which way a small positive charge would be pushed. They leave the red + charges and end on the blue - ones. The background is the electric potential, with contour lines where it's level.\n\nTap to place a charge and drag one to move it. Switch to Probe and flick to launch a test charge through the field."


func hint() -> String:
	return "Tap to place charges, drag to move them. Probe mode: flick to launch"


func controls() -> Array:
	return [
		{type = "choice", label = "Tap adds", options = ["Plus", "Minus", "Probe"], value = mode,
			on = func(v: int) -> void: mode = v},
		{type = "slider", label = "New charge", min = 0.5, max = 3.0, step = 0.1, value = strength, fmt = "%.1f",
			on = func(v: float) -> void: strength = v},
		{type = "toggle", label = "Field lines", value = show_lines, on = func(v: bool) -> void:
			show_lines = v
			dirty = true},
		{type = "toggle", label = "Arrows", value = show_arrows, on = func(v: bool) -> void: show_arrows = v},
		{type = "button", label = "Dipole", on = func() -> void: _preset(0)},
		{type = "button", label = "Capacitor", on = func() -> void: _preset(1)},
		{type = "button", label = "Quadrupole", on = func() -> void: _preset(2)},
		{type = "button", label = "Clear", on = func() -> void:
			charges.clear()
			probes.clear()
			dirty = true},
	]


func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://sims/field.gdshader")
	view.material = mat
	view.show_behind_parent = true
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	resize(size)
	_preset(0)


func resize(new_size: Vector2) -> void:
	var old := size
	size = new_size
	view.size = size
	if old.x > 0 and old.y > 0:
		for c in charges:
			c.p *= size / old
	dirty = true


func _preset(which: int) -> void:
	charges.clear()
	probes.clear()
	var c := size * 0.5
	var s := minf(size.x, size.y)
	match which:
		0:
			charges.append({p = c - Vector2(s * 0.2, 0), q = 1.5})
			charges.append({p = c + Vector2(s * 0.2, 0), q = -1.5})
		1:
			for i in 7:
				var y := c.y + (i - 3) * s * 0.07
				charges.append({p = Vector2(c.x - s * 0.18, y), q = 0.8})
				charges.append({p = Vector2(c.x + s * 0.18, y), q = -0.8})
		2:
			for i in 4:
				charges.append({p = c + Vector2.from_angle(PI / 4 + i * PI / 2) * s * 0.2, q = 1.4 if i % 2 == 0 else -1.4})
	dirty = true


func field_at(p: Vector2) -> Vector2:
	var e := Vector2.ZERO
	for c in charges:
		var d: Vector2 = p - c.p
		var r2 := d.length_squared() + SOFT
		e += d * (c.q / (r2 * sqrt(r2)))
	return e


func _trace_lines() -> void:
	lines.clear()
	var positives := charges.filter(func(c): return c.q > 0.0)
	# With only negative charges, trace backwards from them instead
	var sources: Array = positives if not positives.is_empty() else charges
	var dir_sign := 1.0 if not positives.is_empty() else -1.0
	var budget := 5200                  # total steps, so lots of charges stay quick
	var per_line := clampi(budget / maxi(sources.size() * LINES_PER_CHARGE, 1), 40, 260)
	for c in sources:
		var n := int(LINES_PER_CHARGE * clampf(absf(c.q), 0.5, 2.0))
		for k in n:
			var p: Vector2 = c.p + Vector2.from_angle(TAU * (k + 0.5) / n) * 14.0
			var pts := PackedVector2Array([p])
			for step in per_line:
				var e := field_at(p) * dir_sign
				if e.length_squared() < 1e-14:
					break
				var ds := 7.0
				var mid := p + e.normalized() * ds * 0.5
				var e2 := field_at(mid) * dir_sign
				p += e2.normalized() * ds
				pts.append(p)
				if p.x < -50 or p.y < -50 or p.x > size.x + 50 or p.y > size.y + 50:
					break
				var ended := false
				for o in charges:
					if o.q * dir_sign < 0.0 and p.distance_squared_to(o.p) < 144.0:
						ended = true
				if ended:
					break
			lines.append(pts)


func touch_down(index: int, p: Vector2) -> void:
	for i in charges.size():
		if charges[i].p.distance_to(p) < 30.0:
			drags[index] = {what = "charge", i = i}
			return
	if mode == 2:
		drags[index] = {what = "fling", from = p, to = p}
		return
	if charges.size() >= MAX_CHARGES:
		charges.pop_front()
	charges.append({p = p, q = strength if mode == 0 else -strength})
	drags[index] = {what = "charge", i = charges.size() - 1}
	dirty = true


func touch_move(index: int, p: Vector2) -> void:
	if not drags.has(index):
		return
	var d: Dictionary = drags[index]
	if d.what == "charge" and d.i < charges.size():
		charges[d.i].p = p.clamp(Vector2.ZERO, size)
		dirty = true
	elif d.what == "fling":
		d.to = p


func touch_up(index: int, p: Vector2) -> void:
	if not drags.has(index):
		return
	var d: Dictionary = drags[index]
	drags.erase(index)
	if d.what == "fling":
		if probes.size() > 12:
			probes.pop_front()
		probes.append({p = d.from, v = (d.from - p) * 2.5, trail = PackedVector2Array()})


func _physics_process(delta: float) -> void:
	# Probes: a small positive test charge each, pushed by the field
	for i in range(probes.size() - 1, -1, -1):
		var pr: Dictionary = probes[i]
		var gone := false
		for s in 4:
			var h := delta / 4.0
			pr.v += field_at(pr.p) * K * h
			pr.p += pr.v * h
			for c in charges:
				if c.q < 0.0 and pr.p.distance_squared_to(c.p) < 100.0:
					gone = true
		var t: PackedVector2Array = pr.trail
		t.append(pr.p)
		if t.size() > 160:
			t = t.slice(t.size() - 160)
		pr.trail = t
		var far := maxf(size.x, size.y)
		if gone or pr.p.x < -far or pr.p.y < -far or pr.p.x > size.x + far or pr.p.y > size.y + far:
			probes.remove_at(i)
	if dirty:
		dirty = false
		if show_lines:
			_trace_lines()
		var packed: Array[Vector4] = []
		for i in MAX_CHARGES:
			packed.append(Vector4(charges[i].p.x, charges[i].p.y, charges[i].q, 0) if i < charges.size() else Vector4.ZERO)
		var mat := view.material as ShaderMaterial
		mat.set_shader_parameter("charges", packed)
		mat.set_shader_parameter("count", charges.size())
		mat.set_shader_parameter("size", size)
	queue_redraw()


func _draw() -> void:
	if show_lines:
		for pts in lines:
			if pts.size() > 1:
				draw_polyline(pts, Color(1, 1, 1, 0.45), 1.5, true)
				# An arrowhead partway along, pointing the way the field goes
				var m := pts.size() / 2
				if m > 1:
					var dir := (pts[m] - pts[m - 1]).normalized()
					var tip := pts[m]
					draw_colored_polygon(PackedVector2Array([tip + dir * 6.0, tip - dir * 4.0 + dir.orthogonal() * 4.0,
						tip - dir * 4.0 - dir.orthogonal() * 4.0]), Color(1, 1, 1, 0.6))
	if show_arrows:
		var step := 44.0
		var y := step * 0.5
		while y < size.y:
			var x := step * 0.5
			while x < size.x:
				var e := field_at(Vector2(x, y))
				var mag := clampf(sqrt(e.length() * 2.0e4), 0.0, 1.0)
				var dir := e.normalized() * step * 0.4 * mag
				draw_line(Vector2(x, y) - dir * 0.5, Vector2(x, y) + dir * 0.5, Color(1, 1, 1, 0.3 + 0.4 * mag), 2.0)
				draw_circle(Vector2(x, y) + dir * 0.5, 2.0, Color(1, 1, 1, 0.3 + 0.4 * mag))
				x += step
			y += step
	for pr in probes:
		var t: PackedVector2Array = pr.trail
		if t.size() > 1:
			draw_polyline(t, Color(1.0, 0.95, 0.5, 0.5), 2.0, true)
		draw_circle(pr.p, 6.0, Color(1.0, 0.95, 0.5))
	for d in drags.values():
		if d.what == "fling" and d.from.distance_to(d.to) > 4.0:
			draw_line(d.from, d.to, Color(1, 1, 1, 0.4), 2.0, true)
			draw_circle(d.from, 6.0, Color(1.0, 0.95, 0.5, 0.8))
	for c in charges:
		var pos_c: bool = c.q > 0.0
		var col := Color("ff5a5a") if pos_c else Color("4a8cff")
		var r := 12.0 + absf(c.q) * 4.0
		draw_circle(c.p, r + 4.0, Color(col, 0.3))
		draw_circle(c.p, r, col)
		draw_line(c.p - Vector2(r * 0.5, 0), c.p + Vector2(r * 0.5, 0), Color.WHITE, 3.0)
		if pos_c:
			draw_line(c.p - Vector2(0, r * 0.5), c.p + Vector2(0, r * 0.5), Color.WHITE, 3.0)
