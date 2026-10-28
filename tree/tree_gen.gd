@tool
class_name TreeGen
extends Resource
## Any tree, built from code by one algorithm: a trunk that grows branches, which grow branches of
## their own (up to four levels), each bending under its own weight or towards the light, curling,
## twisting and wandering as asked; then leaves on the outermost twigs, drawn whichever way is asked
## (`leaf_style`): lumpy faceted blobs, fluffy cards, needle cards, painted cards, or none. Pines,
## firs, oaks, willows and dead snags are all the one generator with different settings (see
## PRESETS); every setting can be changed, and the same settings and seed always make the same tree.
##
## One tree:   var t := TreeGen.preset("Oak"); t.height = 9.0; add_child(t.instance())
## A forest:   TreeGen.forest(parent, points, t, 4)   (a MultiMesh per variant: a few draws)
##
## The mesh has up to two surfaces, each carrying its material: 0 the solid parts (wood, the dark
## mass inside the crown, blob leaves), 1 the leaf cards. Every vertex carries an sRGB colour and in
## UV2.y how much it sways in the wind (0 at the trunk's foot, 1 out at the tips); normals in the
## crown are bent out from its middle so it shades as one soft shape. The shaders take the same wind
## uniforms as GameCommon wind's wind_sway.gdshader: `WindField.register(m)` each of `materials()`.

enum Leaves { BLOBS, FLUFFY, NEEDLES, PAINTED, NONE }
## How long the trunk's branches are up the crown (after Weber and Penn's shapes).
enum Crown { CONICAL, SPHERICAL, HEMISPHERICAL, CYLINDRICAL, TAPERED, FLAME, INVERSE, TEND_FLAME }

const SOLID_SHADER := preload("res://tree/tree_solid.gdshader")
const FLUFFY_SHADER := preload("res://tree/tree_fluffy.gdshader")
const NEEDLE_SHADER := preload("res://tree/tree_needles.gdshader")
const PAINTED_SHADER := preload("res://tree/tree_painted.gdshader")
## painted-woodland's real leaves, used by the painted style when the kit is in the project
const WOODLAND_LEAVES := "res://woodland/leaf_atlas.gd"
const GOLDEN := 2.39996

@export_group("Trunk")
## Height of the trunk at full apical dominance, metres (the crown may reach a little past it), and
## its radius at the foot.
@export_range(0.5, 40.0, 0.1, "or_greater") var height := 8.0
@export_range(0.02, 2.0, 0.01, "or_greater") var trunk_radius := 0.25
## How far up the trunk its first branches grow (0..1 of its height).
@export_range(0.0, 0.95) var trunk_base := 0.3
## The tilt of the trunk where it leaves the ground (radians; it curves back up), and how much it
## wanders as it goes.
@export_range(0.0, 0.8) var lean := 0.03
@export_range(0.0, 1.0) var bend := 0.15
## How much the foot swells, and roots snaking off over the ground from it.
@export_range(0.0, 2.0) var root_flare := 0.4
@export_range(0, 12) var roots := 0
@export var bark := Color(0.36, 0.27, 0.2)

@export_group("Branching")
## Levels of branches (1: only off the trunk, as a pine's; 3 or 4: twigs on twigs).
@export_range(1, 4) var levels := 3
## Branches off the trunk, branches off each branch below the last level, and how much each count
## varies (0 exact, 1 from none to twice as many).
@export_range(1, 150) var children := 8
@export_range(0, 24) var twigs := 4
@export_range(0.0, 1.0) var children_random := 0.3
## Branches growing from the same point (1 one at a time up a spiral, 2 opposite, more a whorl).
@export_range(1, 12) var whorl := 1
## Each point turned the golden angle (137.5 degrees) from the last, as most plants do; or at random.
@export var golden_angle := true
## The angle (degrees) the trunk's branches leave it at, deeper branches leave theirs at, give or take.
@export_range(0.0, 150.0) var branch_angle := 50.0
@export_range(0.0, 150.0) var twig_angle := 40.0
@export_range(0.0, 60.0) var angle_random := 10.0
## How far the crown reaches out from the trunk at its widest, against the height: the trunk's branches
## grow until they reach that outline (shaped up the tree by `crown_shape`). Deeper branches' length is against their parent's.
@export_range(0.02, 1.5) var length := 0.45
@export_range(0.05, 1.2) var twig_length := 0.55
## A branch's radius at its foot against its parent's there.
@export_range(0.1, 1.0) var radius_ratio := 0.55
## Where along a branch its own branches grow, from and to (0..1 of its length).
@export_range(0.0, 1.0) var start := 0.25
@export_range(0.0, 1.0) var end := 0.95
## How the trunk's branches' length goes up the crown.
@export var crown_shape := Crown.SPHERICAL
## How wide the crown is (stretches every branch out from the trunk, keeping the tree's height).
@export_range(0.2, 3.0) var spread := 1.0
## A strong leader (1): the trunk runs to the top, thick, and the crown is a cone round it, a
## conifer's. A weak one (0): the trunk stops low and forks into limbs, an oak's.
@export_range(0.0, 1.0) var apical := 0.4
## Branches turning upward to the light (above 0) or downward (below); `droop` they sag under their
## weight, more the further out (and lift again at the tip, as a fir's fronds do).
@export_range(-1.0, 1.0) var gravitropism := 0.1
@export_range(0.0, 1.5) var droop := 0.1
## The outermost twigs hanging straight down, long, a weeping willow's (0 none, 1 down to the ground).
@export_range(0.0, 1.0) var weep := 0.0
## S-curves along each branch; a turn round the trunk as they go; unevenness in everything.
@export_range(0.0, 1.5) var curl := 0.0
@export_range(-1.0, 1.0) var twist := 0.0
@export_range(0.0, 1.0) var wildness := 0.3

@export_group("Leaves")
@export var leaf_style := Leaves.FLUFFY
## A clump's radius, metres; how many clumps to a metre of twig (1: about one a clump's size apart);
## where on the twigs they grow (0 at the tips only, 1 all along).
@export_range(0.05, 4.0, 0.01, "or_greater") var clump_size := 0.8
@export_range(0.0, 4.0) var leaf_density := 1.0
@export_range(0.0, 1.0) var leaf_reach := 0.35
## The dark mass inside the crown, so it reads as solid (0 none, 1 out to the leaves).
@export_range(0.0, 1.0) var fill := 0.45
## Colours: deep inside, out on the crown, at the sunlit tips; how much each clump or facet differs
## from the next; now and then a clump in `accent` (how often in its alpha); snow on the tops.
@export var leaves_inner := Color(0.09, 0.2, 0.09)
@export var leaves_outer := Color(0.2, 0.4, 0.16)
@export var leaves_tips := Color(0.45, 0.62, 0.26)
@export_range(0.0, 1.0) var dapple := 0.5
@export var accent := Color(0.9, 0.6, 0.15, 0.0)
@export_range(0.0, 1.0) var snow := 0.0
@export var snow_colour := Color(0.94, 0.96, 1.0)

@export_group("Leaf look")
## Cards (fluffy, painted): their size against the clump, how many to a clump.
@export_range(0.2, 3.0) var card_size := 1.0
@export_range(0.1, 3.0) var cards := 1.0
## Fluffy: how far a card turns to face the camera (0 lies on the clump, 1 a billboard), how far its
## normal bends to the crown's (1: one soft shape), where its leaves are cut, broad or narrow leaves.
@export_range(0.0, 1.0) var billboard := 0.85
@export_range(0.0, 1.0) var normal_bend := 0.8
@export_range(0.05, 0.95) var alpha_cut := 0.45
@export_range(0, 1) var fluffy_leaf := 0
## A bright edge to the crown, most with the sun behind it (all styles).
@export_range(0.0, 1.0) var rim := 0.3
## Blobs: how lumpy, and tufts of leaves standing out of each.
@export_range(0.0, 1.0) var lumpiness := 0.4
@export_range(0, 14) var tufts := 4
## Needles: how close the needles grow, cards crossed about each frond (more body), frond thickness.
@export_range(0.4, 2.5) var needle_density := 1.0
@export_range(0, 4) var sprigs := 2
@export_range(0.1, 0.9) var fullness := 0.5
## Painted: which real leaf (0 beech, 1 oak, 2 maple, 3 aspen, 4 birch).
@export_range(0, 4) var painted_leaf := 1

