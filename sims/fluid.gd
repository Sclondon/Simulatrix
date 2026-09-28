extends Sim
## Particle fluid, after Clavet et al.'s double density relaxation: every drop
## pushes its neighbours away when they crowd it and pulls them in when they
## drift off, which is all it takes to splash, slosh and settle. Steps run in
## per-frame units (px and px/frame). Drawn as metaballs: soft blobs summed into
## a half-size buffer, then cut off at a threshold by a shader.

var H := 26.0                        # interaction radius, px (scaled to the tank, so it fills the same)
const REST := 4.2                    # rest density (sum of (1 - r/H)^2)
const STIFF := 0.35
const STIFF_NEAR := 0.9
const MAX_DROPS := 650
const LIQUIDS := [
	{name = "Water", deep = Color("0f4c9c"), light = Color("5cc8ff"), foam = Color("e6f7ff"), visc = 0.02},
	{name = "Slime", deep = Color("2c7a1c"), light = Color("98f25a"), foam = Color("e8ffc8"), visc = 0.35},
	{name = "Lava", deep = Color("8a1c06"), light = Color("ff7a1a"), foam = Color("ffe48a"), visc = 0.2},
]

var gravity := 0.22                  # px / frame^2
var tilt := 0.0                      # degrees off straight down
var viscosity := 0.02
var liquid := 0
var mode := 0                        # 0 stir, 1 pour, 2 drain

var pos := PackedVector2Array()
var prev := PackedVector2Array()
var cell_start := PackedInt32Array()
var cell_items := PackedInt32Array()
var grid_w := 1
var grid_h := 1
var fingers := {}                    # touch index -> {at, last}

var field := SubViewport.new()       # where the blobs are summed
var blobs := Node2D.new()
var surface := ColorRect.new()
var blob_tex: Texture2D


func help() -> String:
	return "A few hundred drops of liquid. Each one only knows about its neighbours: crowd them and they push apart, spread them and they pull back together. Put enough of them in a tank and you get water.\n\nStir drags the liquid along with your finger. Pour adds drops, Drain takes them away. Tilt swings gravity to one side so it sloshes. Slime and lava are thicker, so they flow slowly."


func hint() -> String:
	return "Drag to stir. Switch to Pour to add more"


func controls() -> Array:
	return [
		{type = "choice", label = "Touch", options = ["Stir", "Pour", "Drain"], value = mode,
			on = func(v: int) -> void: mode = v},
		{type = "choice", label = "Liquid", options = ["Water", "Slime", "Lava"], value = liquid,
			on = _set_liquid},
		{type = "slider", label = "Tilt", min = -60.0, max = 60.0, step = 1.0, value = tilt, fmt = "%.0f°",
			on = func(v: float) -> void: tilt = v},
		{type = "slider", label = "Gravity", min = 0.0, max = 0.6, step = 0.01, value = gravity, fmt = "%.2f",
			on = func(v: float) -> void: gravity = v},
		{type = "slider", label = "Thickness", min = 0.0, max = 0.6, step = 0.01, value = viscosity, fmt = "%.2f",
			on = func(v: float) -> void: viscosity = v},
		{type = "button", label = "Dam break", on = _dam_break},
		{type = "button", label = "Rain", on = _rain},
		{type = "button", label = "Empty", on = func() -> void:
			pos.clear()
			prev.clear()},
	]


func _ready() -> void:
	blob_tex = _make_blob()
	field.transparent_bg = true
	field.disable_3d = true
	field.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(field)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	blobs.material = add
	blobs.scale = Vector2(0.5, 0.5)
	blobs.draw.connect(_draw_blobs)
	field.add_child(blobs)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://sims/fluid.gdshader")
	mat.set_shader_parameter("field", field.get_texture())
	surface.material = mat
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(surface)
	_set_liquid(liquid)
	resize(size)
	_dam_break()


func resize(new_size: Vector2) -> void:
	size = new_size
	field.size = Vector2i(maxi(int(size.x * 0.5), 8), maxi(int(size.y * 0.5), 8))
	surface.size = size
	H = clampf(sqrt(size.x * size.y / 450.0), 20.0, 44.0)
	grid_w = maxi(int(ceil(size.x / H)), 1)
	grid_h = maxi(int(ceil(size.y / H)), 1)
	cell_start.resize(grid_w * grid_h + 1)
	for i in pos.size():
		pos[i] = pos[i].clamp(Vector2(4, 4), size - Vector2(4, 4))
	queue_redraw()


func _set_liquid(i: int) -> void:
	liquid = i
	viscosity = LIQUIDS[i].visc
	var mat := surface.material as ShaderMaterial
	mat.set_shader_parameter("deep", LIQUIDS[i].deep)
	mat.set_shader_parameter("light", LIQUIDS[i].light)
	mat.set_shader_parameter("foam", LIQUIDS[i].foam)


func _add(p: Vector2, v := Vector2.ZERO) -> void:
	if pos.size() >= MAX_DROPS:
		return
	pos.append(p)
	prev.append(p - v)


func _dam_break() -> void:
	pos.clear()
	prev.clear()
	var spacing := H * 0.42
	var cols := int(size.x * 0.4 / spacing)
	var rows := mini(int(size.y * 0.85 / spacing), int(MAX_DROPS * 0.8 / maxi(cols, 1)))
	for y in rows:
		for x in cols:
			_add(Vector2(8 + x * spacing + randf() * 2.0, size.y - 8 - y * spacing))


func _rain() -> void:
	for i in 80:
		_add(Vector2(randf_range(10, size.x - 10), randf_range(4, size.y * 0.25)), Vector2(0, 2))


