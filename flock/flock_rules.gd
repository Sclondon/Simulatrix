class_name FlockRules
extends Resource
## Every behaviour setting of a Flock (boids), in one Resource: save one as a .tres to keep a
## flock's character, and share it between flocks. Everything is read live each frame, so a
## change shows at once; changing `count`, `body` or `size` rebuilds the boids.
##
## Distances are metres, speeds m/s, forces m/s². The weights are unitless: 1 is a usual
## amount, 0 is off. Presets: starlings(), fish_school(), bats(), crows_circling(), gnats(),
## sheep(), or preset(name) with a name from PRESETS.

## Wings beat (birds, bats, bugs), a tail swishes (fish), legs walk (herds), or nothing.
enum Motion { FLAP, SWIM, WALK, NONE }
## The built-in bodies; CUSTOM draws Flock.custom_mesh (its +x/-x are wings, -z is its nose).
enum Body { BIRD, FISH, BAT, BUG, SHEEP, CUSTOM }
## Where they stay: a box, a sphere (radius bounds_size.x), or a ground layer (a box across
## the ground with no top or bottom: the height is the ground clearance and ceiling's job).
enum Bounds { BOX, SPHERE, LAYER }

const PRESETS := ["Starlings", "Fish school", "Bats", "Crows circling", "Gnats", "Sheep"]

@export_group("Flock")
@export_range(1, 3000) var count := 300
@export var body := Body.BIRD
@export var motion := Motion.FLAP
## Body length, metres.
@export_range(0.01, 10.0, 0.01) var size := 0.25
## Each boid's size is size × (1 ± this).
@export_range(0.0, 0.8, 0.01) var size_variation := 0.15
@export var colour := Color(0.12, 0.11, 0.13)
## How much lighter or darker one boid is than another.
@export_range(0.0, 1.0, 0.01) var colour_variation := 0.15
## Moves on the ground (or one level), never up or down: herds, things on a table.
@export var planar := false

@export_group("Speed")
@export_range(0.0, 60.0, 0.1) var max_speed := 14.0
@export_range(0.0, 60.0, 0.1) var min_speed := 6.0
## The speed it settles to when nothing is going on.
@export_range(0.0, 60.0, 0.1) var cruise_speed := 10.0
## How hard it can steer (m/s²): low, wide lazy turns; high, darting.
@export_range(0.1, 200.0, 0.1) var max_force := 18.0
## Each boid's cruise is cruise × (1 ± this): some are a little faster than others.
@export_range(0.0, 0.5, 0.01) var speed_variation := 0.08

@export_group("Senses")
## How far it sees its neighbours.
@export_range(0.1, 50.0, 0.1) var perception := 3.0
## How wide it sees, degrees (360: all round; starlings ~300, fish ~330).
@export_range(10.0, 360.0, 1.0) var field_of_view := 290.0
## The most neighbours it heeds (starlings heed their 6-7 nearest, Ballerini et al. 2008).
@export_range(1, 64) var max_neighbours := 7

@export_group("Rules")
## Keep clear of neighbours closer than separation_distance.
@export_range(0.0, 10.0, 0.01) var separation := 1.5
@export_range(0.01, 20.0, 0.01) var separation_distance := 0.8
## Fly the way the neighbours fly.
@export_range(0.0, 10.0, 0.01) var alignment := 1.0
## Make for the middle of the neighbours.
@export_range(0.0, 10.0, 0.01) var cohesion := 0.8
## A slowly turning urge of its own (noise): 0 machine-like, 1+ restless.
@export_range(0.0, 5.0, 0.01) var wander := 0.3
## How fast that urge turns (per second).
@export_range(0.0, 20.0, 0.1) var wander_rate := 1.5
## How much of a neighbour's fright it catches (0..1): high gives the ripples that run
## through a murmuration when a hawk comes in.
@export_range(0.0, 1.0, 0.01) var alarm_spread := 0.6
## A pull toward the middle of the whole flock, so a big flock stays one body instead of
## breaking into clumps (each boid sees only a few neighbours, so cohesion alone cannot hold
## hundreds together).
@export_range(0.0, 5.0, 0.01) var gather := 0.0

