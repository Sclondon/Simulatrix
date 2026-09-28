extends Sim
## Falling sand: a grid of cells, each one a material with a simple rule for
## where it moves and what it does to its neighbours. Sand piles, water levels,
## fire climbs and spreads, lava cools to stone in water, plants drink.
## The grid goes to the GPU as one byte per cell; a shader colours it.

enum { EMPTY, SAND, WATER, STONE, WOOD, FIRE, SMOKE, LAVA, PLANT, OIL }
const NAMES := ["Erase", "Sand", "Water", "Stone", "Wood", "Fire", "Steam", "Lava", "Plant", "Oil"]
const COLORS := [
	Color("20242e"), Color("e8c77a"), Color("3d8bff"), Color("7d8394"), Color("8a5a36"),
	Color("ff7a2a"), Color("c9ced8"), Color("ff4a1a"), Color("4fc24a"), Color("5b3d6e"),
]
# What the brush lays down, in palette order (Steam isn't in it: it only comes from things)
const BRUSH := [EMPTY, SAND, WATER, STONE, WOOD, FIRE, LAVA, PLANT, OIL]
const MAX_CELLS := 17000

var cell := 6.0                      # px per cell
var gw := 1
var gh := 1
var grid := PackedByteArray()
var life := PackedByteArray()        # fire and steam burn out
var stamp := PackedByteArray()       # frame a cell last moved on (so nothing moves twice)
var movers := PackedInt32Array()     # moving cells per row: empty rows are skipped
var frame := 1
var brush := 1                       # index into BRUSH
var brush_size := 3.0
var strokes := {}                    # touch index -> last cell position
var crater := -1                     # where the volcano erupts from
var eruption := 0.0                  # seconds of eruption left

var image: Image
var texture: ImageTexture
var view := ColorRect.new()


func help() -> String:
	return "Every cell is a material with one simple rule. Sand falls and piles up. Water falls and spreads out flat. Fire rises, spreads to wood, plants and oil, and burns out as steam. Lava flows slowly, sets things alight, and turns to stone when it meets water. Plants slowly grow into water they touch.\n\nPick a material and draw with your finger. Erase clears cells. Try building a stone bowl, filling it with oil and dropping a spark in."


func hint() -> String:
	return "Pick a material and draw with it"


func controls() -> Array:
	var names: Array = []
	var colors: Array = []
	for m in BRUSH:
		names.append(NAMES[m])
		colors.append(COLORS[m])
	return [
		{type = "choice", label = "Material", options = names, colors = colors, value = brush,
			on = func(v: int) -> void: brush = v},
		{type = "slider", label = "Brush", min = 1.0, max = 10.0, step = 1.0, value = brush_size, fmt = "%.0f",
			on = func(v: float) -> void: brush_size = v},
		{type = "button", label = "Volcano", on = _volcano},
		{type = "button", label = "Clear", on = _clear},
	]


func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://sims/sand.gdshader")
	var pal := Image.create(COLORS.size(), 1, false, Image.FORMAT_RGBA8)
	for i in COLORS.size():
		pal.set_pixel(i, 0, COLORS[i])
	mat.set_shader_parameter("palette", ImageTexture.create_from_image(pal))
	mat.set_shader_parameter("count", float(COLORS.size()))
	view.material = mat
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	resize(size)
	_volcano()


func resize(new_size: Vector2) -> void:
	var changed := not new_size.is_equal_approx(size) or grid.is_empty()
	size = new_size
	view.size = size
	if not changed:
		return
	cell = maxf(4.0, ceil(sqrt(size.x * size.y / MAX_CELLS)))
	gw = maxi(int(size.x / cell), 4)
	gh = maxi(int(size.y / cell), 4)
	grid = PackedByteArray()
	grid.resize(gw * gh)
	life.resize(gw * gh)
	stamp.resize(gw * gh)
	movers.resize(gh)
	movers.fill(0)
	image = Image.create_from_data(gw, gh, false, Image.FORMAT_R8, grid)
	texture = ImageTexture.create_from_image(image)
	(view.material as ShaderMaterial).set_shader_parameter("cells", texture)
	(view.material as ShaderMaterial).set_shader_parameter("grid", Vector2(gw, gh))


static func _moves(t: int) -> bool:
	return t == SAND or t == WATER or t == FIRE or t == SMOKE or t == LAVA or t == OIL


