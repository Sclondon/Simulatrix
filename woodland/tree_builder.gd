extends RefCounted
## Builds one tree's wood (trunk, branches and roots) as a mesh, and says where its leaves go.
## Branches mostly reach towards +X, so a tree turned to face the path leans its crown out over it.
##
## A tree is made from a `shape` Dictionary (all optional):
##   height, radius (at the foot), reach (how far the branches go), lean (radians the trunk leaves
##   the ground tilted, curving back up), twist (turns the bark's ropes make per metre), flute (how
##   deep those ropes are), flare (how much the foot swells), roots (how many snake off over the
##   ground), branches (how many), curl (how much the branches swirl), bare (no leaves), tip (the
##   trunk's top radius, as a share of its foot), lite (fewer sides, no roots: for trees far off).
##
## The mesh has UV.x round the wood (0..1), UV.y up it in metres, and CUSTOM0: r how far out it is,
## g the tree's girth (its foot radius, so bark is drawn the same size on every tree), b how far
## round the bark's ropes have turned there (bark.gdshader).

var st: SurfaceTool
## Where the leaf clumps go: Vector4(x, y, z, size) in the tree's own space.
var crowns: Array[Vector4] = []

var _rng: RandomNumberGenerator
var _girth := 0.3
var _lite := false
var _bare := false


func build(rng: RandomNumberGenerator, shape: Dictionary) -> ArrayMesh:
	_rng = rng
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	crowns.clear()
	var height: float = shape.get("height", 12.0)
	var radius: float = shape.get("radius", 0.35)
	var reach: float = shape.get("reach", 4.0)
	var lean: float = shape.get("lean", 0.0)
	var twist: float = shape.get("twist", 0.0)
	var flute: float = shape.get("flute", 0.06)
	var flare: float = shape.get("flare", 0.5)
	var curl: float = shape.get("curl", 0.3)
	var tip: float = shape.get("tip", 0.18)
	_bare = shape.get("bare", false)
	_lite = shape.get("lite", false)
	_girth = radius
	var sides := 6 if _lite else clampi(int(round(7.0 + radius * 9.0)), 7, 16)

	# The trunk: it leaves the ground tilted `lean` (towards +X, out over the path) and curves back
	# towards the light, with a wander of its own.
	var pts: Array[Vector3] = []
	var radii: Array[float] = []
	var steps := 14
	var dir := Vector3(sin(lean), cos(lean), 0.0).rotated(Vector3.UP, rng.randf_range(-0.4, 0.4))
	var wander := Vector3(rng.randf_range(-1, 1), 0.0, rng.randf_range(-1, 1)) * 0.12
	var p := Vector3.ZERO
	var seg := height / steps
	for i in steps + 1:
		var t := float(i) / steps
		pts.append(p)
		var r := radius * lerpf(1.0, tip, pow(t, 0.75))
		# the foot swells into its roots
		r *= 1.0 + flare * exp(-p.y / maxf(radius * 1.6, 0.3))
		radii.append(r)
		dir = (dir + Vector3.UP * 0.07 * (1.0 + lean * 2.0) + wander * sin(t * 5.0 + radius)).normalized()
		p += dir * seg
	_tube(_thin_v(pts) if _lite else pts, _thin_f(radii) if _lite else radii, 0.0, 0.5, sides, flute, twist, radius)
	if not _bare:
		crowns.append(Vector4(pts[-1].x, pts[-1].y + 0.4, pts[-1].z, 1.6 + reach * 0.15))

	# Branches off the upper trunk, swirling as they go
	var count: int = shape.get("branches", 5)
	for b in count:
		var t := rng.randf_range(0.35, 0.88)
		var at := _along(pts, t)
		var out_angle := rng.randf_range(-1.2, 1.2) if rng.randf() < 0.75 else rng.randf_range(2.0, 4.3)
		var d := Vector3(cos(out_angle), rng.randf_range(0.25, 0.9), sin(out_angle)).normalized()
		var length := reach * rng.randf_range(0.6, 1.0) * lerpf(1.1, 0.6, t)
		if absf(out_angle) > 1.6:
			length *= 0.6
		var br := radius * lerpf(0.6, 0.3, t) * (1.0 + curl * 0.3)
		_branch(at, d, length, br, 0.5 + t * 0.3, curl, 0)

	# Roots: snaking out over the ground from the swollen foot and down into it. Last, so a lite tree
	# (no roots) has the same branches as the full one.
	var root_count: int = shape.get("roots", 0) if not _lite else 0
	var first := rng.randf() * TAU
	for k in root_count:
		var a := first + TAU * k / root_count + rng.randf_range(-0.3, 0.3)
		_root(a, radius, rng.randf_range(2.2, 4.5) * radius + 0.6)
	return st.commit()


