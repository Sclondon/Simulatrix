extends Sim
## An optics bench: a laser, and glass and mirrors to bend it with. Rays are
## traced in 2D: Snell's law at every glass face (with total internal reflection
## when the angle is too steep), a faint partial reflection off each face, and a
## little dispersion so white light fans out into a rainbow through a prism.

const MAX_BOUNCES := 24
# White light as seven wavelengths (nm) and how each one looks
const SPECTRUM := [
	[410.0, Color(0.55, 0.2, 1.0)], [450.0, Color(0.25, 0.35, 1.0)], [490.0, Color(0.1, 0.85, 1.0)],
	[530.0, Color(0.2, 1.0, 0.35)], [570.0, Color(0.95, 1.0, 0.2)], [600.0, Color(1.0, 0.6, 0.1)],
	[650.0, Color(1.0, 0.15, 0.12)],
]
const LASERS := [[650.0, Color(1.0, 0.15, 0.12)], [530.0, Color(0.2, 1.0, 0.35)], [450.0, Color(0.3, 0.4, 1.0)]]

var ior := 1.52                      # the glass's refractive index (at 550 nm)
var dispersion := 0.05               # how much more violet bends than red
var light := 3                       # 0 red, 1 green, 2 blue, 3 white
var beams := 1                       # parallel rays, side by side
var laser := {pos = Vector2(80, 300), angle = 0.0}
var parts: Array[Dictionary] = []    # {kind, pos, rot, poly (local, CCW), mirror}
var selected := -1
var drags := {}                      # touch index -> {what, offset}
var paths: Array = []                # traced segments: [a, b, color, strength]
var beam_layer := Node2D.new()
var handle_layer := Node2D.new()


func help() -> String:
	return "Light slows down in glass and bends where it goes in and comes out: that's refraction. Violet light bends a little more than red, so a prism spreads white light into a rainbow. Hit a face at too shallow an angle from inside the glass and the light can't get out at all. It reflects back in instead (total internal reflection).\n\nDrag the laser to move it, and drag the ring in front of it to aim. Drag any piece of glass or mirror to move it, and drag its ring to turn it. Add more pieces with the buttons."


func hint() -> String:
	return "Drag the laser's ring to aim it, drag glass to move it"


func controls() -> Array:
	return [
		{type = "choice", label = "Light", options = ["Red", "Green", "Blue", "White"], value = light,
			on = func(v: int) -> void: light = v},
		{type = "slider", label = "Beams", min = 1.0, max = 9.0, step = 1.0, value = beams, fmt = "%.0f",
			on = func(v: float) -> void: beams = int(v)},
		{type = "slider", label = "Glass", min = 1.1, max = 2.4, step = 0.01, value = ior, fmt = "n = %.2f",
			on = func(v: float) -> void: ior = v},
		{type = "slider", label = "Dispersion", min = 0.0, max = 0.2, step = 0.005, value = dispersion, fmt = "%.3f",
			on = func(v: float) -> void: dispersion = v},
		{type = "button", label = "+ Prism", on = func() -> void: _add("prism")},
		{type = "button", label = "+ Lens", on = func() -> void: _add("lens")},
		{type = "button", label = "+ Block", on = func() -> void: _add("block")},
		{type = "button", label = "+ Mirror", on = func() -> void: _add("mirror")},
		{type = "button", label = "+ Dish", on = func() -> void: _add("dish")},
		{type = "button", label = "Remove", on = _remove_selected},
		{type = "button", label = "Reset", on = _reset},
	]


func _ready() -> void:
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	beam_layer.material = add
	beam_layer.draw.connect(_draw_beams)
	add_child(beam_layer)
	handle_layer.draw.connect(_draw_handles)
	add_child(handle_layer)
	_reset()


func resize(new_size: Vector2) -> void:
	var old := size
	size = new_size
	if old.x > 0 and old.y > 0:
		var k := size / old
		laser.pos *= k
		for p in parts:
			p.pos *= k


func _unit() -> float:
	return clampf(minf(size.x, size.y) / 600.0, 0.6, 1.6)


func _reset() -> void:
	parts.clear()
	laser.pos = Vector2(size.x * 0.1, size.y * 0.5)
	laser.angle = -0.08
	light = 3
	_add("prism", Vector2(size.x * 0.45, size.y * 0.5), 0.0)
	_add("mirror", Vector2(size.x * 0.8, size.y * 0.3), 0.6)
	selected = -1