@export_group("Look")
## 0 soft light wrapping round the crown, 1 two-tone cel shading.
@export_range(0.0, 1.0) var toon := 0.0
@export var seed := 1
## What to draw it with instead of the component's shaders: the solid surface, the leaf cards.
@export var material: Material
@export var leaf_material: Material

## Ready-made trees, by name: settings over the defaults above. preset(name) makes one.
const PRESETS := {
	"Pine": {height = 10.0, trunk_radius = 0.22, trunk_base = 0.14, lean = 0.04, bend = 0.05, root_flare = 0.6,
		bark = Color(0.36, 0.25, 0.18), levels = 1, children = 108, whorl = 9, branch_angle = 88.0, angle_random = 5.0,
		length = 0.245, crown_shape = Crown.CONICAL, apical = 1.0, gravitropism = 0.3, droop = 0.45, wildness = 0.35,
		leaf_style = Leaves.NEEDLES, leaf_reach = 1.0, fill = 0.62, fullness = 0.5, sprigs = 2,
		leaves_inner = Color(0.10, 0.22, 0.16), leaves_outer = Color(0.24, 0.42, 0.26), leaves_tips = Color(0.40, 0.56, 0.32), rim = 0.0},
	"Fir": {height = 11.0, trunk_radius = 0.24, trunk_base = 0.1, lean = 0.02, bend = 0.04, root_flare = 0.6,
		bark = Color(0.33, 0.24, 0.19), levels = 2, children = 70, twigs = 5, whorl = 6, branch_angle = 82.0, twig_angle = 55.0,
		angle_random = 6.0, length = 0.21, twig_length = 0.42, start = 0.15, end = 0.9, crown_shape = Crown.CONICAL, apical = 1.0,
		gravitropism = 0.25, droop = 0.3, wildness = 0.25, leaf_style = Leaves.NEEDLES, leaf_reach = 1.0, fill = 0.6,
		fullness = 0.55, sprigs = 1, leaves_inner = Color(0.07, 0.17, 0.14), leaves_outer = Color(0.17, 0.34, 0.25),
		leaves_tips = Color(0.32, 0.5, 0.34), rim = 0.0},
	"Spruce": {height = 10.0, trunk_radius = 0.22, trunk_base = 0.12, lean = 0.03, bend = 0.04, root_flare = 0.6,
		bark = Color(0.34, 0.24, 0.18), levels = 1, children = 135, whorl = 9, branch_angle = 92.0, angle_random = 6.0,
		length = 0.2, crown_shape = Crown.CONICAL, apical = 1.0, gravitropism = 0.2, droop = 0.85, wildness = 0.3,
		leaf_style = Leaves.NEEDLES, leaf_reach = 1.0, fill = 0.62, fullness = 0.5, sprigs = 2,
		leaves_inner = Color(0.08, 0.19, 0.17), leaves_outer = Color(0.2, 0.38, 0.3), leaves_tips = Color(0.38, 0.54, 0.42), rim = 0.0},
	"Snowy spruce": {height = 9.0, trunk_radius = 0.22, trunk_base = 0.12, lean = 0.03, bend = 0.04, root_flare = 0.6,
		levels = 1, children = 108, whorl = 9, branch_angle = 90.0, length = 0.22, crown_shape = Crown.CONICAL, apical = 1.0,
		gravitropism = 0.25, droop = 0.6, wildness = 0.3, leaf_style = Leaves.NEEDLES, leaf_reach = 1.0, fill = 0.62,
		leaves_inner = Color(0.10, 0.22, 0.16), leaves_outer = Color(0.2, 0.36, 0.26), leaves_tips = Color(0.40, 0.56, 0.32),
		snow = 0.8, rim = 0.0},
	"Lodgepole": {height = 13.0, trunk_radius = 0.2, trunk_base = 0.45, lean = 0.05, bend = 0.08, root_flare = 0.4,
		bark = Color(0.4, 0.3, 0.22), levels = 1, children = 64, whorl = 8, branch_angle = 85.0, length = 0.15,
		crown_shape = Crown.CONICAL, apical = 1.0, gravitropism = 0.35, droop = 0.2, wildness = 0.4,
		leaf_style = Leaves.NEEDLES, leaf_reach = 1.0, fill = 0.55, fullness = 0.55, sprigs = 2,
		leaves_inner = Color(0.10, 0.22, 0.14), leaves_outer = Color(0.26, 0.42, 0.24), leaves_tips = Color(0.42, 0.56, 0.3), rim = 0.0},
	"Oak": {height = 7.5, trunk_radius = 0.32, trunk_base = 0.36, lean = 0.04, bend = 0.25, root_flare = 0.6,
		levels = 3, children = 6, twigs = 4, branch_angle = 55.0, twig_angle = 45.0, angle_random = 14.0, length = 0.55,
		twig_length = 0.55, radius_ratio = 0.6, start = 0.3, end = 0.95, crown_shape = Crown.SPHERICAL, apical = 0.15,
		spread = 1.15, gravitropism = 0.22, droop = 0.1, curl = 0.25, wildness = 0.45, leaf_style = Leaves.FLUFFY,
		clump_size = 0.85, leaf_density = 0.9, leaf_reach = 0.45, fill = 0.55},
	"Aspen": {height = 9.0, trunk_radius = 0.15, trunk_base = 0.32, lean = 0.03, bend = 0.12, root_flare = 0.3,
		bark = Color(0.88, 0.86, 0.8), levels = 2, children = 16, twigs = 4, branch_angle = 42.0, twig_angle = 40.0,
		length = 0.3, twig_length = 0.55, crown_shape = Crown.TEND_FLAME, apical = 0.9, gravitropism = 0.2, droop = 0.15,
		wildness = 0.35, leaf_style = Leaves.FLUFFY, clump_size = 0.45, leaf_density = 1.5, leaf_reach = 0.7, fill = 0.45, card_size = 1.2,
		leaves_inner = Color(0.45, 0.32, 0.06), leaves_outer = Color(0.88, 0.64, 0.14), leaves_tips = Color(1.0, 0.85, 0.3),
		accent = Color(0.85, 0.35, 0.1, 0.05)},
	"Cottonwood": {height = 9.0, trunk_radius = 0.42, trunk_base = 0.3, lean = 0.06, bend = 0.3, root_flare = 0.7,
		bark = Color(0.5, 0.47, 0.42), levels = 2, children = 6, twigs = 5, branch_angle = 45.0, twig_angle = 45.0,
		angle_random = 18.0, length = 0.6, twig_length = 0.5, radius_ratio = 0.65, crown_shape = Crown.SPHERICAL, apical = 0.3,
		spread = 1.1, gravitropism = 0.25, droop = 0.2, curl = 0.35, wildness = 0.6, leaf_style = Leaves.BLOBS,
		clump_size = 0.95, leaf_density = 0.5, leaf_reach = 0.3, fill = 0.35, lumpiness = 0.55, tufts = 4,
		accent = Color(0.85, 0.7, 0.2, 0.05)},
	"Willow": {height = 7.5, trunk_radius = 0.36, trunk_base = 0.45, lean = 0.1, bend = 0.3, root_flare = 0.7,
		levels = 3, children = 6, twigs = 4, branch_angle = 55.0, twig_angle = 30.0, length = 0.5, twig_length = 0.5,
		start = 0.35, crown_shape = Crown.HEMISPHERICAL, apical = 0.15, spread = 1.05, gravitropism = 0.1, droop = 0.1, weep = 1.0,
		wildness = 0.35, leaf_style = Leaves.FLUFFY, clump_size = 0.26, leaf_density = 1.6, leaf_reach = 0.85, fill = 0.0, cards = 0.45, card_size = 1.3,
		fluffy_leaf = 1, leaves_inner = Color(0.14, 0.26, 0.1), leaves_outer = Color(0.32, 0.5, 0.2),
		leaves_tips = Color(0.58, 0.72, 0.32)},
	"Birch": {height = 9.0, trunk_radius = 0.16, trunk_base = 0.3, lean = 0.08, bend = 0.15, root_flare = 0.3,
		bark = Color(0.9, 0.88, 0.84), levels = 3, children = 12, twigs = 3, branch_angle = 40.0, twig_angle = 40.0,
		length = 0.28, twig_length = 0.55, crown_shape = Crown.TEND_FLAME, apical = 0.8, gravitropism = 0.0, droop = 0.6,
		wildness = 0.35, leaf_style = Leaves.FLUFFY, clump_size = 0.42, leaf_density = 1.5, leaf_reach = 0.7, fill = 0.4, card_size = 1.15,
		leaves_inner = Color(0.16, 0.3, 0.1), leaves_outer = Color(0.36, 0.56, 0.2), leaves_tips = Color(0.64, 0.78, 0.34)},
	"Maple": {height = 8.0, trunk_radius = 0.28, trunk_base = 0.25, lean = 0.03, bend = 0.15, root_flare = 0.5,
		bark = Color(0.32, 0.26, 0.22), levels = 3, children = 7, twigs = 4, branch_angle = 45.0, twig_angle = 40.0,
		length = 0.45, twig_length = 0.55, crown_shape = Crown.SPHERICAL, apical = 0.35, gravitropism = 0.2, droop = 0.15,
		curl = 0.15, wildness = 0.35, leaf_style = Leaves.FLUFFY, clump_size = 0.8, leaf_density = 1.0, leaf_reach = 0.4,
		fill = 0.55, leaves_inner = Color(0.36, 0.06, 0.04), leaves_outer = Color(0.78, 0.2, 0.08),
		leaves_tips = Color(1.0, 0.55, 0.18), accent = Color(0.95, 0.75, 0.2, 0.15)},
	"Pinyon": {height = 3.6, trunk_radius = 0.2, trunk_base = 0.12, lean = 0.12, bend = 0.4, root_flare = 0.6,
		bark = Color(0.33, 0.24, 0.17), levels = 2, children = 7, twigs = 4, branch_angle = 60.0, twig_angle = 45.0,
		angle_random = 20.0, length = 0.6, twig_length = 0.5, crown_shape = Crown.HEMISPHERICAL, apical = 0.2, spread = 1.2,
		gravitropism = 0.2, droop = 0.2, curl = 0.4, wildness = 0.7, leaf_style = Leaves.BLOBS, clump_size = 0.55,
		leaf_density = 0.8, leaf_reach = 0.5, fill = 0.3, lumpiness = 0.5, tufts = 6,
		leaves_inner = Color(0.07, 0.16, 0.09), leaves_outer = Color(0.16, 0.3, 0.17), leaves_tips = Color(0.3, 0.44, 0.26)},
	"Dead": {height = 7.0, trunk_radius = 0.3, trunk_base = 0.25, lean = 0.12, bend = 0.4, root_flare = 0.8, roots = 4,
		bark = Color(0.42, 0.38, 0.34), levels = 3, children = 6, twigs = 3, branch_angle = 50.0, twig_angle = 45.0,
		angle_random = 25.0, length = 0.45, twig_length = 0.55, crown_shape = Crown.TAPERED, apical = 0.4, gravitropism = 0.15,
		droop = 0.1, curl = 0.6, twist = 0.2, wildness = 0.8, leaf_style = Leaves.NONE, fill = 0.0},
	"Painted oak": {height = 9.0, trunk_radius = 0.6, trunk_base = 0.35, lean = 0.15, bend = 0.3, root_flare = 1.1, roots = 6,
		bark = Color(0.4, 0.3, 0.24), levels = 3, children = 6, twigs = 3, branch_angle = 60.0, twig_angle = 45.0,
		angle_random = 20.0, length = 0.6, twig_length = 0.5, radius_ratio = 0.55, crown_shape = Crown.HEMISPHERICAL,
		apical = 0.25, spread = 1.1, gravitropism = 0.3, droop = 0.15, curl = 0.9, twist = 0.15, wildness = 0.5,
		leaf_style = Leaves.PAINTED, clump_size = 1.0, leaf_density = 1.0, leaf_reach = 0.4, fill = 0.0, cards = 1.0, dapple = 0.2,
		card_size = 1.0, painted_leaf = 1, leaves_inner = Color(0.45, 0.18, 0.06), leaves_outer = Color(0.84, 0.43, 0.13),
		leaves_tips = Color(0.95, 0.72, 0.28), rim = 0.4},
	"Painted aspen": {height = 11.0, trunk_radius = 0.2, trunk_base = 0.45, lean = 0.06, bend = 0.12, root_flare = 0.4,
		bark = Color(0.88, 0.86, 0.8), levels = 2, children = 12, twigs = 3, branch_angle = 45.0, twig_angle = 40.0,
		length = 0.22, twig_length = 0.5, crown_shape = Crown.TEND_FLAME, apical = 0.9, gravitropism = 0.3, droop = 0.1,
		curl = 0.3, wildness = 0.4, leaf_style = Leaves.PAINTED, clump_size = 0.85, leaf_density = 0.6, leaf_reach = 0.5,
		fill = 0.0, painted_leaf = 3, leaves_inner = Color(0.5, 0.32, 0.06), leaves_outer = Color(0.92, 0.66, 0.16),
		leaves_tips = Color(1.0, 0.86, 0.36), rim = 0.4},
}

