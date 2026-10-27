class_name PineTree
extends Resource
## A pine (fir, spruce, lodgepole...) built from code, as a mesh: a tapering trunk with a flare at
## its foot, whorls of drooping branch fronds that shorten towards a spire, each frond fat in the
## middle and turned up a little at its tip, with side sprigs, darker within and lighter at the
## tips, and snow on the upper faces if asked. Every setting below can be changed; the same
## settings and seed always make the same tree.
##
## One tree:   var made := PineTree.new(); made.height = 12.0; add_child(made.instance())
## A forest:   PineTree.forest(parent, points, made, 6)   (a MultiMesh per variant: a few draws)
##
## The mesh carries vertex colours (sRGB) and normals bent outward from the trunk, so the whole
## crown shades as one soft shape (good with cel shading). It is drawn with `material` if set, or
## else a plain material that uses the vertex colours.

## Overall height, metres, and the trunk's radius at its foot.
@export var height := 10.0
@export var trunk_radius := 0.22
## How far up the trunk the lowest branches start (0..1 of the height).
@export_range(0.0, 0.8) var crown_base := 0.14
## Whorls (rings of branches) and branches in each.
@export_range(3, 30) var whorls := 12
@export_range(3, 14) var branches := 9
## How wide the crown is, against its height (0.3 slim spire, 0.6 broad fir).
@export_range(0.15, 1.0) var spread := 0.42
## How much the branches hang (0 straight out, 1 hanging down like a spruce's).
@export_range(0.0, 1.0) var droop := 0.45
## How the branch length falls off up the tree: 1 a straight cone, more a rounder shoulder.
@export_range(0.4, 2.5) var taper := 1.05
## How thick a frond is, against its length.
@export_range(0.1, 0.8) var fullness := 0.5
## Side sprigs on each frond (more detail, more triangles).
@export_range(0, 4) var sprigs := 2
## Unevenness: branch lengths and angles, and the lean of the whole tree.
@export_range(0.0, 1.0) var wildness := 0.35
@export_range(0.0, 0.3) var lean := 0.04
## Colours.
@export var bark := Color(0.36, 0.25, 0.18)
@export var needles_inner := Color(0.10, 0.22, 0.16)
@export var needles_outer := Color(0.24, 0.42, 0.26)
@export var tips := Color(0.40, 0.56, 0.32)
## Snow on the upper faces, 0..1.
@export_range(0.0, 1.0) var snow := 0.0
@export var snow_colour := Color(0.94, 0.96, 1.0)
@export var seed := 1
## What to draw it with. Empty: a plain material that takes the vertex colours.
@export var material: Material

static var _cache := {}


## The settings as a key (for sharing built meshes).
func _key(variant: int) -> String:
	return "%s|%d" % [var_to_str([_steps, height, trunk_radius, crown_base, whorls, branches, spread, droop, taper, fullness, sprigs, wildness, lean,
		bark, needles_inner, needles_outer, tips, snow, snow_colour, seed]).hash(), variant]


## The tree's mesh, built once for each variant and kept.
func mesh(variant := 0) -> ArrayMesh:
	var key := _key(variant)
	if _cache.has(key):
		return _cache[key]
	var built := _build(seed * 7919 + variant * 104729)
	_cache[key] = built
	return built


## A MeshInstance3D of it.
func instance(variant := 0) -> MeshInstance3D:
	var made := MeshInstance3D.new()
	made.mesh = mesh(variant)
	made.material_override = _material()
	return made


