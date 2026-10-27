extends RefCounted
## The one wind the Wind sim shares between everything in it. The grass and the trees work it
## out again in their shaders from the same numbers (the gust noise is the grass shader's),
## the leaves, seeds, streaks and arrows ask sample() here.
##
## The air at a point: the steady wind, raised by gusts (noise rolling downwind at gust_speed),
## stirred by turbulence (swirling noise, mostly across the wind), and pushed outward by blasts,
## rings of air running out from where a blast went off.

const BLAST_SPEED := 9.0 # m/s the ring runs out at (Grass's blast_speed)
const BLAST_LIFE := 3.0

var speed := 6.0 # m/s
var direction := 20.0 # degrees, the way it blows to (0 = +x, 90 = +z)
var gustiness := 0.6
var gust_size := 16.0
var turbulence := 0.3
var time := 0.0
var blasts: Array = [] # {at: Vector3, born: float, strength: float}


func dir() -> Vector2:
	var a := deg_to_rad(direction)
	return Vector2(cos(a), sin(a))


func gust_speed() -> float:
	return 2.0 + speed * 0.6


## Gust strength 0..1 at a point on the ground, as the grass shader works it out.
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


func blast(at: Vector3, strength: float) -> void:
	blasts.append({at = at, born = time, strength = strength})
	if blasts.size() > 4:
		blasts.pop_front()


## The blasts as the shaders take them: (x, z, TIME it went off, strength), four of them.
func blast_uniform() -> PackedVector4Array:
	var out := PackedVector4Array([Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO])
	for i in blasts.size():
		var b: Dictionary = blasts[i]
		out[i] = Vector4(b.at.x, b.at.z, b.born, b.strength)
	return out


## Keeps time with the shaders' TIME (seconds since start, rolling over hourly), so the gusts
## the leaves feel are the ones the grass shows.
func step() -> void:
	time = fmod(Time.get_ticks_msec() / 1000.0, 3600.0)
	blasts = blasts.filter(func(b: Dictionary) -> bool: return time - b.born < BLAST_LIFE)


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
