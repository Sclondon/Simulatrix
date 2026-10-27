class_name FireflyField
extends Node3D
## Fireflies: clouds of them out over the grass at dusk and through the night,
## how they look, fly and blink, and nothing of what they mean in a game. The
## game says where they live (`add_patch`), how dark it is (`night`) and who runs
## through them (`scarers`); they do the rest.
##
##     var fireflies := FireflyField.new()
##     add_child(fireflies)
##     fireflies.add_patch(meadow_point, 6.0, 30)      # as many patches as you like
##     fireflies.night = 1.0                           # 0 by day (none out), 1 at night
##     fireflies.scarers = [player]                    # whenever it changes
##
## WHAT THEY ARE. Lightning bugs (Lampyridae): small dark beetles, a pale shield
## over the head, dark wing cases held up as they fly, and a lantern under the
## tail that lights in cold yellow-green, each kind in its own rhythm (the shader
## says how): "big dippers" (one long flash every five to seven seconds as they
## swoop up in a J), synchronous ones (bursts of six quick flashes, all together,
## the burst rolling across the field in a wave), and a cold green kind that
## glows slowly on and off. They rise from the grass as it gets dark (each at its
## own darkness), drift low and slow about where they live, scatter flashing from
## anyone who runs through them, and drift back.
##
## THE COST is kept small: every firefly is moved and blinked in the shader. Those
## within `draw_range` of the camera (at most `max_drawn`) are one MultiMesh of
## glows (one draw); the few within `body_range` are a second of beetles; they are
## written again only when the camera has moved `refill_step` metres. By day
## (`night` 0) nothing is drawn. `lights` OmniLights (0 by default) give a little
## real light, at the patches nearest the camera.
##
## Seeded by each patch's seed: two machines that make the same patches get the same fireflies.

const MODEL := "res://creatures/fireflies/models/firefly.glb"
const SHADER := preload("res://creatures/fireflies/firefly.gdshader")
## The beetle's parts, by material, as the shader numbers them.
const PARTS := {"head": 0, "shield": 1, "elytra": 2, "abdomen": 3, "lantern": 4, "wing": 5, "leg": 6}

## How dark it is: 0 by day (none are out), 1 at night (all of them).
@export_range(0.0, 1.0) var night := 1.0
## The most drawn at once, and how far from the camera.
@export var max_drawn := 700
@export var draw_range := 65.0
## Nearer the camera than this, the beetles themselves are drawn (the closest `max_bodies`).
@export var body_range := 7.0
@export var max_bodies := 48
## The camera moves this far, and the near ones are found again.
@export var refill_step := 8.0
## A firefly's length, metres, and its glow's (least, most: each its own).
@export var size := Vector2(0.012, 0.018)
@export var halo_size := 0.2
@export var brightness := 1.0
## How far their glow carries in the mist (the fraction lost each metre).
@export var mist := 0.022
## How near someone must be, running, to scatter them, metres.
@export var scatter_reach := 2.6
## OmniLights at the nearest patches (0: none: they are only seen, they light nothing).
@export_range(0, 4) var lights := 0
@export var light_range := 4.0
@export var light_energy := 0.35
## The share of each kind where nothing else is said: big dippers, synchronous, cold green.
@export var kinds := Vector3(0.5, 0.3, 0.2)

## Who scatters them (Node3D's, up to four): running through, more than walking.
var scarers: Array = []

## How long the last refill took, microseconds; how many are drawn.
var cost := 0
var drawn := 0
var bodies_drawn := 0

## Each patch: [middle, radius, homes (PackedVector3Array), customs (PackedFloat32Array, 4 each), sizes (PackedFloat32Array)].
var _patches: Array = []
var _glows: MultiMeshInstance3D
var _bodies: MultiMeshInstance3D
var _glow_material: ShaderMaterial
var _body_material: ShaderMaterial
var _filled_at := Vector3.INF
var _bodies_at := Vector3.INF
var _dirty := true
var _scare := PackedFloat32Array()
var _scarer_was := {}
var _near_in := 0.0
var _lights: Array[OmniLight3D] = []
var _light_patches: Array = []
# What is drawn now (for the beetles near): the homes and their custom data.
var _drawn_homes := PackedVector3Array()
var _drawn_customs := PackedFloat32Array()
var _drawn_sizes := PackedFloat32Array()

