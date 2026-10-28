class_name ShapePad
extends Control
## A small square canvas to draw a sprite on with a finger or the mouse:
##   Shape: draw round an outline; when you let go it closes, is smoothed and filled.
##   Brush / Eraser: paint or rub out with a round brush.
## Mirror draws both halves at once (draw half a leaf, get the whole leaf). The picture is
## `res` pixels square (64-256). result() gives it with its soft edge (feather) as RGBA8: in mask
## mode white with the shape in the alpha (what effects tint), else in the colours painted.
##
## For a lab: ShapePad.picker_controls(label, current_id, on_pick, builtins) gives the controls()
## entries for a sprite picker (built-in sprites, then Custom: + Draw, + Import and the saved ones);
## ShapePad.texture(id, fallback) gives the texture for whatever id was picked. See ui/sprite_picker.gd
## and ui/shape_editor.gd (the big editing view the picker opens over everything).
##
## It is in the "keeps_drags" group, so a drag on it never scrolls the panel it sits in.

signal changed # after each stroke, undo, clear or load

const MAX_UNDO := 30
const C_BACK := Color("1f1f22")
const C_CHECK := Color("2a2a2f")
const C_EDGE := Color("111113")
const C_GUIDE := Color(0.31, 0.53, 0.78, 0.55)
const C_STROKE := Color("ffd166")

var res := 128
var tool := "shape" # "shape", "brush" or "erase"
var mirror := true
var feather := 1.0 # soft edge, pixels at res
var brush := 6.0 # brush radius, pixels at res
var mask := true # white mask; false: colour
var color := Color.WHITE # what colour mode paints with
var paint: Image # the picture as drawn (straight alpha)

var _undo: Array[Image] = []
var _stroke := PackedVector2Array() # canvas coordinates
var _drawing := false
var _last := Vector2.ZERO
var _tex: ImageTexture
var _shown: Image # what is drawn: the result when idle, the raw paint while drawing
var _check: ImageTexture


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(160, 160)
	add_to_group("keeps_drags")
	paint = Image.create(res, res, false, Image.FORMAT_RGBA8)
	_refresh(true)


# --- the API for labs ----------------------------------------------------------

## The properties entries for a sprite picker (see ui/sprite_picker.gd). `builtins` lists the
## lab's own sprites as {id, label, tex}; a custom sprite's id is "user:<name>". on_pick(id) is
## called when one is picked, drawn or imported. Add the result to a lab's controls():
##   c.append_array(ShapePad.picker_controls("Sprite", e.tex, func(id: String) -> void: _put("tex", id),
##       ShapePad.builtins(Tex.NAMES, Tex.LABELS, Tex.get_texture)))
static func picker_controls(label: String, current: String, on_pick: Callable, builtins: Array = []) -> Array:
	var Picker: GDScript = load("res://ui/sprite_picker.gd")
	return [{type = "custom", node = Picker.new(label, current, on_pick, builtins)}]


## Built-in sprite entries for picker_controls from parallel name and label lists and a
## Callable(name) -> Texture2D.
static func builtins(names: Array, labels: Array, get_tex: Callable) -> Array:
	var out := []
	for i in names.size():
		out.append({id = names[i], label = labels[i] if i < labels.size() else String(names[i]).capitalize(),
			tex = get_tex.call(names[i]) if get_tex.is_valid() else null})
	return out


## The texture for an id from a picker: a custom sprite, else fallback.call(id) (the lab's own).
static func texture(id: String, fallback := Callable()) -> Texture2D:
	return ShapeStore.texture(id, fallback)


## Opens the big editing view over everything (see ui/shape_editor.gd). done(id) gets the saved
## sprite's id, or "" if it was cancelled. `edit` is a custom sprite's name to change, or "".
## `host` is any node in the UI (its theme is borrowed).
static func open_editor(host: Node, edit: String, done: Callable, import_first := false) -> Node:
	var Editor: GDScript = load("res://ui/shape_editor.gd")
	var ed: Node = Editor.new()
	ed.setup(host, edit, done, import_first)
	host.get_tree().root.add_child(ed)
	return ed


# --- the picture -----------------------------------------------------------------

func set_res(n: int) -> void:
	if n == res:
		return
	_push_undo()
	res = n
	paint.resize(n, n, Image.INTERPOLATE_BILINEAR)
	_refresh(true)
	changed.emit()


