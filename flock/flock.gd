class_name Flock
extends Node3D
## A flock (boids, after Craig Reynolds, 1987): `rules.count` birds, fish, bats, bugs or sheep,
## each steering by what its nearest neighbours do (keep clear, go the same way, keep
## together), plus a goal, predators to flee, obstacles to miss, bounds, the ground and a wind.
## Every setting is in `rules` (a FlockRules: save one as a .tres), read live.
##
## They live round this node: the bounds are centred on it. Positions are world space, so
## leave the node unrotated and unscaled. All of them are drawn by ONE MultiMesh (one draw;
## wings, tails and legs are moved in the shader from a phase this keeps), so a flock costs one
## draw and its CPU time, which is held to `budget_ms` a frame: neighbours are found through a
## spatial hash, each heeds at most `rules.max_neighbours`, and when there are too many to
## think about in one frame they take turns (every boid still moves every frame, on its last
## decision). `sim_ms` and `steered` say what it cost.
##
## A game sets `target` (or `target_node`), puts its hunters in the group `flock_predators`
## (or sets `predators` each frame), adds obstacles (`add_obstacle`, or nodes in the group
## `flock_obstacles` with a `flock_radius` meta), calls `scatter(at)` for a bang, and reads
## `positions()`. `wind` takes anything with `sample(point) -> Vector3` (GameCommon's WindField).

## scatter() was called.
signal scattered(at: Vector3)

const BUCKETS := 4096
const _P1 := 73856093
const _P2 := 19349663
const _P3 := 83492791
const _CELLS_3D: Array[Vector3i] = [Vector3i(0, 0, 0),
	Vector3i(-1, -1, -1), Vector3i(0, -1, -1), Vector3i(1, -1, -1), Vector3i(-1, 0, -1), Vector3i(0, 0, -1), Vector3i(1, 0, -1),
	Vector3i(-1, 1, -1), Vector3i(0, 1, -1), Vector3i(1, 1, -1), Vector3i(-1, -1, 0), Vector3i(0, -1, 0), Vector3i(1, -1, 0),
	Vector3i(-1, 0, 0), Vector3i(1, 0, 0), Vector3i(-1, 1, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0),
	Vector3i(-1, -1, 1), Vector3i(0, -1, 1), Vector3i(1, -1, 1), Vector3i(-1, 0, 1), Vector3i(0, 0, 1), Vector3i(1, 0, 1),
	Vector3i(-1, 1, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1)]
const _CELLS_2D: Array[Vector3i] = [Vector3i(0, 0, 0),
	Vector3i(-1, 0, -1), Vector3i(0, 0, -1), Vector3i(1, 0, -1), Vector3i(-1, 0, 0), Vector3i(1, 0, 0),
	Vector3i(-1, 0, 1), Vector3i(0, 0, 1), Vector3i(1, 0, 1)]

@export var rules: FlockRules
## Where they make for (world): pulled by rules.seek, circled by rules.orbit. Vector3.INF: this
## node (the middle of the bounds), so a flock placed anywhere keeps its goal.
@export var target := Vector3.INF
## Followed instead of `target` while set.
@export var target_node: Node3D
## Nodes in this group are predators.
@export var predator_group := &"flock_predators"
## Nodes in this group are obstacles, of radius get_meta("flock_radius", 1.0).
@export var obstacle_group := &"flock_obstacles"
## Drawn when rules.body is CUSTOM (faces -z, wings along x, up +y).
@export var custom_mesh: Mesh
## Anything with sample(point) -> Vector3 (m/s): GameCommon's WindField.
@export var wind: Resource
## The ground's height (world y), unless `ground_at` is set.
@export var ground_y := 0.0
@export var cast_shadows := false
## Milliseconds of thinking a frame, at most; past it, boids take turns.
@export_range(0.2, 20.0, 0.1) var budget_ms := 3.0
@export var flock_seed := 1
## Stops them (they are still drawn).
@export var frozen := false

## Predator positions of the game's own, set each frame (added to the group's).
var predators := PackedVector3Array()
## Obstacles: xyz the centre, w the radius.
var obstacles := PackedVector4Array()
## Optional: Callable(point: Vector3) -> float, the ground's height under a point.
var ground_at: Callable
## One boid whose neighbours are kept in `watched` (for debug drawing); -1 none.
var watch := -1
var watched := PackedInt32Array()
## What the last frame cost: ms in all, boids thought about, their mean neighbour count.
var sim_ms := 0.0
var steered := 0
var mean_neighbours := 0.0

