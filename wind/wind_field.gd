class_name WindField
extends Resource
## One wind for a whole scene: a steady wind raised by gusts (noise rolling downwind at
## gust_speed()), stirred by turbulence (swirling noise, mostly across the wind), and pushed
## outward by blasts (rings of air running out from a point). Everything that should move in the
## same wind reads one WindField: sample(point) gives the air's velocity there for anything on the
## CPU (WindDebris, WindRibbons, WindFlag, a game's own things), and the shaders that sway work
## the gusts out again from the same numbers (wind_sway.gdshader for trees; GameCommon's grass has
## the same gust noise), kept set by register() and apply_grass().
##
## Save one as a .tres to keep a wind; share it between nodes by giving them the same resource.
## Time follows the shaders' TIME (seconds since start, rolling over hourly), so the gust a leaf
## feels is the one crossing the grass. Made in The Simulatrix's Wind lab (2026-10-27).

const SWAY := preload("res://wind/wind_sway.gdshader")
const BLAST_SPEED := 9.0 # m/s a blast's ring runs out at (Grass's blast_speed)
const BLAST_LIFE := 3.0

## m/s.
@export_range(0.0, 30.0, 0.5) var speed := 6.0:
	set(v): speed = v; _changed()
## Degrees: the way it blows to (0 = +x, 90 = +z).
@export_range(0.0, 360.0, 1.0) var direction := 20.0:
	set(v): direction = v; _changed()
## 0 a steady wind, 1 all in gusts.
@export_range(0.0, 1.0, 0.05) var gustiness := 0.6:
	set(v): gustiness = v; _changed()
## How wide a gust front is, m.
@export_range(2.0, 60.0, 1.0) var gust_size := 16.0:
	set(v): gust_size = v; _changed()
## Swirling eddies.
@export_range(0.0, 1.0, 0.05) var turbulence := 0.3:
	set(v): turbulence = v; _changed()

var time := 0.0
var blasts: Array = [] # {at: Vector3, born: float, strength: float}
var _materials: Array[ShaderMaterial] = []
var _grass: Array = []


func dir() -> Vector2:
	var a := deg_to_rad(direction)
	return Vector2(cos(a), sin(a))


func gust_speed() -> float:
	return 2.0 + speed * 0.6


## Gust strength 0..1 at a point on the ground, as the grass and sway shaders work it out.
func gust(xz: Vector2) -> float:
	var wd := dir()
	var g := xz / gust_size - wd * time * gust_speed() / gust_size
	var n := _noise(g) * 0.65 + _noise(g * 2.3 + Vector2(7, 7)) * 0.35
	return smoothstep(0.25, 0.85, n)


## The air's velocity (m/s) at a point.
func sample(p: Vector3) -> Vector3:
	var wd := dir()
	var xz := Vector2(p.x, p.z)
	var g := gust(xz)
	var along := speed * (0.45 + gustiness * 1.1 * g + (1.0 - gustiness) * 0.4)
	var v := Vector3(wd.x, 0, wd.y) * along
	if turbulence > 0.0:
		var q := xz * 0.35 - wd * time * 0.8
		var swirl := Vector3(
			_noise(q + Vector2(3.1, 0)) - 0.5,
			(_noise(q * 1.3 + Vector2(0, 9.2)) - 0.45) * 0.8,
			_noise(q + Vector2(0, 5.7)) - 0.5)
		v += swirl * turbulence * (2.0 + speed * 0.9)
	for b: Dictionary in blasts:
		var age: float = time - b.born
		var away: Vector3 = p - b.at
		away.y = 0.0
		var d := away.length()
		var ring := exp(-pow((d - age * BLAST_SPEED) / 2.2, 2.0))
		var fade: float = b.strength * (1.0 - smoothstep(0.0, BLAST_LIFE, age)) / (1.0 + d * 0.06)
		var out := away / maxf(d, 0.001)
		v += (out * 14.0 + Vector3.UP * 4.0) * ring * fade
	return v