static var _cache := {}
static var _materials := {}
static var _clusters: ImageTexture

## How finely it is made (1 in full; 0 the plain far tree, see simple()).
var _lod := 1
## After mesh() builds a tree (not when it comes from the cache): how tall it came out, metres.
var built_height := 0.0


## A ready-made tree (a key of PRESETS).
static func preset(name: String) -> TreeGen:
	var t := TreeGen.new()
	t.apply_preset(name)
	return t


## Sets every setting to the defaults, then to a preset's.
func apply_preset(name: String) -> void:
	var fresh := TreeGen.new()
	for p in get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and p.usage & PROPERTY_USAGE_STORAGE and p.name != "seed":
			set(p.name, fresh.get(p.name))
	var s: Dictionary = PRESETS.get(name, {})
	for k in s:
		set(k, s[k])


## Forgets every built mesh and material (a tool that rebuilds at each change would keep them all).
static func clear_cache() -> void:
	_cache.clear()
	_materials.clear()


func _key(variant: int) -> String:
	var vals: Array = [_lod]
	for p in get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and p.usage & PROPERTY_USAGE_STORAGE:
			var v: Variant = get(p.name)
			vals.append(v.get_instance_id() if v is Object else v)
	return "%d|%d" % [var_to_str(vals).hash(), variant]


## The tree's mesh, built once for each variant and kept.
func mesh(variant := 0) -> ArrayMesh:
	var key := _key(variant)
	if _cache.has(key):
		return _cache[key]
	var built := _build(seed * 7919 + variant * 104729)
	_cache[key] = built
	return built


## A MeshInstance3D of it.
func instance(variant := 0) -> MeshInstance3D:
	var made := MeshInstance3D.new()
	made.mesh = mesh(variant)
	return made


## Gives a MeshInstance3D holding a baked mesh of this tree (one saved without its materials) the
## materials it is drawn with.
func dress(node: MeshInstance3D) -> void:
	var mats := materials()
	for i in mini(node.mesh.get_surface_count(), mats.size()):
		node.set_surface_override_material(i, mats[i])


## What it is drawn with: [the solid parts' material, the leaf cards' (null with blobs or none)].
## Shared by every tree that looks the same: set a uniform on one (wind, toon, debug_view) and all change.
func materials() -> Array[Material]:
	var out: Array[Material] = [material if material else _solid_material(), null]
	if leaf_style in [Leaves.FLUFFY, Leaves.NEEDLES, Leaves.PAINTED]:
		out[1] = leaf_material if leaf_material else _card_material()
	return out


## Plants trees at `points` (Vector3s on the ground), `variants` different ones turned and sized at
## random, under `parent`, as MultiMeshes, one per variant in each square of `chunk` metres; beyond
## `near` metres each square changes over to the plain version (see `simple`), with no shadow.
## `near` 0 keeps the full tree at every distance. (As PineTree.forest.)
static func forest(parent: Node3D, points: Array, shape: TreeGen, variants := 4, sizes := Vector2(0.8, 1.25), chunk := 64.0, near := 70.0) -> Array[MultiMeshInstance3D]:
	var rng := RandomNumberGenerator.new()
	rng.seed = shape.seed
	var plain := shape.simple() if near > 0.0 else null
	var groups := {}
	for p: Vector3 in points:
		var size := rng.randf_range(sizes.x, sizes.y)
		var cell := Vector2i(floori(p.x / chunk), floori(p.z / chunk))
		var key := [cell, rng.randi() % variants]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size), p))
	var made: Array[MultiMeshInstance3D] = []
	for key: Array in groups:
		var trees: Array = groups[key]
		for detailed: bool in ([true, false] if plain else [true]):
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = shape.mesh(key[1]) if detailed else plain.mesh(key[1])
			multi.instance_count = trees.size()
			for i in trees.size():
				multi.set_instance_transform(i, trees[i])
			var node := MultiMeshInstance3D.new()
			node.multimesh = multi
			if plain:
				node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				if detailed:
					node.visibility_range_end = near
					node.visibility_range_end_margin = 10.0
				else:
					node.visibility_range_begin = near
					node.visibility_range_begin_margin = 10.0
					node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(node)
			made.append(node)
	return made


