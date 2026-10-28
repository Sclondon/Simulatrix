@tool
class_name RopeLine
extends Node3D
## One rope, vine, kelp stalk, wire or chain (as its RopeStyle says). It hangs from where this
## node is (or, buoyant, stands up from it, as kelp does from the seabed), or is strung from
## here to `end` with some slack (a wire, a strung vine), or lies free (`pinned` off: a piece
## cut loose, falling to `floor_height`).
##
## It is a real chain: points held a piece apart (Verlet, with XPBD distance constraints so its
## stretch means the same at any number of solver passes), pulled by gravity, dragged towards
## the water or air moving round it (the style's current, surge and travelling gusts, and a
## WindField if `field` is set), stiffened against bending as the style says. Anything in the
## group `rope_pushers` with a `radius` shoves it out of the way (and along with its `velocity`
## if it has one); one with a `heft` below 1 is pushed back in turn and told by `rope_hit`, so
## a ball dropped on a stretchy wire dips it and is thrown back up (Hemlock's Tower's wires).
## Still, with nothing stirring it, it sleeps and costs next to nothing; it wakes when touched.
##
## Drawn by the GPU: a still tube mesh whose vertex shader lays it along the points, and the
## leaves as one MultiMesh whose shader places, droops, streams and flutters each one. The
## CPU only sends the points (25 at most) each step.
##
## After The Clearing's (Warren's) Rope, Vine and VineStrand, Hemlock's Tower's tightrope wires
## and the Dynamic Kelp in Unity article (seasaltcrackers, 2021). Made in The Simulatrix's Rope
## Lab, 2026-10-27.

## Anything in this group with a `radius` (float, m) pushes ropes out of its way. Optional:
## `velocity` (Vector3, m/s) drags the rope along with it; `heft` (0..1, default 1) is how much
## of the overlap the rope gives (1: the pusher does not give at all); `rope_hit(rope, push,
## rope_velocity)` is called with how far the rope pushed it back this step and how fast the
## rope there was going.
const PUSHERS := &"rope_pushers"
const MAX_POINTS := 25
## How stretchy a stretch of 1 is (XPBD compliance per piece, s²/kg with a point weighing 1).
const STRETCHY := 0.00003
## How still it must be (m a step at every point), and for how many steps, before it sleeps.
const STILL := 0.0004
const STILL_STEPS := 40

const TUBE_SHADER := preload("res://rope/rope.gdshader")
const LEAF_SHADER := preload("res://rope/rope_leaf.gdshader")

## Cut by cut(): the new lines made from it (it may be one of them).
signal was_cut(lines: Array)

@export var style: RopeStyle:
	set(v):
		if style and style.changed.is_connected(_on_style):
			style.changed.disconnect(_on_style)
		style = v
		if style and is_inside_tree():
			style.changed.connect(_on_style)
		_on_style()
## m, along it (strung: the whole of it, worked out from the gap and `slack` if left at 0).
@export_range(0.1, 100.0, 0.05) var length := 4.0:
	set(v): length = maxf(v, 0.05); _relay()
## Strung from here to `end` (in this node's space), with `slack` (1 taut, 1.05 a deep sag).
@export var strung := false:
	set(v): strung = v; _relay()
@export var end := Vector3(6, 0, 0):
	set(v): end = v; _relay()
@export_range(1.0, 1.5, 0.001) var slack := 1.02:
	set(v): slack = v; _relay()
## Held where this node is (off: it lies free and falls).
@export var pinned := true
## Nothing goes below this height (world), m.
@export var floor_height := -1000.0
## Picks where its leaves grow (0: from where it is).
@export var seed := 0:
	set(v): seed = v; _restyle_leaves = true
@export var shadows := true:
	set(v):
		shadows = v
		if _tube:
			_tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if v else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## A WindField (GameCommon wind) or anything with sample(point) -> Vector3 (m/s): the air
## or water moving round it, on top of its style's current.
var field: Object

var _p := PackedVector3Array()
var _q := PackedVector3Array()
var _w := PackedFloat32Array()
var _lambda := PackedFloat32Array()
var _piece := 0.25
var _laid := false
var _laying := false
var _sleeping := false
var _still := 0
var _root_was := Vector3.INF
var _end_was := Vector3.INF
var _rest_dir := Vector3.DOWN
var _rest_n := Vector3.RIGHT
var _held := -1
var _held_at := Vector3.ZERO
## [node, distance, offset, weight]
var _attached: Array = []
var _tube: MeshInstance3D
var _leaves: MultiMeshInstance3D
var _tube_mat: ShaderMaterial
var _leaf_mat: ShaderMaterial
var _restyle_leaves := true
var _leaf_count := 0
var _flow := Vector3.ZERO
var _time := 0.0
var _dt := 1.0 / 60.0
# (what the leaves are given: each point's velocity smoothed over a few steps, since a Verlet
# step's own is jittery, and a flutter clock that runs quicker in a stronger flow)
var _leaf_vel := PackedVector3Array()
var _leaf_clock := 0.0
var _bounds := AABB()