@export_group("Bounds")
@export var bounds := Bounds.BOX
## Half extents round the Flock node (SPHERE uses x as the radius).
@export var bounds_size := Vector3(30, 10, 30)
## They start turning back this far inside the edge.
@export_range(0.0, 50.0, 0.1) var bounds_margin := 8.0
## How hard they turn back.
@export_range(0.0, 10.0, 0.01) var bounds_force := 1.5

@export_group("Ground")
@export var avoid_ground := true
## The least height they keep above the ground (planar: the height they move at).
@export_range(0.0, 100.0, 0.1) var ground_clearance := 3.0
## The most height above the ground (0: no ceiling but the bounds).
@export_range(0.0, 500.0, 0.1) var ceiling := 0.0

@export_group("Goal")
## Pull towards Flock.target.
@export_range(0.0, 10.0, 0.01) var seek := 0.4
## Within this of the target the pull fades: they mill about it instead of piling onto it.
@export_range(0.0, 50.0, 0.1) var arrive_radius := 6.0
## Circling the target (crows, vultures, a bait ball): sideways pull round it.
@export_range(0.0, 10.0, 0.01) var orbit := 0.0
@export_range(0.0, 100.0, 0.1) var orbit_radius := 12.0

@export_group("Predators")
@export_range(0.0, 20.0, 0.01) var flee := 3.0
@export_range(0.0, 100.0, 0.1) var flee_radius := 8.0
## Top speed when frightened, × max_speed.
@export_range(1.0, 4.0, 0.01) var panic_speed := 1.5
## How fast a fright wears off (per second).
@export_range(0.05, 5.0, 0.01) var calm_rate := 0.6

@export_group("Obstacles")
@export_range(0.0, 20.0, 0.01) var avoid := 3.0
## Seconds ahead they look for something to miss.
@export_range(0.0, 5.0, 0.01) var look_ahead := 0.8

@export_group("Motion")
## How far they roll into turns (0..1 of a real banked turn).
@export_range(0.0, 1.5, 0.01) var banking := 0.8
@export_range(0.0, 90.0, 1.0) var max_bank := 60.0
## Wingbeats (or tail beats, or strides) a second.
@export_range(0.0, 60.0, 0.1) var flap_rate := 10.0
## How wide: radians for wings, a share of the length for tails and legs.
@export_range(0.0, 1.5, 0.01) var flap_amount := 0.7
## Share of the time spent gliding between bursts of beats (0: always flapping).
@export_range(0.0, 1.0, 0.01) var glide := 0.25
## How much a wind (Flock.wind) carries them: 1 drifts with the air, 0 ignores it.
@export_range(0.0, 2.0, 0.01) var wind_carry := 0.3


## A copy set to one of the PRESETS by name (or index).
static func preset(which: Variant) -> FlockRules:
	var name: String = PRESETS[which] if which is int else str(which)
	match name:
		"Fish school": return fish_school()
		"Bats": return bats()
		"Crows circling": return crows_circling()
		"Gnats": return gnats()
		"Sheep": return sheep()
	return starlings()


## A murmuration: hundreds of small dark birds in one shape-shifting cloud, each heeding its
## seven nearest, fast, tight, quick to take fright and to pass it on.
static func starlings() -> FlockRules:
	var r := FlockRules.new()
	r.count = 800
	r.body = Body.BIRD
	r.motion = Motion.FLAP
	r.size = 0.36
	r.colour = Color(0.1, 0.09, 0.11)
	r.max_speed = 16.0
	r.min_speed = 9.0
	r.cruise_speed = 12.5
	r.max_force = 22.0
	r.perception = 3.5
	r.field_of_view = 300.0
	r.max_neighbours = 7
	r.separation = 2.5
	r.separation_distance = 1.0
	r.alignment = 1.8
	r.cohesion = 2.2
	r.wander = 0.25
	r.alarm_spread = 0.85
	r.gather = 0.6
	r.bounds = Bounds.SPHERE
	r.bounds_size = Vector3(26, 26, 26)
	r.bounds_margin = 8.0
	r.bounds_force = 1.2
	r.ground_clearance = 8.0
	r.seek = 0.6
	r.arrive_radius = 6.0
	r.flee = 4.0
	r.flee_radius = 10.0
	r.panic_speed = 1.4
	r.flap_rate = 12.0
	r.flap_amount = 0.75
	r.glide = 0.3
	return r