## Plants trees at `points` (Vector3s on the ground), `variants` different ones turned and sized at
## random, under `parent`. They are drawn as MultiMeshes, one per variant in each square of `chunk`
## metres (so trees off screen are not drawn); beyond `near` metres each square changes over to a
## plain version of the same tree (see `simple`) with no shadow. `sizes` scales them (min, max).
## `near` 0 keeps the full tree at every distance.
static func forest(parent: Node3D, points: Array, shape: PineTree, variants := 4, sizes := Vector2(0.8, 1.25), chunk := 64.0, near := 70.0) -> Array[MultiMeshInstance3D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = shape.seed
	var plain := shape.simple() if near > 0.0 else null
	var groups := {}
	for p: Vector3 in points:
		var size := rng.randf_range(sizes.x, sizes.y)
		var cell := Vector2i(floori(p.x / chunk), floori(p.z / chunk))
		var key := [cell, rng.randi() % variants]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size), p))
	var made: Array[MultiMeshInstance3D] = []
	for key: Array in groups:
		var trees: Array = groups[key]
		for detailed: bool in ([true, false] if plain else [true]):
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = shape.mesh(key[1]) if detailed else plain.mesh(key[1])
			multi.instance_count = trees.size()
			for i in trees.size():
				multi.set_instance_transform(i, trees[i])
			var node := MultiMeshInstance3D.new()
			node.multimesh = multi
			node.material_override = shape._material()
			if plain:
				node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				if detailed:
					node.visibility_range_end = near
					node.visibility_range_end_margin = 10.0
				else:
					node.visibility_range_begin = near
					node.visibility_range_begin_margin = 10.0
					node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(node)
			made.append(node)
	return made


## A plainer version of this tree, for far off: the same height, shape and colours, with fewer and
## fuller whorls, fewer branches, and no sprigs (about a tenth of the triangles).
func simple() -> PineTree:
	var plain: PineTree = duplicate()
	plain.whorls = maxi(int(whorls / 2.5), 4)
	plain.branches = mini(branches, 6)
	plain.sprigs = 0
	plain.fullness = minf(fullness * 1.4, 0.8)
	plain._steps = 2
	return plain


## Segments along each frond (fewer for a plain tree).
var _steps := 4


func _material() -> Material:
	if material:
		return material
	var plain := StandardMaterial3D.new()
	plain.vertex_color_use_as_albedo = true
	plain.vertex_color_is_srgb = true
	plain.roughness = 1.0
	return plain


func _build(variant_seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = variant_seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tilt := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, lean)) if lean > 0.0 else Basis.IDENTITY
	var top := height * rng.randf_range(0.94, 1.06)
	_trunk(st, top, tilt)
	var crown := top * (1.0 - crown_base)
	var first := top * crown_base
	var turn := rng.randf() * TAU
	_fill(st, tilt, first + crown / whorls * 0.4, top, rng)
	for w in whorls:
		var t := (w + 0.5) / whorls
		var y := first + crown * pow(t, 0.92)
		# (shorter towards the top, by `taper`; a little uneven)
		var reach := spread * top * 0.5 * pow(1.0 - t, taper) + top * 0.035
		turn += 2.39996  # (the golden angle, so no branch sits right over the one below)
		var count := maxi(branches - int(t * 2.5), 3)
		for b in count:
			var angle := turn + b * TAU / count + rng.randf_range(-0.35, 0.35) * wildness
			var length := reach * rng.randf_range(1.0 - 0.35 * wildness, 1.0 + 0.2 * wildness)
			var hang := droop * rng.randf_range(0.8, 1.2) * lerpf(1.0, 0.55, t)
			var base := Vector3(0, y + rng.randf_range(-0.3, 0.3) * crown / whorls, 0)
			_frond(st, tilt, base, angle, length, hang, t, top, rng, true)
	# The leader at the very top.
	_frond(st, tilt, Vector3(0, top * 0.97, 0), 0.0, top * 0.09, -1.0, 1.0, top, rng, false)
	return st.commit()


