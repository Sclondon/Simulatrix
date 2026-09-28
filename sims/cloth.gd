extends Sim
## Verlet cloth: a grid of points held together by distance constraints.

const DT := 1.0 / 60.0

var gravity := 1200.0
var wind := 0.0
var iterations := 6
var tear := 2.2 # a link snaps past this multiple of its rest length; 6 means never
var mode := 0 # 0 grab, 1 cut
var pin_style := 0 # 0 every few, 1 corners, 2 whole top

var cols := 0
var rows := 0
var spacing := 20.0
var pos := PackedVector2Array()
var prev := PackedVector2Array()
var pinned := PackedByteArray()
var link_a := PackedInt32Array()
var link_b := PackedInt32Array()
var link_rest := PackedFloat32Array()
var link_alive := PackedByteArray()
var grabs := {} # touch index -> point index
var cuts := {} # touch index -> last position
var time := 0.0


func help() -> String:
	return "A sheet of cloth made of a few hundred points held together by springy links.\n\nIn Grab mode, drag the cloth around. Pull hard enough and it rips. In Cut mode, swipe across it like a knife.\n\nTurn up the wind to make it billow. Tear strength sets how far a link can stretch before it snaps. Drop pins lets the whole sheet fall."


func hint() -> String:
	return "Drag the cloth. Switch to Cut and swipe to slice it"


func controls() -> Array:
	return [
		{type = "choice", label = "Touch", options = ["Grab", "Cut"], value = mode,
			on = func(v: int) -> void: mode = v},
		{type = "choice", label = "Pins", options = ["Some", "Ends", "All top"], value = pin_style,
			on = func(v: int) -> void:
				pin_style = v
				_build()},
		{type = "slider", label = "Wind", min = -1500.0, max = 1500.0, step = 10.0, value = wind, fmt = "%.0f",
			on = func(v: float) -> void: wind = v},
		{type = "slider", label = "Gravity", min = 0.0, max = 3000.0, step = 10.0, value = gravity, fmt = "%.0f px/s²",
			on = func(v: float) -> void: gravity = v},
		{type = "slider", label = "Stiffness", min = 1.0, max = 16.0, step = 1.0, value = iterations, fmt = "%.0f passes",
			on = func(v: float) -> void: iterations = int(v)},
		{type = "slider", label = "Tear strength", min = 1.3, max = 6.0, step = 0.1, value = tear, fmt = "%.1fx",
			on = func(v: float) -> void: tear = v},
		{type = "button", label = "Drop pins", on = func() -> void: pinned.fill(0)},
		{type = "button", label = "New cloth", on = _build},
	]


func _ready() -> void:
	_build()


func resize(new_size: Vector2) -> void:
	var changed := not new_size.is_equal_approx(size)
	size = new_size
	if changed and is_inside_tree():
		_build()


func _build() -> void:
	grabs.clear()
	cols = 28 if size.x >= size.y else 20
	rows = 20 if size.x >= size.y else 24
	spacing = minf(size.x * 0.84 / (cols - 1), size.y * 0.62 / (rows - 1))
	var origin := Vector2((size.x - spacing * (cols - 1)) * 0.5, maxf(size.y * 0.06, 16.0))
	pos.resize(cols * rows)
	pinned.resize(cols * rows)
	pinned.fill(0)
	for y in rows:
		for x in cols:
			pos[y * cols + x] = origin + Vector2(x, y) * spacing
	prev = pos.duplicate()
	for x in cols:
		match pin_style:
			0: pinned[x] = 1 if x % 4 == 0 or x == cols - 1 else 0
			1: pinned[x] = 1 if x == 0 or x == cols - 1 else 0
			2: pinned[x] = 1
	link_a.clear()
	link_b.clear()
	for y in rows:
		for x in cols:
			var i := y * cols + x
			if x < cols - 1:
				link_a.append(i)
				link_b.append(i + 1)
			if y < rows - 1:
				link_a.append(i)
				link_b.append(i + cols)
	link_rest.resize(link_a.size())
	link_rest.fill(spacing)
	link_alive.resize(link_a.size())
	link_alive.fill(1)