var _n := 0
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _acc := PackedVector3Array()
var _fwd := PackedVector3Array()
var _wander := PackedVector3Array()
var _drift := PackedVector3Array()
var _fear := PackedFloat32Array()
var _bank := PackedFloat32Array()
var _scale := PackedFloat32Array()
var _pace := PackedFloat32Array()
var _shade := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _glide := PackedFloat32Array()
var _mark := PackedFloat32Array()
var _head := PackedInt32Array()
var _next := PackedInt32Array()
var _buffer := PackedFloat32Array()
var _cursor := 0
var _time := 0.0
var _us_per := 8.0
var _rng := RandomNumberGenerator.new()
var _mm: MultiMeshInstance3D
var _material: ShaderMaterial
var _built := [-1, -1, -1.0, null]
var _all_predators := PackedVector3Array()
var _all_obstacles := PackedVector4Array()
var _goal := Vector3.ZERO
var _middle := Vector3.ZERO


func _ready() -> void:
	if rules == null:
		rules = FlockRules.new()
	_rng.seed = flock_seed
	_material = ShaderMaterial.new()
	_material.shader = preload("flock.gdshader")
	_mm = MultiMeshInstance3D.new()
	_mm.name = "Boids"
	_mm.top_level = true
	_mm.material_override = _material
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.use_colors = true
	many.use_custom_data = true
	_mm.multimesh = many
	add_child(_mm)
	_mm.global_transform = Transform3D.IDENTITY
	_head.resize(BUCKETS)
	_rebuild()


## Starts them all again, scattered through the bounds.
func respawn() -> void:
	_built[0] = -1
	_rebuild()


func boid_count() -> int:
	return _n


## Every boid's position (world).
func positions() -> PackedVector3Array:
	return _pos


func velocities() -> PackedVector3Array:
	return _vel


func boid_position(i: int) -> Vector3:
	return _pos[i]


## How frightened one is (0..1).
func fear_of(i: int) -> float:
	return _fear[i]


## Where they are making for just now: target_node, target, or this node.
func goal_point() -> Vector3:
	if is_instance_valid(target_node):
		return target_node.global_position
	return target if target.is_finite() else global_position


## The middle of the flock.
func centre() -> Vector3:
	if _n == 0:
		return global_position
	var sum := Vector3.ZERO
	for p in _pos:
		sum += p
	return sum / _n


## The boid nearest a point.
func nearest(point: Vector3) -> int:
	var best := -1
	var near := INF
	for i in _n:
		var d := _pos[i].distance_squared_to(point)
		if d < near:
			near = d
			best = i
	return best


## A bang, a stone thrown, a hand slapped on the glass: everything within `radius` (default
## twice flee_radius) bolts away from `at`, and the fright spreads.
func scatter(at: Vector3, strength := 1.0, radius := 0.0) -> void:
	var r := radius if radius > 0.0 else maxf(rules.flee_radius * 2.0, 0.5)
	for i in _n:
		var off := _pos[i] - at
		if rules.planar:
			off.y = 0.0
		var d := off.length()
		if d < r:
			var k := (1.0 - d / r) * strength
			var away := off / d if d > 0.001 else Vector3(_rng.randf_range(-1, 1), 0.3, _rng.randf_range(-1, 1)).normalized()
			_vel[i] += away * rules.max_speed * rules.panic_speed * k
			_fear[i] = maxf(_fear[i], minf(k * 1.5, 1.0))
	scattered.emit(at)


func add_obstacle(at: Vector3, radius: float) -> void:
	obstacles.append(Vector4(at.x, at.y, at.z, radius))


func clear_obstacles() -> void:
	obstacles.clear()


## The mesh a built-in body is drawn with (1 m long, facing -z).
static func body_mesh(body: int) -> ArrayMesh:
	match body:
		FlockRules.Body.FISH: return _fish_mesh()
		FlockRules.Body.BAT: return _bat_mesh()
		FlockRules.Body.BUG: return _bug_mesh()
		FlockRules.Body.SHEEP: return _sheep_mesh()
	return _bird_mesh()


# --- the boids ------------------------------------------------------------------