## A school: silver fish that keep close, line up hard and turn together.
static func fish_school() -> FlockRules:
	var r := FlockRules.new()
	r.count = 220
	r.body = Body.FISH
	r.motion = Motion.SWIM
	r.size = 0.32
	r.size_variation = 0.12
	r.colour = Color(0.85, 0.9, 0.95)
	r.colour_variation = 0.12
	r.max_speed = 4.5
	r.min_speed = 1.2
	r.cruise_speed = 2.4
	r.max_force = 6.0
	r.perception = 2.0
	r.field_of_view = 330.0
	r.max_neighbours = 9
	r.separation = 1.4
	r.separation_distance = 0.4
	r.alignment = 1.8
	r.cohesion = 1.5
	r.wander = 0.2
	r.wander_rate = 0.8
	r.alarm_spread = 0.7
	r.gather = 0.4
	r.bounds = Bounds.SPHERE
	r.bounds_size = Vector3(8, 8, 8)
	r.bounds_margin = 4.0
	r.bounds_force = 1.2
	r.ground_clearance = 1.0
	r.seek = 0.3
	r.arrive_radius = 3.0
	r.flee = 5.0
	r.flee_radius = 4.0
	r.panic_speed = 2.0
	r.calm_rate = 0.5
	r.avoid = 4.0
	r.look_ahead = 1.0
	r.banking = 0.25
	r.max_bank = 25.0
	r.flap_rate = 2.2
	r.flap_amount = 0.22
	r.glide = 0.0
	r.wind_carry = 0.0
	return r


## Bats: a loose, jittery crowd, each darting after insects of its own.
static func bats() -> FlockRules:
	var r := FlockRules.new()
	r.count = 120
	r.body = Body.BAT
	r.motion = Motion.FLAP
	r.size = 0.36
	r.size_variation = 0.2
	r.colour = Color(0.16, 0.12, 0.12)
	r.max_speed = 9.0
	r.min_speed = 3.5
	r.cruise_speed = 6.0
	r.max_force = 30.0
	r.perception = 3.0
	r.field_of_view = 250.0
	r.max_neighbours = 5
	r.separation = 2.0
	r.separation_distance = 1.4
	r.alignment = 0.35
	r.cohesion = 0.45
	r.wander = 1.6
	r.wander_rate = 6.0
	r.alarm_spread = 0.3
	r.bounds = Bounds.BOX
	r.bounds_size = Vector3(16, 8, 16)
	r.bounds_margin = 5.0
	r.bounds_force = 2.0
	r.ground_clearance = 2.5
	r.seek = 0.2
	r.flee = 3.0
	r.flee_radius = 6.0
	r.banking = 1.0
	r.max_bank = 75.0
	r.flap_rate = 9.0
	r.flap_amount = 0.95
	r.glide = 0.05
	return r