## The dark mass of needles inside the crown, round the trunk: a ragged cone, so the tree reads as
## solid between its fronds, as a real one does from any way off.
func _fill(st: SurfaceTool, tilt: Basis, first: float, top: float, rng: RandomNumberGenerator) -> void:
	var sides := 11
	var rings := maxi(whorls, 4)
	var base_r := spread * top * 0.5 * 0.62
	var radii: Array = []
	for r in rings + 1:
		var t := float(r) / rings
		var row: Array[float] = []
		for s in sides:
			# (ragged: in and out between the fronds, more so lower down)
			row.append(base_r * pow(1.0 - t, taper) * rng.randf_range(0.78, 1.12) + top * 0.012)
		radii.append(row)
	for r in rings:
		var t0 := float(r) / rings
		var t1 := float(r + 1) / rings
		var y0 := first + (top * 0.985 - first) * t0
		var y1 := first + (top * 0.985 - first) * t1
		for s in sides:
			var u0 := s * TAU / sides
			var u1 := (s + 1) * TAU / sides
			var a := tilt * Vector3(cos(u0) * radii[r][s], y0, sin(u0) * radii[r][s])
			var b := tilt * Vector3(cos(u1) * radii[r][(s + 1) % sides], y0, sin(u1) * radii[r][(s + 1) % sides])
			var c := tilt * Vector3(cos(u0) * radii[r + 1][s], y1, sin(u0) * radii[r + 1][s])
			var d := tilt * Vector3(cos(u1) * radii[r + 1][(s + 1) % sides], y1, sin(u1) * radii[r + 1][(s + 1) % sides])
			var n0 := tilt * Vector3(cos(u0), 0.55, sin(u0)).normalized()
			var n1 := tilt * Vector3(cos(u1), 0.55, sin(u1)).normalized()
			var inner := needles_inner.lerp(needles_outer, 0.25)
			var snowy0 := inner.lerp(snow_colour, snow * 0.5) if snow > 0.0 else inner
			_tri(st, [a, c, b], [n0, n0, n1], [inner, snowy0, inner])
			_tri(st, [b, c, d], [n1, n0, n1], [inner, snowy0, snowy0])
	# (and its underside, so it does not show hollow from below)
	var y := first
	for s in sides:
		var u0 := s * TAU / sides
		var u1 := (s + 1) * TAU / sides
		var a := tilt * Vector3(cos(u0) * radii[0][s], y, sin(u0) * radii[0][s])
		var b := tilt * Vector3(cos(u1) * radii[0][(s + 1) % sides], y, sin(u1) * radii[0][(s + 1) % sides])
		var dark := needles_inner.darkened(0.2)
		_tri(st, [a, b, tilt * Vector3(0, y + 0.3, 0)], [Vector3.DOWN, Vector3.DOWN, Vector3.DOWN], [dark, dark, dark])


func _trunk(st: SurfaceTool, top: float, tilt: Basis) -> void:
	var sides := 7
	var rings := 4
	for r in rings:
		var a := float(r) / rings
		var b := float(r + 1) / rings
		var ya := top * a
		var yb := top * b
		# (a flare at the foot, tapering to a point)
		var ra := trunk_radius * (1.0 - a * 0.92) * (1.0 + 0.6 * pow(1.0 - a, 6.0))
		var rb := trunk_radius * (1.0 - b * 0.92) * (1.0 + 0.6 * pow(1.0 - b, 6.0))
		for s in sides:
			var u0 := s * TAU / sides
			var u1 := (s + 1) * TAU / sides
			var p00 := tilt * Vector3(cos(u0) * ra, ya, sin(u0) * ra)
			var p01 := tilt * Vector3(cos(u1) * ra, ya, sin(u1) * ra)
			var p10 := tilt * Vector3(cos(u0) * rb, yb, sin(u0) * rb)
			var p11 := tilt * Vector3(cos(u1) * rb, yb, sin(u1) * rb)
			var n0 := tilt * Vector3(cos(u0), 0.2, sin(u0)).normalized()
			var n1 := tilt * Vector3(cos(u1), 0.2, sin(u1)).normalized()
			var shade := bark.darkened(0.15 * float(s % 2))
			_tri(st, [p00, p10, p01], [n0, n0, n1], [shade, shade, shade])
			_tri(st, [p01, p10, p11], [n1, n0, n1], [shade, shade, shade])


