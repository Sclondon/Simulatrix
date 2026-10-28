@tool
class_name RopeStyle
extends Resource
## How a rope behaves and looks: everything a RopeLine (or a RopePatch of them) needs bar its
## length and where it hangs. Share one style between many ropes; change it at run time and
## every rope using it follows at once (it emits `changed`). Save one as a .tres to keep it.
##
## One kind of thing covers ropes, vines, kelp, bouncy wires and chains: a chain of points
## (Verlet, held apart by distance constraints) pulled by gravity (negative floats it up, as
## kelp stands in the sea), dragged towards the water or air moving round it (a current with
## travelling gusts and a to-and-fro surge, or a GameCommon WindField), with bend stiffness
## and stretch (0 rigid, up to a wire that bounces like Hemlock's Tower's tightropes). Drawn
## as a tapering tube with a colour gradient and leaves (a vine's, kelp blades or grass-like
## blades) placed, swept by the flow and fluttered by the GPU.

enum Leaf { NONE, VINE, KELP, BLADE }

const MAX_PIECES := 24

# --- Physics -----------------------------------------------------------------

## How many pieces the chain is made of (4..24). More bends more smoothly and costs more.
@export_range(4, 24, 1) var pieces := 16:
	set(v): pieces = clampi(v, 4, MAX_PIECES); emit_changed()
## m/s² down; negative is buoyancy (kelp stands up from the seabed).
@export_range(-20.0, 30.0, 0.1) var gravity := 9.8:
	set(v): gravity = v; emit_changed()
## Per second: how quickly it takes up the speed of the air or water round it (and how
## quickly a swing dies away in still air).
@export_range(0.0, 8.0, 0.05) var drag := 0.4:
	set(v): drag = v; emit_changed()
## 0 limp, 1 stiff as a cane.
@export_range(0.0, 1.0, 0.01) var bend := 0.1:
	set(v): bend = v; emit_changed()
## 0 does not stretch; up to 1, a rubbery wire that dips and throws back what lands on it.
@export_range(0.0, 1.0, 0.01) var stretch := 0.0:
	set(v): stretch = v; emit_changed()
## Solver passes a step: more holds it to its length better under load.
@export_range(1, 24, 1) var iterations := 6:
	set(v): iterations = clampi(v, 1, 24); emit_changed()
## Degrees round from +x towards +z the current flows to.
@export_range(0.0, 360.0, 1.0) var current_direction := 0.0:
	set(v): current_direction = v; emit_changed()
## m/s of steady current (or breeze).
@export_range(0.0, 5.0, 0.05) var current := 0.0:
	set(v): current = v; emit_changed()
## m/s of to-and-fro along the current (the swell's surge on a kelp forest), and its period.
@export_range(0.0, 3.0, 0.05) var surge := 0.0:
	set(v): surge = v; emit_changed()
@export_range(1.0, 20.0, 0.5) var surge_period := 7.0:
	set(v): surge_period = v; emit_changed()
## m/s of gusts: 3D noise rolling along the current, so waves cross a forest of them.
@export_range(0.0, 5.0, 0.05) var gusts := 0.0:
	set(v): gusts = v; emit_changed()
## How big a gust is, m, and how fast gusts travel, m/s.
@export_range(1.0, 40.0, 0.5) var gust_size := 8.0:
	set(v): gust_size = v; emit_changed()
@export_range(0.0, 10.0, 0.1) var gust_speed := 2.0:
	set(v): gust_speed = v; emit_changed()
## How much a WindField's wind (RopeLine.field) moves it.
@export_range(0.0, 2.0, 0.05) var wind_response := 1.0:
	set(v): wind_response = v; emit_changed()

# --- Look ---------------------------------------------------------------------

## Radius at the root and at the tip, m, and how the one runs into the other (1 evenly,
## more keeps it thick for longer then tapers late).
@export_range(0.002, 0.3, 0.001) var thickness_root := 0.03:
	set(v): thickness_root = v; emit_changed()
@export_range(0.0, 0.3, 0.001) var thickness_tip := 0.03:
	set(v): thickness_tip = v; emit_changed()
@export_range(0.2, 4.0, 0.05) var taper := 1.0:
	set(v): taper = v; emit_changed()
@export var colour_root := Color(0.55, 0.45, 0.3):
	set(v): colour_root = v; emit_changed()
@export var colour_tip := Color(0.5, 0.41, 0.27):
	set(v): colour_tip = v; emit_changed()
## Strands twisted round it (a laid rope), 0..1 how strongly they show.
@export_range(0.0, 1.0, 0.01) var twist := 0.0:
	set(v): twist = v; emit_changed()
## Pinched into beads or links (a chain, a string of pearls), 0..1.
@export_range(0.0, 1.0, 0.01) var beads := 0.0:
	set(v): beads = v; emit_changed()