func _rebuild() -> void:
	var r := rules
	var mesh: Mesh = custom_mesh if r.body == FlockRules.Body.CUSTOM and custom_mesh else body_mesh(r.body)
	if _built[1] != r.body or _built[3] != custom_mesh:
		_mm.multimesh.instance_count = 0
		_mm.multimesh.mesh = mesh
		_shape_uniforms(mesh)
	var old := _n
	_n = r.count
	_pos.resize(_n)
	_vel.resize(_n)
	_acc.resize(_n)
	_fwd.resize(_n)
	_wander.resize(_n)
	_drift.resize(_n)
	_fear.resize(_n)
	_bank.resize(_n)
	_scale.resize(_n)
	_pace.resize(_n)
	_shade.resize(_n)
	_phase.resize(_n)
	_glide.resize(_n)
	_mark.resize(_n)
	_next.resize(_n)
	var from := 0 if _built[0] == -1 else old
	for i in range(from, _n):
		_spawn(i)
	if _built[2] != r.size or _built[1] != r.body:
		for i in _n:
			_scale[i] = r.size * (1.0 + _rng.randf_range(-1.0, 1.0) * r.size_variation)
	_mm.multimesh.instance_count = _n
	_buffer.resize(_n * 20)
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_built = [r.count, r.body, r.size, custom_mesh]
	_cursor = 0
	watched.clear()
	_draw_all(0.0)


func _spawn(i: int) -> void:
	var r := rules
	var c := global_position
	var p := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * r.bounds_size * 0.45
	if r.bounds == FlockRules.Bounds.SPHERE:
		p = _rng_unit() * r.bounds_size.x * 0.45 * pow(_rng.randf(), 0.33)
	p += c
	var g := _ground(p)
	if r.planar:
		p.y = g + r.ground_clearance
	elif r.avoid_ground:
		p.y = maxf(p.y, g + r.ground_clearance + 1.0)
	var dir := _rng_unit()
	if r.planar:
		dir = Vector3(dir.x, 0.0, dir.z).normalized()
	_pos[i] = p
	_vel[i] = dir * maxf(r.cruise_speed, 0.01)
	_fwd[i] = dir
	_acc[i] = Vector3.ZERO
	_wander[i] = _rng_unit()
	_drift[i] = Vector3.ZERO
	_fear[i] = 0.0
	_bank[i] = 0.0
	_scale[i] = r.size * (1.0 + _rng.randf_range(-1.0, 1.0) * r.size_variation)
	_pace[i] = 1.0 + _rng.randf_range(-1.0, 1.0) * r.speed_variation
	_shade[i] = _rng.randf()
	_phase[i] = _rng.randf() * TAU
	_glide[i] = 0.0
	_mark[i] = _rng.randf() * 100.0


func _rng_unit() -> Vector3:
	var v := Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn())
	return v.normalized() if v.length_squared() > 0.0001 else Vector3.FORWARD


func _ground(p: Vector3) -> float:
	return ground_at.call(p) if ground_at.is_valid() else ground_y


func _shape_uniforms(mesh: Mesh) -> void:
	var box := mesh.get_aabb() if mesh else AABB(Vector3(-0.5, -0.1, -0.5), Vector3(1, 0.2, 1))
	var span := maxf(absf(box.position.x), absf(box.end.x))
	_material.set_shader_parameter("span_half", span)
	_material.set_shader_parameter("length_half", maxf(absf(box.position.z), absf(box.end.z)))
	match rules.body:
		FlockRules.Body.BIRD: _material.set_shader_parameter("body_half", 0.065)
		FlockRules.Body.BAT: _material.set_shader_parameter("body_half", 0.06)
		FlockRules.Body.BUG: _material.set_shader_parameter("body_half", 0.07)
		FlockRules.Body.SHEEP: _material.set_shader_parameter("leg_top", 0.36)
		_: _material.set_shader_parameter("body_half", span * 0.15)
	if rules.body == FlockRules.Body.CUSTOM:
		_material.set_shader_parameter("leg_top", box.position.y + box.size.y * 0.35)


func _process(delta: float) -> void:
	if rules == null or _mm == null:
		return
	if _built[0] != rules.count or _built[1] != rules.body or _built[2] != rules.size or _built[3] != custom_mesh:
		_rebuild()
	if frozen:
		_draw_all(0.0)
		return
	var t0 := Time.get_ticks_usec()
	var dt := minf(delta, 1.0 / 20.0)
	_time += dt
	_gather()
	_think()
	_move(dt)
	_draw_all(dt)
	sim_ms = lerpf(sim_ms, (Time.get_ticks_usec() - t0) / 1000.0, 0.1)


func _gather() -> void:
	_all_predators = predators.duplicate()
	_all_obstacles = obstacles.duplicate()
	_goal = goal_point()
	_middle = centre()
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group(predator_group):
		if node is Node3D and (node as Node3D).is_visible_in_tree():
			_all_predators.append((node as Node3D).global_position)
	for node in get_tree().get_nodes_in_group(obstacle_group):
		if node is Node3D:
			var p := (node as Node3D).global_position
			_all_obstacles.append(Vector4(p.x, p.y, p.z, float(node.get_meta("flock_radius", 1.0))))


