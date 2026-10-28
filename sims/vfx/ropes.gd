extends Sim3D
## Rope Lab: GameCommon's rope (RopeStyle, RopeLine, RopePatch) in four scenes. A kelp forest
## standing up in a surging current with a seal to part it (after the Dynamic Kelp in Unity
## article); Warren's vines hanging from a stone lintel and strung between its pillars, to push
## and cut; Hemlock's Tower's telegraph wires, bouncy, with crows riding them, to drop balls on;
## plain hemp ropes and a chain to grab and swing. Every RopeStyle setting is a property, and
## Export saves the style (.tres) and the scene's patch (.tscn).

enum Scene { KELP, VINES, WIRES, ROPES }
const SCENES := ["Kelp forest", "Vines", "Wires", "Ropes"]
const NAMES := ["Kelp Forest", "Jungle Vines", "Telegraph Wires", "Hemp Ropes"]
const SEABED := preload("res://sims/vfx/ropes_seabed.gdshader")
const MAX_BALLS := 10

## Stem colours and leaf colours: [name, root, tip].
const STEMS := [
	["Giant kelp", Color(0.2, 0.15, 0.06), Color(0.55, 0.45, 0.14)],
	["Bull kelp", Color(0.25, 0.2, 0.08), Color(0.45, 0.38, 0.12)],
	["Red weed", Color(0.3, 0.08, 0.06), Color(0.6, 0.2, 0.12)],
	["Jungle vine", Color(0.2, 0.24, 0.12), Color(0.26, 0.33, 0.14)],
	["Hemp", Color(0.56, 0.46, 0.3), Color(0.5, 0.4, 0.26)],
	["Tarred", Color(0.16, 0.12, 0.08), Color(0.2, 0.15, 0.1)],
	["Black wire", Color(0.09, 0.08, 0.09), Color(0.09, 0.08, 0.09)],
	["Copper", Color(0.55, 0.3, 0.15), Color(0.5, 0.27, 0.13)],
	["Iron", Color(0.28, 0.27, 0.27), Color(0.36, 0.3, 0.26)],
]
const LEAVES := [
	["Kelp gold", Color(0.33, 0.25, 0.08), Color(0.62, 0.52, 0.16)],
	["Kelp olive", Color(0.25, 0.27, 0.1), Color(0.5, 0.5, 0.18)],
	["Red weed", Color(0.4, 0.1, 0.08), Color(0.75, 0.28, 0.15)],
	["Ivy green", Color(0.17, 0.29, 0.12), Color(0.26, 0.4, 0.15)],
	["Spring", Color(0.3, 0.5, 0.15), Color(0.55, 0.7, 0.25)],
	["Autumn", Color(0.55, 0.25, 0.08), Color(0.85, 0.55, 0.15)],
	["Dead", Color(0.35, 0.3, 0.2), Color(0.5, 0.42, 0.28)],
]

var scene := Scene.KELP
## Each scene's style, kept while you switch between them.
var styles := {
	Scene.KELP: RopeStyle.kelp(),
	Scene.VINES: RopeStyle.vine(),
	Scene.WIRES: RopeStyle.wire(),
	Scene.ROPES: RopeStyle.rope(),
}
var preset := {Scene.KELP: 2, Scene.VINES: 1, Scene.WIRES: 4, Scene.ROPES: 0}
var stem_palette := {Scene.KELP: 0, Scene.VINES: 3, Scene.WIRES: 6, Scene.ROPES: 4}
var leaf_palette := {Scene.KELP: 0, Scene.VINES: 3, Scene.WIRES: 3, Scene.ROPES: 3}

var kelp_count := 32
var swimmer_auto := true
var bubbles_on := true
var vine_tap := 0 # 0 push, 1 cut
var bird_count := 7
var ball_heft := 0.85

var root: Node3D
## The scene's main patch (what Export saves) and every line in the scene.
var patch: RopePatch
var extra: Array[RopeLine] = []
var strand: RopeLine
var swimmer: Pusher
var hand: Pusher
var balls: Array[Ball] = []
var crows: Array[Crow] = []
var bubbles: CPUParticles3D

var _t := 0.0
var _grab: RopeLine
var _grab_at := 0.0
var _grab_plane := Plane()
var _finger := Vector3.ZERO
var _fingering := false
var _rng := RandomNumberGenerator.new()


func style() -> RopeStyle:
	return styles[scene]


func pokeable() -> bool:
	return true


func hint() -> String:
	return "Kelp, vines, wires and ropes on one chain sim. Set Finger to Poke to touch them."


func help() -> String:
	return ("GameCommon's rope: a chain of points (Verlet, held to length by XPBD constraints) pulled by "
		+ "gravity, dragged towards the water or air round it and stiffened against bending. Negative "
		+ "gravity floats it up, so kelp stands from the seabed. The current is a steady flow, a to-and-fro "
		+ "surge and gusts of 3D noise rolling along it, so waves cross the forest. Stretch makes it rubbery: "
		+ "a wire dips under a ball and throws it back up (Hemlock's Tower's tightropes). The GPU lays the "
		+ "tube and every leaf along the points: leaves lean out, droop, stream in the flow past them and "
		+ "flutter, with no work on the CPU.\n\n"
		+ "Kelp forest: drag the seal through the kelp in Poke mode (or let it swim). Vines: push them, or "
		+ "set Tap to Cut and tap one; cut the strung vine and it falls into two hanging vines, with the "
		+ "vines hung from it. Wires: tap to drop a ball onto a wire; the crows ride its bounce, or fly. "
		+ "Ropes: grab a rope or the chain and swing it.\n\n"
		+ "Look: one finger orbits, two pinch and pan, the wheel zooms.\n\n"
		+ "Export saves the style (.tres) and this scene's RopePatch (.tscn) for any project "
		+ "(needs godot/rope).")


func build() -> void:
	_rng.seed = 7
	_build_scene()


func status() -> String:
	var lines := _lines()
	var awake := 0
	var leaves := 0
	for line in lines:
		if not line.is_sleeping():
			awake += 1
		leaves += line.leaf_count()
	return "%s: %d lines, %d awake, %d leaves  %.1f ms" % [SCENES[scene], lines.size(), awake, leaves, frame_ms()]