func _add(kind: String, at := Vector2.INF, rot := INF) -> void:
	var u := _unit()
	var poly := PackedVector2Array()
	match kind:
		"prism":
			for i in 3:
				poly.append(Vector2.from_angle(-PI / 2 + TAU * i / 3) * 90.0 * u)
		"block":
			var h := Vector2(70, 45) * u
			poly = PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)])
		"lens":
			# Biconvex: two circular arcs meeting at the top and bottom
			var half := 80.0 * u
			var bulge := 22.0 * u
			for i in 13:
				var t := float(i) / 12.0
				poly.append(Vector2(bulge * sin(PI * t), lerpf(-half, half, t)))
			for i in range(1, 12):
				var t := float(i) / 12.0
				poly.append(Vector2(-bulge * sin(PI * t), lerpf(half, -half, t)))
		"mirror":
			poly = PackedVector2Array([Vector2(0, -70 * u), Vector2(0, 70 * u)])
		"dish":
			# A curved mirror: an arc that brings parallel light to a focus
			for i in 13:
				var a := lerpf(-0.6, 0.6, i / 12.0)
				poly.append(Vector2(-cos(a) * 160.0 * u + 160.0 * u, sin(a) * 160.0 * u))
	var pos := at if at != Vector2.INF else size * 0.5 + Vector2(randf_range(-60, 60), randf_range(-60, 60))
	parts.append({kind = kind, pos = pos, rot = rot if rot != INF else randf_range(-0.3, 0.3), poly = poly,
		mirror = kind in ["mirror", "dish"]})
	selected = parts.size() - 1


func _remove_selected() -> void:
	if selected >= 0 and selected < parts.size():
		parts.remove_at(selected)
	selected = -1