func clear() -> void:
	_push_undo()
	paint = Image.create(res, res, false, Image.FORMAT_RGBA8)
	_refresh(true)
	changed.emit()


func undo() -> void:
	if _undo.is_empty():
		return
	paint = _undo.pop_back()
	res = paint.get_width()
	_refresh(true)
	changed.emit()


func can_undo() -> bool:
	return not _undo.is_empty()


## Puts a picture on the pad (an imported image, a sprite to change), fitted to res.
func load_image(img: Image, keep_res := false) -> void:
	_push_undo()
	var copy: Image = img.duplicate()
	copy.clear_mipmaps()
	copy.convert(Image.FORMAT_RGBA8)
	if not keep_res:
		res = clampi(nearest_size(maxi(copy.get_width(), copy.get_height())), 64, 256)
	if copy.get_size() != Vector2i(res, res):
		copy.resize(res, res, Image.INTERPOLATE_BILINEAR)
	paint = copy
	_refresh(true)
	changed.emit()


static func nearest_size(n: int) -> int:
	var best := 128
	for s: int in ShapeStore.SIZES:
		if absi(s - n) < absi(best - n):
			best = s
	return best


## True when every pixel that shows is white: a mask.
func is_mask() -> bool:
	var data := paint.get_data()
	for i in range(0, data.size(), 4):
		if data[i + 3] > 8 and (data[i] < 250 or data[i + 1] < 250 or data[i + 2] < 250):
			return false
	return true


## True when nothing is drawn.
func is_empty() -> bool:
	return paint.get_used_rect().size == Vector2i.ZERO


## The finished sprite: res square RGBA8, with the soft edge, white in mask mode.
func result() -> Image:
	var img: Image = paint.duplicate()
	var data := img.get_data()
	var n := res
	if feather > 0.05:
		# blur the alpha (and, in colour, the colour weighted by it, so the soft edge keeps the
		# colour of what it spread from rather than going dark)
		var r := maxi(int(round(feather)), 1)
		var fields: Array[PackedFloat32Array] = []
		for ch in (1 if mask else 4):
			var f := PackedFloat32Array()
			f.resize(n * n)
			fields.append(f)
		for i in n * n:
			var a := data[i * 4 + 3]
			fields[0][i] = a
			if not mask:
				for ch in 3:
					fields[ch + 1][i] = data[i * 4 + ch] * a
		for k in fields.size():
			for pass_i in 2:
				fields[k] = _box(fields[k], n, r, true)
				fields[k] = _box(fields[k], n, r, false)
		for i in n * n:
			var a := fields[0][i]
			data[i * 4 + 3] = clampi(int(a + 0.5), 0, 255)
			if not mask and a > 0.01:
				for ch in 3:
					data[i * 4 + ch] = clampi(int(fields[ch + 1][i] / a + 0.5), 0, 255)
	if mask:
		for i in range(0, data.size(), 4):
			data[i] = 255
			data[i + 1] = 255
			data[i + 2] = 255
	return Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, data)


## One pass of a box blur `r` wide over an n x n field, along rows or columns.
static func _box(src: PackedFloat32Array, n: int, r: int, rows: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n * n)
	var w := 2.0 * r + 1.0
	for line in n:
		var sum := 0.0
		for k in range(-r, r + 1):
			sum += src[_at(line, clampi(k, 0, n - 1), n, rows)]
		for i in n:
			out[_at(line, i, n, rows)] = sum / w
			sum += src[_at(line, mini(i + r + 1, n - 1), n, rows)] - src[_at(line, maxi(i - r, 0), n, rows)]
	return out


static func _at(line: int, i: int, n: int, rows: bool) -> int:
	return line * n + i if rows else i * n + line


func _push_undo() -> void:
	_undo.append(paint.duplicate())
	if _undo.size() > MAX_UNDO:
		_undo.remove_at(0)


func _refresh(idle: bool) -> void:
	_shown = result() if idle else paint
	if _tex and Vector2i(_tex.get_size()) == _shown.get_size():
		_tex.update(_shown)
	else:
		_tex = ImageTexture.create_from_image(_shown)
	queue_redraw()


# --- drawing -----------------------------------------------------------------------

## Where the canvas is drawn in the control: the biggest square that fits, centred.
func view() -> Rect2:
	var side := minf(size.x, size.y)
	return Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))