# A root from the foot, the `a` way round: out and down, wandering, thinning to nothing
func _root(a: float, radius: float, length: float) -> void:
	var pts: Array[Vector3] = []
	var radii: Array[float] = []
	var steps := 6
	var out := Vector3(cos(a), 0.0, sin(a))
	var p := out * radius * 0.55 + Vector3.UP * radius * _rng.randf_range(0.5, 1.1)
	var thick := radius * _rng.randf_range(0.35, 0.55)
	var bend := _rng.randf_range(-0.6, 0.6)
	for i in steps + 1:
		var t := float(i) / steps
		pts.append(p)
		radii.append(thick * lerpf(1.0, 0.12, pow(t, 0.8)))
		var d := out.rotated(Vector3.UP, bend * sin(t * 3.0 + a))
		# arch down to the ground quickly, then run along it, humping, and dive in
		var y := -0.55 * radius * (1.0 - t) - (0.12 if t > 0.75 else 0.0)
		p += d * length / steps + Vector3.UP * y + Vector3.UP * sin(t * 9.0 + a * 3.0) * 0.04
		p.y = maxf(p.y, -0.25)
	_tube(pts, radii, 0.0, 0.1, 6, 0.0, 0.0, radius)


func _branch(from: Vector3, dir: Vector3, length: float, radius: float, outness: float, curl: float, depth: int) -> void:
	var pts: Array[Vector3] = []
	var radii: Array[float] = []
	var p := from
	var d := dir
	var steps := 4 if depth > 0 else 7
	# swirl: the branch turns about its own sideways axis one way then the other, like an S
	var axis := d.cross(Vector3.UP).normalized() if absf(d.y) < 0.95 else Vector3.RIGHT
	var phase := _rng.randf() * TAU
	for i in steps + 1:
		var t := float(i) / steps
		pts.append(p)
		radii.append(radius * lerpf(1.0, 0.15, t))
		d = d.rotated(axis, curl * 0.5 * sin(t * PI * 2.0 + phase) / steps * 3.0)
		# droop a little under its own weight, and wander
		d = (d + Vector3(_rng.randf_range(-0.2, 0.2), -0.07, _rng.randf_range(-0.2, 0.2))).normalized()
		p += d * length / steps
	# far off, twigs are not drawn and every other ring is left out; close up, nor are twigs too thin to see
	if not (_lite and depth >= 2) and radius > (0.02 if not _lite else 0.05):
		_tube(_thin_v(pts) if _lite else pts, _thin_f(radii) if _lite else radii, outness, 1.0, (5 if _lite else 6) if depth > 0 else (5 if _lite else 7), 0.0, 0.0, _girth)
	if depth < 2 and length > 1.2:
		for k in _rng.randi_range(1, 3 - depth):
			var t := _rng.randf_range(0.35, 0.85)
			var at := _along(pts, t)
			var nd := (dir + Vector3(_rng.randf_range(-0.9, 0.9), _rng.randf_range(0.0, 0.6), _rng.randf_range(-0.9, 0.9))).normalized()
			_branch(at, nd, length * 0.5, radius * 0.45, outness + 0.2, curl, depth + 1)
	if _bare:
		return
	# leaves along the outer half and at the tip
	var clumps := 1 + int(length / 1.6)
	for k in clumps:
		var t := lerpf(0.5, 1.0, float(k + 1) / clumps)
		var c := _along(pts, t)
		crowns.append(Vector4(c.x, c.y + 0.2, c.z, lerpf(0.9, 1.6, _rng.randf()) * (1.0 if depth == 0 else 0.8)))