func _put(i: int, t: int) -> void:
	var was := grid[i]
	if was == t:
		return
	var row := i / gw
	if _moves(was):
		movers[row] -= 1
	if _moves(t):
		movers[row] += 1
	grid[i] = t
	life[i] = randi_range(40, 90) if t == FIRE else (randi_range(60, 160) if t == SMOKE else 0)
	stamp[i] = frame


func _swap(a: int, b: int) -> void:
	var ta := grid[a]
	var tb := grid[b]
	grid[a] = tb
	grid[b] = ta
	var la := life[a]
	life[a] = life[b]
	life[b] = la
	var ra := a / gw
	var rb := b / gw
	if ra != rb:
		if _moves(ta):
			movers[ra] -= 1
			movers[rb] += 1
		if _moves(tb):
			movers[rb] -= 1
			movers[ra] += 1
	stamp[a] = frame
	stamp[b] = frame


func _clear() -> void:
	eruption = 0.0
	grid.fill(0)
	life.fill(0)
	movers.fill(0)


# A stone mountain in a lake, trees on the shore, and an eruption: lava wells
# out of the crater for a while and runs down the slopes into the water
func _volcano() -> void:
	_clear()
	var shore := gh - 1 - int(gh * 0.16)
	var peak := int(gh * 0.42)
	var cx := gw / 2
	for y in range(peak, gh):
		var half := int((y - peak) * gw * 0.3 / (gh - peak)) + 3     # the base spans about 60% of the width
		for x in range(cx - half, cx + half + 1):
			if x >= 0 and x < gw:
				_put(x + y * gw, STONE)
	# The crater: a notch in the summit
	for y in range(peak, peak + 3):
		for x in range(cx - 2, cx + 3):
			_put(x + y * gw, EMPTY)
	for x in gw:
		for y in range(shore, gh):
			if grid[x + y * gw] == EMPTY:
				_put(x + y * gw, WATER)
	# Trees on the slopes, where the lava will find them
	for side in [-1, 1]:
		for k in 2:
			var tx: int = cx + side * int(gw * (0.18 + 0.08 * k))
			var ground := peak
			while ground < gh - 1 and grid[tx + ground * gw] == EMPTY:
				ground += 1
			for y in range(ground - 7, ground):
				if y > 0:
					_put(tx + y * gw, WOOD)
			for dx in range(-2, 3):
				for dy in range(-10, -6):
					if absi(dx) + absi(dy + 8) < 3 and ground + dy > 0:
						_put(tx + dx + (ground + dy) * gw, PLANT)
	crater = cx + peak * gw
	eruption = 6.0


func _paint(from: Vector2, to: Vector2) -> void:
	var t: int = BRUSH[brush]
	var a := from / cell
	var b := to / cell
	var steps := maxi(int(a.distance_to(b)), 1)
	var r := brush_size
	for s in steps + 1:
		var c := a.lerp(b, float(s) / steps)
		for dy in range(-int(r), int(r) + 1):
			for dx in range(-int(r), int(r) + 1):
				if dx * dx + dy * dy > r * r:
					continue
				var x := int(c.x) + dx
				var y := int(c.y) + dy
				if x < 0 or y < 0 or x >= gw or y >= gh:
					continue
				var i := x + y * gw
				# Loose materials go down speckled, solid ones fill in
				if t == EMPTY or t == STONE or t == WOOD or t == PLANT or randf() < 0.5:
					if t == EMPTY or grid[i] == EMPTY or t == STONE or t == WOOD:
						_put(i, t)


func touch_down(index: int, p: Vector2) -> void:
	strokes[index] = p
	_paint(p, p)


func touch_move(index: int, p: Vector2) -> void:
	if strokes.has(index):
		_paint(strokes[index], p)
		strokes[index] = p


func touch_up(index: int, _p: Vector2) -> void:
	strokes.erase(index)


func _physics_process(delta: float) -> void:
	if eruption > 0.0 and crater >= 0:
		eruption -= delta
		for k in 5:
			var at := crater + randi_range(-2, 2) - gw * randi_range(0, 1)
			if at >= 0 and grid[at] == EMPTY:
				_put(at, LAVA)
	for s in strokes:
		_paint(strokes[s], strokes[s])     # holding still keeps pouring
	frame = frame % 250 + 1
	var flip := frame % 2 == 0
	for y in range(gh - 1, -1, -1):
		if movers[y] == 0:
			continue
		var row := y * gw
		for k in gw:
			var x := k if flip else gw - 1 - k
			var i := row + x
			var t := grid[i]
			if t == EMPTY or not _moves(t) or stamp[i] == frame:
				continue
			match t:
				SAND: _sand(i, x, y)
				WATER: _liquid(i, x, y, 4, WATER)
				OIL: _liquid(i, x, y, 3, OIL)
				LAVA:
					_hot(i, x, y)
					if grid[i] == LAVA and frame % 2 == 0:
						_liquid(i, x, y, 1, LAVA)
				FIRE: _fire(i, x, y)
				SMOKE: _smoke(i, x, y)
	image.set_data(gw, gh, false, Image.FORMAT_R8, grid)
	texture.update(image)