# Fills the spatial hash, then thinks about as many boids as the budget allows, in turn.
func _think() -> void:
	var r := rules
	var cell := maxf(r.perception, 0.05)
	var inv := 1.0 / cell
	_head.fill(-1)
	for i in _n:
		var p := _pos[i]
		var h := ((floori(p.x * inv) * _P1) ^ (floori(p.y * inv) * _P2) ^ (floori(p.z * inv) * _P3)) & (BUCKETS - 1)
		_next[i] = _head[h]
		_head[h] = i
	var start := Time.get_ticks_usec()
	var least := maxi(_n / 8, mini(_n, 32))
	var most := maxi(least, int(budget_ms * 1000.0 / maxf(_us_per, 0.5)))
	var todo := mini(_n, most)
	var found_sum := 0
	if watch >= _n:
		watch = -1
	for k in todo:
		var i := (_cursor + k) % _n
		found_sum += _steer(i, inv)
	_cursor = (_cursor + todo) % maxi(_n, 1)
	steered = todo
	mean_neighbours = float(found_sum) / maxf(todo, 1)
	if todo > 0:
		_us_per = lerpf(_us_per, float(Time.get_ticks_usec() - start) / todo, 0.2)


# One boid decides where to steer; returns how many neighbours it heeded.
func _steer(i: int, inv: float) -> int:
	var r := rules
	var p := _pos[i]
	var v := _vel[i]
	var fwd := _fwd[i]
	var planar := r.planar
	var see2 := r.perception * r.perception
	var sep_d := r.separation_distance
	var cos_fov := cos(deg_to_rad(r.field_of_view * 0.5))
	var all_round := r.field_of_view >= 359.0
	var cap := r.max_neighbours
	var sep := Vector3.ZERO
	var ali := Vector3.ZERO
	var mid := Vector3.ZERO
	var fright := 0.0
	var found := 0
	var keep := i == watch
	if keep:
		watched.clear()
	var cx := floori(p.x * inv)
	var cy := floori(p.y * inv)
	var cz := floori(p.z * inv)
	# the boid's own cell first, so a capped search keeps the nearest
	for o in (_CELLS_2D if planar else _CELLS_3D):
		var h := (((cx + o.x) * _P1) ^ ((cy + o.y) * _P2) ^ ((cz + o.z) * _P3)) & (BUCKETS - 1)
		var j := _head[h]
		while j != -1 and found < cap:
			if j != i:
				var off := _pos[j] - p
				var d2 := off.length_squared()
				if d2 < see2 and d2 > 0.000001:
					var d := sqrt(d2)
					if all_round or fwd.dot(off) >= cos_fov * d:
						found += 1
						if d < sep_d:
							sep -= off / d * (1.0 - d / sep_d)
						ali += _vel[j]
						mid += off
						fright = maxf(fright, _fear[j])
						if keep:
							watched.append(j)
			j = _next[j]
		if found >= cap:
			break
	var mf := r.max_force
	var force := Vector3.ZERO
	var cruise := r.cruise_speed * _pace[i]
	var speed := v.length()
	if found > 0:
		force += sep * mf * r.separation * 2.0
		var avg := ali / found
		force += (avg - v) * r.alignment * 1.5
		var to_mid := mid / found
		force += to_mid.limit_length(1.0) * mf * r.cohesion * 0.6
		_fear[i] = maxf(_fear[i], fright * r.alarm_spread * 0.97)
	# keep up its own pace
	force += (fwd * cruise - v) * 1.2
	# a wandering urge of its own
	var w := _wander[i] + Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn()) * r.wander_rate * 0.05
	if planar:
		w.y = 0.0
	w = w.normalized() if w.length_squared() > 0.0001 else fwd
	_wander[i] = w
	force += w * mf * r.wander * 0.5
	# the whole flock: one body
	if r.gather > 0.0:
		var to_c := _middle - p
		if planar:
			to_c.y = 0.0
		var dc := to_c.length()
		if dc > 0.001:
			force += to_c / dc * mf * r.gather * minf(dc / maxf(r.perception * 4.0, 0.1), 1.0)
	# the goal: pulled to it, and round it
	var goal := _goal
	if goal.is_finite():
		var to := goal - p
		if planar:
			to.y = 0.0
		var dist := to.length()
		if dist > 0.001:
			var near := clampf((dist - r.arrive_radius * 0.5) / maxf(r.arrive_radius, 0.01), 0.15, 1.0)
			force += to / dist * mf * r.seek * near
			if r.orbit > 0.0:
				var flat := Vector3(to.x, 0.0, to.z)
				var fl := flat.length()
				if fl > 0.01:
					var round_dir := Vector3(-flat.z, 0.0, flat.x) / fl
					# hold the radius: in if too far out, out if too close
					var hold := clampf((fl - r.orbit_radius) / maxf(r.orbit_radius * 0.5, 0.5), -1.0, 1.0)
					force += (round_dir * cruise - Vector3(v.x, 0.0, v.z)) * r.orbit * 0.8
					force += flat / fl * hold * mf * r.orbit * 0.5
	# predators
	var flee_r := r.flee_radius
	for q in _all_predators:
		var off := p - q
		if planar:
			off.y = 0.0
		var d := off.length()
		if d < flee_r and d > 0.001:
			var k := 1.0 - d / flee_r
			force += off / d * mf * r.flee * (0.5 + 1.5 * k)
			_fear[i] = maxf(_fear[i], minf(k * 1.6, 1.0))
	if _fear[i] > 0.05:
		force *= 1.0 + _fear[i]
	force = force.limit_length(mf * (1.0 + _fear[i]))
	# then what must win: the bounds, the ground, obstacles
	force += _keep_in(p) * mf * r.bounds_force
	var g := _ground(p)
	if r.avoid_ground and not planar:
		var low := g + r.ground_clearance
		var margin := maxf(r.ground_clearance * 0.5, 1.0)
		if p.y < low + margin:
			force.y += mf * 2.0 * clampf((low + margin - p.y) / margin, 0.0, 2.0)
		if r.ceiling > 0.0 and p.y > g + r.ceiling - margin:
			force.y -= mf * 2.0 * clampf((p.y - (g + r.ceiling - margin)) / margin, 0.0, 2.0)
	if r.avoid > 0.0 and not _all_obstacles.is_empty():
		var reach := r.look_ahead * maxf(speed, 0.5) + _scale[i]
		for o in _all_obstacles:
			var c := Vector3(o.x, o.y, o.z)
			var off := p - c
			if planar:
				off.y = 0.0
			var d := off.length()
			var room := o.w + reach
			if d < room and d > 0.001:
				var out := off / d
				var k := 1.0 - (d - o.w) / reach
				# sideways round it, more than straight back from it
				var side := out - fwd * out.dot(fwd)
				var sl := side.length()
				side = side / sl if sl > 0.01 else out
				var ahead := maxf(-out.dot(fwd), 0.0)
				force += (side * (0.4 + ahead) + out * 0.6) * mf * r.avoid * clampf(k, 0.0, 1.5)
				if d < o.w + _scale[i] * 0.5:
					var pushed := c + out * (o.w + _scale[i] * 0.5)
					if planar:
						pushed.y = p.y
					_pos[i] = pushed
	if planar:
		force.y = 0.0
	_acc[i] = force
	if wind != null and r.wind_carry > 0.0 and wind.has_method("sample"):
		var air: Vector3 = wind.call("sample", p)
		_drift[i] = air * r.wind_carry
	else:
		_drift[i] = Vector3.ZERO
	return found