## A murder of crows wheeling round a point, high and slow, rowing and gliding.
static func crows_circling() -> FlockRules:
	var r := FlockRules.new()
	r.count = 40
	r.body = Body.BIRD
	r.motion = Motion.FLAP
	r.size = 0.55
	r.size_variation = 0.1
	r.colour = Color(0.07, 0.07, 0.08)
	r.colour_variation = 0.08
	r.max_speed = 9.0
	r.min_speed = 5.0
	r.cruise_speed = 7.0
	r.max_force = 7.0
	r.perception = 8.0
	r.field_of_view = 300.0
	r.max_neighbours = 6
	r.separation = 1.8
	r.separation_distance = 3.0
	r.alignment = 0.6
	r.cohesion = 0.3
	r.wander = 0.4
	r.wander_rate = 0.6
	r.alarm_spread = 0.5
	r.bounds = Bounds.LAYER
	r.bounds_size = Vector3(40, 20, 40)
	r.bounds_margin = 10.0
	r.ground_clearance = 9.0
	r.ceiling = 22.0
	r.seek = 0.3
	r.arrive_radius = 10.0
	r.orbit = 1.2
	r.orbit_radius = 11.0
	r.flee = 2.5
	r.flee_radius = 8.0
	r.banking = 1.0
	r.max_bank = 50.0
	r.flap_rate = 3.2
	r.flap_amount = 0.6
	r.glide = 0.55
	return r


## Gnats: a cloud of specks dancing round one spot, never lining up.
static func gnats() -> FlockRules:
	var r := FlockRules.new()
	r.count = 260
	r.body = Body.BUG
	r.motion = Motion.FLAP
	r.size = 0.035
	r.size_variation = 0.25
	r.colour = Color(0.12, 0.1, 0.08)
	r.max_speed = 2.2
	r.min_speed = 0.4
	r.cruise_speed = 1.1
	r.max_force = 14.0
	r.perception = 0.35
	r.field_of_view = 360.0
	r.max_neighbours = 4
	r.separation = 1.0
	r.separation_distance = 0.08
	r.alignment = 0.0
	r.cohesion = 0.2
	r.wander = 2.2
	r.wander_rate = 10.0
	r.alarm_spread = 0.2
	r.bounds = Bounds.SPHERE
	r.bounds_size = Vector3(1.5, 1.5, 1.5)
	r.bounds_margin = 0.6
	r.bounds_force = 1.5
	r.ground_clearance = 0.4
	r.seek = 1.6
	r.arrive_radius = 0.6
	r.flee = 3.0
	r.flee_radius = 0.8
	r.panic_speed = 2.0
	r.calm_rate = 1.5
	r.avoid = 2.0
	r.look_ahead = 0.3
	r.banking = 0.0
	r.flap_rate = 40.0
	r.flap_amount = 0.9
	r.glide = 0.0
	r.wind_carry = 0.8
	return r


## A herd (sheep) on the ground: slow, close, ambling and stopping to graze, bunching and
## bolting when a dog comes.
static func sheep() -> FlockRules:
	var r := FlockRules.new()
	r.count = 60
	r.body = Body.SHEEP
	r.motion = Motion.WALK
	r.planar = true
	r.size = 1.1
	r.size_variation = 0.12
	r.colour = Color(0.93, 0.9, 0.82)
	r.colour_variation = 0.1
	r.max_speed = 4.0
	r.min_speed = 0.0
	r.cruise_speed = 0.35
	r.max_force = 4.0
	r.perception = 5.0
	r.field_of_view = 320.0
	r.max_neighbours = 8
	r.separation = 2.2
	r.separation_distance = 1.5
	r.alignment = 0.4
	r.cohesion = 0.7
	r.wander = 0.5
	r.wander_rate = 0.4
	r.alarm_spread = 0.75
	r.gather = 0.15
	r.bounds = Bounds.LAYER
	r.bounds_size = Vector3(22, 5, 22)
	r.bounds_margin = 5.0
	r.bounds_force = 1.2
	r.ground_clearance = 0.0
	r.seek = 0.3
	r.arrive_radius = 4.0
	r.flee = 4.0
	r.flee_radius = 9.0
	r.panic_speed = 1.0
	r.calm_rate = 0.35
	r.avoid = 4.0
	r.look_ahead = 1.2
	r.banking = 0.0
	r.flap_rate = 1.8
	r.flap_amount = 0.5
	r.glide = 0.0
	r.wind_carry = 0.0
	return r