func _along(pts: Array[Vector3], t: float) -> Vector3:
	var f := t * (pts.size() - 1)
	var i := mini(int(f), pts.size() - 2)
	return pts[i].lerp(pts[i + 1], f - i)


## A tube through `pts`, thinning by `radii`, rings of `sides`. `flute` cuts ropes into it that turn
## `twist` times round per metre (the swirled trunks); `girth` is the tree's, for the bark's scale.
func _tube(pts: Array[Vector3], radii: Array[float], out0: float, out1: float, sides: int, flute: float, twist: float, girth: float) -> void:
	var rings: Array = []
	var v := 0.0
	var side := Vector3.ZERO
	var ropes := float(maxi(3, int(round(girth * 9.0))))
	for i in pts.size():
		var fwd: Vector3
		if i == 0:
			fwd = pts[1] - pts[0]
		elif i == pts.size() - 1:
			fwd = pts[i] - pts[i - 1]
		else:
			fwd = pts[i + 1] - pts[i - 1]
		fwd = fwd.normalized()
		# carry the frame along the tube so it does not flip
		if i == 0:
			side = fwd.cross(Vector3.FORWARD if absf(fwd.z) < 0.9 else Vector3.RIGHT).normalized()
		else:
			side = (side - fwd * side.dot(fwd)).normalized()
		var up := side.cross(fwd).normalized()
		if i > 0:
			v += pts[i].distance_to(pts[i - 1])
		var turn := twist * v
		# a knot or a bulge here and there
		# (from where it is, not the dice, so a lite tree drawn with fewer rings keeps its shape)
		var bulge := 1.0 + (fposmod(sin(pts[i].dot(Vector3(12.9, 78.2, 37.7))) * 43758.5, 1.0) * 0.14 - 0.06) * float(i > 0 and i < pts.size() - 1)
		var ring: Array = []
		for s in sides + 1:
			var a := TAU * s / sides
			var r: float = radii[i] * bulge
			if flute > 0.0:
				# deeper ropes low down, where the trunk runs into its roots
				var deep := flute * (1.0 + 1.5 * exp(-v / maxf(girth * 2.0, 0.4)))
				r *= 1.0 + deep * (pow(0.5 + 0.5 * cos((a + turn * TAU) * ropes), 2.0) - 0.4)
			var radial := side * cos(a) + up * sin(a)
			ring.append([pts[i] + radial * r, Vector2(float(s) / sides, v), radial, turn])
		rings.append(ring)
	for i in rings.size() - 1:
		var o0 := lerpf(out0, out1, float(i) / (rings.size() - 1))
		var o1 := lerpf(out0, out1, float(i + 1) / (rings.size() - 1))
		for s in sides:
			var a: Array = rings[i][s]
			var b: Array = rings[i][s + 1]
			var c: Array = rings[i + 1][s]
			var d: Array = rings[i + 1][s + 1]
			_vert(a, o0); _vert(c, o1); _vert(b, o0)
			_vert(b, o0); _vert(c, o1); _vert(d, o1)


func _vert(rv: Array, outness: float) -> void:
	st.set_custom(0, Color(outness, _girth, rv[3], 0.0))
	st.set_uv(rv[1])
	st.set_normal(rv[2])
	st.add_vertex(rv[0])


# Every other point, keeping both ends: a plainer tube along the same line
func _thin_v(a: Array[Vector3]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in range(0, a.size(), 2):
		out.append(a[i])
	if (a.size() - 1) % 2 != 0:
		out.append(a[-1])
	return out


func _thin_f(a: Array[float]) -> Array[float]:
	var out: Array[float] = []
	for i in range(0, a.size(), 2):
		out.append(a[i])
	if (a.size() - 1) % 2 != 0:
		out.append(a[-1])
	return out
