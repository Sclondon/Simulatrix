extends MultiMeshInstance3D
## Things the wind carries, one MultiMesh: leaves that tear off the trees in gusts, tumble
## downwind, settle on the ground and are lifted again by a strong gust or a blast; or seeds
## (thistledown) that drift light and high. Each asks the shared wind field for the air where
## it is and is dragged towards it.

enum Kind { LEAF, SEED }

const HANGING := 0
const FLYING := 1
const RESTING := 2

var field: RefCounted
var kind := Kind.LEAF
var count := 220
## Where leaves hang: crowns as (centre, radius).
var crowns: Array = []
var bounds := 36.0
var amount := 1.0 # share of the pool in use, 0..1

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _state := PackedByteArray()
var _timer := PackedFloat32Array()
var _yaw := PackedFloat32Array()
var _axis: Array[Vector3] = []
var _spin := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _frame := 0


func _ready() -> void:
	_rng.seed = 7 if kind == Kind.LEAF else 11
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _leaf_mesh() if kind == Kind.LEAF else _seed_mesh()
	mm.instance_count = count
	multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.9
	if kind == Kind.SEED:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material_override = mat
	custom_aabb = AABB(Vector3(-60, -2, -60), Vector3(120, 50, 120))
	var leaf_tints := [Color(0.85, 0.42, 0.1), Color(0.93, 0.66, 0.16), Color(0.7, 0.22, 0.1), Color(0.55, 0.6, 0.18), Color(0.95, 0.8, 0.35)]
	for i in count:
		_pos.append(Vector3.ZERO)
		_vel.append(Vector3.ZERO)
		_state.append(HANGING)
		_timer.append(0.0)
		_yaw.append(_rng.randf() * TAU)
		_axis.append(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized())
		_spin.append(_rng.randf_range(2.0, 7.0) * (1.0 if _rng.randf() < 0.5 else -1.0))
		var tint: Color = leaf_tints[_rng.randi() % leaf_tints.size()] if kind == Kind.LEAF else Color(1, 1, 1)
		mm.set_instance_color(i, tint * _rng.randf_range(0.8, 1.1) if kind == Kind.LEAF else tint)
		if kind == Kind.LEAF and _rng.randf() < 0.5:
			# half of them start on the ground
			_pos[i] = Vector3(_rng.randf_range(-bounds, bounds) * 0.6, 0.01, _rng.randf_range(-bounds, bounds) * 0.6)
			_state[i] = RESTING
			_timer[i] = _rng.randf() * 10.0
		else:
			_respawn(i)
			if kind == Kind.SEED:
				_pos[i] += Vector3(_rng.randf_range(-bounds, bounds), 0, _rng.randf_range(-bounds, bounds)) * 0.8


## How many are in the air.
func aloft() -> int:
	var n := 0
	for s in _state:
		if s == FLYING:
			n += 1
	return n


func _respawn(i: int) -> void:
	_vel[i] = Vector3.ZERO
	_timer[i] = 0.0
	if kind == Kind.LEAF and not crowns.is_empty():
		var c: Array = crowns[_rng.randi() % crowns.size()]
		var r: float = c[1]
		_pos[i] = c[0] + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.6, 0.8), _rng.randf_range(-1, 1)) * r
		_state[i] = HANGING
	else:
		# seeds come in on the wind from upwind, low over the meadow
		var wd: Vector2 = field.dir()
		var side := Vector2(-wd.y, wd.x) * _rng.randf_range(-bounds, bounds)
		var start := -wd * bounds * _rng.randf_range(0.7, 1.0) + side
		_pos[i] = Vector3(start.x, _rng.randf_range(0.3, 4.0), start.y)
		_state[i] = FLYING


func _process(delta: float) -> void:
	if field == null:
		return
	delta = minf(delta, 1.0 / 20.0)
	_frame += 1
	var mm := multimesh
	var live := int(count * amount)
	var leaf := kind == Kind.LEAF
	for i in count:
		if i >= live:
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
			continue
		var p := _pos[i]
		var s := _state[i]
		var size := 1.0
		if s == HANGING:
			# torn off now and then, more often in a gust
			if (i + _frame) % 6 == 0:
				var air: Vector3 = field.sample(p)
				# checked every sixth frame: about 5% a second for each m/s over 3
				var chance := maxf(air.length() - 3.0, 0.0) * 0.05 * delta * 6.0
				if _rng.randf() < chance:
					_state[i] = FLYING
					_vel[i] = air * 0.3
			size = 0.0
		elif s == RESTING:
			_timer[i] += delta
			if (i + _frame) % 4 == 0:
				var air: Vector3 = field.sample(p + Vector3.UP * 0.3)
				var lift := air.length() - (6.5 if leaf else 2.0)
				if lift > 0.0 and _rng.randf() < lift * 0.06:
					_state[i] = FLYING
					_vel[i] = air * 0.4 + Vector3.UP * _rng.randf_range(1.5, 3.5)
			if leaf and _timer[i] > 30.0:
				size = clampf(31.0 - _timer[i], 0.0, 1.0)
				if size <= 0.0:
					_respawn(i)
		else:
			var air: Vector3 = field.sample(p)
			var v := _vel[i]
			if leaf:
				# heavy-ish, lots of drag, a sideways flutter as it tumbles
				v += ((air - v) * 2.2 + Vector3(0, -6.0, 0)) * delta
				v += _axis[i].cross(Vector3.UP) * sin(_timer[i] * absf(_spin[i]) * 1.3) * 3.0 * delta
			else:
				# thistledown: goes where the air goes and hardly falls
				v += ((air - v) * 5.0 + Vector3(0, -0.35, 0)) * delta
			_timer[i] += delta
			p += v * delta
			_vel[i] = v
			if p.y <= 0.01:
				p.y = 0.01
				if leaf:
					_state[i] = RESTING
					_timer[i] = 0.0
				else:
					_vel[i].y = absf(v.y) * 0.3 + 0.4
			_pos[i] = p
			if absf(p.x) > bounds or absf(p.z) > bounds or p.y > 30.0:
				_respawn(i)
				if not leaf:
					p = _pos[i]
		var basis: Basis
		if _state[i] == FLYING and leaf:
			basis = Basis(_axis[i], _timer[i] * _spin[i]) * Basis(Vector3.UP, _yaw[i])
		elif leaf:
			basis = Basis(Vector3.UP, _yaw[i])
		else:
			basis = Basis()
		mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * size), _pos[i]))


func _leaf_mesh() -> ArrayMesh:
	# a pointed leaf, flat in the ground plane, with a fold down its middle
	var verts := PackedVector3Array([
		Vector3(0, 0, -0.1), Vector3(0.05, 0.008, -0.02), Vector3(0, 0.015, 0.0),
		Vector3(0, 0, -0.1), Vector3(0, 0.015, 0.0), Vector3(-0.05, 0.008, -0.02),
		Vector3(0.05, 0.008, -0.02), Vector3(0, 0, 0.09), Vector3(0, 0.015, 0.0),
		Vector3(0, 0.015, 0.0), Vector3(0, 0, 0.09), Vector3(-0.05, 0.008, -0.02),
	])
	for k in verts.size():
		verts[k] *= 2.0
	var normals := PackedVector3Array()
	for k in verts.size():
		normals.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _seed_mesh() -> Mesh:
	var s := SphereMesh.new()
	s.radius = 0.035
	s.height = 0.07
	s.radial_segments = 6
	s.rings = 3
	return s