## One frond: out from the trunk along `angle`, `length` long, hanging by `hang`; a long flattened
## diamond in section, fat in the middle, with sprigs off its sides.
func _frond(st: SurfaceTool, tilt: Basis, base: Vector3, angle: float, length: float, hang: float, up_tree: float, top: float, rng: RandomNumberGenerator, with_sprigs: bool) -> void:
	var out := Vector3(cos(angle), 0, sin(angle))
	var points: Array[Vector3] = []
	var steps := _steps
	for k in steps + 1:
		var s := float(k) / steps
		var p := base + out * length * s
		if hang >= 0.0:
			# (droops through its middle and lifts a little at the tip)
			p.y -= hang * length * (0.55 * s * s - 0.12 * pow(s, 4.0) * 3.0) + 0.02 * length
		else:
			# (the leader: straight up)
			p = base + Vector3.UP * length * s
		points.append(p)
	var wide := length * fullness
	var axis_up := Vector3.UP if hang >= 0.0 else out
	_spindle(st, tilt, points, wide, wide * 0.6, axis_up, up_tree, top)
	if with_sprigs and sprigs > 0:
		for n in sprigs:
			var s := 0.3 + 0.55 * (n + 0.5) / sprigs
			var at := points[int(s * steps)]
			for side: float in [-1.0, 1.0]:
				var dir := (out + out.cross(Vector3.UP) * side * 0.9).normalized()
				var sprig_len := length * 0.42 * (1.0 - s * 0.45)
				var sprig: Array[Vector3] = [at, at + dir * sprig_len * 0.5 + Vector3.DOWN * hang * sprig_len * 0.25, at + dir * sprig_len + Vector3.DOWN * hang * sprig_len * 0.35]
				_spindle(st, tilt, sprig, sprig_len * fullness * 1.1, sprig_len * fullness * 0.55, Vector3.UP, up_tree, top)


## A long shape round a bent line: in section a flattened diamond `wide` across and `thick` deep,
## swelling to the middle of its length and coming to a point at both ends.
func _spindle(st: SurfaceTool, tilt: Basis, line: Array[Vector3], wide: float, thick: float, up: Vector3, up_tree: float, top: float) -> void:
	var count := line.size()
	var rings: Array = []
	for k in count:
		var s := float(k) / (count - 1)
		var ahead := (line[mini(k + 1, count - 1)] - line[maxi(k - 1, 0)]).normalized()
		var across := ahead.cross(up).normalized()
		var above := across.cross(ahead).normalized()
		var swell := sin(PI * clampf(s * 0.92 + 0.08, 0.0, 1.0))
		var w := wide * swell * 0.5
		var h := thick * swell * 0.5
		rings.append([line[k] + across * w, line[k] + above * h, line[k] - across * w, line[k] - above * h])
	for k in count - 1:
		var s0 := float(k) / (count - 1)
		var s1 := float(k + 1) / (count - 1)
		for f in 4:
			var a: Vector3 = rings[k][f]
			var b: Vector3 = rings[k][(f + 1) % 4]
			var c: Vector3 = rings[k + 1][f]
			var d: Vector3 = rings[k + 1][(f + 1) % 4]
			var pts: Array[Vector3] = [tilt * a, tilt * c, tilt * b, tilt * b, tilt * c, tilt * d]
			var shades := [s0, s1, s0, s0, s1, s1]
			var normals := []
			var colours := []
			var face: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
			for i in 6:
				var p: Vector3 = pts[i]
				# Bent outward from the trunk, so the crown shades as one shape.
				var round_ := Vector3(p.x, (p.y - top * 0.45) * 0.45 + top * 0.08, p.z).normalized()
				var n: Vector3 = face.lerp(round_, 0.72).normalized()
				normals.append(n)
				var along: float = shades[i]
				var colour := needles_inner.lerp(needles_outer, smoothstep(0.0, 0.7, along)).lerp(tips, smoothstep(0.65, 1.0, along) * 0.8)
				colour = colour.lightened(up_tree * 0.06)
				if snow > 0.0 and n.y > 0.35 and face.y > 0.1:
					colour = colour.lerp(snow_colour, snow * smoothstep(0.35, 0.8, n.y))
				colours.append(colour)
			_tri(st, [pts[0], pts[1], pts[2]], [normals[0], normals[1], normals[2]], [colours[0], colours[1], colours[2]])
			_tri(st, [pts[3], pts[4], pts[5]], [normals[3], normals[4], normals[5]], [colours[3], colours[4], colours[5]])


func _tri(st: SurfaceTool, points: Array, normals: Array, colours: Array) -> void:
	for i in 3:
		st.set_color(colours[i])
		st.set_normal(normals[i])
		st.add_vertex(points[i])