func _physics_process(_delta: float) -> void:
	time += DT
	var grabbed_points := {}
	for p in grabs.values():
		grabbed_points[p] = true
	var accel_y := gravity * DT * DT
	var bottom := size.y - 4.0
	for i in pos.size():
		if pinned[i] or grabbed_points.has(i):
			continue
		var p := pos[i]
		var gust := wind * (0.6 + 0.4 * sin(time * 2.3 + p.y * 0.02 + p.x * 0.01))
		var v := (p - prev[i]) * 0.99
		prev[i] = p
		p += v + Vector2(gust * DT * DT, accel_y)
		if p.y > bottom:
			p.y = bottom
			prev[i] = Vector2(lerpf(prev[i].x, p.x, 0.3), prev[i].y) # floor friction
		p.x = clampf(p.x, 2.0, size.x - 2.0)
		pos[i] = p
	for it in iterations:
		for k in link_a.size():
			if not link_alive[k]:
				continue
			var a := link_a[k]
			var b := link_b[k]
			var pa := pos[a]
			var pb := pos[b]
			var d := pb - pa
			var dist := d.length()
			if dist < 0.0001:
				continue
			var fix_a := pinned[a] or grabbed_points.has(a)
			var fix_b := pinned[b] or grabbed_points.has(b)
			if fix_a and fix_b:
				continue
			var corr := d * ((dist - link_rest[k]) / dist)
			if fix_a:
				pos[b] = pb - corr
			elif fix_b:
				pos[a] = pa + corr
			else:
				pos[a] = pa + corr * 0.5
				pos[b] = pb - corr * 0.5
	if tear < 5.95:
		var limit := spacing * tear
		for k in link_a.size():
			if link_alive[k] and pos[link_a[k]].distance_to(pos[link_b[k]]) > limit:
				link_alive[k] = 0
	queue_redraw()


func _nearest(p: Vector2, reach: float) -> int:
	var best := -1
	var best_d := reach * reach
	for i in pos.size():
		var d := pos[i].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = i
	return best


func _cut(from: Vector2, to: Vector2) -> void:
	var reach := spacing * 0.6
	for k in link_a.size():
		if not link_alive[k]:
			continue
		var mid := (pos[link_a[k]] + pos[link_b[k]]) * 0.5
		var closest := Geometry2D.get_closest_point_to_segment(mid, from, to)
		if closest.distance_to(mid) < reach:
			link_alive[k] = 0


func touch_down(index: int, p: Vector2) -> void:
	if mode == 1:
		cuts[index] = p
		_cut(p, p)
		return
	var i := _nearest(p, maxf(spacing * 2.5, 44.0))
	if i != -1:
		grabs[index] = i
		touch_move(index, p)


func touch_move(index: int, p: Vector2) -> void:
	if cuts.has(index):
		_cut(cuts[index], p)
		cuts[index] = p
	elif grabs.has(index):
		var i: int = grabs[index]
		prev[i] = pos[i]
		pos[i] = p


func touch_up(index: int, _p: Vector2) -> void:
	grabs.erase(index)
	cuts.erase(index)


func _draw() -> void:
	draw_backdrop(Color("141221"))
	var lines := PackedVector2Array()
	var colors := PackedColorArray()
	var calm := Color("7fe3d0")
	var hot := Color("ff5f6d")
	for k in link_a.size():
		if not link_alive[k]:
			continue
		var pa := pos[link_a[k]]
		var pb := pos[link_b[k]]
		lines.append(pa)
		lines.append(pb)
		var strain := clampf((pa.distance_to(pb) / spacing - 1.0) / maxf(tear - 1.0, 0.3), 0.0, 1.0)
		colors.append(calm.lerp(hot, strain))
	if lines.size() > 0:
		draw_multiline_colors(lines, colors, 2.0)
	for i in cols:
		if pinned[i]:
			draw_circle(pos[i], 6.0, Color("ffd166"))
	for i in grabs.values():
		draw_arc(pos[i], 22.0, 0, TAU, 24, Color(1, 1, 1, 0.6), 3.0, true)
	for p in cuts.values():
		draw_circle(p, 12.0, Color(1, 0.4, 0.5, 0.35))