## A knot at the free end, 0..1 of its size.
@export_range(0.0, 1.0, 0.01) var knot := 0.0:
	set(v): knot = v; emit_changed()
## 0 matt, 1 glossy (wire, wet kelp).
@export_range(0.0, 1.0, 0.01) var shine := 0.0:
	set(v): shine = v; emit_changed()
## Sides round the tube.
@export_range(3, 12, 1) var sides := 6:
	set(v): sides = clampi(v, 3, 12); emit_changed()

# --- Leaves -------------------------------------------------------------------

@export var leaf_kind := Leaf.NONE:
	set(v): leaf_kind = v; emit_changed()
## Leaves for each metre of it.
@export_range(0.0, 60.0, 0.5) var leaves_per_metre := 0.0:
	set(v): leaves_per_metre = v; emit_changed()
## How long a leaf is, m.
@export_range(0.02, 2.0, 0.01) var leaf_size := 0.2:
	set(v): leaf_size = v; emit_changed()
## Where along it (0 root, 1 tip) leaves grow.
@export_range(0.0, 1.0, 0.01) var leaf_from := 0.0:
	set(v): leaf_from = v; emit_changed()
@export_range(0.0, 1.0, 0.01) var leaf_to := 1.0:
	set(v): leaf_to = v; emit_changed()
## A share more bunched round the root, where it is held (a vine's top).
@export_range(0.0, 1.0, 0.01) var leaf_bunch := 0.0:
	set(v): leaf_bunch = v; emit_changed()
@export var leaf_colour_root := Color(0.19, 0.31, 0.14):
	set(v): leaf_colour_root = v; emit_changed()
@export var leaf_colour_tip := Color(0.24, 0.36, 0.15):
	set(v): leaf_colour_tip = v; emit_changed()
## How much each leaf's shade differs, 0..1.
@export_range(0.0, 1.0, 0.01) var leaf_vary := 0.4:
	set(v): leaf_vary = v; emit_changed()
## Degrees out from along the stem a leaf stands at rest (0 lies along it, 90 straight out).
@export_range(0.0, 120.0, 1.0) var leaf_lean := 45.0:
	set(v): leaf_lean = v; emit_changed()
## How much a leaf hangs with gravity (or floats up, buoyant), 0..1.
@export_range(0.0, 1.0, 0.01) var leaf_droop := 0.2:
	set(v): leaf_droop = v; emit_changed()
## How much a leaf streams out in the flow past it, 0..1.
@export_range(0.0, 1.0, 0.01) var leaf_stream := 0.3:
	set(v): leaf_stream = v; emit_changed()
## How much a leaf flutters, 0..1.
@export_range(0.0, 1.0, 0.01) var leaf_flutter := 0.15:
	set(v): leaf_flutter = v; emit_changed()
## How much a long leaf curves along its length into the flow, 0..1.
@export_range(0.0, 1.0, 0.01) var leaf_curl := 0.0:
	set(v): leaf_curl = v; emit_changed()
## Ruffled edges rippling along a blade (kelp), 0..1.
@export_range(0.0, 1.0, 0.01) var leaf_ruffle := 0.0:
	set(v): leaf_ruffle = v; emit_changed()


## The current's heading on the ground (x, z), unit length.
func current_dir() -> Vector3:
	var a := deg_to_rad(current_direction)
	return Vector3(cos(a), 0.0, sin(a))


## Whether anything stirs it with nobody touching it (then it never sleeps).
func restless() -> bool:
	return current > 0.0 or surge > 0.0 or gusts > 0.0


## The radius at `t` (0 root .. 1 tip), without beads or knot.
func radius_at(t: float) -> float:
	return lerpf(thickness_root, thickness_tip, pow(clampf(t, 0.0, 1.0), taper))


## Copies every setting from `other` (keeps this resource, so ropes using it follow).
func copy_from(other: RopeStyle) -> void:
	for p in other.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and p.usage & PROPERTY_USAGE_STORAGE:
			set(p.name, other.get(p.name))


# --- Presets ------------------------------------------------------------------

## A hemp rope: laid strands, a knot at the end, swings and settles.
static func rope() -> RopeStyle:
	var s := RopeStyle.new()
	s.pieces = 16
	s.gravity = 9.8
	s.drag = 0.35
	s.bend = 0.08
	s.iterations = 8
	s.thickness_root = 0.035
	s.thickness_tip = 0.035
	s.colour_root = Color(0.56, 0.46, 0.3)
	s.colour_tip = Color(0.5, 0.4, 0.26)
	s.twist = 0.7
	s.knot = 0.7
	s.sides = 8
	return s