static var _halo_mesh: ArrayMesh
static var _body_mesh: ArrayMesh


func _ready() -> void:
	_glow_material = ShaderMaterial.new()
	_glow_material.shader = SHADER
	_body_material = ShaderMaterial.new()
	_body_material.shader = SHADER
	_body_material.set_shader_parameter(&"is_body", true)
	_glows = _many("Glows", halo_mesh(), _glow_material, max_drawn)
	_bodies = _many("Beetles", body_mesh(), _body_material, max_bodies)
	_scare.resize(4)
	for k in lights:
		var light := OmniLight3D.new()
		light.name = "Light%d" % k
		light.light_color = Color(0.72, 1.0, 0.5)
		light.omni_range = light_range
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.top_level = true
		add_child(light)
		_lights.append(light)
	_uniforms()


func _many(named: String, mesh: Mesh, material: ShaderMaterial, most: int) -> MultiMeshInstance3D:
	var shown := MultiMeshInstance3D.new()
	shown.name = named
	shown.top_level = true
	shown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shown.material_override = material
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.use_custom_data = true
	many.mesh = mesh
	many.instance_count = maxi(most, 1)
	many.visible_instance_count = 0
	shown.multimesh = many
	add_child(shown)
	shown.global_transform = Transform3D.IDENTITY
	return shown


## Puts in a patch of `count` fireflies living round `middle` (on the ground, or
## over water), out to `radius`, flying `heights` (least, most metres) over where
## they rose from. `ground` (optional Callable(Vector3) -> float) is how high the
## ground is under each, if it is not level. `mix` the share of each kind (big
## dippers, synchronous, cold green; ZERO: `kinds`). Returns its number.
func add_patch(middle: Vector3, radius: float, count: int, heights := Vector2(0.25, 1.6), patch_seed := 0, ground := Callable(), mix := Vector3.ZERO) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = patch_seed if patch_seed != 0 else hash(str(middle.snapped(Vector3.ONE * 0.1)))
	var shares := mix if mix != Vector3.ZERO else kinds
	shares /= maxf(shares.x + shares.y + shares.z, 0.001)
	var homes := PackedVector3Array()
	var customs := PackedFloat32Array()
	var sizes := PackedFloat32Array()
	for i in count:
		var spot := Vector2.from_angle(rng.randf() * TAU) * radius * sqrt(rng.randf())
		var home := middle + Vector3(spot.x, 0.0, spot.y)
		if ground.is_valid():
			home.y = float(ground.call(home))
		homes.append(home)
		var pick := rng.randf()
		var kind := 0.0 if pick < shares.x else (1.0 if pick < shares.x + shares.y else 2.0)
		# (who it is; its kind; how dark before it comes out; how high it flies: most of them low)
		customs.append(rng.randf())
		customs.append(kind)
		customs.append(rng.randf_range(0.0, 0.75))
		customs.append(lerpf(heights.x, heights.y, pow(rng.randf(), 1.6)))
		sizes.append(rng.randf_range(size.x, size.y))
	_patches.append([middle, radius, homes, customs, sizes])
	_dirty = true
	return _patches.size() - 1


## Takes every patch away.
func clear_patches() -> void:
	_patches.clear()
	_dirty = true


## How many fireflies there are in all.
func total() -> int:
	var n := 0
	for patch: Array in _patches:
		n += (patch[2] as PackedVector3Array).size()
	return n


## How many patches there are.
func patch_count() -> int:
	return _patches.size()


## The middle of patch `k`.
func patch_middle(k: int) -> Vector3:
	return _patches[k][0]


## Whether any are drawn now (it is dark enough, and some are near the camera).
func showing() -> bool:
	return _glows != null and _glows.visible and drawn > 0