# Can a `t` cell move into cell j? (empty, or something lighter it sinks through)
func _open(j: int, t: int) -> bool:
	var o := grid[j]
	if o == EMPTY:
		return true
	match t:
		SAND: return o == WATER or o == OIL or o == SMOKE
		WATER: return o == OIL or o == SMOKE
		LAVA: return o == WATER or o == OIL or o == SMOKE
		OIL: return o == SMOKE
	return false


func _sand(i: int, x: int, y: int) -> void:
	if y + 1 >= gh:
		return
	var below := i + gw
	if _open(below, SAND):
		_swap(i, below)
		return
	var d := 1 if randf() < 0.5 else -1
	for side in [d, -d]:
		var nx: int = x + side
		if nx >= 0 and nx < gw and _open(below + side, SAND):
			_swap(i, below + side)
			return


func _liquid(i: int, x: int, y: int, spread: int, t: int) -> void:
	if y + 1 < gh:
		var below := i + gw
		if _open(below, t):
			_swap(i, below)
			return
		var d := 1 if randf() < 0.5 else -1
		for side in [d, -d]:
			var nx: int = x + side
			if nx >= 0 and nx < gw and _open(below + side, t):
				_swap(i, below + side)
				return
	# Flow sideways, up to `spread` cells, so the surface levels out
	var dir := 1 if randf() < 0.5 else -1
	var at := i
	for s in spread:
		var nx := x + dir * (s + 1)
		if nx < 0 or nx >= gw or not _open(i + dir * (s + 1), t) or grid[i + dir * (s + 1)] != EMPTY:
			break
		at = i + dir * (s + 1)
	if at != i:
		_swap(i, at)
	# Plants drink: water touching a plant sometimes becomes more plant
	if t == WATER and randf() < 0.02:
		for n in _neighbours(i, x, y):
			if grid[n] == PLANT:
				_put(i, PLANT)
				return


func _neighbours(i: int, x: int, y: int) -> Array[int]:
	var out: Array[int] = []
	if x > 0: out.append(i - 1)
	if x < gw - 1: out.append(i + 1)
	if y > 0: out.append(i - gw)
	if y < gh - 1: out.append(i + gw)
	return out


static func _burns(t: int) -> bool:
	return t == WOOD or t == PLANT or t == OIL


# Lava: lights what it touches; water on it boils away and it sets as stone
func _hot(i: int, x: int, y: int) -> void:
	for n in _neighbours(i, x, y):
		var o := grid[n]
		if o == WATER:
			_put(n, SMOKE)
			_put(i, STONE)
			return
		if _burns(o) and randf() < 0.1:
			_put(n, FIRE)


func _fire(i: int, x: int, y: int) -> void:
	for n in _neighbours(i, x, y):
		var o := grid[n]
		if o == WATER:
			_put(i, SMOKE)          # doused
			return
		if _burns(o) and randf() < (0.35 if o == OIL else 0.07):
			_put(n, FIRE)
	var l := life[i]
	if l <= 1:
		_put(i, SMOKE if randf() < 0.3 else EMPTY)
		return
	life[i] = l - 1
	# Flames lick upward, wavering
	if y > 0 and randf() < 0.6:
		var up := i - gw + randi_range(-1, 1)
		var ux := up - (y - 1) * gw
		if ux >= 0 and ux < gw and grid[up] == EMPTY:
			_swap(i, up)


func _smoke(i: int, x: int, y: int) -> void:
	var l := life[i]
	if l <= 1:
		_put(i, EMPTY)
		return
	life[i] = l - 1
	if y > 0:
		var drift := randi_range(-1, 1)
		var nx := x + drift
		if nx >= 0 and nx < gw:
			var up := i - gw + drift
			var o := grid[up]
			if o == EMPTY or o == WATER or o == OIL:
				_swap(i, up)
				return
	var side := i + (1 if randf() < 0.5 else -1)
	if side / gw == y and side >= 0 and grid[side] == EMPTY:
		_swap(i, side)