# How hard and which way the bounds push a point back in (0 well inside).
func _keep_in(p: Vector3) -> Vector3:
	var r := rules
	var rel := p - global_position
	var m := maxf(r.bounds_margin, 0.01)
	var push := Vector3.ZERO
	if r.bounds == FlockRules.Bounds.SPHERE:
		var d := rel.length()
		var over := d - (r.bounds_size.x - m)
		if over > 0.0 and d > 0.001:
			push = -rel / d * (over / m)
	else:
		var half := r.bounds_size
		for a in 3:
			if a == 1 and (r.bounds == FlockRules.Bounds.LAYER or r.planar):
				continue
			var over := absf(rel[a]) - (half[a] - m)
			if over > 0.0:
				push[a] = -signf(rel[a]) * over / m
	return push * push.length() if push.length() > 1.0 else push


# Every boid moves every frame, on its last decision.
func _move(dt: float) -> void:
	var r := rules
	var planar := r.planar
	var lo := r.min_speed
	var hi := r.max_speed
	var calm := r.calm_rate * dt
	var turn := 1.0 - exp(-10.0 * dt)
	for i in _n:
		var v := _vel[i] + _acc[i] * dt
		var fear := _fear[i]
		if planar:
			v.y = 0.0
		var top := hi * (1.0 + fear * (r.panic_speed - 1.0))
		var s := v.length()
		if s > top:
			v *= top / s
		elif s < lo:
			v = (v / s if s > 0.0001 else _fwd[i]) * lo
		_vel[i] = v
		var p := _pos[i] + (v + _drift[i]) * dt
		if planar:
			p.y = _ground(p) + r.ground_clearance
		elif r.avoid_ground:
			var floor_y := _ground(p) + 0.05
			if p.y < floor_y:
				p.y = floor_y
				if v.y < 0.0:
					_vel[i].y = 0.0
		_pos[i] = p
		if fear > 0.0:
			_fear[i] = maxf(fear - calm, 0.0)
		s = v.length()
		if s > 0.05:
			var f := _fwd[i].lerp(v / s, turn)
			if planar:
				f.y = 0.0
			if f.length_squared() > 0.0001:
				_fwd[i] = f.normalized()