# --- Properties ----------------------------------------------------------------------

func controls() -> Array:
	var s := style()
	var list := look_controls()
	list.append_array([
		{type = "section", label = "Scene"},
		{type = "choice", label = "Scene", options = SCENES, value = scene, on = func(i: int) -> void:
			if i != scene:
				scene = i as Scene
				_build_scene()
				controls_changed.emit()},
		{type = "button", label = "Reset", on = func() -> void: _build_scene()},
	])
	match scene:
		Scene.KELP:
			list.append_array([
				{type = "slider", label = "Stalks", min = 4.0, max = 60.0, step = 1.0, value = kelp_count, fmt = "%.0f",
					on = func(v: float) -> void:
						if int(v) != kelp_count:
							kelp_count = int(v)
							_build_scene()},
				{type = "toggle", label = "Seal swims", value = swimmer_auto, on = func(on: bool) -> void: swimmer_auto = on},
				{type = "toggle", label = "Bubbles", value = bubbles_on, on = func(on: bool) -> void:
					bubbles_on = on
					if bubbles:
						bubbles.emitting = on},
			])
		Scene.VINES:
			list.append_array([
				{type = "choice", label = "Tap", options = ["Push", "Cut"], value = vine_tap, on = func(i: int) -> void: vine_tap = i},
				{type = "button", label = "Cut the strung vine", on = func() -> void:
					if is_instance_valid(strand):
						strand.cut(strand.rest_length() * 0.55)},
			])
		Scene.WIRES:
			list.append_array([
				{type = "button", label = "Drop a ball", on = func() -> void: _drop_on_wire()},
				{type = "slider", label = "Crows", min = 0.0, max = 14.0, step = 1.0, value = bird_count, fmt = "%.0f",
					on = func(v: float) -> void:
						if int(v) != bird_count:
							bird_count = int(v)
							_make_crows()},
				{type = "slider", label = "Ball heft", min = 0.3, max = 0.98, step = 0.01, value = ball_heft, fmt = "%.2f",
					on = func(v: float) -> void:
						ball_heft = v
						for b in balls:
							b.heft = v},
			])
		Scene.ROPES:
			list.append_array([
				{type = "button", label = "Kick them", on = func() -> void:
					for line in _lines():
						line.push(line.rest_length() * 0.8, Vector3(_rng.randf_range(-4, 4), 0, _rng.randf_range(-4, 4)))},
			])
	list.append_array([
		{type = "choice", label = "Start from", options = RopeStyle.PRESETS, value = preset[scene], on = func(i: int) -> void:
			preset[scene] = i
			s.copy_from(RopeStyle.preset(RopeStyle.PRESETS[i]))
			_match_palettes()
			controls_changed.emit()},
		{type = "section", label = "Physics"},
		{type = "slider", label = "Pieces", min = 4.0, max = 24.0, step = 1.0, value = s.pieces, fmt = "%.0f",
			on = func(v: float) -> void: s.pieces = int(v)},
		{type = "slider", label = "Gravity", min = -15.0, max = 25.0, step = 0.1, value = s.gravity, fmt = "%.1f", unit = "m/s²",
			on = func(v: float) -> void: s.gravity = v},
		{type = "slider", label = "Drag", min = 0.0, max = 6.0, step = 0.05, value = s.drag, fmt = "%.2f", unit = "/s",
			on = func(v: float) -> void: s.drag = v},
		{type = "slider", label = "Bend", min = 0.0, max = 1.0, step = 0.01, value = s.bend, fmt = "%.2f",
			on = func(v: float) -> void: s.bend = v},
		{type = "slider", label = "Stretch", min = 0.0, max = 1.0, step = 0.01, value = s.stretch, fmt = "%.2f",
			on = func(v: float) -> void: s.stretch = v},
		{type = "slider", label = "Iterations", min = 1.0, max = 16.0, step = 1.0, value = s.iterations, fmt = "%.0f",
			on = func(v: float) -> void: s.iterations = int(v)},
		{type = "section", label = "Current"},
		{type = "slider", label = "Flow", min = 0.0, max = 3.0, step = 0.05, value = s.current, fmt = "%.2f", unit = "m/s",
			on = func(v: float) -> void: s.current = v},
		{type = "slider", label = "Heading", min = 0.0, max = 360.0, step = 5.0, value = s.current_direction, fmt = "%.0f", unit = "°",
			on = func(v: float) -> void: s.current_direction = v},
		{type = "slider", label = "Surge", min = 0.0, max = 2.0, step = 0.05, value = s.surge, fmt = "%.2f", unit = "m/s",
			on = func(v: float) -> void: s.surge = v},
		{type = "slider", label = "Surge period", min = 2.0, max = 20.0, step = 0.5, value = s.surge_period, fmt = "%.1f", unit = "s",
			on = func(v: float) -> void: s.surge_period = v},
		{type = "slider", label = "Gusts", min = 0.0, max = 3.0, step = 0.05, value = s.gusts, fmt = "%.2f", unit = "m/s",
			on = func(v: float) -> void: s.gusts = v},
		{type = "slider", label = "Gust size", min = 1.0, max = 30.0, step = 0.5, value = s.gust_size, fmt = "%.1f", unit = "m",
			on = func(v: float) -> void: s.gust_size = v},
		{type = "slider", label = "Gust speed", min = 0.0, max = 8.0, step = 0.1, value = s.gust_speed, fmt = "%.1f", unit = "m/s",
			on = func(v: float) -> void: s.gust_speed = v},
		{type = "section", label = "Look"},
		{type = "slider", label = "Thick at root", min = 0.2, max = 15.0, step = 0.1, value = s.thickness_root * 100.0, fmt = "%.1f", unit = "cm",
			on = func(v: float) -> void: s.thickness_root = v / 100.0},
		{type = "slider", label = "Thick at tip", min = 0.0, max = 15.0, step = 0.1, value = s.thickness_tip * 100.0, fmt = "%.1f", unit = "cm",
			on = func(v: float) -> void: s.thickness_tip = v / 100.0},
		{type = "slider", label = "Taper", min = 0.2, max = 4.0, step = 0.05, value = s.taper, fmt = "%.2f",
			on = func(v: float) -> void: s.taper = v},
		{type = "choice", label = "Colours", options = STEMS.map(func(p: Array) -> String: return p[0]), value = stem_palette[scene],
			on = func(i: int) -> void:
				stem_palette[scene] = i
				s.colour_root = STEMS[i][1]
				s.colour_tip = STEMS[i][2]},
		{type = "slider", label = "Strands", min = 0.0, max = 1.0, step = 0.01, value = s.twist, fmt = "%.2f",
			on = func(v: float) -> void: s.twist = v},
		{type = "slider", label = "Links", min = 0.0, max = 1.0, step = 0.01, value = s.beads, fmt = "%.2f",
			on = func(v: float) -> void: s.beads = v},
		{type = "slider", label = "End knot", min = 0.0, max = 1.0, step = 0.01, value = s.knot, fmt = "%.2f",
			on = func(v: float) -> void: s.knot = v},
		{type = "slider", label = "Shine", min = 0.0, max = 1.0, step = 0.01, value = s.shine, fmt = "%.2f",
			on = func(v: float) -> void: s.shine = v},
		{type = "slider", label = "Sides", min = 3.0, max = 12.0, step = 1.0, value = s.sides, fmt = "%.0f",
			on = func(v: float) -> void: s.sides = int(v)},
		{type = "section", label = "Leaves"},
		{type = "choice", label = "Kind", options = ["None", "Vine", "Kelp", "Blade"], value = s.leaf_kind,
			on = func(i: int) -> void: s.leaf_kind = i as RopeStyle.Leaf},
		{type = "slider", label = "Per metre", min = 0.0, max = 40.0, step = 0.5, value = s.leaves_per_metre, fmt = "%.1f",
			on = func(v: float) -> void: s.leaves_per_metre = v},
		{type = "slider", label = "Size", min = 2.0, max = 150.0, step = 1.0, value = s.leaf_size * 100.0, fmt = "%.0f", unit = "cm",
			on = func(v: float) -> void: s.leaf_size = v / 100.0},
		{type = "slider", label = "From", min = 0.0, max = 1.0, step = 0.01, value = s.leaf_from, fmt = "%.2f",
			on = func(v: float) -> void: s.leaf_from = v},
		{type = "slider", label = "To", min = 0.0, max = 1.0, step = 0.01, value = s.leaf_to, fmt = "%.2f",
			on = func(v: float) -> void: s.leaf_to = v},
		{type = "slider", label = "Bunched at root", min = 0.0, max = 1.0, step = 0.01, value = s.leaf_bunch, fmt = "%.2f",
			on = func(v: float) -> void: s.leaf_bunch = v},
		{type = "choice", label = "Leaf colours", options = LEAVES.map(func(p: Array) -> String: return p[0]), value = leaf_palette[scene],
			on = func(i: int) -> void:
				leaf_palette[scene] = i
				s.leaf_colour_root = LEAVES[i][1]
				s.leaf_colour_tip = LEAVES[i][2]},
		{type = "slider", label = "Vary", min = 0.0, max = 1.0, step = 0.01, value = s.leaf_vary, fmt = "%.2f",
			on = func(v: float) -> void: s.leaf_vary = v},
		{type = "slider", label = "Lean", min = 0.0, max = 120.0, step = 1.0, value = s.leaf_lean, fmt = "%.0f", unit = "°",
			on = func(v: float) -> void: s.leaf_lean = v},
		{type = "slider", label = "Droop", min = 0.0, max = 1.0, step = 0.01, value = s.leaf_droop, fmt = "%.2f",
			on = func(v: float) -> void: s.leaf_droop = v},
		{type = "slider", label = "Stream", min = 0.0, max = 1.0, step = 0.01, value = s.leaf_stream, fmt = "%.2f",
			on = func(v: float) -> void: s.leaf_stream = v},
		{type = "slider", label = "Flutter", min = 0.0, max = 1.0, step = 0.01, value = s.leaf_flutter, fmt = "%.2f",
			on = func(v: float) -> void: s.leaf_flutter = v},
		{type = "slider", label = "Curl", min = 0.0, max = 1.0, step = 0.01, value = s.leaf_curl, fmt = "%.2f",
			on = func(v: float) -> void: s.leaf_curl = v},
		{type = "slider", label = "Ruffle", min = 0.0, max = 1.0, step = 0.01, value = s.leaf_ruffle, fmt = "%.2f",
			on = func(v: float) -> void: s.leaf_ruffle = v},
	])
	list.append_array(Exporter.controls(NAMES[scene], _export, "ropes", func(line: String) -> void: say.emit(line)))
	return list


