extends RefCounted
## Real leaf shapes, drawn as SVG at start-up into one sheet (`texture()`): English oak, sugar maple, beech,
## aspen and silver birch, each after the real leaf's outline, with its midrib and veins. White leaf, grey
## veins, alpha the outline; each in a square cell, tip up, the stalk at the bottom. foliage.gdshader,
## leaf.gdshader and leaf3d.gdshader cut their leaves from it (`leaf_atlas`, cell `shape`).

const CELL := 128
## The cells, in order (a shader's `shape` index).
const SHAPES := ["beech", "oak", "maple", "aspen", "birch"]

static var _texture: ImageTexture


static func texture() -> ImageTexture:
	if _texture == null:
		var sheet := Image.create(CELL * SHAPES.size(), CELL, false, Image.FORMAT_RGBA8)
		for i in SHAPES.size():
			var img := Image.new()
			img.load_svg_from_string(_svg(SHAPES[i]))
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(0, 0, CELL, CELL), Vector2i(i * CELL, 0))
		sheet.generate_mipmaps()
		_texture = ImageTexture.create_from_image(sheet)
	return _texture


static func _svg(shape: String) -> String:
	var outline := ""
	var veins := ""
	match shape:
		"oak":
			# English oak: five rounded lobes a side, widest towards the tip, little ears at the base
			outline = "M50,4 Q61,4 60,12 Q59,15 57,17 Q71,15 72,24 Q72,31 61,32 Q77,32 77,42 Q76,49 63,50 " \
				+ "Q72,51 71,58 Q69,64 60,65 Q65,67 63,73 Q61,78 56,79 Q58,83 56,87 L50,91 " \
				+ "L44,87 Q42,83 44,79 Q39,78 37,73 Q35,67 40,65 Q31,64 29,58 Q28,51 37,50 " \
				+ "Q24,49 23,42 Q23,32 39,32 Q28,31 28,24 Q29,15 43,17 Q41,15 40,12 Q39,4 50,4 Z"
			veins = _pinnate([[12, 58], [24, 70], [42, 75], [58, 69], [73, 62]], 4, 91)
		"maple":
			# sugar maple: five lobes, rounded sinuses, a few sharp teeth at the lobes' ends
			outline = "M50,4 L54,14 L60,11 L58,22 L60,31 L64,41 L71,35 L77,23 L81,30 L91,27 L86,38 L94,44 " \
				+ "L84,48 L78,53 L70,58 L77,62 L86,70 L76,72 L68,78 L56,80 L50,79 " \
				+ "L44,80 L32,78 L24,72 L14,70 L23,62 L30,58 L22,53 L16,48 L6,44 L14,38 L9,27 L19,30 " \
				+ "L23,23 L29,35 L36,41 L40,31 L42,22 L40,11 L46,14 Z"
			veins = "M50,79 L50,6 M50,79 L90,28 M50,79 L10,28 M50,79 L85,69 M50,79 L15,69 " \
				+ "M50,50 L58,40 M50,50 L42,40 M50,30 L56,22 M50,30 L44,22"
		"beech":
			# beech: an even oval, pointed, the edge gently waved between straight parallel veins
			outline = _ovate(func(t: float) -> float: return 24.0 * pow(sin(PI * pow(t, 0.8)), 0.85), 8, 1.4, 4.0, 90.0)
			veins = _pinnate([[14, 56], [24, 66], [34, 71], [44, 73], [54, 73], [64, 71], [74, 66], [83, 60]], 4, 90)
		"aspen":
			# quaking aspen: nearly round, a short sharp tip, a fine round-toothed edge
			outline = _ovate(func(t: float) -> float: return 34.0 * pow(sin(PI * pow(t, 0.9)), 0.75), 22, 1.0, 10.0, 84.0)
			veins = "M50,84 L50,12 M50,80 L78,58 M50,80 L22,58 M50,60 L74,40 M50,60 L26,40 M50,42 L66,28 M50,42 L34,28"
		"birch":
			# silver birch: a triangle with a long point and a broad flat base, doubly toothed
			outline = _ovate(func(t: float) -> float: return 36.0 * pow(t, 1.1) * pow(1.0 - pow(t, 6.0), 0.5), 18, 1.6, 4.0, 86.0)
			veins = _pinnate([[24, 58], [36, 66], [48, 72], [60, 78], [72, 82]], 4, 86)
	return ("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 100 100\">" % [CELL, CELL]) \
		+ "<path d=\"%s\" fill=\"#ffffff\"/>" % outline \
		+ "<path d=\"%s\" fill=\"none\" stroke=\"#8a8a8a\" stroke-width=\"1.4\" stroke-linecap=\"round\"/>" % veins \
		+ "<path d=\"M50,%d L50,99\" stroke=\"#ffffff\" stroke-width=\"2.6\" stroke-linecap=\"round\"/>" % (91 if shape != "maple" else 79) \
		+ "</svg>"


## A leaf outline down a midrib from the tip (y `top`) to the base (y `base`): `half(t)` is the half width
## at t (0 tip, 1 base) in the 100 box, with `teeth` teeth a side `tooth` deep (doubled when `tooth` > 1.5).
static func _ovate(half: Callable, teeth: int, tooth: float, top: float, base: float) -> String:
	var right: Array[Vector2] = []
	var steps := teeth * 6
	for k in steps + 1:
		var t := float(k) / steps
		var w: float = half.call(t)
		# a saw tooth along the edge, sharp side towards the tip
		var saw := fmod(t * teeth, 1.0)
		var d := tooth * (1.0 - saw) * sin(PI * t)
		if tooth > 1.5:
			d += tooth * 0.5 * (1.0 - fmod(t * teeth * 2.0, 1.0)) * sin(PI * t)
		right.append(Vector2(50.0 + w + d, lerpf(top, base, t)))
	var s := "M50,%.1f" % top
	for p in right:
		s += " L%.1f,%.1f" % [p.x, p.y]
	for k in range(right.size() - 1, -1, -1):
		s += " L%.1f,%.1f" % [100.0 - right[k].x, right[k].y]
	return s + " Z"


## A midrib from `top` to `base` and pairs of side veins: each [y on the midrib, x where it reaches the edge
## (the left one mirrored)], running up and out
static func _pinnate(pairs: Array, top: int, base: int) -> String:
	var s := "M50,%d L50,%d" % [base, top + 2]
	for p in pairs:
		var y: float = p[0]
		var x: float = p[1]
		s += " M50,%.1f L%.1f,%.1f M50,%.1f L%.1f,%.1f" % [y + 6.0, x, y, y + 6.0, 100.0 - x, y]
	return s