func _draw_all(dt: float) -> void:
	if _n == 0:
		return
	var r := rules
	var swim := r.motion == FlockRules.Motion.SWIM
	var walk := r.motion == FlockRules.Motion.WALK
	var flap := r.motion == FlockRules.Motion.FLAP
	var bank_max := deg_to_rad(r.max_bank)
	var ease := 1.0 - exp(-5.0 * dt)
	var rate := r.flap_rate * TAU * dt
	var cruise := maxf(r.cruise_speed, 0.1)
	var glide_cut := 1.0 - 2.0 * r.glide
	var shade := r.colour_variation
	var b := _buffer
	for i in _n:
		var f := _fwd[i]
		var v := _vel[i]
		var a := _acc[i]
		var right := f.cross(Vector3.UP)
		if right.length_squared() < 0.0001:
			right = Vector3.RIGHT
		right = right.normalized()
		var up := right.cross(f)
		# banked into the turn: lift tilted toward the sideways pull, as a real turn
		if r.banking > 0.0:
			var want := clampf(atan2(a.dot(right), 9.8) * r.banking, -bank_max, bank_max)
			_bank[i] = lerpf(_bank[i], want, ease)
			var bk := _bank[i]
			var cb := cos(bk)
			var sb := sin(bk)
			var up2 := up * cb + right * sb
			right = right * cb - up * sb
			up = up2
		var s := _scale[i]
		var o := _pos[i]
		var k := i * 20
		b[k] = right.x * s
		b[k + 1] = up.x * s
		b[k + 2] = -f.x * s
		b[k + 3] = o.x
		b[k + 4] = right.y * s
		b[k + 5] = up.y * s
		b[k + 6] = -f.y * s
		b[k + 7] = o.y
		b[k + 8] = right.z * s
		b[k + 9] = up.z * s
		b[k + 10] = -f.z * s
		b[k + 11] = o.z
		# the beat: faster when climbing, frightened or hurrying; wings held out in a glide
		var speed := v.length()
		var effort := 1.0
		var glide := 0.0
		if flap:
			effort = clampf(0.8 + a.y / maxf(r.max_force, 0.1) + _fear[i] * 0.8, 0.4, 2.0)
			if r.glide > 0.0:
				var gliding := sin(_time * 0.8 + _mark[i]) * cos(_time * 0.37 + _mark[i] * 1.7) > glide_cut and _fear[i] < 0.2 and a.y < r.max_force * 0.4
				_glide[i] = move_toward(_glide[i], 1.0 if gliding else 0.0, dt * 3.0)
			else:
				_glide[i] = 0.0
			glide = _glide[i]
		elif swim:
			effort = clampf(0.4 + speed / cruise * 0.6, 0.3, 2.0)
		elif walk:
			effort = clampf(speed / maxf(r.max_speed * 0.35, 0.1), 0.0, 1.5)
		_phase[i] = fmod(_phase[i] + rate * effort * (1.0 - glide * 0.95), TAU * 64.0)
		var tone := 1.0 - _shade[i] * shade
		b[k + 12] = tone
		b[k + 13] = tone
		b[k + 14] = tone
		b[k + 15] = 1.0
		b[k + 16] = _phase[i]
		b[k + 17] = effort
		b[k + 18] = glide
		b[k + 19] = _fear[i]
	_mm.multimesh.buffer = b
	_material.set_shader_parameter("colour", r.colour)
	_material.set_shader_parameter("motion", int(r.motion))
	_material.set_shader_parameter("amount", r.flap_amount)
	_material.set_shader_parameter("sheen", 0.5 if r.body == FlockRules.Body.FISH else 0.25)


# --- built-in bodies (1 m long, nose at -z) -----------------------------------------

static var _meshes := {}


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col := Color.WHITE) -> void:
	st.set_color(col)
	st.add_vertex(a)
	st.set_color(col)
	st.add_vertex(b)
	st.set_color(col)
	st.add_vertex(c)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col := Color.WHITE) -> void:
	_tri(st, a, b, c, col)
	_tri(st, a, c, d, col)


