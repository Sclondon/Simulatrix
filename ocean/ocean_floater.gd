class_name OceanFloater
extends Node3D
## Floats on an OceanSurface: put whatever is to float under this node (a crate, a barrel, a
## buoy, a boat with no physics of its own) and add it to the scene. It bobs on the very waves
## the ocean draws, drifts with the water and a little with the wind, tilts with the slope,
## and splashes when it drops in from above.
##
## It is not a physics body: a spring toward its waterline, drag, the water's own motion and
## windage, worked out each frame in fixed substeps. Set `anchored` for a moored thing.

## The sea to float on; empty: the first OceanSurface in the scene (group "oceans").
@export var ocean: OceanSurface
## Half its height, m: how far its middle is from its top and its bottom.
@export var half_height := 0.5
## How much of it sits under the water at rest, 0..1 (0.5: half under).
@export_range(0.05, 1.0, 0.01) var sink := 0.45
## Moored: pulled back toward where it started.
@export var anchored := false
## How fast it turns as it drifts, radians a second.
@export var spin := 0.0
## How much the wind pushes it, against the wind speed.
@export var windage := 0.025

var velocity := Vector3.ZERO
var _anchor := Vector3.ZERO
var _above := false


func _ready() -> void:
	_anchor = global_position
	if ocean == null:
		ocean = get_tree().get_first_node_in_group("oceans") as OceanSurface
	if ocean and ocean.is_inside_tree():
		_above = global_position.y > ocean.height_at(global_position.x, global_position.z) + half_height


## How much of it is under water now, 0 (above) to 1 (all under).
func submerged() -> float:
	if ocean == null:
		return 0.0
	var p := global_position
	return clampf((ocean.height_at(p.x, p.z) - (p.y - half_height)) / (2.0 * half_height), 0.0, 1.0)


func _process(delta: float) -> void:
	if ocean == null:
		ocean = get_tree().get_first_node_in_group("oceans") as OceanSurface
		if ocean == null:
			return
	# Fixed substeps, so a slow frame does not slow the floating down or blow it up
	var steps := clampi(ceili(delta * 60.0), 1, 4)
	var dt := minf(delta, 4.0 / 60.0) / steps
	for i in steps:
		_float(dt)


func _float(dt: float) -> void:
	var p := global_position
	var v := velocity
	var w := ocean.wave_at(p.x, p.z)
	var sub := clampf((w.x - (p.y - half_height)) / (2.0 * half_height), 0.0, 1.0)
	var was_above := _above
	_above = sub <= 0.0
	if was_above and sub > 0.0 and v.y < -3.0:
		ocean.splash(p, clampf(-v.y / 10.0, 0.3, 1.2))
	var acc := Vector3(0, -OceanSurface.G, 0)
	acc.y += OceanSurface.G * sub / sink
	if sub > 0.0:
		# Water drag toward the water's own velocity, and a little push from the wind
		var wd := ocean.wind_dir()
		var water_v := Vector3(w.y, 0, w.z) + Vector3(wd.x, 0, wd.y) * ocean.wind * windage
		acc += (water_v - Vector3(v.x, 0, v.z)) * 1.8 * sub
		acc.y -= v.y * 3.2 * sub
	if anchored:
		var to := _anchor - p
		acc += Vector3(to.x, 0, to.z) * 0.6
	v += acc * dt
	p += v * dt
	global_position = p
	velocity = v
	if sub > 0.0:
		var up := ocean.normal_at(p.x, p.z)
		var yaw_now := global_rotation.y + spin * dt
		var target := Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, yaw_now)
		global_basis = global_basis.orthonormalized().slerp(target.orthonormalized(), clampf(dt * 3.0, 0.0, 1.0))