## A plainer version of this tree for far off: the same branches and crown, with fewer sides to the
## wood and no thin twigs, coarser blobs without tufts, fewer and bigger cards, single needle cards.
func simple() -> TreeGen:
	var plain: TreeGen = duplicate()
	plain._lod = 0
	return plain


# ------------------------------------------------------------------ materials

func _look_key(kind: String) -> String:
	return var_to_str([kind, toon, rim, billboard, normal_bend, alpha_cut, fluffy_leaf, needle_density, painted_leaf])


func _solid_material() -> ShaderMaterial:
	var key := _look_key("solid")
	if not _materials.has(key):
		var m := ShaderMaterial.new()
		m.shader = SOLID_SHADER
		m.set_shader_parameter("toon", toon)
		m.set_shader_parameter("rim", rim)
		_materials[key] = m
	return _materials[key]


func _card_material() -> ShaderMaterial:
	var key := _look_key(str(leaf_style))
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	match leaf_style:
		Leaves.FLUFFY:
			m.shader = FLUFFY_SHADER
			m.set_shader_parameter("clusters", clusters())
			m.set_shader_parameter("leaf_row", float(fluffy_leaf))
			m.set_shader_parameter("billboard", billboard)
			m.set_shader_parameter("normal_bend", normal_bend)
			m.set_shader_parameter("alpha_cut", alpha_cut)
		Leaves.NEEDLES:
			m.shader = NEEDLE_SHADER
			m.set_shader_parameter("needle_density", needle_density)
			m.set_shader_parameter("alpha_cut", alpha_cut)
		Leaves.PAINTED:
			m.shader = PAINTED_SHADER
			m.set_shader_parameter("normal_bend", normal_bend)
			if ResourceLoader.exists(WOODLAND_LEAVES):
				m.set_shader_parameter("leaf_atlas", load(WOODLAND_LEAVES).texture())
				m.set_shader_parameter("shape", float(painted_leaf))
			else:
				m.set_shader_parameter("leaf_atlas", clusters())
				m.set_shader_parameter("atlas_cols", 4.0)
				m.set_shader_parameter("atlas_rows", 2.0)
				m.set_shader_parameter("shape", 0.0)
	m.set_shader_parameter("toon", toon)
	m.set_shader_parameter("rim", rim)
	_materials[key] = m
	return m


## The fluffy leaves' texture, drawn as SVG at start-up: four clusters of broad leaves in a row over
## four of narrow ones, each radiating from its middle. R is dark at a leaf's foot and light at its
## tip, G each leaf's own shade, alpha the leaves.
static func clusters() -> ImageTexture:
	if _clusters:
		return _clusters
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"512\" height=\"256\" viewBox=\"0 0 512 256\"><defs>"
	var body := ""
	var n := 0
	for row in 2:
		for col in 4:
			var cx := col * 128.0 + 64.0
			var cy := row * 128.0 + 64.0
			var count := (13 if row == 0 else 20) + col * 2
			var turn := rng.randf() * TAU
			for k in count:
				turn += GOLDEN + rng.randf_range(-0.25, 0.25)
				var inner := k > count * 0.6
				var long := rng.randf_range(26.0, 36.0) if row == 0 else rng.randf_range(30.0, 42.0)
				var wide := long * (rng.randf_range(0.42, 0.55) if row == 0 else rng.randf_range(0.16, 0.24))
				var from := rng.randf_range(4.0, 12.0) if inner else rng.randf_range(14.0, 60.0 - long)
				var x := cx + cos(turn) * from
				var y := cy + sin(turn) * from
				var g := rng.randi_range(110, 255)
				var id := "g%d" % n
				n += 1
				svg += ("<radialGradient id=\"%s\" gradientUnits=\"userSpaceOnUse\" cx=\"%.1f\" cy=\"%.1f\" r=\"60\">" % [id, cx, cy]
					+ "<stop offset=\"0\" stop-color=\"rgb(40,%d,0)\"/><stop offset=\"1\" stop-color=\"rgb(255,%d,0)\"/></radialGradient>" % [g, g])
				body += ("<g transform=\"translate(%.1f,%.1f) rotate(%.1f)\">" % [x, y, rad_to_deg(turn) + rng.randf_range(-20, 20)]
					+ "<path d=\"M0,0 Q%.1f,%.1f %.1f,0 Q%.1f,%.1f 0,0 Z\" fill=\"url(#%s)\" stroke=\"rgba(0,0,0,0.3)\" stroke-width=\"1\"/>" % [long * 0.4, -wide, long, long * 0.4, wide, id]
					+ "<path d=\"M1,0 L%.1f,0\" stroke=\"rgba(0,0,0,0.25)\" stroke-width=\"1.2\"/></g>" % (long * 0.8))
	svg += "</defs>" + body + "</svg>"
	var img := Image.new()
	img.load_svg_from_string(svg)
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	_clusters = ImageTexture.create_from_image(img)
	return _clusters


# ------------------------------------------------------------------ growing it

class _Branch:
	var pts: Array[Vector3] = []
	var radii: Array[float] = []
	var level := 0
	var length := 0.0
	var leafy := false


## A surface's arrays as they are built.
class _Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var cu := PackedFloat32Array()
	var idx := PackedInt32Array()
	var custom := false

	func add(p: Vector3, nn: Vector3, col: Color, t: Vector2, t2: Vector2) -> int:
		v.append(p)
		n.append(nn)
		c.append(col)
		uv.append(t)
		uv2.append(t2)
		return v.size() - 1

	func add_custom(q: Vector4) -> void:
		cu.append(q.x)
		cu.append(q.y)
		cu.append(q.z)
		cu.append(q.w)

	func tri(a: int, b: int, d: int) -> void:
		idx.append(a)
		idx.append(b)
		idx.append(d)

	func commit(mesh: ArrayMesh, mat: Material) -> void:
		if idx.is_empty():
			return
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_INDEX] = idx
		var flags := 0
		if custom:
			arr[Mesh.ARRAY_CUSTOM0] = cu
			flags = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


const MAX_BRANCHES := 3000
const MAX_CLUMPS := 2400
const MAX_CARDS := 24000
var _card_cap := 80

var _rng: RandomNumberGenerator
var _branches: Array[_Branch] = []
var _trunk: _Branch
var _base_y := 0.0
var _top_y := 1.0
var _top := 1.0
var _centre := Vector3.ZERO
var _rx := 1.0
var _ry := 1.0


func _build(variant_seed: int) -> ArrayMesh:
	_rng = RandomNumberGenerator.new()
	_rng.seed = variant_seed
	_branches.clear()
	_grow()
	_spread()
	# what follows draws: a generator of its own, so a plain tree keeps the same branches and crown
	var draw := RandomNumberGenerator.new()
	draw.seed = variant_seed + 17
	var leaf_spots := _leaf_spots(draw)
	_measure(leaf_spots)
	_card_cap = MAX_CARDS / maxi(leaf_spots.size(), 1)
	var solid := _Buf.new()
	var leaves := _Buf.new()
	leaves.custom = true
	for b in _branches:
		_wood(solid, b)
	for k in roots:
		_root(solid, k, draw)
	if not leaf_spots.is_empty():
		match leaf_style:
			Leaves.BLOBS:
				for s: Array in leaf_spots:
					_blob(solid, s[0], s[1], draw)
			Leaves.FLUFFY:
				for s: Array in leaf_spots:
					_fluffy(leaves, s[0], s[1], draw)
			Leaves.PAINTED:
				for s: Array in leaf_spots:
					_painted(leaves, s[0], s[1], draw)
			Leaves.NEEDLES:
				for b in _branches:
					if b != _trunk and _leaf_from(b) < 0.999:
						_fronds(leaves, b)
				if apical >= 0.6:
					_leader(leaves)
		if fill > 0.0:
			_fill(solid, leaf_spots.filter(func(s: Array) -> bool: return s[2]), draw)
	var mesh := ArrayMesh.new()
	var mats := materials()
	solid.commit(mesh, mats[0])
	leaves.commit(mesh, mats[1])
	# (cards turn to the camera and everything sways: room for that)
	mesh.custom_aabb = mesh.get_aabb().grow(clump_size * card_size + 1.0)
	return mesh