func to_canvas(p: Vector2) -> Vector2:
	var v := view()
	return (p - v.position) / maxf(v.size.x, 1.0) * res


func to_screen(c: Vector2) -> Vector2:
	var v := view()
	return v.position + c / res * v.size.x


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			begin_stroke(to_canvas(event.position))
		elif _drawing:
			end_stroke()
		accept_event()
	elif event is InputEventMouseMotion and _drawing:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			extend_stroke(to_canvas(event.position))
		else:
			end_stroke()
		accept_event()


func begin_stroke(c: Vector2) -> void:
	_push_undo()
	_drawing = true
	_stroke = PackedVector2Array([c])
	_last = c
	if tool != "shape":
		_dab_line(c, c)
		_refresh(false)
	queue_redraw()


func extend_stroke(c: Vector2) -> void:
	if not _drawing:
		return
	if c.distance_to(_last) < 0.6:
		return
	if tool == "shape":
		_stroke.append(c)
	else:
		_dab_line(_last, c)
		_refresh(false)
	_last = c
	queue_redraw()


func end_stroke() -> void:
	if not _drawing:
		return
	_drawing = false
	if tool == "shape":
		if _stroke.size() >= 3:
			var poly := smooth(_stroke)
			fill_polygon(poly)
			if mirror:
				var m := PackedVector2Array()
				for p in poly:
					m.append(Vector2(res - p.x, p.y))
				fill_polygon(m)
		else:
			_undo.pop_back() # a tap: nothing was drawn
	_stroke.clear()
	_refresh(true)
	changed.emit()


## A closed outline smoothed (two rounds of Chaikin's corner cutting), after dropping points
## too close together.
static func smooth(pts: PackedVector2Array) -> PackedVector2Array:
	var thin := PackedVector2Array([pts[0]])
	for p in pts:
		if p.distance_to(thin[thin.size() - 1]) >= 1.0:
			thin.append(p)
	var cur := thin
	for round_i in 2:
		var next := PackedVector2Array()
		var n := cur.size()
		for i in n:
			var a := cur[i]
			var b := cur[(i + 1) % n]
			next.append(a.lerp(b, 0.25))
			next.append(a.lerp(b, 0.75))
		cur = next
	return cur


## Fills a closed polygon (canvas coordinates) into the paint, anti-aliased: four scanlines a
## pixel, each span's ends covered by how much of the pixel they cross.
func fill_polygon(poly: PackedVector2Array) -> void:
	var n := res
	var cover := PackedFloat32Array()
	cover.resize(n * n)
	var sub := 4
	var count := poly.size()
	var lo := n
	var hi := 0
	for p in poly:
		lo = mini(lo, int(floor(p.y)))
		hi = maxi(hi, int(ceil(p.y)))
	lo = clampi(lo, 0, n - 1)
	hi = clampi(hi, 0, n - 1)
	for y in range(lo, hi + 1):
		for s in sub:
			var sy := y + (s + 0.5) / sub
			var xs := PackedFloat32Array()
			for i in count:
				var a := poly[i]
				var b := poly[(i + 1) % count]
				if (a.y <= sy and b.y > sy) or (b.y <= sy and a.y > sy):
					xs.append(a.x + (sy - a.y) / (b.y - a.y) * (b.x - a.x))
			xs.sort()
			for k in range(0, xs.size() - 1, 2):
				var x0 := clampf(xs[k], 0.0, n)
				var x1 := clampf(xs[k + 1], 0.0, n)
				if x1 <= x0:
					continue
				var i0 := int(floor(x0))
				var i1 := mini(int(floor(x1)), n - 1)
				var row := y * n
				if i0 == i1:
					cover[row + i0] += (x1 - x0) / sub
					continue
				cover[row + i0] += (i0 + 1 - x0) / sub
				for x in range(i0 + 1, i1):
					cover[row + x] += 1.0 / sub
				if i1 < n:
					cover[row + i1] += (x1 - i1) / sub
	_lay(cover, false)