# A spindle along z: a point at each end and rings between; ring = [z, half width, half height, y].
static func _spindle(st: SurfaceTool, nose: Vector3, rings: Array, tail: Vector3, sides: int, cols: Array) -> void:
	var pts: Array = []
	for ring: Array in rings:
		var row: Array = []
		for k in sides:
			var a := TAU * k / sides
			row.append(Vector3(sin(a) * ring[1], ring[3] + cos(a) * ring[2], ring[0]))
		pts.append(row)
	for k in sides:
		var k2 := (k + 1) % sides
		var col: Color = cols[k]
		_tri(st, nose, pts[0][k2], pts[0][k], col)
		for r in pts.size() - 1:
			_quad(st, pts[r][k], pts[r][k2], pts[r + 1][k2], pts[r + 1][k], col)
		_tri(st, tail, pts[-1][k], pts[-1][k2], col)


static func _finish(st: SurfaceTool, key: int) -> ArrayMesh:
	st.generate_normals()
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


# A starling-like bird: a spindle body, a short notched tail, long pointed swept wings.
static func _bird_mesh() -> ArrayMesh:
	if _meshes.has(0):
		return _meshes[0]
	var st := _begin()
	var back := Color(0.85, 0.85, 0.85)
	var cols := [back, back, Color.WHITE, Color.WHITE, Color.WHITE, back]
	_spindle(st, Vector3(0, 0.0, -0.5), [[-0.36, 0.045, 0.045, 0.01], [-0.12, 0.065, 0.06, 0.0], [0.15, 0.045, 0.045, 0.0]], Vector3(0, 0.01, 0.3), 6, cols)
	# the tail, notched
	_tri(st, Vector3(-0.03, 0.01, 0.22), Vector3(0.03, 0.01, 0.22), Vector3(0.0, 0.01, 0.44))
	_tri(st, Vector3(-0.03, 0.01, 0.22), Vector3(0.0, 0.01, 0.44), Vector3(-0.1, 0.01, 0.5))
	_tri(st, Vector3(0.03, 0.01, 0.22), Vector3(0.1, 0.01, 0.5), Vector3(0.0, 0.01, 0.44))
	for s: float in [-1.0, 1.0]:
		var root_f := Vector3(s * 0.05, 0.02, -0.13)
		var root_b := Vector3(s * 0.05, 0.02, 0.07)
		var mid_f := Vector3(s * 0.25, 0.03, -0.12)
		var mid_b := Vector3(s * 0.25, 0.03, 0.08)
		var tip := Vector3(s * 0.52, 0.0, 0.14)
		_quad(st, root_f, mid_f, mid_b, root_b, back)
		_tri(st, mid_f, tip, mid_b, back)
	return _finish(st, 0)


# A bat: a stubby furry body, ears, and broad wings scalloped between the fingers.
static func _bat_mesh() -> ArrayMesh:
	if _meshes.has(2):
		return _meshes[2]
	var st := _begin()
	var fur := Color(1.0, 0.9, 0.82)
	var skin := Color(0.7, 0.62, 0.6)
	_spindle(st, Vector3(0, 0.0, -0.32), [[-0.22, 0.055, 0.05, 0.0], [0.0, 0.07, 0.065, 0.0], [0.15, 0.045, 0.045, 0.0]], Vector3(0, 0.0, 0.25), 6, [fur, fur, fur, fur, fur, fur])
	for s: float in [-1.0, 1.0]:
		_tri(st, Vector3(s * 0.015, 0.03, -0.25), Vector3(s * 0.045, 0.03, -0.2), Vector3(s * 0.04, 0.11, -0.25), fur)
		var hub := Vector3(s * 0.22, 0.015, -0.02)
		var edge := [Vector3(s * 0.05, 0.02, -0.14), Vector3(s * 0.2, 0.04, -0.17), Vector3(s * 0.38, 0.02, -0.1),
			Vector3(s * 0.55, 0.0, -0.02), Vector3(s * 0.42, 0.0, 0.05), Vector3(s * 0.4, 0.0, 0.16),
			Vector3(s * 0.28, 0.0, 0.09), Vector3(s * 0.22, 0.0, 0.22), Vector3(s * 0.13, 0.0, 0.12),
			Vector3(s * 0.05, 0.0, 0.2)]
		for k in edge.size() - 1:
			_tri(st, hub, edge[k], edge[k + 1], skin)
		_tri(st, hub, edge[-1], edge[0], skin)
	return _finish(st, 2)