## The trunk, its branches, theirs...
func _grow() -> void:
	var tilt := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
	var dir := Vector3.UP.rotated(tilt.cross(Vector3.UP).normalized() if tilt.length() > 0.0 else Vector3.RIGHT, -lean)
	# a strong leader runs to the top; a weak one stops a little above the first branches and forks
	var reach := lerpf(minf(trunk_base + (1.0 - trunk_base) * 0.3, 1.0), 1.0, pow(apical, 0.8))
	var t := _Branch.new()
	t.level = 0
	t.length = height * reach
	var steps := 10
	var p := Vector3.ZERO
	var wander := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) * bend * 0.12
	var tip := lerpf(0.6, 0.06, apical)
	for i in steps + 1:
		var s := float(i) / steps
		t.pts.append(p)
		var r := trunk_radius * lerpf(1.0, tip, pow(s, 0.8))
		r *= 1.0 + root_flare * exp(-p.y / maxf(trunk_radius * 1.6, 0.15))
		t.radii.append(r)
		dir = (dir + Vector3.UP * 0.06 + wander * sin(s * 5.0 + seed) + _jitter() * bend * 0.08).normalized()
		p += dir * t.length / steps
	_trunk = t
	_branches.append(t)
	_base_y = height * trunk_base
	_top_y = height
	_children(t)
	# the fork at a weak leader's top: limbs going on up
	if apical < 0.7 and levels >= 1:
		var forks := clampi(roundi(lerpf(4.0, 2.0, apical / 0.7)), 2, 4)
		var turn := _rng.randf() * TAU
		for k in forks:
			_spawn(t, 1.0, turn + k * TAU / forks + _rng.randf_range(-0.4, 0.4) * wildness, 0.55)
	if levels == 0:
		t.leafy = true


func _jitter() -> Vector3:
	return Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))


## The branches along `b`.
func _children(b: _Branch) -> void:
	if b.level >= levels or _branches.size() >= MAX_BRANCHES:
		b.leafy = true
		return
	var want := children if b.level == 0 else twigs
	var count := roundi(want * (1.0 + _rng.randf_range(-1.0, 1.0) * children_random))
	if b.level > 0:
		# (shorter branches carry fewer)
		count = roundi(count * clampf(b.length / maxf(_level_length(b.level), 0.01), 0.4, 1.3))
	if count <= 0:
		b.leafy = true
		return
	var t0 := start
	var t1 := end
	if b.level == 0:
		t0 = clampf(trunk_base * height / maxf(b.length, 0.01), 0.0, 0.98)
		t1 = 0.98 if apical >= 0.7 else 0.92
	t1 = maxf(t1, t0)
	var per := mini(whorl, count)
	var nodes := ceili(float(count) / per)
	var roll := _rng.randf() * TAU
	var placed := 0
	for k in nodes:
		var t := lerpf(t0, t1, (k + 0.5) / nodes)
		t = clampf(t + _rng.randf_range(-0.5, 0.5) * (t1 - t0) / nodes * children_random, 0.0, 1.0)
		roll += GOLDEN if golden_angle else _rng.randf_range(0.6, TAU - 0.6)
		# (whorls thin out towards the top, as a pine's)
		var here := mini(per - int(t * 2.5) if per > 3 else per, count - placed)
		here = maxi(here, mini(3, count - placed))
		for j in here:
			# (each a little above or below the others at its point, so whorls do not read as rings)
			var tj := t + _rng.randf_range(-0.3, 0.3) * (t1 - t0) / nodes * (0.5 + wildness) if here > 1 else t
			_spawn(b, clampf(tj, 0.0, 1.0), roll + j * TAU / here + _rng.randf_range(-0.3, 0.3) * wildness, 1.0)
		placed += here
		if placed >= count:
			break
	if b.level >= 1 and placed > 0 and leaf_reach > 0.0:
		# (leaves along it too, between its twigs, if they reach that far in)
		b.leafy = leaf_reach > 0.85


## A typical length for a branch at `level` (to scale how many twigs a branch carries).
func _level_length(level: int) -> float:
	var l := height * length
	for k in level - 1:
		l *= twig_length * 0.75
	return l


## How far the crown reaches out from the trunk at height `y` (its outline).
func _outline_at(y: float) -> float:
	return height * length * _shape_ratio((y - _base_y) / maxf(_top_y - _base_y, 0.01))


## How long a branch off the trunk at `at` going `dir` grows: until it reaches the crown's outline
## (out from the trunk, or past the top), so that limbs at any angle fill the same crown.
func _to_outline(at: Vector3, dir: Vector3) -> float:
	var step := maxf(height * 0.01, 0.02)
	var p := at
	var walked := 0.0
	while walked < height * 2.0:
		p += dir * step
		walked += step
		if p.y > _top_y or (dir.y < 0.0 and p.y < _base_y * 0.5):
			break
		var axis := _trunk_at(p.y)
		if Vector2(p.x - axis.x, p.z - axis.z).length() > _outline_at(maxf(p.y, _base_y)):
			break
	return maxf(walked, height * length * 0.15)