static var _noise: FastNoiseLite
static var _tube_meshes := {}
static var _leaf_meshes := {}
static var _pushers: Array = []
static var _pushers_frame := -1


func _ready() -> void:
	if style == null:
		style = RopeStyle.rope()
	elif not style.changed.is_connected(_on_style):
		style.changed.connect(_on_style)
	_tube = MeshInstance3D.new()
	_tube.top_level = true
	_tube_mat = ShaderMaterial.new()
	_tube_mat.shader = TUBE_SHADER
	_tube.material_override = _tube_mat
	_tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_tube, false, Node.INTERNAL_MODE_BACK)
	_tube.global_transform = Transform3D.IDENTITY
	_leaves = MultiMeshInstance3D.new()
	_leaves.top_level = true
	_leaf_mat = ShaderMaterial.new()
	_leaf_mat.shader = LEAF_SHADER
	_leaves.material_override = _leaf_mat
	_leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_leaves, false, Node.INTERNAL_MODE_BACK)
	_leaves.global_transform = Transform3D.IDENTITY
	if not _laid:
		_lay_rest()
	_apply_look()
	_draw()


# --- What a game talks to ------------------------------------------------------

## How many points it is (pieces + 1).
func point_count() -> int:
	return _p.size()


## Its points as they are now (world).
func points() -> PackedVector3Array:
	return _p.duplicate()


## Where it is `distance` m along it from its root.
func point_at(distance: float) -> Vector3:
	if _p.size() < 2:
		return global_position
	var u := clampf(distance / _piece, 0.0, _p.size() - 1.0)
	var i := mini(int(u), _p.size() - 2)
	return _p[i].lerp(_p[i + 1], u - i)


## How fast it is moving there, m/s.
func velocity_at(distance: float) -> Vector3:
	if _p.size() < 2:
		return Vector3.ZERO
	var u := clampf(distance / _piece, 0.0, _p.size() - 1.0)
	var i := mini(int(u), _p.size() - 2)
	var a := (_p[i] - _q[i]) / _dt
	var b := (_p[i + 1] - _q[i + 1]) / _dt
	return a.lerp(b, u - i)


## How far along it (m from its root) the part of it nearest `point` is.
func nearest(point: Vector3) -> float:
	var best := 0.0
	var least := INF
	for i in _p.size() - 1:
		var a := _p[i]
		var ab := _p[i + 1] - a
		var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		var d := (a + ab * t).distance_squared_to(point)
		if d < least:
			least = d
			best = (i + t) * _piece
	return best


## How far `point` is from it, m.
func distance_to(point: Vector3) -> float:
	return point_at(nearest(point)).distance_to(point)


## Its whole length as laid (m).
func rest_length() -> float:
	return _piece * (_p.size() - 1)


## Shoves it `distance` along it, and less so a few points either side: a change of speed, m/s.
func push(distance: float, velocity: Vector3) -> void:
	wake()
	var middle := distance / _piece
	for i in _p.size():
		var share := clampf(1.0 - absf(i - middle) / 3.0, 0.0, 1.0) * minf(_w[i], 1.0)
		_q[i] -= velocity * share * _dt


## Holds the point `distance` along it at `at` (world) until let_go(): a hand on it, a grab.
func hold(distance: float, at: Vector3) -> void:
	wake()
	if _held == -1:
		_held = clampi(roundi(distance / _piece), 0, _p.size() - 1)
	_held_at = at


func let_go() -> void:
	_held = -1
	_set_weights()
	wake()


## Hangs `node` from it `distance` along it (offset from it by `offset`): it goes where that
## point goes, a crow riding a wire's bounce, a vine hung from a strung vine (a RopeLine's top
## goes with it). `weight`: how many points' worth it weighs on the rope.
func attach(node: Node3D, distance: float, offset := Vector3.ZERO, weight := 0.0) -> void:
	_attached.append([node, distance, offset, weight])
	node.global_position = point_at(distance) + offset
	if weight > 0.0:
		wake()


func detach(node: Node3D) -> void:
	_attached = _attached.filter(func(a: Array) -> bool: return a[0] != node)
	wake()


## What hangs from it, as [node, distance, offset, weight].
func attached() -> Array:
	return _attached.duplicate()