func _gravity() -> Vector2:
	return Vector2.DOWN.rotated(deg_to_rad(-tilt)) * gravity * H / 26.0


func _physics_process(_delta: float) -> void:
	var n := pos.size()
	var g := _gravity()
	# Integrate: velocity is how far a drop moved last frame
	for i in n:
		var v := (pos[i] - prev[i]) * 0.998 + g
		prev[i] = pos[i]
		pos[i] += v.limit_length(H * 0.5)
	_stir()
	_bin()
	_relax()
	# Walls: slide along them, losing a little speed
	var lo := Vector2(3, 3)
	var hi := size - Vector2(3, 3)
	for i in n:
		var p := pos[i]
		if p.x < lo.x or p.x > hi.x or p.y < lo.y or p.y > hi.y:
			var c := p.clamp(lo, hi)
			pos[i] = c
			var pr := prev[i]
			if p.x != c.x:
				pr.x = lerpf(pr.x, c.x, 0.7)
			if p.y != c.y:
				pr.y = lerpf(pr.y, c.y, 0.7)
			prev[i] = pr
	blobs.queue_redraw()


# Sort drops into grid cells of size H (a counting sort into flat arrays)
func _bin() -> void:
	var n := pos.size()
	var cells := grid_w * grid_h
	cell_start.fill(0)
	var cell_of := PackedInt32Array()
	cell_of.resize(n)
	for i in n:
		var cx := clampi(int(pos[i].x / H), 0, grid_w - 1)
		var cy := clampi(int(pos[i].y / H), 0, grid_h - 1)
		var c := cx + cy * grid_w
		cell_of[i] = c
		cell_start[c + 1] += 1
	for c in cells:
		cell_start[c + 1] += cell_start[c]
	cell_items.resize(n)
	var fill := cell_start.duplicate()
	for i in n:
		var c := cell_of[i]
		cell_items[fill[c]] = i
		fill[c] += 1


# Double density relaxation, with a little viscosity mixed in
func _relax() -> void:
	var n := pos.size()
	var h2 := H * H
	var near_j := PackedInt32Array()
	var near_q := PackedFloat32Array()
	for i in n:
		var p := pos[i]
		var cx := clampi(int(p.x / H), 0, grid_w - 1)
		var cy := clampi(int(p.y / H), 0, grid_h - 1)
		var rho := 0.0
		var rho_near := 0.0
		near_j.clear()
		near_q.clear()
		for gy in range(maxi(cy - 1, 0), mini(cy + 2, grid_h)):
			for gx in range(maxi(cx - 1, 0), mini(cx + 2, grid_w)):
				var c := gx + gy * grid_w
				for k in range(cell_start[c], cell_start[c + 1]):
					var j := cell_items[k]
					if j == i:
						continue
					var r2 := p.distance_squared_to(pos[j])
					if r2 < h2 and r2 > 0.0001:
						var q := 1.0 - sqrt(r2) / H
						rho += q * q
						rho_near += q * q * q
						near_j.append(j)
						near_q.append(q)
		var press := STIFF * (rho - REST)
		var press_near := STIFF_NEAR * rho_near
		var dx := Vector2.ZERO
		var vi := pos[i] - prev[i]
		for k in near_j.size():
			var j := near_j[k]
			var q := near_q[k]
			var dir := (pos[j] - p).normalized()
			var d := dir * ((press * q + press_near * q * q) * 0.5)
			pos[j] += d
			dx -= d
			if viscosity > 0.0:
				# Thick liquids drag their neighbours along with them
				var vj := pos[j] - prev[j]
				var mix := (vj - vi) * (viscosity * q * 0.5)
				dx += mix * 0.5
		pos[i] += dx


func _stir() -> void:
	for f in fingers.values():
		var at: Vector2 = f.at
		var move: Vector2 = at - f.last
		f.last = at
		match mode:
			0:
				var reach := 70.0
				for i in pos.size():
					var d := pos[i].distance_to(at)
					if d < reach:
						var w := 1.0 - d / reach
						# Carry the drops along with the finger, and part them a little
						var v := (pos[i] - prev[i]).lerp(move.limit_length(H * 0.4), w * 0.6)
						prev[i] = pos[i] - v
			1:
				for k in 3:
					_add(at + Vector2(randf_range(-10, 10), randf_range(-10, 10)), move.limit_length(6.0) + Vector2(0, 1))
			2:
				for i in range(pos.size() - 1, -1, -1):
					if pos[i].distance_to(at) < 40.0:
						pos.remove_at(i)
						prev.remove_at(i)


func touch_down(index: int, p: Vector2) -> void:
	fingers[index] = {at = p, last = p}


func touch_move(index: int, p: Vector2) -> void:
	if fingers.has(index):
		fingers[index].at = p


func touch_up(index: int, _p: Vector2) -> void:
	fingers.erase(index)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0c1220"))
	# A faint tank: back wall tiles
	var line := Color(1, 1, 1, 0.04)
	var y := size.y
	while y > 0:
		draw_line(Vector2(0, y), Vector2(size.x, y), line, 1.0)
		y -= 40.0


# Each drop as a soft blob; the red channel sums density, green sums speed
func _draw_blobs() -> void:
	var r := H * 0.95
	for i in pos.size():
		var speed := clampf((pos[i] - prev[i]).length() / 6.0, 0.0, 1.0)
		blobs.draw_texture_rect(blob_tex, Rect2(pos[i] - Vector2(r, r), Vector2(r, r) * 2.0), false,
			Color(1.0, speed, 0.0, 1.0))


static func _make_blob() -> Texture2D:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (n - 1) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x - c, y - c).length() / (n * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * 0.55
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