func _shape_ratio(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	match crown_shape:
		Crown.CONICAL: return 0.1 + 0.9 * (1.0 - t)
		Crown.SPHERICAL: return 0.2 + 0.8 * sin(PI * t)
		Crown.HEMISPHERICAL: return 0.2 + 0.8 * sin(0.5 * PI * (1.0 - t))
		Crown.CYLINDRICAL: return 1.0
		Crown.TAPERED: return 0.5 + 0.5 * (1.0 - t)
		Crown.FLAME: return maxf(t / 0.7 if t <= 0.7 else (1.0 - t) / 0.3, 0.1)
		Crown.INVERSE: return 1.0 - 0.8 * (1.0 - t)
		Crown.TEND_FLAME: return 0.5 + 0.5 * (t / 0.7 if t <= 0.7 else (1.0 - t) / 0.3)
	return 1.0


## A branch off `parent`, `t` of the way along it, turned `roll` round it. `steer` < 1 points it
## nearer the parent's way (a fork going on up).
func _spawn(parent: _Branch, t: float, roll: float, steer: float) -> void:
	if _branches.size() >= MAX_BRANCHES:
		return
	var level := parent.level + 1
	var at := _along(parent.pts, t)
	var pdir := _dir_along(parent.pts, t)
	var pr := _radius_along(parent, t)
	var angle := (branch_angle if level == 1 else twig_angle) + _rng.randf_range(-1.0, 1.0) * angle_random
	angle = deg_to_rad(clampf(angle * steer, 0.0, 170.0))
	var side := _perp(pdir).rotated(pdir, roll)
	var dir := (pdir * cos(angle) + side * sin(angle)).normalized()
	if level == levels and weep > 0.0:
		# (a weeping twig arches over at once: out a little, then down)
		dir = (Vector3(dir.x, minf(dir.y, 0.2), dir.z).normalized() + Vector3.DOWN * weep * 0.6).normalized()
	var long: float
	if level == 1:
		long = _to_outline(at, dir)
	else:
		long = parent.length * twig_length * lerpf(1.0, 0.55, t)
	long *= 1.0 + _rng.randf_range(-0.3, 0.2) * wildness
	if level == levels and weep > 0.0:
		long *= 1.0 + weep * 4.0
	var radius := minf(pr * radius_ratio, pr * 0.9)
	if steer < 1.0:
		radius = pr * 0.85
	var b := _grow_branch(at, dir, long, radius, level)
	_branches.append(b)
	_children(b)


func _grow_branch(from: Vector3, dir: Vector3, long: float, radius: float, level: int) -> _Branch:
	var b := _Branch.new()
	b.level = level
	b.length = long
	var steps: int = [10, 6, 4, 3, 3][mini(level, 4)] if not (level == levels and weep > 0.0) else 6
	var k := 4.0 / steps
	var axis := dir.cross(Vector3.UP).normalized() if absf(dir.y) < 0.98 else Vector3.RIGHT
	var phase := _rng.randf() * TAU
	var weight := float(level) / maxf(levels, 1)
	var d := dir
	var p := from
	for i in steps + 1:
		var s := float(i) / steps
		b.pts.append(p)
		b.radii.append(radius * lerpf(1.0, 0.3, s))
		if i == steps:
			break
		# towards the light (or away), sagging under its weight near its foot, lifting at its tip
		d += Vector3.UP * gravitropism * 0.14 * (0.5 + weight) * k
		d += Vector3.DOWN * droop * 0.2 * weight * (1.0 - 1.5 * s) * k
		if level == levels and weep > 0.0:
			d = d.lerp(Vector3.DOWN, clampf(weep * 0.6 * k, 0.0, 1.0)).normalized()
		# S-curves, a turn round the trunk, and a wander
		d = d.rotated(axis, curl * 0.9 * sin(s * TAU + phase) * k)
		d = d.rotated(Vector3.UP, twist * 0.35 * k)
		d = (d + _jitter() * wildness * 0.16 * k).normalized()
		p += d * long / steps
		p.y = maxf(p.y, 0.1)
	return b


## Every branch stretched out from the trunk by `spread`.
func _spread() -> void:
	if is_equal_approx(spread, 1.0):
		return
	for b in _branches:
		if b == _trunk:
			continue
		for i in b.pts.size():
			var p := b.pts[i]
			var axis := _trunk_at(p.y)
			b.pts[i] = Vector3(axis.x + (p.x - axis.x) * spread, p.y, axis.z + (p.z - axis.z) * spread)


## The trunk's middle at height `y`.
func _trunk_at(y: float) -> Vector3:
	var pts := _trunk.pts
	for i in pts.size() - 1:
		if y <= pts[i + 1].y:
			var f := clampf((y - pts[i].y) / maxf(pts[i + 1].y - pts[i].y, 0.001), 0.0, 1.0)
			return pts[i].lerp(pts[i + 1], f)
	return pts[-1]


func _along(pts: Array[Vector3], t: float) -> Vector3:
	var f := clampf(t, 0.0, 1.0) * (pts.size() - 1)
	var i := mini(int(f), pts.size() - 2)
	return pts[i].lerp(pts[i + 1], f - i)


func _dir_along(pts: Array[Vector3], t: float) -> Vector3:
	var f := clampf(t, 0.0, 1.0) * (pts.size() - 1)
	var i := mini(int(f), pts.size() - 2)
	return (pts[i + 1] - pts[i]).normalized()


func _radius_along(b: _Branch, t: float) -> float:
	var f := clampf(t, 0.0, 1.0) * (b.radii.size() - 1)
	var i := mini(int(f), b.radii.size() - 2)
	return lerpf(b.radii[i], b.radii[i + 1], f - i)


static func _perp(d: Vector3) -> Vector3:
	return d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized()


# ------------------------------------------------------------------ leaves

## Where the leaves go: [position, size] on the leafy twigs, from `leaf_reach` in to their tips (or
## for needles, the fronds' own points, so the crown can be measured).
func _leaf_spots(rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	if leaf_style == Leaves.NONE or leaf_density <= 0.0:
		return out
	for b in _branches:
		if b == _trunk:
			continue
		var from := _leaf_from(b)
		if from >= 0.999:
			continue
		# (a weeping strand's leaves hang outside the crown: the dark fill does not follow them)
		var inside := not (weep > 0.0 and b.level == levels)
		if leaf_style == Leaves.NEEDLES:
			for k in 5:
				out.append([_along(b.pts, lerpf(from, 1.0, k / 4.0)), b.length * (1.0 - from) * fullness * 0.62, true])
			continue
		var span := b.length * (1.0 - from)
		var count := maxi(1, roundi(span * leaf_density / maxf(clump_size, 0.05)))
		for k in count:
			var t := 1.0 - (float(k) / count) * (1.0 - from)
			var p := _along(b.pts, t) + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 1), rng.randf_range(-1, 1)) * clump_size * 0.3
			# (the end of a branch that has twigs of its own is thicker: a bigger clump hides it)
			var big := 1.0 if b.leafy else maxf(1.5, b.radii[-1] * 6.0 / maxf(clump_size, 0.05))
			out.append([p, clump_size * big * rng.randf_range(0.8, 1.15) * lerpf(1.0, 0.8, float(k) / count), inside])
		if out.size() >= MAX_CLUMPS:
			break
	# a strong leader's tip
	if leaf_style != Leaves.NEEDLES and apical >= 0.6 and levels > 0:
		out.append([_trunk.pts[-1], clump_size * 1.3, true])
	return out


## Where on a branch its leaves start (0..1 along it): the outermost twigs from `leaf_reach` in;
## a branch that has twigs of its own only past the last of them, so it does not end bare.
func _leaf_from(b: _Branch) -> float:
	if b.leafy:
		return 1.0 - leaf_reach
	return maxf(end, 1.0 - leaf_reach) if leaf_reach > 0.0 else 1.0


func _measure(spots: Array) -> void:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	_top = 0.0
	for b in _branches:
		for p in b.pts:
			_top = maxf(_top, p.y)
	for s: Array in spots:
		var p: Vector3 = s[0]
		var r: float = s[1]
		lo = lo.min(p - Vector3.ONE * r)
		hi = hi.max(p + Vector3.ONE * r)
		_top = maxf(_top, p.y + r * 0.5)
	if spots.is_empty():
		lo = Vector3(-1, _top * 0.5, -1)
		hi = Vector3(1, _top, 1)
	_centre = (lo + hi) * 0.5
	_rx = maxf(maxf(hi.x - lo.x, hi.z - lo.z) * 0.5, 0.3)
	_ry = maxf((hi.y - lo.y) * 0.5, 0.3)
	built_height = _top


## The normal for a point of the crown: out from its middle (so it shades as one shape), up a little.
func _round(p: Vector3) -> Vector3:
	var off := p - _centre
	return Vector3(off.x / _rx, off.y / _ry * 0.6 + 0.3, off.z / _rx).normalized()


## A leaf's colour at `p`: darker deep in the crown and underneath, lighter on top and outside;
## `shade` its own difference (-1..1, by `dapple`).
func _leaf_colour(p: Vector3, own: Vector3, shade: float, deep: float, odd: bool) -> Color:
	var off := p - _centre
	var outside := clampf(Vector3(off.x / _rx, off.y / _ry, off.z / _rx).length(), 0.0, 1.2)
	var light := clampf(0.15 + 0.55 * outside + 0.3 * own.y + 0.25 * off.y / _ry + shade * 0.35, 0.0, 1.0) * (1.0 - deep)
	var c := leaves_inner.lerp(leaves_outer, smoothstep(0.0, 0.55, light)).lerp(leaves_tips, smoothstep(0.55, 1.0, light))
	if odd:
		c = c.lerp(accent, 0.75)
	if snow > 0.0:
		c = c.lerp(snow_colour, snow * 0.8 * smoothstep(0.35, 0.8, own.y))
	return Color(c.r, c.g, c.b, 1.0)


## How much a point sways in the wind: nothing at the foot, more up the tree and out from it.
func _sway(p: Vector3) -> float:
	var h := clampf(p.y / maxf(_top, 0.1), 0.0, 1.0)
	var out := clampf(Vector2(p.x - _centre.x, p.z - _centre.z).length() / _rx, 0.0, 1.2)
	return clampf(pow(h, 1.5) * 0.7 + out * h * 0.4, 0.0, 1.0)


## A clump of fluffy cards: quads over a lumpy ball, each with the crown's normal.
func _fluffy(buf: _Buf, at: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	var count := clampi(roundi(22.0 * cards * (1.0 if _lod > 0 else 0.4)), 3, clampi(_card_cap, 3, 80))
	var grow := 1.0 if _lod > 0 else 1.35
	var odd := accent.a > 0.0 and rng.randf() < accent.a
	var shade := rng.randf_range(-1.0, 1.0) * dapple
	var spin := Basis(_jitter_on(rng).normalized(), rng.randf() * TAU)
	var phase := Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
	for i in count:
		# (spread evenly over the ball: a Fibonacci sphere, turned at random)
		var y := 1.0 - 2.0 * (i + 0.5) / count
		var r := sqrt(1.0 - y * y)
		var a := i * GOLDEN
		var d := spin * Vector3(cos(a) * r, y, sin(a) * r)
		var lump := 1.0 + lumpiness * 0.3 * sin(d.x * 3.0 + phase.x) * sin(d.y * 3.0 + phase.y) * sin(d.z * 3.0 + phase.z) * 2.0
		var centre := at + d * size * rng.randf_range(0.55, 0.9) * lump * Vector3(1.0, 0.85, 1.0)
		var half := size * card_size * 0.6 * rng.randf_range(0.8, 1.2) * grow
		var normal := (_round(centre) * 0.65 + d * 0.35).normalized()
		var col := _leaf_colour(centre, d, shade + rng.randf_range(-0.25, 0.25) * dapple, 0.0, odd)
		_card(buf, centre, d, half, rng.randf() * TAU, normal, col, Vector2(rng.randf(), _sway(centre)))


## Painted cards: a few big camera-facing ones to a clump.
func _painted(buf: _Buf, at: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	var count := clampi(roundi(3.0 * cards * (1.0 if _lod > 0 else 0.4)), 1, maxi(_card_cap, 1))
	var odd := accent.a > 0.0 and rng.randf() < accent.a
	for i in count:
		var d := _jitter_on(rng)
		var centre := at + Vector3(d.x, d.y * 0.7, d.z) * size * 0.6
		var half := size * card_size * rng.randf_range(0.75, 1.0) * (1.0 if _lod > 0 else 1.25)
		var normal := _round(centre)
		var col := _leaf_colour(centre, d.normalized(), rng.randf_range(-1.0, 1.0) * dapple, 0.0, odd)
		_card(buf, centre, (centre - _centre).normalized(), half, rng.randf() * TAU, normal, col, Vector2(rng.randf(), _sway(centre)))


func _jitter_on(rng: RandomNumberGenerator) -> Vector3:
	return Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))