## Cuts it `distance` along it. Strung, it falls into two lines hanging from its two ends
## (Warren's strung vine cut); hanging, it keeps the part above the cut and the rest falls free
## (to `floor_height`). Whatever hung from it goes with its part. Returns the new lines (added
## to this one's parent); a strung one frees itself.
func cut(distance: float) -> Array[RopeLine]:
	var whole := rest_length()
	distance = clampf(distance, _piece * 0.5, whole - _piece * 0.5)
	var made: Array[RopeLine] = []
	var parent := get_parent()
	if strung:
		var first := _piece_of(0.0, distance, true)
		var second := _piece_of(whole, distance, true)
		for line: RopeLine in [first, second]:
			parent.add_child(line)
			made.append(line)
		for a: Array in _attached:
			if not is_instance_valid(a[0]):
				continue
			if a[1] < distance:
				first.attach(a[0], a[1], a[2], a[3])
			else:
				second.attach(a[0], whole - a[1], a[2], a[3])
		_attached.clear()
		was_cut.emit(made)
		queue_free()
		return made
	var lower := _piece_of(distance, whole, false)
	parent.add_child(lower)
	made.append(lower)
	var keep: Array = []
	for a: Array in _attached:
		if not is_instance_valid(a[0]):
			continue
		if a[1] <= distance:
			keep.append(a)
		else:
			lower.attach(a[0], a[1] - distance, a[2], a[3])
	_attached = keep
	# (this one keeps the part above the cut, laid where it was)
	var pts := _resample(0.0, distance, style.pieces + 1)
	var before := _resample_prev(0.0, distance, style.pieces + 1)
	_laying = true
	length = distance
	_laying = false
	lay(pts, before)
	was_cut.emit(made)
	return made


## Lays it out along `pts` (world), resampled to its points, moving as it moved from `before`
## if given: for one that is thrown, or made from another. Its `length` stays as it is (set
## that first); laid longer or shorter, it is pulled to its length as it runs.
func lay(pts: PackedVector3Array, before := PackedVector3Array()) -> void:
	var n := (style.pieces if style else 16) + 1
	_p = _resample_poly(pts, n)
	_q = _resample_poly(before, n) if before.size() >= 2 else _p.duplicate()
	_piece = length / (n - 1)
	_finish_lay()
	wake()


## Whether it is asleep (still, costing next to nothing).
func is_sleeping() -> bool:
	return _sleeping


func wake() -> void:
	_sleeping = false
	_still = 0


## Runs it on for `seconds` at once, so it starts settled (kelp leant in its current, a
## wire sagged) rather than settling as the scene opens.
func settle(seconds := 2.0) -> void:
	var steps := int(seconds * 60.0)
	_pushers_frame = -1
	for k in steps:
		_step(1.0 / 60.0)
	_q = _p.duplicate()
	_draw()


# --- Laying it out --------------------------------------------------------------

func _relay() -> void:
	if not _laying and is_inside_tree() and style:
		_lay_rest()
		_draw()


func _on_style() -> void:
	if not is_inside_tree() or style == null or _tube == null:
		return
	if _p.size() != style.pieces + 1:
		if _laid and _p.size() >= 2:
			var pts := _p.duplicate()
			var before := _q.duplicate()
			var keep := length
			_p = _resample_poly(pts, style.pieces + 1)
			_q = _resample_poly(before, style.pieces + 1)
			_piece = keep / style.pieces
			_finish_lay()
		else:
			_lay_rest()
	_apply_look()
	wake()
	_draw()


## Hanging straight down (up if buoyant), or strung from here to `end` in a sag.
func _lay_rest() -> void:
	if style == null:
		return
	var n := style.pieces + 1
	var root := global_position if is_inside_tree() else position
	_p.resize(n)
	if strung:
		var tail := to_global(end) if is_inside_tree() else position + end
		var gap := root.distance_to(tail)
		_laying = true
		length = gap * slack
		_laying = false
		var extra := maxf(length - gap, 0.0)
		# (a shallow curve sags by about sqrt(3/8 gap extra))
		var sag := sqrt(3.0 / 8.0 * gap * extra)
		for i in n:
			var t := float(i) / (n - 1)
			_p[i] = root.lerp(tail, t) + Vector3.DOWN * 4.0 * t * (1.0 - t) * sag
	else:
		var way := Vector3.UP if style.gravity < 0.0 else Vector3.DOWN
		for i in n:
			_p[i] = root + way * length * float(i) / (n - 1)
	_piece = length / (n - 1)
	_q = _p.duplicate()
	_finish_lay()


func _finish_lay() -> void:
	_laid = true
	var n := _p.size()
	_lambda.resize(n)
	_set_weights()
	_rest_dir = (_p[1] - _p[0]).normalized() if _p.size() > 1 and _p[0].distance_squared_to(_p[1]) > 1e-10 else Vector3.DOWN
	var side := _rest_dir.cross(Vector3.UP)
	if side.length_squared() < 0.01:
		side = _rest_dir.cross(Vector3.BACK)
	_rest_n = side.normalized()
	_root_was = _p[0]
	_end_was = _p[n - 1]
	_restyle_leaves = true
	_still = 0
	_sleeping = false


func _set_weights() -> void:
	var n := _p.size()
	_w.resize(n)
	_w.fill(1.0)
	if pinned and n > 0:
		_w[0] = 0.0
	if strung and n > 0:
		_w[n - 1] = 0.0


