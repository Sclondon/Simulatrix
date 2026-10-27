class_name WindRibbons
extends MeshInstance3D
## The wind drawn the Wind Waker way (after Hemlock's Tower's WindGusts and Daughter of the
## Wind's wind lines): thin white ribbons whose heads ride the shared wind field, now and then
## curling into a loop, each leaving a tail that tapers and fades. More of them the harder it
## blows; a blast flings them outward. Give it a `field` and say where to show them (`around`,
## or `follow_camera`). The ribbons are in world space, so leave this node at the origin.

const TAIL_LIFE := 0.9
const WIDTH := 0.05
const MIN_STEP := 0.2
const LOOP_TIME := 0.8

@export var field: WindField
## Where to show them; with `follow_camera`, they keep round the camera instead.
@export var around := Vector3.ZERO
@export var follow_camera := false
## How far round `around` they appear, m.
@export var reach := 20.0
## The most at once (in a strong wind).
@export_range(1, 40) var most := 18
var heads: Array = [] # {p, age, life, loop_at, loop_a, radius, pts}
var _time := 0.0
var _wait := 0.0
var _mesh := ImmediateMesh.new()


func _ready() -> void:
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	custom_aabb = AABB(Vector3.ONE * -100000.0, Vector3.ONE * 200000.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true
	material_override = m


func _process(delta: float) -> void:
	if field == null:
		return
	field.step()
	if follow_camera:
		var cam := get_viewport().get_camera_3d()
		if cam:
			around = cam.global_position - cam.global_basis.z * reach * 0.6
			around.y = global_position.y
	delta = minf(delta, 1.0 / 20.0)
	_time += delta
	var spd: float = field.speed
	var wanted := 0 if not visible else clampi(int(spd * 1.1), 0, most)
	var live := 0
	for h: Dictionary in heads:
		if h.age < h.life:
			live += 1
	_wait -= delta
	if live < wanted and _wait <= 0.0:
		_wait = randf_range(0.05, 0.25)
		_spawn()
	for h: Dictionary in heads:
		h.age += delta
		if h.age < h.life:
			var v: Vector3 = field.sample(h.p)
			var step := v * delta
			if h.loop_a < 0.0 and h.age >= h.loop_at:
				h.loop_a = 0.0
			if h.loop_a >= 0.0 and h.loop_a < TAU:
				# a loop: the head runs round a circle standing along the wind
				var a0: float = h.loop_a
				h.loop_a = minf(a0 + TAU * delta / LOOP_TIME, TAU)
				var along := Vector3(v.x, 0, v.z).normalized()
				var r: float = h.radius
				step = along * (sin(h.loop_a) - sin(a0)) * r + Vector3.UP * (cos(a0) - cos(h.loop_a)) * r
			h.p += step
			var pts: Array = h.pts
			if pts.is_empty() or pts[-1].p.distance_to(h.p) > MIN_STEP:
				pts.append({p = h.p, t = _time})
		while not h.pts.is_empty() and _time - h.pts[0].t > TAIL_LIFE:
			h.pts.pop_front()
	heads = heads.filter(func(h: Dictionary) -> bool: return h.age < h.life or not h.pts.is_empty())
	_rebuild()


func _spawn() -> void:
	var wd: Vector2 = field.dir()
	var side := Vector2(-wd.y, wd.x) * randf_range(-reach, reach)
	var back := -wd * randf_range(0.0, reach)
	heads.append({
		p = around + Vector3(side.x + back.x, randf_range(0.6, 7.0), side.y + back.y),
		age = 0.0, life = randf_range(1.4, 2.8),
		loop_at = randf_range(0.4, 1.2) if randf() < 0.45 else INF, loop_a = -1.0,
		radius = randf_range(0.5, 1.2), pts = [],
	})


func _rebuild() -> void:
	_mesh.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var strength := clampf(field.speed / 6.0, 0.35, 1.0)
	for h: Dictionary in heads:
		var pts: Array = h.pts
		var n := pts.size()
		if n < 3:
			continue
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in n:
			var p: Vector3 = pts[i].p
			var along: Vector3 = pts[mini(i + 1, n - 1)].p - pts[maxi(i - 1, 0)].p
			var side := along.cross(cam.global_position - p).normalized()
			var life: float = clampf(1.0 - (_time - pts[i].t) / TAIL_LIFE, 0.0, 1.0)
			var head := clampf(float(n - 1 - i) / 3.0, 0.0, 1.0)
			var w := WIDTH * sqrt(life) * (0.35 + 0.65 * head)
			var c := Color(1, 1, 1, 0.8 * strength * life)
			_mesh.surface_set_color(c)
			_mesh.surface_add_vertex(p + side * w)
			_mesh.surface_set_color(c)
			_mesh.surface_add_vertex(p - side * w)
		_mesh.surface_end()