## A jungle vine after The Clearing's (Warren's): a dark green stem, leaves along it hanging
## down and out, bunched thick where it is held.
static func vine() -> RopeStyle:
	var s := RopeStyle.new()
	s.pieces = 14
	s.gravity = 9.8
	s.drag = 0.5
	s.bend = 0.12
	s.iterations = 6
	s.thickness_root = 0.04
	s.thickness_tip = 0.02
	s.taper = 1.4
	s.colour_root = Color(0.2, 0.24, 0.12)
	s.colour_tip = Color(0.26, 0.33, 0.14)
	s.knot = 0.25
	s.leaf_kind = Leaf.VINE
	s.leaves_per_metre = 20.0
	s.leaf_size = 0.24
	s.leaf_bunch = 0.18
	s.leaf_colour_root = Color(0.17, 0.29, 0.12)
	s.leaf_colour_tip = Color(0.26, 0.4, 0.15)
	s.leaf_vary = 0.45
	s.leaf_lean = 45.0
	s.leaf_droop = 0.25
	s.leaf_stream = 0.35
	s.leaf_flutter = 0.12
	return s


## Giant kelp (after the Dynamic Kelp in Unity article): a thin stipe floated upright by its
## gas bladders, swaying in a surging current, long ruffled blades streaming off it, a
## colour gradient from dark root to golden tip.
static func kelp() -> RopeStyle:
	var s := RopeStyle.new()
	s.pieces = 12
	s.gravity = -3.5
	s.drag = 2.2
	s.bend = 0.15
	s.iterations = 3
	s.current_direction = 20.0
	s.current = 0.35
	s.surge = 0.55
	s.surge_period = 7.0
	s.gusts = 0.45
	s.gust_size = 9.0
	s.gust_speed = 1.6
	s.thickness_root = 0.04
	s.thickness_tip = 0.008
	s.taper = 0.8
	s.colour_root = Color(0.2, 0.15, 0.06)
	s.colour_tip = Color(0.55, 0.45, 0.14)
	s.shine = 0.35
	s.sides = 5
	s.leaf_kind = Leaf.KELP
	s.leaves_per_metre = 5.0
	s.leaf_size = 0.85
	s.leaf_from = 0.12
	s.leaf_colour_root = Color(0.33, 0.25, 0.08)
	s.leaf_colour_tip = Color(0.62, 0.52, 0.16)
	s.leaf_vary = 0.35
	s.leaf_lean = 55.0
	s.leaf_droop = 0.1
	s.leaf_stream = 0.85
	s.leaf_flutter = 0.25
	s.leaf_curl = 0.7
	s.leaf_ruffle = 0.7
	return s


## Sea grass or a reed bed: grass-like blades off a short soft stem.
static func seagrass() -> RopeStyle:
	var s := kelp()
	s.pieces = 8
	s.gravity = -2.0
	s.thickness_root = 0.012
	s.thickness_tip = 0.004
	s.colour_root = Color(0.16, 0.24, 0.1)
	s.colour_tip = Color(0.4, 0.55, 0.2)
	s.leaf_kind = Leaf.BLADE
	s.leaves_per_metre = 8.0
	s.leaf_size = 0.5
	s.leaf_from = 0.0
	s.leaf_to = 0.7
	s.leaf_colour_root = Color(0.2, 0.32, 0.12)
	s.leaf_colour_tip = Color(0.5, 0.62, 0.22)
	s.leaf_lean = 20.0
	s.leaf_ruffle = 0.15
	return s


## A telegraph or tightrope wire after Hemlock's Tower's: thin, dark, a little glossy,
## stretchy enough to dip under what lands on it and throw it back up.
static func wire() -> RopeStyle:
	var s := RopeStyle.new()
	s.pieces = 24
	s.gravity = 9.8
	s.drag = 0.25
	s.bend = 0.0
	s.stretch = 0.55
	s.iterations = 6
	s.thickness_root = 0.014
	s.thickness_tip = 0.014
	s.colour_root = Color(0.09, 0.08, 0.09)
	s.colour_tip = Color(0.09, 0.08, 0.09)
	s.shine = 0.5
	s.sides = 5
	return s


## An iron chain: heavy, links pinched along it, no bend at all.
static func chain() -> RopeStyle:
	var s := RopeStyle.new()
	s.pieces = 24
	s.gravity = 12.0
	s.drag = 0.2
	s.bend = 0.0
	s.iterations = 10
	s.thickness_root = 0.045
	s.thickness_tip = 0.045
	s.colour_root = Color(0.28, 0.27, 0.27)
	s.colour_tip = Color(0.36, 0.3, 0.26)
	s.beads = 1.0
	s.shine = 0.7
	s.sides = 6
	return s


## The presets by name, for a menu.
const PRESETS := ["Rope", "Vine", "Kelp", "Sea grass", "Wire", "Chain"]


static func preset(name: String) -> RopeStyle:
	match name:
		"Vine": return vine()
		"Kelp": return kelp()
		"Sea grass": return seagrass()
		"Wire": return wire()
		"Chain": return chain()
	return rope()
