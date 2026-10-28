@tool
class_name RopePatch
extends Node3D
## Many RopeLines at once, scattered by a seed, for a game to drop in:
##   GROUND  rooted over an area round this node (`size`, x by z): a kelp forest from the
##           seabed, a reed bed, weeds; buoyant styles stand up, others hang down from it (a
##           ceiling of roots, if you turn it over).
##   BEAM    hanging along a line from here to `to`: a curtain of vines from a beam or a ledge,
##           ropes from a rafter.
##   SPAN    strung from here to `to`, `count` of them side by side `spread` apart: telegraph
##           wires, tightropes, strung vines; with telegraph poles (Hemlock's Tower's: a crossbar
##           and glass insulators) at either or both ends if `posts` says.
## All share one RopeStyle, so changing it changes them all. Build again with build() after
## changing the layout (the style's changes show at once).

enum Mode { GROUND, BEAM, SPAN }
enum Posts { NONE, BOTH, START, END }

@export var style: RopeStyle:
	set(v):
		style = v
		for line in lines:
			if is_instance_valid(line):
				line.style = v
@export var mode := Mode.GROUND
@export_range(1, 200, 1) var count := 20
@export var seed := 1
## GROUND: the area, m (x by z), centred here.
@export var size := Vector2(10, 10)
## BEAM and SPAN: the far end, in this node's space.
@export var to := Vector3(8, 0, 0)
## How long each is, m, between these (SPAN works its length out from the gap and `slack`).
@export var length_min := 3.0
@export var length_max := 5.0
## SPAN: how far apart side by side, m. BEAM: how far off the line each may hang.
@export var spread := 0.5
## SPAN: how much longer than the gap (1 taut).
@export_range(1.0, 1.5, 0.001) var slack := 1.01
## SPAN: telegraph poles under the ends, and how far down they go to the ground, m.
@export var posts := Posts.NONE
@export var post_height := 6.0
## Passed to every line: nothing goes below this height (world).
@export var floor_height := -1000.0
@export var shadows := true

## A WindField (or anything with sample(point)) for every line.
var field: Object:
	set(v):
		field = v
		for line in lines:
			if is_instance_valid(line):
				line.field = v

var lines: Array[RopeLine] = []
var _posts: MeshInstance3D


func _ready() -> void:
	if style == null:
		style = RopeStyle.kelp() if mode == Mode.GROUND else RopeStyle.vine()
	build()


## Makes the lines (and posts) afresh from the settings.
func build() -> void:
	for line in lines:
		if is_instance_valid(line):
			line.queue_free()
	lines.clear()
	if _posts:
		_posts.queue_free()
		_posts = null
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	match mode:
		Mode.GROUND:
			# (in a jittered grid, so they spread evenly without rows)
			var cols := maxi(1, roundi(sqrt(count * size.x / maxf(size.y, 0.01))))
			var rows := maxi(1, ceili(float(count) / cols))
			var cells: Array = []
			for r in rows:
				for c in cols:
					cells.append(Vector2i(c, r))
			cells.shuffle()
			for k in count:
				var cell: Vector2i = cells[k % cells.size()]
				var x := (cell.x + rng.randf_range(0.1, 0.9)) / cols - 0.5
				var z := (cell.y + rng.randf_range(0.1, 0.9)) / rows - 0.5
				_add(Vector3(x * size.x, 0.0, z * size.y), rng.randf_range(length_min, length_max), rng)
		Mode.BEAM:
			var across := _across()
			for k in count:
				var t := (k + rng.randf_range(0.15, 0.85)) / count
				var at := Vector3.ZERO.lerp(to, t) + across * rng.randf_range(-spread, spread)
				_add(at, rng.randf_range(length_min, length_max), rng)
		Mode.SPAN:
			var across := _across()
			for k in count:
				var off := across * (k - (count - 1) * 0.5) * spread
				_add(off, 1.0, rng)
			if posts != Posts.NONE:
				_build_posts()


func _add(at: Vector3, long: float, rng: RandomNumberGenerator) -> RopeLine:
	var line := RopeLine.new()
	line.style = style
	line.length = long
	line.position = at
	line.seed = rng.randi() | 1
	line.floor_height = floor_height
	line.shadows = shadows
	line.field = field
	if mode == Mode.SPAN:
		line.strung = true
		line.end = to
		line.slack = slack * (1.0 + rng.randf_range(-0.002, 0.002))
	add_child(line)
	lines.append(line)
	return line


## Level, at right angles to the line from here to `to`.
func _across() -> Vector3:
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length_squared() < 0.0001:
		return Vector3.RIGHT
	return flat.normalized().cross(Vector3.UP)


## Runs every line on for `seconds` at once, so the patch starts settled.
func settle(seconds := 2.0) -> void:
	for line in lines:
		line.settle(seconds)


## How many leaves the whole patch has.
func leaf_count() -> int:
	var n := 0
	for line in lines:
		n += line.leaf_count()
	return n


## Telegraph poles (after Hemlock's Tower's): a pole down to the ground, a crossbar the wires
## sit on, and a glass insulator under each wire.
func _build_posts() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := Color(0.36, 0.27, 0.18)
	var glass := Color(0.45, 0.7, 0.65)
	var across := _across()
	var half := (count - 1) * 0.5 * spread + 0.35
	var ends: Array[Vector3] = []
	if posts == Posts.BOTH or posts == Posts.START:
		ends.append(Vector3.ZERO)
	if posts == Posts.BOTH or posts == Posts.END:
		ends.append(to)
	for e in ends:
		var foot := e + Vector3.DOWN * post_height
		_beam(st, foot, e + Vector3.UP * 0.55, 0.11, wood.darkened(0.15))
		_beam(st, e + Vector3.DOWN * 0.12 - across * half, e + Vector3.DOWN * 0.12 + across * half, 0.06, wood)
		for k in count:
			var at := e + across * (k - (count - 1) * 0.5) * spread
			_beam(st, at + Vector3.DOWN * 0.06, at + Vector3.DOWN * 0.005, 0.045, glass)
	st.generate_normals()
	_posts = MeshInstance3D.new()
	_posts.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_posts.material_override = m
	add_child(_posts, false, Node.INTERNAL_MODE_BACK)


## A square beam from `a` to `b`, `half` thick each way.
static func _beam(st: SurfaceTool, a: Vector3, b: Vector3, half: float, colour: Color) -> void:
	var along := (b - a).normalized()
	var x := along.cross(Vector3.UP if absf(along.y) < 0.9 else Vector3.RIGHT).normalized() * half
	var y := along.cross(x).normalized() * half
	var corners := [x + y, -x + y, -x - y, x - y]
	st.set_color(colour)
	for k in 4:
		var c0: Vector3 = corners[k]
		var c1: Vector3 = corners[(k + 1) % 4]
		for v: Vector3 in [a + c0, b + c0, b + c1, a + c0, b + c1, a + c1]:
			st.add_vertex(v)
	for cap: Array in [[a, false], [b, true]]:
		var o: Vector3 = cap[0]
		var tri := [o + corners[0], o + corners[1], o + corners[2], o + corners[0], o + corners[2], o + corners[3]]
		if cap[1]:
			tri.reverse()
		for v: Vector3 in tri:
			st.add_vertex(v)
