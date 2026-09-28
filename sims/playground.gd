extends Sim
## Rigid-body sandbox: drop shapes, pour them, grab and fling them.

const MAX_BODIES := 140
const WALL := 400.0
const BASE_GRAVITY := 980.0 # project default, gravity_scale is relative to it
const COLORS := [
	Color("ff5fa2"), Color("3de0c4"), Color("ffd166"), Color("7aa2ff"), Color("ff8a5b"), Color("b98cff"),
]

var gravity := 980.0
var bounce := 0.35
var spawn_kind := 3 # 0 ball, 1 box, 2 triangle, 3 mix
var spawn_size := 1.0
var pegs_on := false

var walls := StaticBody2D.new()
var pegs := StaticBody2D.new()
var bodies := Node2D.new()
var grabs := {} # touch index -> {body, offset (body-local), target}
var pours := {} # touch index -> last spawn position


func help() -> String:
	return "Tap empty space to drop a shape. Drag across empty space to pour a stream of them.\n\nPress on a shape to grab it, then drag and let go to throw it. Use two fingers to juggle two at once.\n\nTurn gravity down to zero for a space station, crank bounce for a super-ball pit, or switch on pegs for a plinko board."


func hint() -> String:
	return "Tap to drop shapes, drag to pour, grab a shape to throw it"


func controls() -> Array:
	return [
		{type = "choice", label = "Shape", options = ["Ball", "Box", "Tri", "Mix"], value = spawn_kind,
			on = func(v: int) -> void: spawn_kind = v},
		{type = "slider", label = "Size", min = 0.5, max = 2.0, step = 0.05, value = spawn_size, fmt = "%.2fx",
			on = func(v: float) -> void: spawn_size = v},
		{type = "slider", label = "Gravity", min = 0.0, max = 3000.0, step = 10.0, value = gravity, fmt = "%.0f px/s²",
			on = _set_gravity},
		{type = "slider", label = "Bounce", min = 0.0, max = 1.0, step = 0.01, value = bounce, fmt = "%.2f",
			on = _set_bounce},
		{type = "toggle", label = "Pegs", value = pegs_on, on = _set_pegs},
		{type = "button", label = "Rain 30", on = _rain},
		{type = "button", label = "Explode", on = _explode},
		{type = "button", label = "Clear", on = _clear},
	]


func _ready() -> void:
	add_child(walls)
	add_child(pegs)
	add_child(bodies)
	resize(size)
	_rain()


func resize(new_size: Vector2) -> void:
	size = new_size
	for child in walls.get_children():
		child.free()
	var rects := [
		Rect2(-WALL, size.y, size.x + WALL * 2, WALL), # floor
		Rect2(-WALL, -WALL * 4, WALL, size.y + WALL * 5), # left
		Rect2(size.x, -WALL * 4, WALL, size.y + WALL * 5), # right
		Rect2(-WALL, -WALL * 5, size.x + WALL * 2, WALL), # lid, well above the top
	]
	for r: Rect2 in rects:
		var shape := RectangleShape2D.new()
		shape.size = r.size
		var col := CollisionShape2D.new()
		col.shape = shape
		col.position = r.get_center()
		walls.add_child(col)
	_build_pegs()
	# keep anything that ended up outside the new bounds
	for b: ShapeBody in bodies.get_children():
		b.position = b.position.clamp(Vector2(b.radius, -WALL * 3), size - Vector2(b.radius, b.radius))
	queue_redraw()


func _build_pegs() -> void:
	for child in pegs.get_children():
		child.free()
	if not pegs_on:
		return
	var gap := clampf(minf(size.x, size.y) / 7.0, 60.0, 110.0)
	var row := 0
	var y := size.y * 0.3
	while y < size.y - gap * 0.9:
		var x := gap * (0.5 if row % 2 == 0 else 1.0)
		while x < size.x - gap * 0.25:
			var shape := CircleShape2D.new()
			shape.radius = 7.0
			var col := CollisionShape2D.new()
			col.shape = shape
			col.position = Vector2(x, y)
			pegs.add_child(col)
			x += gap
		y += gap * 0.8
		row += 1


func _set_gravity(v: float) -> void:
	gravity = v
	for b: ShapeBody in bodies.get_children():
		b.gravity_scale = gravity / BASE_GRAVITY
		b.sleeping = false