## A new line of this one from `start` to `to` m along it (backwards from the far end if `to`
## is less), held where that part starts if `held`.
func _piece_of(start: float, to: float, held: bool) -> RopeLine:
	var line := RopeLine.new()
	line.style = style
	line.field = field
	line.floor_height = floor_height
	line.shadows = shadows
	line.seed = seed + int(start * 100.0) + 1
	line.pinned = held
	var pts := _resample(start, to, style.pieces + 1)
	var before := _resample_prev(start, to, style.pieces + 1)
	line.position = pts[0]
	line.length = absf(to - start)
	line.lay(pts, before)
	return line


## Points from `from` to `to` m along it, as it lies now (fractions of its laid length).
func _resample(from: float, to: float, n: int) -> PackedVector3Array:
	return _sample_span(_p, from, to, n)


func _resample_prev(from: float, to: float, n: int) -> PackedVector3Array:
	return _sample_span(_q, from, to, n)


func _sample_span(poly: PackedVector3Array, from: float, to: float, n: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var whole := maxf(rest_length(), 0.0001)
	for k in n:
		var d := lerpf(from, to, float(k) / (n - 1)) / whole * (poly.size() - 1)
		var i := clampi(int(d), 0, poly.size() - 2)
		out.append(poly[i].lerp(poly[i + 1], clampf(d - i, 0.0, 1.0)))
	return out


## `poly` resampled to `n` points evenly along it.
static func _resample_poly(poly: PackedVector3Array, n: int) -> PackedVector3Array:
	if poly.size() == n:
		return poly.duplicate()
	var acc := PackedFloat32Array([0.0])
	for i in poly.size() - 1:
		acc.append(acc[i] + poly[i].distance_to(poly[i + 1]))
	var total := maxf(acc[acc.size() - 1], 0.0001)
	var out := PackedVector3Array()
	var j := 0
	for k in n:
		var d := total * float(k) / (n - 1)
		while j < poly.size() - 2 and acc[j + 1] < d:
			j += 1
		var span := maxf(acc[j + 1] - acc[j], 0.000001)
		out.append(poly[j].lerp(poly[j + 1], clampf((d - acc[j]) / span, 0.0, 1.0)))
	return out


# --- Running ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or style == null or _p.size() < 2:
		return
	_step(delta)
	_carry()
	if not _sleeping:
		_settle_leaf_motion(delta)
		_draw()


func _step(delta: float) -> void:
	_dt = delta
	_time += delta
	var n := _p.size()
	var root := global_position
	var tail := to_global(end)
	var moved := pinned and root.distance_squared_to(_root_was) > 1e-10
	if strung and tail.distance_squared_to(_end_was) > 1e-10:
		moved = true
	_root_was = root
	_end_was = tail
	_bounds = _aabb()
	var near := _near_pushers()
	var weighed := false
	for a: Array in _attached:
		if a[3] > 0.0:
			weighed = true
	if _sleeping:
		if moved or not near.is_empty() or _held >= 0 or style.restless() or field != null:
			wake()
		else:
			return
	var p := _p
	var q := _q
	var w := _w
	# The water or air round it: the style's current, surge and gusts (3D noise rolling along
	# the current), and the wind field, at its root, middle and tip.
	var mid := n / 2
	var f0 := _flow_at(p[0])
	var f1 := _flow_at(p[mid])
	var f2 := _flow_at(p[n - 1])
	_flow = f1
	var g := Vector3.DOWN * style.gravity
	var take := 1.0 - exp(-style.drag * delta)
	var extra := {}
	if weighed:
		for a: Array in _attached:
			if a[3] > 0.0:
				var i := clampi(roundi(a[1] / _piece), 1, n - 1)
				extra[i] = extra.get(i, 0.0) + a[3]
	for i in n:
		if w[i] == 0.0:
			continue
		var at := p[i]
		var v := (at - q[i]) / delta
		var s := float(i) / mid if i <= mid else float(i - mid) / maxf(n - 1 - mid, 1)
		var f := f0.lerp(f1, s) if i <= mid else f1.lerp(f2, s)
		v += (f - v) * take + g * delta
		if extra.has(i):
			v += Vector3.DOWN * absf(style.gravity) * extra[i] * delta
		q[i] = at
		p[i] = at + v * delta
	if pinned:
		q[0] = p[0]
		p[0] = root
	if strung:
		q[n - 1] = p[n - 1]
		p[n - 1] = tail
	if _held >= 0:
		w[_held] = 0.0
	# Held to its length (XPBD: compliance from its stretch), stiffened against bending,
	# pushed out of the way of whatever is pushing it.
	var compliance := style.stretch * style.stretch * STRETCHY / (delta * delta)
	var lam := _lambda
	lam.fill(0.0)
	var piece := _piece
	var bend := style.bend * 0.5
	var pushers: Array = []
	for node: Node3D in near:
		var r: float = node.get(&"radius")
		var heft: float = node.get(&"heft") if &"heft" in node else 1.0
		pushers.append([node, node.global_position, r, clampf(heft, 0.0, 1.0), node.global_position])
	for it in style.iterations:
		if _held >= 0:
			p[_held] = _held_at
		for i in n - 1:
			var wa := w[i]
			var wb := w[i + 1]
			var ws := wa + wb
			if ws == 0.0:
				continue
			var d := p[i + 1] - p[i]
			var l := d.length()
			if l < 1e-9:
				continue
			var dl := (piece - l - compliance * lam[i]) / (ws + compliance)
			lam[i] += dl
			var corr := d * (dl / l)
			p[i] -= corr * wa
			p[i + 1] += corr * wb
		if bend > 0.0 and it == 0:
			for i in n - 2:
				var wa := w[i]
				var wb := w[i + 2]
				var ws := wa + wb + w[i + 1] * 0.5
				if ws == 0.0:
					continue
				# (the middle point pulled to between its neighbours)
				var middle := (p[i] + p[i + 2]) * 0.5
				var off := (p[i + 1] - middle) * bend
				p[i + 1] -= off * w[i + 1]
				p[i] += off * 0.5 * wa
				p[i + 2] += off * 0.5 * wb
		for push: Array in pushers:
			_push_out(p, w, push)
	for i in n:
		if p[i].y < floor_height:
			# (landing hard, a little nudge aside, so a rope falling straight down buckles and
			# coils rather than standing on its own heap)
			if q[i].y - p[i].y > 0.004:
				p[i].x += sin(i * 12.99 + _time * 7.0) * 0.004
				p[i].z += cos(i * 78.23 + _time * 5.0) * 0.004
			p[i].y = floor_height
			# (friction on the ground)
			q[i].x = lerpf(q[i].x, p[i].x, 0.3)
			q[i].z = lerpf(q[i].z, p[i].z, 0.3)
			q[i].y = minf(q[i].y, floor_height)
	# Dragged along with what pushed it; and whoever was pushed back is told.
	for push: Array in pushers:
		var node: Node3D = push[0]
		if &"velocity" in node:
			var vel: Vector3 = node.get(&"velocity")
			var r2: float = push[2] * push[2] * 1.44
			for i in n:
				if w[i] > 0.0 and p[i].distance_squared_to(push[1]) < r2:
					q[i] = q[i].lerp(p[i] - vel * delta, 0.35)
		var moved_by: Vector3 = push[4] - push[1]
		if moved_by.length_squared() > 1e-12 and node.has_method(&"rope_hit"):
			var at := nearest(push[4])
			node.call(&"rope_hit", self, moved_by, velocity_at(at))
	if _held >= 0:
		p[_held] = _held_at
		_set_weights()
		w = _w
	_p = p
	_q = q
	# Asleep once it has been still a while, with nothing stirring it.
	var most := 0.0
	for i in n:
		most = maxf(most, p[i].distance_squared_to(q[i]))
	if most < STILL * STILL and near.is_empty() and _held < 0 and not style.restless() and field == null:
		_still += 1
		if _still > STILL_STEPS:
			_sleeping = true
			_q = _p.duplicate()
	else:
		_still = 0


## Pushes the chain out of a sphere: [node, centre, radius, heft, centre as pushed back].
func _push_out(p: PackedVector3Array, w: PackedFloat32Array, push: Array) -> void:
	var c: Vector3 = push[4]
	var r: float = push[2]
	var heft: float = push[3]
	var r2 := r * r
	for i in p.size() - 1:
		var a := p[i]
		var ab := p[i + 1] - a
		var t := clampf((c - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		var at := a + ab * t
		var d2 := at.distance_squared_to(c)
		if d2 >= r2:
			continue
		var d := sqrt(d2)
		var out := (at - c) / d if d > 1e-5 else Vector3.UP
		var deep := r - d
		var wa := w[i] * (1.0 - t)
		var wb := w[i + 1] * t
		var sum := wa * (1.0 - t) + wb * t
		var gives := heft
		if sum <= 1e-5:
			gives = 0.0
		else:
			var k := deep * gives / sum
			p[i] += out * k * wa
			p[i + 1] += out * k * wb
		# (what the rope did not give, the pusher does)
		c -= out * deep * (1.0 - gives)
	push[4] = c


## The water or air's velocity at `at`, m/s.
func _flow_at(at: Vector3) -> Vector3:
	var f := Vector3.ZERO
	if style.restless():
		var dir := style.current_dir()
		var along := style.current
		if style.surge > 0.0:
			along += style.surge * sin(_now() * TAU / style.surge_period - at.dot(dir) * 0.35)
		f = dir * along
		if style.gusts > 0.0:
			if _noise == null:
				_noise = FastNoiseLite.new()
				_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
				_noise.frequency = 1.0
			var drift := dir * _now() * style.gust_speed
			var s := (at - drift) / style.gust_size
			var across := Vector3(-dir.z, 0.0, dir.x)
			f += dir * style.gusts * _noise.get_noise_3d(s.x, s.y * 0.6, s.z)
			f += across * style.gusts * 0.6 * _noise.get_noise_3d(s.x + 31.0, s.y * 0.6, s.z - 17.0)
	if field != null and field.has_method(&"sample"):
		f += (field.call(&"sample", at) as Vector3) * style.wind_response
	return f


## Seconds, the same for every rope (so gusts and surge line up across a forest).
static func _now() -> float:
	return Time.get_ticks_msec() * 0.001


func _near_pushers() -> Array:
	var frame := Engine.get_physics_frames()
	if frame != _pushers_frame:
		_pushers_frame = frame
		_pushers = get_tree().get_nodes_in_group(PUSHERS)
	var out: Array = []
	for node: Variant in _pushers:
		if not is_instance_valid(node):
			continue
		var body := node as Node3D
		if body == null or not &"radius" in body:
			continue
		var r: float = body.get(&"radius")
		if _bounds.grow(r).has_point(body.global_position):
			out.append(body)
	return out


func _aabb() -> AABB:
	var lo := _p[0]
	var hi := _p[0]
	for i in range(1, _p.size()):
		lo = lo.min(_p[i])
		hi = hi.max(_p[i])
	return AABB(lo, hi - lo)


func _carry() -> void:
	if _attached.is_empty():
		return
	for a: Array in _attached:
		var node: Node3D = a[0]
		if is_instance_valid(node):
			node.global_position = point_at(a[1]) + a[2]
	_attached = _attached.filter(func(a: Array) -> bool: return is_instance_valid(a[0]))


# --- Drawing ---------------------------------------------------------------------

func _apply_look() -> void:
	if _tube_mat == null or style == null:
		return
	var s := style
	_tube.mesh = _tube_mesh(s.pieces * 3, s.sides)
	for m: ShaderMaterial in [_tube_mat, _leaf_mat]:
		m.set_shader_parameter(&"r_root", s.thickness_root)
		m.set_shader_parameter(&"r_tip", s.thickness_tip)
		m.set_shader_parameter(&"taper", s.taper)
		m.set_shader_parameter(&"shine", s.shine)
	_tube_mat.set_shader_parameter(&"colour_root", s.colour_root)
	_tube_mat.set_shader_parameter(&"colour_tip", s.colour_tip)
	_tube_mat.set_shader_parameter(&"twist", s.twist)
	_tube_mat.set_shader_parameter(&"beads", s.beads)
	_tube_mat.set_shader_parameter(&"knot", s.knot if not strung else 0.0)
	_leaf_mat.set_shader_parameter(&"colour_root", s.leaf_colour_root)
	_leaf_mat.set_shader_parameter(&"colour_tip", s.leaf_colour_tip)
	_leaf_mat.set_shader_parameter(&"size", s.leaf_size)
	_leaf_mat.set_shader_parameter(&"lean", deg_to_rad(s.leaf_lean))
	_leaf_mat.set_shader_parameter(&"droop", s.leaf_droop)
	_leaf_mat.set_shader_parameter(&"stream", s.leaf_stream)
	_leaf_mat.set_shader_parameter(&"flutter", s.leaf_flutter)
	_leaf_mat.set_shader_parameter(&"curl", s.leaf_curl)
	_leaf_mat.set_shader_parameter(&"ruffle", s.leaf_ruffle)
	_leaf_mat.set_shader_parameter(&"vary", s.leaf_vary)
	_leaf_mat.set_shader_parameter(&"fall_dir", Vector3.UP if s.gravity < 0.0 else Vector3.DOWN)
	_restyle_leaves = true


func _build_leaves() -> void:
	_restyle_leaves = false
	var s := style
	var count := 0
	if s.leaf_kind != RopeStyle.Leaf.NONE:
		count = mini(roundi(rest_length() * s.leaves_per_metre * maxf(s.leaf_to - s.leaf_from, 0.0)), 600)
	var bunch := roundi(count * s.leaf_bunch) if count > 0 else 0
	if count + bunch == 0:
		_leaves.visible = false
		_leaf_count = 0
		return
	_leaves.visible = true
	var rng := RandomNumberGenerator.new()
	rng.seed = seed if seed != 0 else hash(global_position.snappedf(0.01))
	var mm := _leaves.multimesh
	if mm == null:
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		_leaves.multimesh = mm
	mm.instance_count = 0
	mm.mesh = _leaf_mesh(s.leaf_kind)
	mm.instance_count = count + bunch
	var golden := 0.381966
	for k in count:
		var t := lerpf(s.leaf_from, s.leaf_to, (k + rng.randf()) / count)
		var around := fposmod(k * golden + rng.randf_range(-0.08, 0.08), 1.0)
		mm.set_instance_transform(k, Transform3D.IDENTITY)
		mm.set_instance_custom_data(k, Color(t, around, rng.randf_range(0.7, 1.2), rng.randf()))
	# (bunched thick round the root, where it is held)
	var reach := minf(0.8 / maxf(rest_length(), 0.1), 0.3)
	for k in bunch:
		var t := pow(rng.randf(), 1.6) * reach
		mm.set_instance_transform(count + k, Transform3D.IDENTITY)
		mm.set_instance_custom_data(count + k, Color(t, rng.randf(), rng.randf_range(0.6, 1.05), rng.randf()))
	_leaf_count = count + bunch


## How many leaves it has.
func leaf_count() -> int:
	return _leaf_count


func _draw() -> void:
	if _tube == null or _p.size() < 2:
		return
	if _restyle_leaves:
		_build_leaves()
	var n := _p.size()
	var pts := _p.duplicate()
	pts.resize(MAX_POINTS)
	# A frame carried along it (each normal turned the least way onto the next tangent),
	# starting from the root's rest frame turned to where the root points now, so leaves keep
	# their places round it as it swings.
	var nrm := PackedVector3Array()
	nrm.resize(MAX_POINTS)
	var t0 := (_p[1] - _p[0])
	t0 = t0.normalized() if t0.length_squared() > 1e-12 else _rest_dir
	var n0 := _rest_n
	if t0.dot(_rest_dir) > -0.999:
		n0 = Quaternion(_rest_dir, t0) * _rest_n
	var prev := n0
	for i in n:
		var tg := _p[mini(i + 1, n - 1)] - _p[maxi(i - 1, 0)]
		tg = tg.normalized() if tg.length_squared() > 1e-12 else t0
		var nn := prev - tg * prev.dot(tg)
		nn = nn.normalized() if nn.length_squared() > 1e-8 else prev
		nrm[i] = nn
		prev = nn
	_tube_mat.set_shader_parameter(&"pts", pts)
	_tube_mat.set_shader_parameter(&"nrm", nrm)
	_tube_mat.set_shader_parameter(&"count", n)
	_tube_mat.set_shader_parameter(&"rope_length", rest_length())
	_bounds = _aabb()
	var r := maxf(style.thickness_root, style.thickness_tip) * (2.5 + style.knot * 2.0)
	_tube.custom_aabb = _bounds.grow(r + 0.05)
	if _leaves.visible:
		if _leaf_vel.size() != MAX_POINTS:
			_leaf_vel.resize(MAX_POINTS)
		_leaf_mat.set_shader_parameter(&"pts", pts)
		_leaf_mat.set_shader_parameter(&"nrm", nrm)
		_leaf_mat.set_shader_parameter(&"vel", _leaf_vel)
		_leaf_mat.set_shader_parameter(&"clock", _leaf_clock)
		_leaf_mat.set_shader_parameter(&"count", n)
		_leaf_mat.set_shader_parameter(&"rope_length", rest_length())
		_leaf_mat.set_shader_parameter(&"flow", _flow)
		_leaves.custom_aabb = _bounds.grow(style.leaf_size * 1.6 + r)


func _settle_leaf_motion(delta: float) -> void:
	if _leaf_vel.size() != MAX_POINTS:
		_leaf_vel.resize(MAX_POINTS)
	var k := 1.0 - exp(-10.0 * delta)
	var rel := 0.0
	var n := _p.size()
	for i in n:
		_leaf_vel[i] = _leaf_vel[i].lerp((_p[i] - _q[i]) / maxf(_dt, 1e-4), k)
		rel += (_flow - _leaf_vel[i]).length()
	_leaf_clock += delta * (0.6 + minf(rel / maxi(n, 1), 2.0))


## A tube of `rings` rings of `sides` sides with an end cap at each end, along UV.x (0..1)
## and round UV.y (0..1); UV2.x is 0 at a cap's centre. Shared by every rope like it.
static func _tube_mesh(rings: int, sides: int) -> ArrayMesh:
	var key := Vector2i(rings, sides)
	if _tube_meshes.has(key):
		return _tube_meshes[key]
	var verts := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for r in rings + 1:
		for s in sides + 1:
			verts.append(Vector3.ZERO)
			uv.append(Vector2(float(r) / rings, float(s) / sides))
			uv2.append(Vector2(1, 0))
	var row := sides + 1
	for r in rings:
		for s in sides:
			var a := r * row + s
			var b := a + 1
			var c := a + row
			var d := c + 1
			idx.append_array([a, c, b, b, c, d])
	for at_end: int in [0, 1]:
		var centre := verts.size()
		verts.append(Vector3.ZERO)
		uv.append(Vector2(at_end, 0))
		uv2.append(Vector2(0, 0))
		var ring := at_end * rings * row
		for s in sides:
			if at_end == 0:
				idx.append_array([centre, ring + s, ring + s + 1])
			else:
				idx.append_array([centre, ring + s + 1, ring + s])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_tube_meshes[key] = mesh
	return mesh


## A leaf one unit long along +Y, its face to +Z, its shading in UV.x (multiplying its colour).
static func _leaf_mesh(kind: int) -> ArrayMesh:
	if _leaf_meshes.has(kind):
		return _leaf_meshes[kind]
	var mesh: ArrayMesh
	match kind:
		RopeStyle.Leaf.KELP:
			mesh = _kelp_blade()
		RopeStyle.Leaf.BLADE:
			mesh = _grass_blade()
		_:
			mesh = _vine_leaf()
	_leaf_meshes[kind] = mesh
	return mesh


## Warren's vine leaf (The Clearing's Vine.leaf_mesh): a short stalk, then a pointed oval
## blade widest a third of the way along, folded a little along its midrib, its tip curling
## back; paler down the midrib. Ten triangles.
static func _vine_leaf() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stalk := 0.2
	var blade := 0.8
	var stations := [0.0, 0.3, 0.64, 1.0]
	var widths := [0.0, 0.31, 0.25, 0.0]
	var mid: Array[Vector3] = []
	var left: Array[Vector3] = []
	var right: Array[Vector3] = []
	for k in stations.size():
		var t: float = stations[k]
		var w: float = widths[k] * blade
		var z := -0.12 * blade * t * t
		mid.append(Vector3(0.0, stalk + blade * t, z))
		left.append(Vector3(-w, stalk + blade * t, z + w * 0.3))
		right.append(Vector3(w, stalk + blade * t, z + w * 0.3))
	var pale := 1.15
	var edge := 0.82
	var foot := 1.1
	var s := 0.022
	for v: Array in [[Vector3(-s, 0, 0), foot], [Vector3(s, 0, 0), foot], [Vector3(s, stalk + blade * 0.05, 0), pale],
			[Vector3(-s, 0, 0), foot], [Vector3(s, stalk + blade * 0.05, 0), pale], [Vector3(-s, stalk + blade * 0.05, 0), pale]]:
		tool.set_uv(Vector2(v[1], 0))
		tool.add_vertex(v[0])
	for k in stations.size() - 1:
		for side: Array in [left, right]:
			var a: Vector3 = mid[k]
			var b: Vector3 = mid[k + 1]
			var c: Vector3 = side[k + 1]
			var d: Vector3 = side[k]
			var flip: bool = side == right
			if k < stations.size() - 2:
				for v: Vector3 in ([a, b, c] if not flip else [a, c, b]):
					tool.set_uv(Vector2(pale if v == a or v == b else edge, 0))
					tool.add_vertex(v)
			if k > 0:
				for v: Vector3 in ([a, c, d] if not flip else [a, d, c]):
					tool.set_uv(Vector2(pale if v == a else edge, 0))
					tool.add_vertex(v)
	tool.generate_normals()
	return tool.commit()


## A giant kelp blade: a gas bladder at its foot, then a long strap widest past its middle,
## edges a little darker, in rows so it can curve and ripple.
static func _kelp_blade() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 9
	var mid_col := 1.1
	var edge_col := 0.75
	var prev: Array = []
	for r in rows + 1:
		var y := 0.08 + 0.92 * float(r) / rows
		var u := float(r) / rows
		var w := 0.11 * pow(sin(PI * minf(u * 0.92 + 0.06, 1.0)), 0.65) + 0.012
		if r == rows:
			w = 0.0
		var row := [Vector3(-w, y, w * 0.25), Vector3(0, y, 0), Vector3(w, y, w * 0.25)]
		if r > 0:
			for side in 2:
				var a: Vector3 = prev[side]
				var b: Vector3 = prev[side + 1]
				var c: Vector3 = row[side]
				var d: Vector3 = row[side + 1]
				for v: Vector3 in [a, c, b, b, c, d]:
					tool.set_uv(Vector2(mid_col if is_zero_approx(v.x) else edge_col, 0))
					tool.add_vertex(v)
		prev = row
	# (the gas bladder: a little spindle at its foot, on a short stalk)
	var bulb := 0.035
	var top := Vector3(0, 0.1, 0)
	var bottom := Vector3(0, 0.0, 0)
	var ring: Array[Vector3] = []
	for k in 4:
		var a := k * TAU / 4.0
		ring.append(Vector3(cos(a) * bulb, 0.045, sin(a) * bulb))
	var gold := 1.4
	for k in 4:
		var a := ring[k]
		var b := ring[(k + 1) % 4]
		for v: Vector3 in [bottom, a, b, a, top, b]:
			tool.set_uv(Vector2(gold, 0))
			tool.add_vertex(v)
	tool.generate_normals()
	return tool.commit()


## A grass-like blade: narrow, running to a point, folded a little along its middle.
static func _grass_blade() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := 6
	var prev: Array = []
	for r in rows + 1:
		var u := float(r) / rows
		var w := 0.045 * (1.0 - u * u)
		var row := [Vector3(-w, u, w * 0.4), Vector3(0, u, 0), Vector3(w, u, w * 0.4)]
		if r > 0:
			for side in 2:
				var a: Vector3 = prev[side]
				var b: Vector3 = prev[side + 1]
				var c: Vector3 = row[side]
				var d: Vector3 = row[side + 1]
				for v: Vector3 in [a, c, b, b, c, d]:
					tool.set_uv(Vector2(1.05 if is_zero_approx(v.x) else 0.85, 0))
					tool.add_vertex(v)
		prev = row
	tool.generate_normals()
	return tool.commit()
