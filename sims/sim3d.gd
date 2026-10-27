class_name Sim3D
extends Sim
## Base for the 3D (VFX) sims. The world renders in a SubViewport the size of the play
## area and is drawn as this node's texture. Put things under `world`, build them in
## build(), and describe controls as usual (look_controls() adds the finger mode).
##
## Touch: one finger orbits the camera, or pokes the scene when the sim is pokeable()
## and the Finger choice is on Poke. Two fingers pinch to zoom and drag to pan.
## The mouse wheel zooms.

var viewport := SubViewport.new()
var world := Node3D.new()
var camera := Camera3D.new()
var environment := Environment.new()
var sun := DirectionalLight3D.new()

## Orbit camera: it looks at `focus` from `distance` away, turned by `yaw` and `pitch`.
var focus := Vector3.ZERO
var yaw := 0.6
var pitch := -0.35
var distance := 12.0
var min_distance := 2.0
var max_distance := 60.0
var min_pitch := -1.45
var max_pitch := 0.15
## Radians a second the camera drifts round on its own until it is touched.
var auto_orbit := 0.0
var poke_mode := false

var _touches := {} # index -> position
var _pinch := 0.0
var _mid := Vector2.ZERO
var _poking := -1
var _frame_ms := 0.0


func _ready() -> void:
	viewport.own_world_3d = true
	viewport.size = Vector2i(size.max(Vector2.ONE))
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	viewport.add_child(world)
	var we := WorldEnvironment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("2b2b2b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.58, 0.65)
	environment.ambient_light_energy = 0.6
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = environment
	viewport.add_child(we)
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-35), 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	world.add_child(sun)
	camera.fov = 55.0
	camera.near = 0.05
	camera.far = 600.0
	viewport.add_child(camera)
	build()
	_place_camera()


## Override: make the scene under `world`.
func build() -> void:
	pass


## Override: true if a finger can poke the scene (then a Look/Poke choice is offered).
func pokeable() -> bool:
	return false


## Override: a finger in Poke mode. `pos` is in the sim's own coordinates; use ray()/ground().
func poke_down(_pos: Vector2) -> void:
	pass


func poke_move(_pos: Vector2) -> void:
	pass


func poke_up(_pos: Vector2) -> void:
	pass


## Override: one line for the status bar (scene stats, what the finger does...).
func status() -> String:
	return ""


## The "Finger" choice; sims put this first in controls() when they are pokeable.
func look_controls() -> Array:
	if not pokeable():
		return []
	return [{type = "choice", label = "Finger", options = ["Look", "Poke"], value = 1 if poke_mode else 0,
		on = func(i: int) -> void: poke_mode = i == 1}]


## Milliseconds the last frame took, for status lines.
func frame_ms() -> float:
	return _frame_ms


## The camera ray through a point in sim coordinates: {from, dir}.
func ray(pos: Vector2) -> Dictionary:
	var p := pos * Vector2(viewport.size) / size.max(Vector2.ONE)
	return {from = camera.project_ray_origin(p), dir = camera.project_ray_normal(p)}


## Where the camera ray through `pos` meets the level plane at `height`, or null.
func ground(pos: Vector2, height := 0.0) -> Variant:
	var r := ray(pos)
	return Plane(Vector3.UP, height).intersects_ray(r.from, r.dir)


## A sky gradient for the environment, from the zenith down to the horizon and below.
func set_sky(top: Color, horizon: Color, bottom := Color(-1, 0, 0)) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon
	sky_mat.ground_bottom_color = bottom if bottom.r >= 0.0 else horizon.darkened(0.4)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky


func resize(new_size: Vector2) -> void:
	size = new_size
	viewport.size = Vector2i(size.max(Vector2.ONE))
	queue_redraw()


func _process(delta: float) -> void:
	_frame_ms = lerpf(_frame_ms, delta * 1000.0, 0.1)
	if auto_orbit != 0.0 and _touches.is_empty():
		yaw += auto_orbit * delta
		_place_camera()


func _draw() -> void:
	draw_texture_rect(viewport.get_texture(), Rect2(Vector2.ZERO, size), false)


func _place_camera() -> void:
	pitch = clampf(pitch, min_pitch, max_pitch)
	distance = clampf(distance, min_distance, max_distance)
	var dir := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))
	camera.look_at_from_position(focus + dir * distance, focus, Vector3.UP)


func touch_down(index: int, pos: Vector2) -> void:
	_touches[index] = pos
	auto_orbit = 0.0
	if _touches.size() == 1 and poke_mode and pokeable():
		_poking = index
		poke_down(pos)
	elif _touches.size() == 2:
		if _poking != -1:
			poke_up(_touches.get(_poking, pos))
			_poking = -1
		_start_pinch()


func touch_move(index: int, pos: Vector2) -> void:
	if not _touches.has(index):
		return
	var last: Vector2 = _touches[index]
	_touches[index] = pos
	if index == _poking:
		poke_move(pos)
	elif _touches.size() >= 2:
		var pts: Array = _touches.values()
		var d: float = pts[0].distance_to(pts[1])
		var mid: Vector2 = (pts[0] + pts[1]) * 0.5
		if _pinch > 1.0:
			distance *= _pinch / maxf(d, 1.0)
		var r := camera.global_basis
		var pan := (mid - _mid) * distance * 0.0016
		focus += -r.x * pan.x + r.y * pan.y
		_pinch = d
		_mid = mid
		_place_camera()
	elif _touches.size() == 1:
		var d := pos - last
		yaw -= d.x * 0.008
		pitch += d.y * 0.006
		_place_camera()


func touch_up(index: int, pos: Vector2) -> void:
	if index == _poking:
		poke_up(pos)
		_poking = -1
	_touches.erase(index)
	if _touches.size() == 2:
		_start_pinch()


func _start_pinch() -> void:
	var pts: Array = _touches.values()
	_pinch = pts[0].distance_to(pts[1])
	_mid = (pts[0] + pts[1]) * 0.5


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if not Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position()):
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance *= 0.9
			_place_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance /= 0.9
			_place_camera()