## After a preset: the colour choices that match it (or the first).
func _match_palettes() -> void:
	var s := style()
	stem_palette[scene] = 0
	for i in STEMS.size():
		if STEMS[i][1].is_equal_approx(s.colour_root):
			stem_palette[scene] = i
	leaf_palette[scene] = 0
	for i in LEAVES.size():
		if LEAVES[i][1].is_equal_approx(s.leaf_colour_root):
			leaf_palette[scene] = i


func _export(name: String) -> void:
	var slug := Exporter.slug(name)
	var saved := style().duplicate() as RopeStyle
	var out := RopePatch.new()
	out.name = slug.to_pascal_case()
	for p in ["mode", "count", "seed", "size", "to", "length_min", "length_max", "spread", "slack", "posts",
			"post_height", "floor_height", "shadows", "transform"]:
		out.set(p, patch.get(p))
	out.style = style().duplicate() as RopeStyle
	say.emit(Exporter.save("ropes", name, {"tres": saved, "tscn": out}, ["godot/rope"],
		"var patch := (load(\"res://assets/ropes/%s.tscn\") as PackedScene).instantiate() as RopePatch\n" % slug
		+ "add_child(patch)   # its RopeLines build themselves; patch.settle(2.0) to start them settled\n"
		+ "var line := RopeLine.new(); line.style = load(\"res://assets/ropes/%s.tres\"); line.length = 4.0; add_child(line)" % slug,
		"Rope Lab"))
	out.free()


# --- Scenes --------------------------------------------------------------------------

func _lines() -> Array[RopeLine]:
	var out: Array[RopeLine] = []
	if not is_instance_valid(root):
		return out
	_collect(root, out)
	return out