func _set_bounce(v: float) -> void:
	bounce = v
	for b: ShapeBody in bodies.get_children():
		b.physics_material_override.bounce = v


func _set_pegs(on: bool) -> void:
	pegs_on = on
	_build_pegs()
	queue_redraw()


func _spawn(pos: Vector2, velocity := Vector2.ZERO) -> ShapeBody:
	if bodies.get_child_count() >= MAX_BODIES:
		var oldest := bodies.get_child(0)
		for grab in grabs.values():
			if grab.body == oldest:
				return null
		oldest.free()
	var kind: int = spawn_kind if spawn_kind < 3 else randi() % 3
	var body := ShapeBody.new()
	var radius := randf_range(16.0, 30.0) * spawn_size * clampf(minf(size.x, size.y) / 720.0, 0.7, 1.3)
	body.setup(kind, radius, COLORS.pick_random(), bounce)
	body.position = pos
	body.rotation = randf() * TAU
	body.gravity_scale = gravity / BASE_GRAVITY
	body.linear_velocity = velocity
	bodies.add_child(body)
	return body


func _rain() -> void:
	for i in 30:
		_spawn(Vector2(randf_range(40, size.x - 40), -randf_range(40, 900)))


func _explode() -> void:
	var center := Vector2(size.x * 0.5, size.y * 0.8)
	for b: ShapeBody in bodies.get_children():
		var away := b.position - center
		var push := away.normalized() * 180000.0 / maxf(away.length(), 80.0) + Vector2(0, -500)
		b.sleeping = false
		b.linear_velocity += push
		b.angular_velocity += randf_range(-12, 12)


func _clear() -> void:
	grabs.clear()
	for b in bodies.get_children():
		b.free()


func _body_at(pos: Vector2) -> ShapeBody:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = to_global(pos)
	for hit in get_world_2d().direct_space_state.intersect_point(query, 8):
		if hit.collider is ShapeBody:
			return hit.collider
	# fingers are fat: settle for the nearest shape within reach
	var best: ShapeBody = null
	var best_d := 36.0
	for b: ShapeBody in bodies.get_children():
		var d := b.position.distance_to(pos) - b.radius
		if d < best_d:
			best_d = d
			best = b
	return best


func touch_down(index: int, pos: Vector2) -> void:
	var body := _body_at(pos)
	if body:
		body.sleeping = false
		grabs[index] = {body = body, offset = body.to_local(to_global(pos)), target = pos}
	else:
		_spawn(pos)
		pours[index] = pos


func touch_move(index: int, pos: Vector2) -> void:
	if grabs.has(index):
		grabs[index].target = pos
	elif pours.has(index):
		var spacing := 34.0 * spawn_size
		if pos.distance_to(pours[index]) > spacing:
			var velocity: Vector2 = (pos - pours[index]) * 6.0
			_spawn(pos, velocity)
			pours[index] = pos


func touch_up(index: int, _pos: Vector2) -> void:
	grabs.erase(index)
	pours.erase(index)


func _physics_process(_delta: float) -> void:
	for index in grabs.keys():
		var grab: Dictionary = grabs[index]
		var body: ShapeBody = grab.body
		if not is_instance_valid(body):
			grabs.erase(index)
			continue
		var held := to_local(body.to_global(grab.offset))
		var pull: Vector2 = (grab.target - held) * 14.0
		body.linear_velocity = pull.limit_length(4000.0)
		body.angular_velocity *= 0.9
	for b: ShapeBody in bodies.get_children():
		if b.position.y > size.y + 200 or absf(b.position.x - size.x * 0.5) > size.x + 400:
			b.queue_free()
	queue_redraw()


func _draw() -> void:
	draw_backdrop(Color("121726"))
	for col: CollisionShape2D in pegs.get_children():
		draw_circle(col.position, 7.0, Color("5b6682"))
		draw_circle(col.position, 3.0, Color("aab4cf"))
	# rubber bands to grabbed shapes
	for grab in grabs.values():
		if is_instance_valid(grab.body):
			var held := to_local(grab.body.to_global(grab.offset))
			draw_line(held, grab.target, Color(1, 1, 1, 0.6), 3.0, true)
			draw_circle(grab.target, 10.0, Color(1, 1, 1, 0.25))