func _world_poly(p: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	var xf := Transform2D(p.rot, p.pos)
	for v in p.poly:
		out.append(xf * v)
	return out


func _ring(p: Dictionary) -> Vector2:
	return p.pos + Vector2.from_angle(p.rot - PI / 2) * 115.0 * _unit()


func _aim_ring() -> Vector2:
	return laser.pos + Vector2.from_angle(laser.angle) * 70.0 * _unit()


# --- tracing -------------------------------------------------------------------

func _n(wavelength: float) -> float:
	# Cauchy-style: shorter waves see denser glass
	return ior + dispersion * ((550.0 / wavelength) * (550.0 / wavelength) - 1.0)


func _trace_all() -> void:
	paths.clear()
	var polys: Array = []
	for p in parts:
		polys.append(_world_poly(p))
	var waves: Array = SPECTRUM if light == 3 else [LASERS[light]]
	var dir := Vector2.from_angle(laser.angle)
	var across := dir.orthogonal()
	var gap := 9.0 * _unit()
	for b in beams:
		var start: Vector2 = laser.pos + dir * 30.0 * _unit() + across * (b - (beams - 1) * 0.5) * gap
		for w in waves:
			_trace(start, dir, w[0], w[1], 1.0 / sqrt(waves.size()) * (1.0 if light == 3 else 1.4), polys, 0)


func _trace(origin: Vector2, dir: Vector2, wavelength: float, color: Color, strength: float, polys: Array, depth: int) -> void:
	var p := origin
	var d := dir
	for bounce in MAX_BOUNCES:
		var best_t := INF
		var best_part := -1
		var best_n := Vector2.ZERO
		for k in polys.size():
			var poly: PackedVector2Array = polys[k]
			var closed: bool = not parts[k].mirror
			var count := poly.size() if closed else poly.size() - 1
			for e in count:
				var a := poly[e]
				var b := poly[(e + 1) % poly.size()]
				var t := _hit(p, d, a, b)
				if t > 0.01 and t < best_t:
					best_t = t
					best_part = k
					var edge := b - a
					best_n = Vector2(edge.y, -edge.x).normalized()
					if best_n.dot((a + b) * 0.5 - parts[k].pos) < 0.0:
						best_n = -best_n                    # face normals point out of the glass
		if best_part == -1:
			paths.append([p, p + d * 4000.0, color, strength])
			return
		var hit := p + d * best_t
		paths.append([p, hit, color, strength])
		if parts[best_part].mirror:
			d = d.bounce(best_n) if d.dot(best_n) < 0.0 else d.bounce(-best_n)
			d = d.normalized()
			strength *= 0.92
			p = hit
			continue
		var entering := d.dot(best_n) < 0.0
		var n1 := 1.0 if entering else _n(wavelength)
		var n2 := _n(wavelength) if entering else 1.0
		var face := best_n if entering else -best_n       # against the incoming ray
		var cosi := -d.dot(face)
		var eta := n1 / n2
		var k2 := 1.0 - eta * eta * (1.0 - cosi * cosi)
		var reflected := (d + face * 2.0 * cosi).normalized()
		if k2 < 0.0:
			d = reflected                                 # total internal reflection
			p = hit
			continue
		var refracted := (d * eta + face * (eta * cosi - sqrt(k2))).normalized()
		# Schlick's approximation: how much bounces off the face instead
		var r0 := pow((n1 - n2) / (n1 + n2), 2.0)
		var cos_t := sqrt(k2)
		var fres := r0 + (1.0 - r0) * pow(1.0 - (cosi if n1 <= n2 else cos_t), 5.0)
		if depth < 2 and strength * fres > 0.04:
			_trace(hit, reflected, wavelength, color, strength * fres, polys, depth + 1)
		strength *= 1.0 - fres
		d = refracted
		p = hit


static func _hit(p: Vector2, d: Vector2, a: Vector2, b: Vector2) -> float:
	var e := b - a
	var den := d.cross(e)
	if absf(den) < 1e-9:
		return INF
	var ap := a - p
	var t := ap.cross(e) / den
	var s := ap.cross(d) / den
	return t if s >= 0.0 and s <= 1.0 else INF


# --- input ---------------------------------------------------------------------

func touch_down(index: int, p: Vector2) -> void:
	var u := _unit()
	if p.distance_to(_aim_ring()) < 34.0 * u:
		drags[index] = {what = "aim"}
		return
	if p.distance_to(laser.pos) < 40.0 * u:
		drags[index] = {what = "laser", offset = laser.pos - p}
		return
	if selected >= 0 and p.distance_to(_ring(parts[selected])) < 34.0 * u:
		drags[index] = {what = "turn", part = selected}
		return
	for k in range(parts.size() - 1, -1, -1):
		var poly := _world_poly(parts[k])
		var near := false
		if parts[k].mirror:
			for e in poly.size() - 1:
				if Geometry2D.get_closest_point_to_segment(p, poly[e], poly[e + 1]).distance_to(p) < 28.0 * u:
					near = true
		else:
			near = Geometry2D.is_point_in_polygon(p, poly) or parts[k].pos.distance_to(p) < 40.0 * u
		if near:
			selected = k
			drags[index] = {what = "part", part = k, offset = parts[k].pos - p}
			return
	selected = -1


func touch_move(index: int, p: Vector2) -> void:
	if not drags.has(index):
		return
	var g: Dictionary = drags[index]
	var inside := p.clamp(Vector2.ZERO, size)
	match g.what:
		"aim": laser.angle = (p - laser.pos).angle()
		"laser": laser.pos = inside + g.offset
		"turn":
			if g.part < parts.size():
				var part: Dictionary = parts[g.part]
				part.rot = (p - part.pos).angle() + PI / 2
		"part":
			if g.part < parts.size():
				parts[g.part].pos = inside + g.offset


func touch_up(index: int, _p: Vector2) -> void:
	drags.erase(index)


# --- drawing -------------------------------------------------------------------

func _process(_delta: float) -> void:
	_trace_all()
	queue_redraw()
	beam_layer.queue_redraw()
	handle_layer.queue_redraw()


func _draw() -> void:
	draw_backdrop(Color("0b0a14"), 40.0)
	for k in parts.size():
		var p: Dictionary = parts[k]
		var poly := _world_poly(p)
		if p.mirror:
			draw_polyline(poly, Color("d8e0f0"), 6.0, true)
			# Silvered on the back: hatch marks
			for e in poly.size() - 1:
				var a := poly[e]
				var b := poly[e + 1]
				var back := (b - a).orthogonal().normalized() * -8.0
				for s in 3:
					var q := a.lerp(b, (s + 0.5) / 3.0)
					draw_line(q, q + back + (b - a).normalized() * 5.0, Color(0.6, 0.65, 0.75, 0.6), 2.0)
		else:
			draw_colored_polygon(poly, Color(0.55, 0.8, 1.0, 0.12))
			var loop := poly.duplicate()
			loop.append(poly[0])
			draw_polyline(loop, Color(0.7, 0.9, 1.0, 0.65), 2.0, true)
	# The laser: a housing pointing along its beam
	var u := _unit()
	var fwd := Vector2.from_angle(laser.angle)
	var side := fwd.orthogonal()
	var body := PackedVector2Array([
		laser.pos - fwd * 34 * u - side * 14 * u, laser.pos + fwd * 26 * u - side * 14 * u,
		laser.pos + fwd * 34 * u - side * 7 * u, laser.pos + fwd * 34 * u + side * 7 * u,
		laser.pos + fwd * 26 * u + side * 14 * u, laser.pos - fwd * 34 * u + side * 14 * u,
	])
	draw_colored_polygon(body, Color("3a3f52"))
	var loop := body.duplicate()
	loop.append(body[0])
	draw_polyline(loop, Color("8b93ad"), 2.0, true)


func _draw_beams() -> void:
	for seg in paths:
		var c: Color = seg[2]
		var s: float = seg[3]
		beam_layer.draw_line(seg[0], seg[1], Color(c, 0.12 * s), 10.0)
		beam_layer.draw_line(seg[0], seg[1], Color(c, 0.9 * s), 2.5)


func _draw_handles() -> void:
	var u := _unit()
	handle_layer.draw_arc(_aim_ring(), 16.0 * u, 0, TAU, 24, Color(1, 1, 1, 0.55), 3.0, true)
	handle_layer.draw_circle(_aim_ring(), 4.0 * u, Color(1, 1, 1, 0.7))
	if selected >= 0 and selected < parts.size():
		var p: Dictionary = parts[selected]
		handle_layer.draw_line(p.pos, _ring(p), Color(1, 1, 1, 0.25), 2.0)
		handle_layer.draw_arc(_ring(p), 16.0 * u, 0, TAU, 24, Color("c38bff"), 3.0, true)
		handle_layer.draw_circle(p.pos, 5.0, Color("c38bff"))