func _process(delta: float) -> void:
	var dark := night > 0.001 and not _patches.is_empty()
	_glows.visible = dark
	_bodies.visible = dark and bodies_drawn > 0
	for light in _lights:
		light.visible = dark
	if not dark:
		return
	var camera := get_viewport().get_camera_3d()
	var eye := camera.global_position if camera else global_position
	if _dirty or not _filled_at.is_finite() or eye.distance_to(_filled_at) > refill_step:
		_fill(eye)
	_near_in -= delta
	if _near_in <= 0.0:
		_near_in = 0.2
		if not _bodies_at.is_finite() or eye.distance_to(_bodies_at) > 0.8:
			_fill_bodies(eye)
		_place_lights(eye)
	_watch_scarers(delta)
	_uniforms()


func _uniforms() -> void:
	var scaring: Array[Vector4] = []
	for k in 4:
		var who: Node3D = scarers[k] if k < scarers.size() and is_instance_valid(scarers[k]) else null
		scaring.append(Vector4(who.global_position.x, who.global_position.y, who.global_position.z, _scare[k]) if who and who.is_inside_tree() else Vector4.ZERO)
	for material: ShaderMaterial in [_glow_material, _body_material]:
		material.set_shader_parameter(&"night", night)
		material.set_shader_parameter(&"scarers", scaring)
		material.set_shader_parameter(&"brightness", brightness)
		material.set_shader_parameter(&"halo_size", halo_size)
		material.set_shader_parameter(&"mist", mist)
		material.set_shader_parameter(&"far", draw_range)
		material.set_shader_parameter(&"scatter_reach", scatter_reach)


# How hard each scarer scatters them: running hard, fully; it dies away when he
# slows or stops (and they drift back).
func _watch_scarers(delta: float) -> void:
	for k in 4:
		var who: Node3D = scarers[k] if k < scarers.size() and is_instance_valid(scarers[k]) else null
		if who == null or not who.is_inside_tree():
			_scare[k] = 0.0
			continue
		var at := who.global_position
		var was: Vector3 = _scarer_was.get(k, at)
		_scarer_was[k] = at
		var speed := Vector2(at.x - was.x, at.z - was.z).length() / maxf(delta, 0.001)
		var wish := smoothstep(0.8, 4.5, speed)
		_scare[k] = move_toward(_scare[k], wish, delta * (4.0 if wish > _scare[k] else 0.35))


# Writes in the fireflies of the patches nearest `eye`, nearest first, up to `max_drawn`.
func _fill(eye: Vector3) -> void:
	var started := Time.get_ticks_usec()
	_filled_at = eye
	_dirty = false
	var near: Array = []
	for k in _patches.size():
		var patch: Array = _patches[k]
		var middle: Vector3 = patch[0]
		var d := Vector2(middle.x - eye.x, middle.z - eye.z).length() - float(patch[1])
		if d < draw_range:
			near.append([d, k])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var buffer := PackedFloat32Array()
	buffer.resize(max_drawn * 16)
	_drawn_homes = PackedVector3Array()
	_drawn_customs = PackedFloat32Array()
	_drawn_sizes = PackedFloat32Array()
	var n := 0
	var low := Vector3.INF
	var high := -Vector3.INF
	for entry: Array in near:
		var patch: Array = _patches[entry[1]]
		var homes: PackedVector3Array = patch[2]
		var customs: PackedFloat32Array = patch[3]
		var sizes: PackedFloat32Array = patch[4]
		for i in homes.size():
			if n >= max_drawn:
				break
			_write(buffer, n, homes[i], sizes[i], customs, i)
			_drawn_homes.append(homes[i])
			_drawn_sizes.append(sizes[i])
			for c in 4:
				_drawn_customs.append(customs[i * 4 + c])
			low = low.min(homes[i])
			high = high.max(homes[i])
			n += 1
	drawn = n
	var many := _glows.multimesh
	many.buffer = buffer
	many.visible_instance_count = n
	if n > 0:
		# (they fly up to a few metres off their homes, and the glow is bigger than they are)
		many.custom_aabb = AABB(low - Vector3(4.0, 1.0, 4.0), high - low + Vector3(8.0, 8.0, 8.0))
	_bodies_at = Vector3.INF
	cost = Time.get_ticks_usec() - started