## Paints (or rubs out) round dabs from a to b, and their mirror image.
func _dab_line(a: Vector2, b: Vector2) -> void:
	var n := res
	var r := maxf(brush, 0.5)
	var cover := PackedFloat32Array()
	cover.resize(n * n)
	var mirrors := [false, true] if mirror else [false]
	var box := Rect2i()
	for flip: bool in mirrors:
		var p0 := Vector2(n - a.x, a.y) if flip else a
		var p1 := Vector2(n - b.x, b.y) if flip else b
		var x_lo := clampi(int(floor(minf(p0.x, p1.x) - r - 1)), 0, n - 1)
		var x_hi := clampi(int(ceil(maxf(p0.x, p1.x) + r + 1)), 0, n - 1)
		var y_lo := clampi(int(floor(minf(p0.y, p1.y) - r - 1)), 0, n - 1)
		var y_hi := clampi(int(ceil(maxf(p0.y, p1.y) + r + 1)), 0, n - 1)
		var part := Rect2i(x_lo, y_lo, x_hi - x_lo + 1, y_hi - y_lo + 1)
		box = part if box.size == Vector2i.ZERO else box.merge(part)
		var seg := p1 - p0
		var len2 := maxf(seg.length_squared(), 0.0001)
		for y in range(y_lo, y_hi + 1):
			for x in range(x_lo, x_hi + 1):
				var p := Vector2(x + 0.5, y + 0.5)
				var t := clampf((p - p0).dot(seg) / len2, 0.0, 1.0)
				var d := p.distance_to(p0 + seg * t)
				var c := clampf(r - d + 0.5, 0.0, 1.0)
				var i := y * n + x
				cover[i] = maxf(cover[i], c)
	_lay(cover, tool == "erase", box)


## Lays a coverage field onto the paint in the paint colour (white in mask mode), or rubs out.
func _lay(cover: PackedFloat32Array, erase: bool, box := Rect2i()) -> void:
	if box.size == Vector2i.ZERO:
		box = Rect2i(0, 0, res, res)
	var data := paint.get_data()
	var col := Color.WHITE if mask else color
	var cr := col.r8
	var cg := col.g8
	var cb := col.b8
	for i in _indices(box):
		var c := minf(cover[i], 1.0)
		if c <= 0.0:
			continue
		var j := i * 4
		var a := data[j + 3] / 255.0
		if erase:
			data[j + 3] = int(a * (1.0 - c) * 255.0 + 0.5)
			continue
		var na := a + c * (1.0 - a)
		if na > 0.0:
			# colour "over": what was there shows through by how much this didn't cover
			var keep := a * (1.0 - c) / na
			data[j] = int(lerpf(cr, data[j], keep) + 0.5)
			data[j + 1] = int(lerpf(cg, data[j + 1], keep) + 0.5)
			data[j + 2] = int(lerpf(cb, data[j + 2], keep) + 0.5)
		data[j + 3] = int(na * 255.0 + 0.5)
	paint = Image.create_from_data(res, res, false, Image.FORMAT_RGBA8, data)


## The pixel indices inside a box of the canvas.
func _indices(box: Rect2i) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(box.size.x * box.size.y)
	var k := 0
	for y in range(box.position.y, box.end.y):
		var row := y * res
		for x in range(box.position.x, box.end.x):
			out[k] = row + x
			k += 1
	return out


func _draw() -> void:
	var v := view()
	draw_rect(Rect2(Vector2.ZERO, size), C_BACK)
	# a checkerboard behind, so the soft edge and holes show
	var cells := 8
	var cell := v.size.x / cells
	for y in cells:
		for x in cells:
			draw_rect(Rect2(v.position + Vector2(x, y) * cell, Vector2(cell, cell)),
				C_CHECK if (x + y) % 2 == 0 else C_BACK)
	if _tex:
		draw_texture_rect(_tex, v, false)
	draw_rect(v, C_EDGE, false, 2.0)
	if mirror:
		var x := v.position.x + v.size.x * 0.5
		draw_dashed_line(Vector2(x, v.position.y), Vector2(x, v.end.y), C_GUIDE, 2.0, 8.0)
	if _drawing and tool == "shape" and _stroke.size() >= 2:
		var pts := PackedVector2Array()
		for c in _stroke:
			pts.append(to_screen(c))
		draw_polyline(pts, C_STROKE, 3.0, true)
		draw_dashed_line(pts[pts.size() - 1], pts[0], Color(C_STROKE, 0.5), 2.0, 6.0)
		if mirror:
			var m := PackedVector2Array()
			for c in _stroke:
				m.append(to_screen(Vector2(res - c.x, c.y)))
			draw_polyline(m, Color(C_STROKE, 0.55), 2.0, true)