## One card at `centre` facing `facing` (when not turned to the camera), `half` metres each way.
## Wound counter-clockwise seen from the front (Godot's front faces); corners TL, TR, BR, BL.
func _card(buf: _Buf, centre: Vector3, facing: Vector3, half: float, turn: float, normal: Vector3, col: Color, uv2: Vector2) -> void:
	var f := facing.normalized() if facing.length() > 0.001 else Vector3.BACK
	var t := _perp(f).rotated(f, turn)
	var u := f.cross(t)
	var first := buf.v.size()
	var corners := [[-1.0, 1.0, Vector2(0, 0)], [1.0, 1.0, Vector2(1, 0)], [1.0, -1.0, Vector2(1, 1)], [-1.0, -1.0, Vector2(0, 1)]]
	for c: Array in corners:
		buf.add(centre + (t * c[0] + u * c[1]) * half, normal, col, c[2], uv2)
		buf.add_custom(Vector4(centre.x, centre.y, centre.z, half))
	buf.tri(first, first + 2, first + 1)
	buf.tri(first, first + 3, first + 2)


## A lumpy faceted ball of leaves, every facet its own shade, with tufts standing out of it.
func _blob(buf: _Buf, at: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	var phase := Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
	var freq := rng.randf_range(2.2, 3.4)
	var odd := accent.a > 0.0 and rng.randf() < accent.a
	var squash := 0.75 if at.y < _centre.y else 0.9
	# (many small clumps are made coarser: 20 faces each instead of 80)
	for f: Array in _sphere(_lod if _card_cap > MAX_CARDS / 120 else 0):
		var shade := rng.randf_range(-1.0, 1.0) * dapple
		var first := buf.v.size()
		for v: Vector3 in f:
			var bump := 1.0 + lumpiness * 0.32 * (sin(v.x * freq + phase.x) * sin(v.y * freq + phase.y) * sin(v.z * freq + phase.z) * 2.0 + sin(v.x * freq * 2.3 + phase.y) * 0.5)
			var p := at + v * size * bump * Vector3(1.0, squash, 1.0)
			buf.add(p, (_round(p) * 0.7 + v * 0.3).normalized(), _leaf_colour(p, v, shade, 0.0, odd), Vector2.ZERO, Vector2(0.0, _sway(p)))
		buf.tri(first, first + 1, first + 2)
	if _lod == 0:
		return
	for i in tufts:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 1.0), rng.randf_range(-1, 1)).normalized()
		var foot := at + d * size * 0.82
		var tip := foot + (d + Vector3.UP * 0.3).normalized() * size * rng.randf_range(0.35, 0.6)
		var wide := size * rng.randf_range(0.22, 0.34)
		var ahead := (tip - foot).normalized()
		var side := _perp(ahead)
		var other := ahead.cross(side).normalized()
		var base: Array[Vector3] = [foot + side * wide, foot + other * wide, foot - side * wide, foot - other * wide]
		var shade := rng.randf_range(-1.0, 1.0) * dapple
		for j in 4:
			var a: Vector3 = base[j]
			var b: Vector3 = base[(j + 1) % 4]
			var first := buf.v.size()
			buf.add(a, _round(a), _leaf_colour(a, ahead, shade, 0.0, odd), Vector2.ZERO, Vector2(0.0, _sway(a)))
			buf.add(tip, _round(tip), _leaf_colour(tip, ahead, shade + 0.4, 0.0, odd), Vector2.ZERO, Vector2(0.0, _sway(tip)))
			buf.add(b, _round(b), _leaf_colour(b, ahead, shade, 0.0, odd), Vector2.ZERO, Vector2(0.0, _sway(b)))
			buf.tri(first, first + 1, first + 2)


## Needle cards along a leafy branch (a frond), crossed about it.
func _fronds(buf: _Buf, b: _Branch) -> void:
	var from := _leaf_from(b)
	var line: Array[Vector3] = []
	var steps := 4
	for k in steps + 1:
		line.append(_along(b.pts, lerpf(from, 1.0, float(k) / steps)))
	var span := b.length * (1.0 - from)
	var half := span * fullness * 0.62
	var count := 2 + maxi(sprigs - 1, 0) if _lod > 0 else 1
	var up_tree := clampf(b.pts[0].y / maxf(_top, 0.1), 0.0, 1.0)
	for c in count:
		_needle_card(buf, line, half * (1.0 if c == 0 else 0.65), c * PI / maxf(count, 2), Vector3.UP, up_tree)


## The leader: a frond straight up at the top of a strong trunk.
func _leader(buf: _Buf) -> void:
	var top := _trunk.pts[-1]
	var long := height * 0.09
	var line: Array[Vector3] = []
	for k in 5:
		line.append(top + Vector3.UP * long * (float(k) / 4.0 - 0.6))
	var count := 2 + maxi(sprigs - 1, 0) if _lod > 0 else 1
	for c in count:
		_needle_card(buf, line, long * fullness * 0.62, c * PI / maxf(count, 2), Vector3.RIGHT, 1.0)


## How far the needles reach out from a frond's twig, `s` of the way along it (the shader's outline).
static func _outline(s: float) -> float:
	return maxf(sin(PI * (0.1 + 0.9 * clampf(s, 0.0, 1.0))), 0.0)


func _needle_card(buf: _Buf, line: Array[Vector3], half: float, roll: float, up: Vector3, up_tree: float) -> void:
	var count := line.size()
	var along: Array[float] = [0.0]
	for k in range(1, count):
		along.append(along[k - 1] + line[k].distance_to(line[k - 1]))
	var total: float = along[count - 1]
	var first := buf.v.size()
	for k in count:
		var s := float(k) / (count - 1)
		var ahead := (line[mini(k + 1, count - 1)] - line[maxi(k - 1, 0)]).normalized()
		var across := ahead.cross(up).normalized()
		if across.length() < 0.5:
			across = _perp(ahead)
		var above := across.cross(ahead).normalized()
		var side := across * cos(roll) + above * sin(roll)
		var wide := minf(_outline(s) + 0.6 / (count - 1), 1.0)
		var p: Vector3 = line[k]
		var normal := (_round(p) + Vector3.UP * 0.2).normalized()
		var colour := leaves_inner.lerp(leaves_outer, smoothstep(0.0, 0.7, s)).lerp(leaves_tips, smoothstep(0.65, 1.0, s) * 0.8)
		colour = colour.lightened(up_tree * 0.06)
		if snow > 0.0 and roll == 0.0:
			colour = colour.lerp(snow_colour, snow * 0.6 * smoothstep(0.2, 0.7, normal.y))
		colour.a = clampf(half * 0.5, 0.0, 1.0)
		var sway := _sway(p)
		buf.add(p - side * half * wide, normal, colour, Vector2(along[k], -wide), Vector2(1.0, sway))
		buf.add_custom(Vector4(total, 0, 0, 0))
		buf.add(p + side * half * wide, normal, colour, Vector2(along[k], wide), Vector2(1.0, sway))
		buf.add_custom(Vector4(total, 0, 0, 0))
	for k in count - 1:
		var a := first + k * 2
		buf.tri(a, a + 2, a + 1)
		buf.tri(a + 1, a + 2, a + 3)