func _write(buffer: PackedFloat32Array, n: int, home: Vector3, scale_: float, customs: PackedFloat32Array, i: int) -> void:
	var k := n * 16
	buffer[k] = scale_
	buffer[k + 1] = 0.0
	buffer[k + 2] = 0.0
	buffer[k + 3] = home.x
	buffer[k + 4] = 0.0
	buffer[k + 5] = scale_
	buffer[k + 6] = 0.0
	buffer[k + 7] = home.y
	buffer[k + 8] = 0.0
	buffer[k + 9] = 0.0
	buffer[k + 10] = scale_
	buffer[k + 11] = home.z
	for c in 4:
		buffer[k + 12 + c] = customs[i * 4 + c]


# The beetles of those whose homes are nearest the camera (they wander a couple of
# metres off them, so a little further than `body_range`).
func _fill_bodies(eye: Vector3) -> void:
	_bodies_at = eye
	var reach := body_range + 2.5
	var found: Array = []
	for i in _drawn_homes.size():
		var d := _drawn_homes[i].distance_squared_to(eye)
		if d < reach * reach:
			found.append([d, i])
	if found.size() > max_bodies:
		found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		found.resize(max_bodies)
	var buffer := PackedFloat32Array()
	buffer.resize(max_bodies * 16)
	for n in found.size():
		var i: int = found[n][1]
		_write(buffer, n, _drawn_homes[i], _drawn_sizes[i], _drawn_customs, i)
	bodies_drawn = found.size()
	_bodies.multimesh.buffer = buffer
	_bodies.multimesh.visible_instance_count = bodies_drawn
	if bodies_drawn > 0:
		_bodies.multimesh.custom_aabb = AABB(eye - Vector3.ONE * (reach + 3.0), Vector3.ONE * (reach + 3.0) * 2.0)


# A little real light at the patches nearest the camera, pulsing gently.
func _place_lights(eye: Vector3) -> void:
	if _lights.is_empty():
		return
	var near: Array = []
	for k in _patches.size():
		var middle: Vector3 = _patches[k][0]
		near.append([middle.distance_squared_to(eye), k])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for j in _lights.size():
		var light := _lights[j]
		if j >= near.size():
			light.light_energy = 0.0
			continue
		var middle: Vector3 = _patches[near[j][1]][0]
		light.global_position = middle + Vector3.UP * 0.9
		var beat := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.0021 + j * 2.0)
		light.light_energy = light_energy * smoothstep(0.2, 0.8, night) * beat


# --- The meshes ---

## A glow's quad (its corners in UV), one for everybody.
static func halo_mesh() -> ArrayMesh:
	if _halo_mesh == null:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var corners := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]
		for c: Vector2 in corners:
			tool.set_uv(c)
			tool.set_uv2(Vector2.ZERO)
			tool.add_vertex(Vector3(c.x - 0.5, c.y - 0.5, 0.0))
		tool.index()
		_halo_mesh = tool.commit()
	return _halo_mesh


## The beetle (FireflyField's model), its parts in UV2.x, one for everybody.
static func body_mesh() -> ArrayMesh:
	if _body_mesh == null:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var scene := load(MODEL) as PackedScene
		if scene == null:
			push_error("FireflyField: no model at %s (build it with creatures/fireflies/tools/build_firefly.py)" % MODEL)
		else:
			var model := scene.instantiate()
			for piece: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
				var from := piece.mesh as ArrayMesh
				for surface in from.get_surface_count():
					var paint := from.surface_get_material(surface)
					var part: int = PARTS.get(paint.resource_name if paint else "head", 0)
					var arrays := from.surface_get_arrays(surface)
					var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					var order: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
					var count := order.size() if not order.is_empty() else points.size()
					for i in count:
						var k := order[i] if not order.is_empty() else i
						tool.set_uv(Vector2.ZERO)
						tool.set_uv2(Vector2(part, 0.0))
						tool.add_vertex(points[k])
			model.free()
		tool.index()
		_body_mesh = tool.commit()
	return _body_mesh