# A gnat or midge: a little body and two pairs of narrow wings.
static func _bug_mesh() -> ArrayMesh:
	if _meshes.has(3):
		return _meshes[3]
	var st := _begin()
	var c := Color(0.55, 0.55, 0.55)
	_spindle(st, Vector3(0, 0, -0.4), [[-0.2, 0.09, 0.09, 0.0], [0.1, 0.08, 0.08, 0.0]], Vector3(0, 0, 0.5), 5, [c, c, c, c, c])
	var wing := Color(1.0, 1.0, 1.0)
	for s: float in [-1.0, 1.0]:
		_quad(st, Vector3(s * 0.07, 0.05, -0.15), Vector3(s * 0.45, 0.05, -0.02), Vector3(s * 0.48, 0.05, 0.08), Vector3(s * 0.07, 0.05, -0.02), wing)
		_quad(st, Vector3(s * 0.07, 0.05, 0.0), Vector3(s * 0.36, 0.05, 0.12), Vector3(s * 0.35, 0.05, 0.22), Vector3(s * 0.07, 0.05, 0.1), wing)
	return _finish(st, 3)


# A fish: a deep, flattened body, dark above and pale below, a dorsal fin and a forked tail.
static func _fish_mesh() -> ArrayMesh:
	if _meshes.has(1):
		return _meshes[1]
	var st := _begin()
	var back := Color(0.3, 0.37, 0.45)
	var flank := Color(0.88, 0.88, 0.88)
	var belly := Color(1.0, 0.98, 0.94)
	var cols := [back, back, flank, belly, belly, flank, back, back]
	_spindle(st, Vector3(0, 0.0, -0.5), [[-0.36, 0.05, 0.09, 0.0], [-0.12, 0.07, 0.15, 0.0], [0.12, 0.05, 0.12, 0.0], [0.3, 0.02, 0.05, 0.0]],
		Vector3(0, 0, 0.36), 8, cols)
	var fin := Color(0.5, 0.55, 0.6)
	_tri(st, Vector3(0, 0.13, -0.08), Vector3(0, 0.22, 0.05), Vector3(0, 0.1, 0.14), fin)
	_tri(st, Vector3(0, 0.0, 0.32), Vector3(0, 0.17, 0.5), Vector3(0, 0.03, 0.42), fin)
	_tri(st, Vector3(0, 0.0, 0.32), Vector3(0, -0.03, 0.42), Vector3(0, -0.15, 0.5), fin)
	# an eye each side
	var eye := Color(0.05, 0.05, 0.06)
	for s: float in [-1.0, 1.0]:
		_tri(st, Vector3(s * 0.052, 0.05, -0.36), Vector3(s * 0.052, 0.01, -0.33), Vector3(s * 0.052, 0.01, -0.39), eye)
	return _finish(st, 1)


# A sheep: a woolly body, a black face, black legs (feet at y = 0).
static func _sheep_mesh() -> ArrayMesh:
	if _meshes.has(4):
		return _meshes[4]
	var st := _begin()
	var wool := Color.WHITE
	var face := Color(0.12, 0.11, 0.11)
	_spindle(st, Vector3(0, 0.6, -0.42), [[-0.34, 0.2, 0.2, 0.6], [-0.1, 0.26, 0.25, 0.6], [0.2, 0.26, 0.25, 0.6], [0.38, 0.18, 0.18, 0.62]],
		Vector3(0, 0.62, 0.48), 8, [wool, wool, wool, wool, wool, wool, wool, wool])
	# head: a tapered box, down a little
	var hf := [Vector3(-0.07, 0.62, -0.68), Vector3(0.07, 0.62, -0.68), Vector3(0.06, 0.5, -0.66), Vector3(-0.06, 0.5, -0.66)]
	var hb := [Vector3(-0.1, 0.8, -0.4), Vector3(0.1, 0.8, -0.4), Vector3(0.09, 0.56, -0.4), Vector3(-0.09, 0.56, -0.4)]
	_quad(st, hf[0], hf[1], hf[2], hf[3], face)
	for k in 4:
		var k2 := (k + 1) % 4
		_quad(st, hb[k], hb[k2], hf[k2], hf[k], face)
	for s: float in [-1.0, 1.0]:
		_tri(st, Vector3(s * 0.08, 0.76, -0.47), Vector3(s * 0.2, 0.72, -0.44), Vector3(s * 0.09, 0.7, -0.42), face)
	# legs
	for lx: float in [-0.13, 0.13]:
		for lz: float in [-0.26, 0.26]:
			var w := 0.035
			var top := 0.42
			var c := Vector3(lx, 0, lz)
			var low := [c + Vector3(-w, 0, -w), c + Vector3(w, 0, -w), c + Vector3(w, 0, w), c + Vector3(-w, 0, w)]
			for k in 4:
				var k2 := (k + 1) % 4
				var a: Vector3 = low[k]
				var b2: Vector3 = low[k2]
				_quad(st, a, b2, b2 + Vector3(0, top, 0), a + Vector3(0, top, 0), face)
	return _finish(st, 4)