## A ring of air bursting out from `at` (an explosion, a downdraught, a spell), strength about
## 0.5..3: it reaches everything reading this field, the registered shaders and the grass.
func blast(at: Vector3, strength := 1.5) -> void:
	step()
	blasts.append({at = at, born = time, strength = strength})
	if blasts.size() > 4:
		blasts.pop_front()
	var u := blast_uniform()
	for m in _materials:
		m.set_shader_parameter(&"blasts", u)
	# Grass.blast is static and reaches every field at once
	for g in _grass:
		if is_instance_valid(g) and g.has_method(&"blast"):
			g.blast(at, strength)
			break


## The blasts as the shaders take them: (x, z, TIME it went off, strength), four of them.
func blast_uniform() -> PackedVector4Array:
	var out := PackedVector4Array([Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO])
	for i in blasts.size():
		var b: Dictionary = blasts[i]
		out[i] = Vector4(b.at.x, b.at.z, b.born, b.strength)
	return out


## Keeps time with the shaders' TIME; anything sampling the field calls this each frame.
func step() -> void:
	time = fmod(Time.get_ticks_msec() / 1000.0, 3600.0)
	blasts = blasts.filter(func(b: Dictionary) -> bool: return time - b.born < BLAST_LIFE)


## A material that sways a tree in this wind (registered): GameCommon's LeafyTree sways by its
## UV2.y; anything else (a PineTree, a post) by its height, so give `height` in metres. `stiff`
## scales the push (a pine is stiffer than a willow).
func sway_material(height := 0.0, stiff := 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SWAY
	m.set_shader_parameter(&"sway_by_height", height)
	m.set_meta(&"stiff", stiff)
	register(m)
	return m


## Keeps a sway material's wind uniforms in step with this field (wind_sway.gdshader's, or any
## shader with the same names).
func register(m: ShaderMaterial) -> void:
	if not _materials.has(m):
		_materials.append(m)
	_apply(m)


## Keeps a GameCommon Grass field's wind in step with this one (its gust noise is the same).
func apply_grass(grass: Node) -> void:
	if not _grass.has(grass):
		_grass.append(grass)
	_apply_grass(grass)


func _changed() -> void:
	for m in _materials:
		_apply(m)
	for g in _grass:
		if is_instance_valid(g):
			_apply_grass(g)
	emit_changed()


func _apply(m: ShaderMaterial) -> void:
	m.set_shader_parameter(&"wind_dir", dir())
	m.set_shader_parameter(&"wind", speed * 0.065 * float(m.get_meta(&"stiff", 1.0)))
	m.set_shader_parameter(&"gust_size", gust_size)
	m.set_shader_parameter(&"gust_speed", gust_speed())
	m.set_shader_parameter(&"gustiness", gustiness)
	m.set_shader_parameter(&"turbulence", turbulence)


func _apply_grass(g: Node) -> void:
	g.set(&"wind_dir", dir())
	g.set(&"wind", speed * 0.065 * (0.6 + 0.4 * (1.0 - gustiness)))
	g.set(&"gust_size", gust_size)
	g.set(&"gust_speed", gust_speed())
	g.set(&"flutter", 0.05 + turbulence * 0.3)
	if g.has_method(&"apply_settings"):
		g.apply_settings()


static func _hash(p: Vector2) -> float:
	var q := Vector3(p.x, p.y, p.x) * 0.1031
	q = Vector3(fposmod(q.x, 1.0), fposmod(q.y, 1.0), fposmod(q.z, 1.0))
	var d := q.dot(Vector3(q.y, q.z, q.x) + Vector3.ONE * 33.33)
	q += Vector3.ONE * d
	return fposmod((q.x + q.y) * q.z, 1.0)


static func _noise(p: Vector2) -> float:
	var whole := p.floor()
	var part := p - whole
	part = part * part * (Vector2(3, 3) - 2.0 * part)
	return lerpf(lerpf(_hash(whole), _hash(whole + Vector2(1, 0)), part.x),
		lerpf(_hash(whole + Vector2(0, 1)), _hash(whole + Vector2(1, 1)), part.x), part.y)