func _collect(node: Node, out: Array[RopeLine]) -> void:
	for c in node.get_children():
		if c is RopeLine:
			out.append(c)
		_collect(c, out)


func _build_scene() -> void:
	if is_instance_valid(root):
		root.free()
	root = Node3D.new()
	world.add_child(root)
	patch = null
	extra.clear()
	strand = null
	swimmer = null
	hand = null
	balls.clear()
	crows.clear()
	bubbles = null
	_grab = null
	environment.fog_enabled = false
	environment.background_mode = Environment.BG_COLOR
	sun.shadow_enabled = true
	match scene:
		Scene.KELP:
			_build_kelp()
		Scene.VINES:
			_build_vines()
		Scene.WIRES:
			_build_wires()
		Scene.ROPES:
			_build_ropes()
	_place_camera()


func _build_kelp() -> void:
	var water := Color(0.05, 0.27, 0.36)
	environment.background_color = Color(0.03, 0.15, 0.22)
	environment.fog_enabled = true
	environment.fog_light_color = water
	environment.fog_density = 0.055
	environment.fog_sky_affect = 1.0
	environment.ambient_light_color = Color(0.3, 0.55, 0.62)
	environment.ambient_light_energy = 0.75
	sun.rotation = Vector3(deg_to_rad(-72), deg_to_rad(-30), 0)
	sun.light_color = Color(0.8, 0.95, 1.0)
	sun.light_energy = 1.25
	sun.shadow_opacity = 0.3
	sun.directional_shadow_max_distance = 40.0
	focus = Vector3(0, 4.2, 0)
	distance = 15.0
	pitch = -0.08
	yaw = 0.5
	min_pitch = -1.3
	max_pitch = 0.6
	min_distance = 2.0
	max_distance = 40.0
	auto_orbit = 0.035

	var bed := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	bed.mesh = pm
	var bm := ShaderMaterial.new()
	bm.shader = SEABED
	bed.material_override = bm
	root.add_child(bed)
	# a few rocks
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.36, 0.34, 0.3)
	rock_mat.roughness = 1.0
	for k in 7:
		var rock := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radial_segments = 10
		sm.rings = 6
		rock.mesh = sm
		rock.material_override = rock_mat
		var r := _rng.randf_range(0.5, 1.3)
		rock.scale = Vector3(r * 1.4, r * 0.6, r)
		rock.rotation.y = _rng.randf() * TAU
		rock.position = Vector3(_rng.randf_range(-11, 11), 0.05, _rng.randf_range(-9, 9))
		root.add_child(rock)
	# the surface seen from below: bright, rippling
	var surface := MeshInstance3D.new()
	var sp := PlaneMesh.new()
	sp.size = Vector2(120, 120)
	sp.flip_faces = true
	surface.mesh = sp
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
varying vec3 w;
void vertex() { w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float r = sin(w.x * 0.9 + TIME * 0.7 + sin(w.z * 0.6 + TIME * 0.4) * 2.0) * sin(w.z * 1.1 - TIME * 0.5 + sin(w.x * 0.4) * 2.0);
	float d = length(w.xz - CAMERA_POSITION_WORLD.xz);
	vec3 c = mix(vec3(0.6, 0.9, 1.0), vec3(0.05, 0.3, 0.4), smoothstep(6.0, 40.0, d));
	ALBEDO = c * (0.85 + 0.25 * r);
}"""
	var smat := ShaderMaterial.new()
	smat.shader = sh
	surface.material_override = smat
	surface.position.y = 13.0
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(surface)
	_add_shafts()

	patch = RopePatch.new()
	patch.style = style()
	patch.mode = RopePatch.Mode.GROUND
	patch.count = kelp_count
	patch.seed = 3
	patch.size = Vector2(22, 16)
	patch.length_min = 6.5
	patch.length_max = 11.0
	patch.floor_height = 0.05
	root.add_child(patch)
	patch.settle(2.0)
	# holdfasts: a knot of roots gripping the seabed under each
	var holds := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var lump := SphereMesh.new()
	lump.radial_segments = 8
	lump.rings = 4
	mm.mesh = lump
	mm.instance_count = patch.lines.size()
	for i in patch.lines.size():
		var at := patch.lines[i].global_position
		var r := _rng.randf_range(0.12, 0.2)
		mm.set_instance_transform(i, Transform3D(Basis.from_euler(Vector3(0, _rng.randf() * TAU, 0)).scaled(Vector3(r * 1.5, r * 0.7, r * 1.3)), at))
	holds.multimesh = mm
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.22, 0.17, 0.08)
	hm.roughness = 1.0
	holds.material_override = hm
	root.add_child(holds)

	swimmer = Pusher.seal()
	swimmer.position = Vector3(0, 4, 0)
	root.add_child(swimmer)

	bubbles = CPUParticles3D.new()
	bubbles.amount = 70
	bubbles.lifetime = 7.0
	bubbles.preprocess = 7.0
	bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	bubbles.emission_box_extents = Vector3(10, 0.1, 7)
	bubbles.direction = Vector3.UP
	bubbles.spread = 8.0
	bubbles.gravity = Vector3(0, 0.6, 0)
	bubbles.initial_velocity_min = 0.6
	bubbles.initial_velocity_max = 1.2
	bubbles.scale_amount_min = 0.4
	bubbles.scale_amount_max = 1.2
	var bubble := SphereMesh.new()
	bubble.radius = 0.04
	bubble.height = 0.08
	bubble.radial_segments = 6
	bubble.rings = 3
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.85, 0.97, 1.0, 0.55)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bubble.material = bmat
	bubbles.mesh = bubble
	bubbles.emitting = bubbles_on
	bubbles.position = Vector3(0, 0.2, 0)
	root.add_child(bubbles)


## Tall soft shafts of light slanting down through the water.
func _add_shafts() -> void:
	# (soft on both sides, brightest near the surface, gone before the seabed)
	var img := Image.create(32, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		var v := y / 63.0
		for x in 32:
			var u := x / 31.0
			var a := pow(sin(PI * u), 2.0) * smoothstep(0.0, 0.2, v) * pow(1.0 - v, 1.4)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = Color(0.55, 0.85, 0.95, 0.16)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.disable_fog = true
	m.no_depth_test = false
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	for k in 9:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(_rng.randf_range(1.2, 2.8), 16.0)
		q.mesh = qm
		q.material_override = m
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.position = Vector3(_rng.randf_range(-12, 12), 6.0, _rng.randf_range(-9, 9))
		root.add_child(q)


func _build_vines() -> void:
	set_sky(Color(0.24, 0.3, 0.32), Color(0.56, 0.6, 0.54), Color(0.2, 0.24, 0.18))
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.5, 0.56, 0.5)
	environment.fog_density = 0.012
	environment.fog_sky_affect = 0.3
	environment.ambient_light_color = Color(0.5, 0.58, 0.55)
	environment.ambient_light_energy = 0.55
	sun.rotation = Vector3(deg_to_rad(-40), deg_to_rad(-150), 0)
	sun.light_color = Color(1.0, 0.92, 0.78)
	sun.light_energy = 1.35
	sun.shadow_opacity = 0.7
	sun.directional_shadow_max_distance = 30.0
	focus = Vector3(0, 3.6, 0)
	distance = 12.5
	pitch = -0.12
	yaw = 0.25
	min_pitch = -1.3
	max_pitch = 0.4
	min_distance = 2.0
	max_distance = 35.0
	auto_orbit = 0.0
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	ground.mesh = pm
	var gm := ShaderMaterial.new()
	gm.shader = preload("res://sims/vfx/grass_ground.gdshader")
	gm.set_shader_parameter(&"ground", Color(0.17, 0.2, 0.12))
	gm.set_shader_parameter(&"far_colour", Color(0.45, 0.5, 0.45))
	ground.material_override = gm
	root.add_child(ground)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.4, 0.4, 0.37)
	stone.roughness = 1.0
	var moss := StandardMaterial3D.new()
	moss.albedo_color = Color(0.22, 0.3, 0.13)
	moss.roughness = 1.0
	for x in [-5.0, 5.0]:
		_box(Vector3(x, 3.0, 0), Vector3(1.0, 6.0, 1.0), stone)
		_box(Vector3(x, 0.15, 0), Vector3(1.4, 0.3, 1.4), stone)
	_box(Vector3(0, 6.35, 0), Vector3(12.0, 0.7, 1.1), stone)
	_box(Vector3(0, 6.74, 0), Vector3(12.2, 0.1, 1.2), moss)
	# vines hanging from the lintel's underside
	patch = RopePatch.new()
	patch.style = style()
	patch.mode = RopePatch.Mode.BEAM
	patch.count = 10
	patch.seed = 5
	patch.to = Vector3(8.6, 0, 0)
	patch.spread = 0.3
	patch.length_min = 2.2
	patch.length_max = 5.2
	patch.floor_height = 0.02
	patch.position = Vector3(-4.3, 5.98, 0)
	root.add_child(patch)
	patch.settle(1.0)
	# a vine strung between the pillars, in front, with vines hanging from it
	strand = RopeLine.new()
	strand.style = style()
	strand.strung = true
	strand.slack = 1.06
	strand.position = Vector3(-4.45, 4.3, 0.75)
	strand.end = Vector3(8.9, 0.3, 0)
	strand.floor_height = 0.02
	strand.seed = 77
	root.add_child(strand)
	strand.settle(1.5)
	for d: float in [2.6, 4.4, 6.5]:
		var hung := RopeLine.new()
		hung.style = style()
		hung.length = _rng.randf_range(1.4, 2.6)
		hung.floor_height = 0.02
		hung.seed = int(d * 10)
		hung.position = strand.point_at(d) + Vector3.DOWN * 0.04
		root.add_child(hung)
		strand.attach(hung, d, Vector3.DOWN * 0.04, 0.4)
		hung.settle(1.0)
	strand.settle(1.0)
	hand = Pusher.ball(0.35, Color(1.0, 0.85, 0.6, 0.35))
	hand.visible = false
	hand.position = Vector3(0, -10, 0)
	root.add_child(hand)


func _build_wires() -> void:
	set_sky(Color(0.28, 0.32, 0.58), Color(0.98, 0.66, 0.45), Color(0.3, 0.25, 0.25))
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.82, 0.62, 0.55)
	environment.fog_density = 0.005
	environment.fog_sky_affect = 0.0
	environment.ambient_light_color = Color(0.6, 0.55, 0.62)
	environment.ambient_light_energy = 0.55
	sun.rotation = Vector3(deg_to_rad(-24), deg_to_rad(-60), 0)
	sun.light_color = Color(1.0, 0.78, 0.55)
	sun.light_energy = 1.3
	sun.shadow_opacity = 0.7
	sun.directional_shadow_max_distance = 50.0
	focus = Vector3(0, 4.7, 1.5)
	distance = 10.5
	pitch = -0.07
	yaw = 0.8
	min_pitch = -1.3
	max_pitch = 0.5
	min_distance = 2.0
	max_distance = 45.0
	auto_orbit = 0.0
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := ShaderMaterial.new()
	gm.shader = preload("res://sims/vfx/grass_ground.gdshader")
	gm.set_shader_parameter(&"ground", Color(0.15, 0.21, 0.08))
	gm.set_shader_parameter(&"far_colour", Color(0.45, 0.4, 0.34))
	ground.material_override = gm
	root.add_child(ground)
	# three poles in a row, wires between
	var height := 5.6
	patch = _span(Vector3(0, height, -11), Vector3(0, 0, 11), RopePatch.Posts.BOTH)
	_span(Vector3(0, height, 0), Vector3(0, 0, 11), RopePatch.Posts.END)
	_make_crows()


func _span(from: Vector3, to: Vector3, posts: int) -> RopePatch:
	var p := RopePatch.new()
	p.style = style()
	p.mode = RopePatch.Mode.SPAN
	p.count = 3
	p.spread = 0.55
	p.slack = 1.004
	p.to = to
	p.posts = posts
	p.post_height = from.y
	p.seed = int(from.z) + 20
	p.floor_height = 0.02
	p.position = from
	root.add_child(p)
	p.settle(2.0)
	return p


func _build_ropes() -> void:
	environment.background_color = Color(0.12, 0.1, 0.09)
	environment.ambient_light_color = Color(0.6, 0.52, 0.45)
	environment.ambient_light_energy = 0.55
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.16, 0.13, 0.11)
	environment.fog_density = 0.03
	environment.fog_sky_affect = 1.0
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(-25), 0)
	sun.light_color = Color(1.0, 0.86, 0.66)
	sun.light_energy = 0.8
	sun.shadow_opacity = 0.75
	sun.directional_shadow_max_distance = 30.0
	focus = Vector3(0, 3.4, 0)
	distance = 10.5
	pitch = -0.12
	yaw = 0.3
	min_pitch = -1.3
	max_pitch = 0.4
	min_distance = 2.0
	max_distance = 30.0
	auto_orbit = 0.0
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.3, 0.21, 0.14)
	wood.roughness = 0.9
	var floor_wood := StandardMaterial3D.new()
	floor_wood.albedo_color = Color(0.2, 0.16, 0.12)
	floor_wood.roughness = 1.0
	_box(Vector3(0, -0.05, 0), Vector3(40, 0.1, 40), floor_wood)
	# a warm lamp by the frame
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.75, 0.45)
	lamp.light_energy = 2.2
	lamp.omni_range = 12.0
	lamp.position = Vector3(-2.5, 5.0, 3.0)
	root.add_child(lamp)
	for x in [-4.5, 4.5]:
		_box(Vector3(x, 3.1, 0), Vector3(0.35, 6.2, 0.35), wood)
	_box(Vector3(0, 6.3, 0), Vector3(9.6, 0.4, 0.4), wood)
	patch = RopePatch.new()
	patch.style = style()
	patch.mode = RopePatch.Mode.BEAM
	patch.count = 4
	patch.seed = 9
	patch.to = Vector3(6.4, 0, 0)
	patch.spread = 0.0
	patch.length_min = 3.0
	patch.length_max = 5.4
	patch.floor_height = 0.0
	patch.position = Vector3(-3.6, 6.1, 0)
	root.add_child(patch)
	var chain := RopeLine.new()
	chain.style = RopeStyle.chain()
	chain.length = 4.2
	chain.position = Vector3(3.9, 6.1, 0)
	chain.floor_height = 0.0
	root.add_child(chain)
	extra.append(chain)
	patch.lines[1].push(3.0, Vector3(2.5, 0, 1.0))
	# a tyre swing on the first rope: it weighs on it (attach with a weight)
	var tyre := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.22
	torus.outer_radius = 0.42
	torus.rings = 24
	torus.ring_segments = 10
	tyre.mesh = torus
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color(0.08, 0.08, 0.08)
	rubber.roughness = 0.8
	tyre.material_override = rubber
	tyre.rotation.x = PI * 0.5
	root.add_child(tyre)
	var first := patch.lines[0]
	first.length = 3.9
	first.attach(tyre, first.rest_length(), Vector3.DOWN * 0.38, 6.0)


func _box(at: Vector3, box_size: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box_size
	mi.mesh = bm
	mi.material_override = material
	mi.position = at
	root.add_child(mi)
	return mi


# --- Crows ---------------------------------------------------------------------------

func _wires() -> Array[RopeLine]:
	var out: Array[RopeLine] = []
	for line in _lines():
		if line.strung:
			out.append(line)
	return out


func _make_crows() -> void:
	for c in crows:
		if is_instance_valid(c):
			for line in _wires():
				line.detach(c)
			c.queue_free()
	crows.clear()
	var wires := _wires()
	if wires.is_empty():
		return
	for k in bird_count:
		var crow := Crow.new()
		root.add_child(crow)
		crows.append(crow)
		_perch(crow, wires)


func _perch(crow: Crow, wires: Array[RopeLine]) -> void:
	var wire: RopeLine = wires[_rng.randi() % wires.size()]
	var d := wire.rest_length() * _rng.randf_range(0.12, 0.88)
	crow.rotation.y = (PI * 0.5 if _rng.randf() < 0.5 else -PI * 0.5) + _rng.randf_range(-0.3, 0.3)
	crow.perch(wire, d)


func _scare(wire: RopeLine) -> void:
	for c in crows:
		if c.on == wire:
			if _rng.randf() < 0.75:
				c.fly(Vector3(_rng.randf_range(-4, 4), _rng.randf_range(4, 7), _rng.randf_range(-3, 3)), _rng.randf_range(3.0, 6.0))


# --- Touch ---------------------------------------------------------------------------

## Where the finger is on an upright plane facing the camera through `through`.
func _on_plane(pos: Vector2, through: Vector3) -> Variant:
	var r := ray(pos)
	var fwd: Vector3 = -camera.global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	return Plane(fwd.normalized(), through).intersects_ray(r.from, r.dir)


## The line nearest the camera ray through `pos` (within `reach` m of it): [line, distance along].
func _pick(pos: Vector2, reach := 0.6) -> Array:
	var r := ray(pos)
	var from: Vector3 = r.from
	var dir: Vector3 = r.dir
	var best: Array = []
	var least := reach
	for line in _lines():
		for p in line.points():
			var along: float = (p - from).dot(dir)
			if along < 0.0:
				continue
			var off := (p - from - dir * along).length()
			if off < least:
				least = off
				best = [line, line.nearest(p)]
	return best


func poke_down(pos: Vector2) -> void:
	match scene:
		Scene.KELP:
			_fingering = true
			poke_move(pos)
		Scene.VINES:
			if vine_tap == 1:
				var hit := _pick(pos)
				if not hit.is_empty():
					(hit[0] as RopeLine).cut(hit[1])
			else:
				_fingering = true
				var at: Variant = _on_plane(pos, Vector3(0, 0, 0.4))
				if at != null:
					hand.position = at
				hand.visible = true
		Scene.WIRES:
			var hit := _pick(pos, 2.5)
			if not hit.is_empty():
				_drop(hit[0].point_at(hit[1]) + Vector3(_rng.randf_range(-0.05, 0.05), 3.5, _rng.randf_range(-0.05, 0.05)))
			else:
				var g: Variant = ground(pos)
				if g != null:
					_drop(g + Vector3.UP * 8.0)
		Scene.ROPES:
			var hit := _pick(pos, 0.8)
			if not hit.is_empty():
				_grab = hit[0]
				_grab_at = hit[1]
				var at := _grab.point_at(_grab_at)
				var fwd: Vector3 = -camera.global_basis.z
				_grab_plane = Plane(fwd.normalized(), at)
				_grab.hold(_grab_at, at)


func poke_move(pos: Vector2) -> void:
	match scene:
		Scene.KELP:
			var at: Variant = _on_plane(pos, focus)
			if at != null:
				_finger = at
				_finger.y = clampf(_finger.y, 0.6, 12.0)
		Scene.VINES:
			if _fingering:
				var at: Variant = _on_plane(pos, Vector3(0, 0, 0.4))
				if at != null:
					_finger = at
		Scene.ROPES:
			if _grab and is_instance_valid(_grab):
				var r := ray(pos)
				var at: Variant = _grab_plane.intersects_ray(r.from, r.dir)
				if at != null:
					_grab.hold(_grab_at, at)


func poke_up(_pos: Vector2) -> void:
	_fingering = false
	if hand:
		hand.visible = false
		hand.position = Vector3(0, -10, 0)
		hand.velocity = Vector3.ZERO
	if _grab and is_instance_valid(_grab):
		_grab.let_go()
	_grab = null


func _drop_on_wire() -> void:
	var wires := _wires()
	if wires.is_empty():
		return
	var wire: RopeLine = wires[_rng.randi() % wires.size()]
	_drop(wire.point_at(wire.rest_length() * _rng.randf_range(0.25, 0.75)) + Vector3.UP * 3.5)


func _drop(at: Vector3) -> void:
	if balls.size() >= MAX_BALLS:
		var old: Ball = balls.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var b := Ball.new()
	b.heft = ball_heft
	b.position = at
	b.hit_rope.connect(_scare)
	root.add_child(b)
	balls.append(b)


# --- Running -------------------------------------------------------------------------

func _process(delta: float) -> void:
	super(delta)
	_t += delta
	if scene == Scene.KELP and swimmer:
		var target := _finger
		if not _fingering:
			if swimmer_auto:
				target = Vector3(sin(_t * 0.23) * 8.0, 4.0 + sin(_t * 0.37) * 1.8, sin(_t * 0.46) * 5.0)
			else:
				target = swimmer.position
		swimmer.steer(target, delta, 6.0 if _fingering else 2.6)
	if scene == Scene.VINES and hand and _fingering:
		hand.steer(_finger, delta, 12.0)
	balls = balls.filter(func(b: Ball) -> bool: return is_instance_valid(b) and not b.is_queued_for_deletion())
	for c in crows:
		if c.wants_perch():
			var wires := _wires()
			if not wires.is_empty():
				_perch(c, wires)


## Something that pushes ropes: `radius`, `velocity`, and (for the lab) how it is drawn.
class Pusher extends Node3D:
	var radius := 0.5
	var velocity := Vector3.ZERO

	static func seal() -> Pusher:
		var p := Pusher.new()
		p.radius = 0.75
		p.add_to_group(RopeLine.PUSHERS)
		var skin := StandardMaterial3D.new()
		skin.albedo_color = Color(0.36, 0.33, 0.3)
		skin.roughness = 0.45
		var belly := StandardMaterial3D.new()
		belly.albedo_color = Color(0.62, 0.58, 0.5)
		belly.roughness = 0.5
		var eye := StandardMaterial3D.new()
		eye.albedo_color = Color(0.03, 0.03, 0.03)
		eye.roughness = 0.1
		var body := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.3
		cap.height = 1.5
		body.mesh = cap
		body.material_override = skin
		body.rotation.x = PI * 0.5
		body.scale = Vector3(1.0, 1.0, 0.85)
		p.add_child(body)
		var head := MeshInstance3D.new()
		var hs := SphereMesh.new()
		hs.radius = 0.22
		hs.height = 0.4
		head.mesh = hs
		head.material_override = skin
		head.position = Vector3(0, 0.05, -0.78)
		p.add_child(head)
		var snout := MeshInstance3D.new()
		var ss := SphereMesh.new()
		ss.radius = 0.11
		ss.height = 0.18
		snout.mesh = ss
		snout.material_override = belly
		snout.position = Vector3(0, -0.02, -0.98)
		p.add_child(snout)
		for side in [-1.0, 1.0]:
			var e := MeshInstance3D.new()
			var es := SphereMesh.new()
			es.radius = 0.04
			es.height = 0.08
			e.mesh = es
			e.material_override = eye
			e.position = Vector3(side * 0.12, 0.12, -0.92)
			p.add_child(e)
			var flipper := MeshInstance3D.new()
			var fb := BoxMesh.new()
			fb.size = Vector3(0.36, 0.04, 0.2)
			flipper.mesh = fb
			flipper.material_override = skin
			flipper.position = Vector3(side * 0.32, -0.12, -0.35)
			flipper.rotation = Vector3(0, side * 0.5, side * -0.4)
			p.add_child(flipper)
		var tail := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(0.5, 0.05, 0.25)
		tail.mesh = tb
		tail.material_override = skin
		tail.position = Vector3(0, 0, 0.82)
		p.add_child(tail)
		return p

	static func ball(r: float, colour: Color) -> Pusher:
		var p := Pusher.new()
		p.radius = r
		p.add_to_group(RopeLine.PUSHERS)
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		mi.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = colour
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.add_child(mi)
		return p

	## Swims towards `target` at up to `speed` m/s, turning to face where it goes.
	func steer(target: Vector3, delta: float, speed: float) -> void:
		var want := (target - position)
		var v := want / maxf(delta, 0.001)
		if v.length() > speed:
			v = v.normalized() * speed
		velocity = velocity.lerp(v, minf(1.0, delta * 4.0))
		position += velocity * delta
		if velocity.length_squared() > 0.04:
			var ahead := position + velocity
			if absf(velocity.normalized().y) < 0.98:
				look_at(ahead, Vector3.UP)


## A rubber ball that falls, is pushed back by ropes (heft < 1) and bounces on the ground.
class Ball extends MeshInstance3D:
	signal hit_rope(rope: RopeLine)
	var radius := 0.22
	var velocity := Vector3.ZERO
	var heft := 0.85
	var age := 0.0
	var _touching := 0.0

	func _ready() -> void:
		add_to_group(RopeLine.PUSHERS)
		var sm := SphereMesh.new()
		sm.radius = radius
		sm.height = radius * 2.0
		sm.radial_segments = 16
		sm.rings = 8
		mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.85, 0.18, 0.12)
		m.roughness = 0.35
		material_override = m

	func rope_hit(rope: RopeLine, push: Vector3, rope_velocity: Vector3) -> void:
		position += push
		var n := push.normalized()
		var vn := velocity.dot(n)
		var rn := rope_velocity.dot(n)
		if vn < rn:
			velocity += n * (rn - vn)
		if _touching <= 0.0 and push.length() > 0.002:
			hit_rope.emit(rope)
		_touching = 0.3

	func _physics_process(delta: float) -> void:
		age += delta
		_touching -= delta
		velocity += Vector3.DOWN * 9.8 * delta
		velocity *= exp(-0.05 * delta)
		position += velocity * delta
		if position.y < radius:
			position.y = radius
			if velocity.y < 0.0:
				velocity.y = -velocity.y * 0.55
			velocity.x *= 0.92
			velocity.z *= 0.92
		if age > 12.0:
			queue_free()


## A crow from a few shapes: perches on a wire (riding its bounce), flies off when scared,
## and comes back to perch again.
class Crow extends Node3D:
	var on: RopeLine
	var _wings: Array[Node3D] = []
	var _velocity := Vector3.ZERO
	var _away := 0.0
	var _flap := 0.0
	var _back := false
	var _home := Vector3.ZERO
	var _home_line: RopeLine
	var _home_d := 0.0
	var _phase := randf() * TAU

	static var _black: StandardMaterial3D
	static var _beak: StandardMaterial3D

	func _ready() -> void:
		if _black == null:
			_black = StandardMaterial3D.new()
			_black.albedo_color = Color(0.06, 0.06, 0.08)
			_black.roughness = 0.75
			_black.metallic_specular = 0.3
			_beak = StandardMaterial3D.new()
			_beak.albedo_color = Color(0.12, 0.11, 0.1)
		var body := _part(SphereMesh.new(), Vector3(0, 0.17, 0), Vector3(0.15, 0.13, 0.24), _black)
		body.rotation.x = 0.35
		_part(SphereMesh.new(), Vector3(0, 0.3, -0.13), Vector3(0.1, 0.1, 0.1), _black)
		var beak := _part(CylinderMesh.new(), Vector3(0, 0.29, -0.23), Vector3(0.025, 0.07, 0.025), _beak)
		(beak.mesh as CylinderMesh).top_radius = 0.0
		beak.rotation.x = -PI * 0.5
		var tail := _part(BoxMesh.new(), Vector3(0, 0.11, 0.24), Vector3(0.09, 0.02, 0.18), _black)
		tail.rotation.x = -0.5
		for side in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(side * 0.08, 0.22, 0.0)
			add_child(pivot)
			var wing := MeshInstance3D.new()
			var wb := BoxMesh.new()
			wb.size = Vector3(0.3, 0.02, 0.15)
			wing.mesh = wb
			wing.material_override = _black
			wing.position = Vector3(side * 0.12, 0, 0.02)
			pivot.add_child(wing)
			pivot.rotation = Crow.folded(side)
			pivot.set_meta("side", side)
			_wings.append(pivot)
		for side in [-1.0, 1.0]:
			_part(BoxMesh.new(), Vector3(side * 0.04, 0.03, 0), Vector3(0.012, 0.06, 0.012), _beak)

	## A part `dims` big: a sphere's radii, a box's size, a cone's radius and height.
	func _part(mesh: PrimitiveMesh, at: Vector3, dims: Vector3, m: Material) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		if mesh is SphereMesh:
			(mesh as SphereMesh).radial_segments = 10
			(mesh as SphereMesh).rings = 6
			mi.scale = dims * 2.0
		elif mesh is BoxMesh:
			(mesh as BoxMesh).size = dims
		elif mesh is CylinderMesh:
			(mesh as CylinderMesh).bottom_radius = dims.x
			(mesh as CylinderMesh).height = dims.y
		mi.mesh = mesh
		mi.material_override = m
		mi.position = at
		add_child(mi)
		return mi

	## A wing folded back along the body (it sticks out sideways unturned).
	static func folded(side: float) -> Vector3:
		return Vector3(0.0, -side * 1.35, side * 0.2)

	func perch(line: RopeLine, d: float) -> void:
		on = line
		_back = false
		_away = 0.0
		line.attach(self, d, Vector3.ZERO, 0.25)
		for w in _wings:
			w.rotation = Crow.folded(float(w.get_meta("side")))

	func fly(push: Vector3, seconds: float) -> void:
		if on and is_instance_valid(on):
			_home_line = on
			_home_d = on.nearest(global_position)
			on.detach(self)
		on = null
		_velocity = push
		_away = seconds
		rotation.y = atan2(-push.x, -push.z)

	## Back at its wire and ready to be perched again.
	func wants_perch() -> bool:
		return on == null and _back and _away <= 0.0

	func _process(delta: float) -> void:
		if on != null:
			# (a little bob of the head and tail while it sits)
			rotation.x = sin(Time.get_ticks_msec() * 0.003 + _phase) * 0.04
			return
		_flap += delta * 16.0
		for w in _wings:
			w.rotation = Vector3(0, 0, float(w.get_meta("side")) * sin(_flap) * 0.9)
		if _away > 0.0:
			_away -= delta
			_velocity += Vector3.UP * 1.5 * delta
			position += _velocity * delta
			if _away <= 0.0:
				_back = true
				_away = 2.0
		elif _back and _home_line and is_instance_valid(_home_line):
			# (gliding back in to land)
			var home := _home_line.point_at(_home_d)
			position = position.lerp(home, minf(1.0, delta * 2.2))
			var flat := home - position
			if flat.length() > 0.2:
				rotation.y = atan2(-flat.x, -flat.z)
			if position.distance_to(home) < 0.08:
				_away = 0.0
				_home_line.attach(self, _home_d, Vector3.ZERO, 0.25)
				on = _home_line
				_back = false
				for w in _wings:
					w.rotation = Crow.folded(float(w.get_meta("side")))
		elif _back:
			_away = 0.0