## The dark mass inside the crown: a ragged shape turned about the crown's middle, as wide at each
## height as the leaves reach there (times `fill`), so the crown reads as solid between its clumps.
func _fill(buf: _Buf, spots: Array, rng: RandomNumberGenerator) -> void:
	var bands := 8
	if spots.size() < 3:
		return
	# (from a little above the lowest leaves, so one low branch does not drag it to the ground)
	var heights: Array[float] = []
	var middle := Vector3.ZERO
	for s: Array in spots:
		heights.append((s[0] as Vector3).y)
		middle += s[0]
	heights.sort()
	middle /= spots.size()
	var lo: float = heights[int(heights.size() * 0.08)]
	var hi: float = heights[-1]
	if hi - lo < 0.2:
		return
	var reach: Array[float] = []
	var counts: Array[int] = []
	reach.resize(bands + 1)
	counts.resize(bands + 1)
	reach.fill(0.0)
	counts.fill(0)
	var mids: Array[Vector3] = []
	for k in bands + 1:
		mids.append(Vector3(middle.x, lo + (hi - lo) * k / bands, middle.z))
	# (how far the leaves reach out at each height, on average: the fill at 1 is a little past it)
	for s: Array in spots:
		var p: Vector3 = s[0]
		if p.y < lo:
			continue
		var k := clampi(roundi((p.y - lo) / (hi - lo) * bands), 0, bands)
		reach[k] += (Vector2(p.x - middle.x, p.z - middle.z).length() + float(s[1]) * 0.3) * 1.24
		counts[k] += 1
	for k in bands + 1:
		reach[k] = reach[k] / counts[k] if counts[k] > 0 else -1.0
	# (bands with no leaves take their neighbours'; smoothed; closed to a point at the top)
	for k in bands + 1:
		if reach[k] < 0.0:
			var below := k - 1
			while below >= 0 and reach[below] < 0.0:
				below -= 1
			var above := k + 1
			while above <= bands and reach[above] < 0.0:
				above += 1
			var a := reach[below] if below >= 0 else 0.0
			var b := reach[above] if above <= bands else 0.0
			reach[k] = maxf((a + b) * 0.5, 0.0)
	var smooth: Array[float] = []
	for k in bands + 1:
		smooth.append((reach[maxi(k - 1, 0)] + reach[k] * 2.0 + reach[mini(k + 1, bands)]) * 0.25)
	smooth[bands] *= 0.3
	var sides := 11 if _lod > 0 else 7
	var dark := leaves_inner.lerp(leaves_outer, 0.2)
	var rows: Array = []
	for k in bands + 1:
		var row: Array[int] = []
		for j in sides:
			var a := j * TAU / sides
			var r := smooth[k] * fill * rng.randf_range(0.78, 1.12)
			var p := mids[k] + Vector3(cos(a) * r, 0.0, sin(a) * r)
			var c := dark.lerp(snow_colour, snow * 0.5) if snow > 0.0 and k > 0 else dark
			row.append(buf.add(p, _round(p), c, Vector2.ZERO, Vector2(0.0, _sway(p) * 0.6)))
		rows.append(row)
	for k in bands:
		for j in sides:
			var a: int = rows[k][j]
			var b: int = rows[k][(j + 1) % sides]
			var c: int = rows[k + 1][j]
			var d: int = rows[k + 1][(j + 1) % sides]
			buf.tri(a, c, b)
			buf.tri(b, c, d)
	# its top and underside closed
	var top_i := buf.add(mids[bands] + Vector3.UP * 0.1, Vector3.UP, dark, Vector2.ZERO, Vector2(0.0, _sway(mids[bands]) * 0.6))
	var bottom_i := buf.add(mids[0] + Vector3.UP * 0.2, Vector3.DOWN, dark.darkened(0.2), Vector2.ZERO, Vector2(0.0, 0.0))
	for j in sides:
		buf.tri(rows[bands][(j + 1) % sides], rows[bands][j], top_i)
		buf.tri(rows[0][j], rows[0][(j + 1) % sides], bottom_i)


# ------------------------------------------------------------------ wood

func _wood(buf: _Buf, b: _Branch) -> void:
	# needle fronds draw their own twig; thin twigs far off are not drawn
	if leaf_style == Leaves.NEEDLES and b.level > 0 and _leaf_from(b) < 0.05:
		return
	var thin := 0.012 if _lod > 0 else 0.035
	if b.radii[0] < thin:
		return
	var sides: int = ([8, 6, 4, 3, 3] if _lod > 0 else [6, 4, 3, 3, 3])[mini(b.level, 4)]
	_tube(buf, b.pts, b.radii, sides)


func _tube(buf: _Buf, pts: Array[Vector3], radii: Array[float], sides: int) -> void:
	var side := Vector3.ZERO
	var rings: Array = []
	var v := 0.0
	for i in pts.size():
		var fwd: Vector3
		if i == 0:
			fwd = pts[1] - pts[0]
		elif i == pts.size() - 1:
			fwd = pts[i] - pts[i - 1]
		else:
			fwd = pts[i + 1] - pts[i - 1]
		fwd = fwd.normalized()
		# (the frame carried along, so the tube does not twist)
		side = _perp(fwd) if i == 0 else (side - fwd * side.dot(fwd)).normalized()
		var other := fwd.cross(side).normalized()
		if i > 0:
			v += pts[i].distance_to(pts[i - 1])
		var sway := _sway(pts[i])
		var shade := bark.darkened(0.12 * (fposmod(sin(pts[i].dot(Vector3(12.9, 78.2, 37.7))) * 43758.5, 1.0)))
		var ring: Array[int] = []
		for j in sides + 1:
			var a := j * TAU / sides
			var radial := side * cos(a) + other * sin(a)
			ring.append(buf.add(pts[i] + radial * radii[i], radial, shade, Vector2(float(j) / sides, v), Vector2(0.0, sway)))
		rings.append(ring)
	for i in rings.size() - 1:
		for j in sides:
			var a: int = rings[i][j]
			var b: int = rings[i][j + 1]
			var c: int = rings[i + 1][j]
			var d: int = rings[i + 1][j + 1]
			buf.tri(a, b, c)
			buf.tri(b, d, c)


## A root from the foot: out and down, wandering, thinning to nothing.
func _root(buf: _Buf, k: int, rng: RandomNumberGenerator) -> void:
	var a := TAU * k / roots + rng.randf_range(-0.3, 0.3)
	var out := Vector3(cos(a), 0.0, sin(a))
	var long := trunk_radius * rng.randf_range(2.5, 5.0) + 0.5
	var thick := trunk_radius * rng.randf_range(0.35, 0.55)
	var bendy := rng.randf_range(-0.6, 0.6)
	var pts: Array[Vector3] = []
	var radii: Array[float] = []
	var p := out * trunk_radius * 0.5 + Vector3.UP * trunk_radius * rng.randf_range(0.5, 1.0)
	for i in 7:
		var t := i / 6.0
		pts.append(p)
		radii.append(thick * lerpf(1.0, 0.12, pow(t, 0.8)))
		var d := out.rotated(Vector3.UP, bendy * sin(t * 3.0 + a))
		p += d * long / 6.0 + Vector3.UP * (-0.55 * trunk_radius * (1.0 - t) - (0.1 if t > 0.75 else 0.0))
		p.y = maxf(p.y, -0.2)
	_tube(buf, pts, radii, 5 if _lod > 0 else 4)


## A ball's faces (unit radius): an icosahedron, split once into 80 at full detail.
static var _spheres := {}


static func _sphere(detail: int) -> Array:
	if _spheres.has(detail):
		return _spheres[detail]
	var g := (1.0 + sqrt(5.0)) * 0.5
	var v: Array[Vector3] = [Vector3(-1, g, 0), Vector3(1, g, 0), Vector3(-1, -g, 0), Vector3(1, -g, 0), Vector3(0, -1, g), Vector3(0, 1, g),
		Vector3(0, -1, -g), Vector3(0, 1, -g), Vector3(g, 0, -1), Vector3(g, 0, 1), Vector3(-g, 0, -1), Vector3(-g, 0, 1)]
	for i in v.size():
		v[i] = v[i].normalized()
	var idx := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var faces: Array = []
	for f in idx:
		faces.append([v[f[0]], v[f[1]], v[f[2]]])
	for d in detail:
		var finer: Array = []
		for f: Array in faces:
			var a: Vector3 = f[0]
			var b: Vector3 = f[1]
			var c: Vector3 = f[2]
			var ab := (a + b).normalized()
			var bc := (b + c).normalized()
			var ca := (c + a).normalized()
			finer.append_array([[a, ab, ca], [b, bc, ab], [c, ca, bc], [ab, bc, ca]])
		faces = finer
	_spheres[detail] = faces
	return faces
