extends Sim3D
## Fire: GameCommon's Fire, from a candle to a bonfire, in a clearing at night
## ringed with GameCommon pines. Every setting goes to every fire; a tap on the
## ground lights a small one, and a drag moves it.

const PRESETS := ["Candle", "Torch", "Brazier", "Campfire", "Bonfire"]
## size, spread, tongues, light energy, light range, camera distance, flame height above the ground
const SHAPES := [
	[0.07, 0.42, 1, 0.9, 4.0, 2.2, 0.62],
	[0.3, 0.5, 1, 2.4, 9.0, 4.5, 1.55],
	[0.7, 0.8, 3, 3.2, 12.0, 6.0, 0.95],
	[0.95, 0.85, 4, 3.6, 14.0, 7.0, 0.12],
	[2.6, 0.85, 6, 5.0, 22.0, 11.0, 0.25],
]
const COLOURS := ["Flame", "Copper", "Gas", "Hex", "Ember"]
## core, body, tip
const TONES := [
	[Color(1.0, 0.94, 0.62), Color(1.0, 0.56, 0.12), Color(0.78, 0.16, 0.05)],
	[Color(0.88, 1.0, 0.72), Color(0.3, 0.9, 0.38), Color(0.04, 0.42, 0.22)],
	[Color(0.86, 0.95, 1.0), Color(0.32, 0.56, 1.0), Color(0.1, 0.14, 0.62)],
	[Color(1.0, 0.82, 1.0), Color(0.72, 0.3, 1.0), Color(0.3, 0.04, 0.5)],
	[Color(1.0, 0.62, 0.3), Color(0.86, 0.22, 0.06), Color(0.42, 0.04, 0.03)],
]
const MAX_SMALL := 6
const Sprites := preload("res://sims/vfx/particles/textures.gd")

var preset := 3
var tone := 0
var scale_size := 1.0
var settings := {lean = 0.0, speed = 1.0, ragged = 1.0, intensity = 1.0, halo = 0.22, flicker = 0.13,
	embers = true, smoke = true, banded = true, light = true, light_shadows = false, spark_size = 1.0}
## What the sparks and smoke are drawn with: "" their own shapes, else a sprite id (a particle
## sprite, or one drawn or imported on the shape pad, "user:<name>").
var spark_id := ""
var smoke_id := ""
var fire: Fire
var small: Array[Node3D] = [] # extra fires, each a stake of sticks with a Fire on it
var base: Node3D # what the main fire stands on
var _dragging: Node3D
var _mats := {}


func build() -> void:
	set_sky(Color("02030a"), Color("101626"), Color("05060a"))
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.22, 0.27, 0.42)
	environment.ambient_light_energy = 0.35
	environment.fog_enabled = true
	environment.fog_light_color = Color("0d1220")
	environment.fog_density = 0.015
	environment.fog_sky_affect = 0.0
	sun.light_color = Color(0.55, 0.65, 1.0)
	sun.light_energy = 0.18
	sun.rotation_degrees = Vector3(-35.0, 120.0, 0.0)
	pitch = -0.3
	min_distance = 0.8
	max_distance = 16.0

	# The clearing: a disc of trodden dirt, and needles past it.
	var land := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(160.0, 160.0)
	land.mesh = plane
	land.material_override = _mat("ground", Color(0.16, 0.14, 0.12))
	world.add_child(land)
	var dirt := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 7.0
	disc.bottom_radius = 7.0
	disc.height = 0.02
	disc.radial_segments = 40
	dirt.mesh = disc
	dirt.material_override = _mat("dirt", Color(0.27, 0.22, 0.17))
	world.add_child(dirt)

	# Pines all round, out of the light.
	var pine := PineTree.new()
	pine.height = 11.0
	pine.seed = 4
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var points := []
	for i in 70:
		var a := rng.randf() * TAU
		var r := rng.randf_range(19.0, 42.0)
		points.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
	PineTree.forest(world, points, pine, 3, Vector2(0.7, 1.3))

	# A log to sit on, and a few stones lying about.
	var seat := _log(2.2, 0.22)
	seat.position = Vector3(-2.6, 0.22, 1.4)
	seat.rotation.y = 0.5
	world.add_child(seat)
	_use_preset(preset)


func _mat(key: String, c: Color, metal := 0.0) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.5 if metal > 0.0 else 1.0
		m.metallic = metal
		m.metallic_specular = 0.2 if metal > 0.0 else 0.0
		_mats[key] = m
	return _mats[key]


func _log(length: float, radius: float) -> Node3D:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius * 1.05
	c.height = length
	c.radial_segments = 8
	c.rings = 1
	m.mesh = c
	m.material_override = _mat("bark", Color(0.24, 0.16, 0.1))
	m.rotation.z = PI * 0.5
	var holder := Node3D.new()
	holder.add_child(m)
	return holder


func _stone(at: Vector3, r: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 1.3
	s.radial_segments = 7
	s.rings = 3
	m.mesh = s
	m.material_override = _mat("stone", Color(0.32, 0.31, 0.3))
	m.position = at
	m.rotation.y = at.x * 3.0 + at.z
	return m


## The thing the main fire stands on, for each preset.
func _build_base(kind: int) -> Node3D:
	var b := Node3D.new()
	match kind:
		0: # a candle on a stump
			var stump := MeshInstance3D.new()
			var c := CylinderMesh.new()
			c.top_radius = 0.28
			c.bottom_radius = 0.34
			c.height = 0.45
			c.radial_segments = 12
			stump.mesh = c
			stump.material_override = _mat("bark", Color(0.24, 0.16, 0.1))
			stump.position.y = 0.225
			b.add_child(stump)
			var wax := MeshInstance3D.new()
			var w := CylinderMesh.new()
			w.top_radius = 0.035
			w.bottom_radius = 0.04
			w.height = 0.16
			w.radial_segments = 10
			wax.mesh = w
			wax.material_override = _mat("wax", Color(0.92, 0.88, 0.76))
			wax.position.y = 0.53
			b.add_child(wax)
		1: # a torch on a post
			var post := MeshInstance3D.new()
			var p := CylinderMesh.new()
			p.top_radius = 0.04
			p.bottom_radius = 0.05
			p.height = 1.5
			p.radial_segments = 8
			post.mesh = p
			post.material_override = _mat("bark", Color(0.24, 0.16, 0.1))
			post.position.y = 0.75
			b.add_child(post)
			var wrap := MeshInstance3D.new()
			var r := CylinderMesh.new()
			r.top_radius = 0.075
			r.bottom_radius = 0.055
			r.height = 0.18
			r.radial_segments = 8
			wrap.mesh = r
			wrap.material_override = _mat("rag", Color(0.18, 0.13, 0.1))
			wrap.position.y = 1.45
			b.add_child(wrap)
		2: # a brazier: an iron bowl on three legs
			var bowl := MeshInstance3D.new()
			var bm := CylinderMesh.new()
			bm.top_radius = 0.5
			bm.bottom_radius = 0.22
			bm.height = 0.3
			bm.radial_segments = 16
			bowl.mesh = bm
			bowl.material_override = _mat("iron", Color(0.2, 0.19, 0.18), 0.6)
			bowl.position.y = 0.8
			b.add_child(bowl)
			for i in 3:
				var leg := MeshInstance3D.new()
				var lm := CylinderMesh.new()
				lm.top_radius = 0.03
				lm.bottom_radius = 0.03
				lm.height = 0.9
				lm.radial_segments = 6
				leg.mesh = lm
				leg.material_override = bowl.material_override
				var a := i * TAU / 3.0
				leg.position = Vector3(cos(a) * 0.3, 0.42, sin(a) * 0.3)
				leg.rotation = Vector3(sin(a) * 0.25, 0.0, -cos(a) * 0.25)
				b.add_child(leg)
		3, 4: # a ring of stones round crossed logs; a bigger pile for a bonfire
			var big := kind == 4
			var ring := 1.9 if big else 0.85
			var stones := 16 if big else 11
			for i in stones:
				var a := i * TAU / stones
				b.add_child(_stone(Vector3(cos(a) * ring, 0.06, sin(a) * ring), (0.28 if big else 0.16) * (0.85 + 0.3 * fmod(i * 0.618, 1.0))))
			var logs := 6 if big else 4
			for i in logs:
				var l := _log(1.9 if big else 1.1, 0.09 if big else 0.07)
				var a := i * TAU / logs + 0.3
				if big:
					# a teepee: logs leaning in to a point
					l.rotation = Vector3(0.0, -a, 0.0)
					l.get_child(0).rotation = Vector3(0.0, 0.0, 0.45)
					l.position = Vector3(cos(a) * 0.5, 0.86, sin(a) * 0.5)
				else:
					l.rotation.y = a
					l.position = Vector3(0.0, 0.07 + (i % 2) * 0.1, 0.0)
				b.add_child(l)
			var embers := MeshInstance3D.new()
			var e := CylinderMesh.new()
			e.top_radius = ring * 0.6
			e.bottom_radius = ring * 0.65
			e.height = 0.06
			e.radial_segments = 16
			embers.mesh = e
			var em := StandardMaterial3D.new()
			em.albedo_color = Color(0.1, 0.06, 0.05)
			em.emission_enabled = true
			em.emission = Color(1.0, 0.3, 0.06)
			em.emission_energy_multiplier = 0.6
			embers.material_override = em
			embers.position.y = 0.03
			b.add_child(embers)
	return b


func _use_preset(kind: int) -> void:
	preset = kind
	if fire:
		fire.queue_free()
	if base:
		base.queue_free()
	base = _build_base(kind)
	world.add_child(base)
	var s: Array = SHAPES[kind]
	fire = Fire.new()
	fire.size = s[0] * scale_size
	fire.spread = s[1]
	fire.tongues = s[2]
	fire.light_energy = s[3]
	fire.light_range = s[4]
	if kind == 0:
		fire.flicker = 0.07
		settings.ragged = minf(settings.ragged, 0.35)
	fire.position.y = s[6]
	world.add_child(fire)
	_dress(fire)
	distance = s[5]
	focus = Vector3(0.0, s[6] + s[0] * 0.6, 0.0)
	_place_camera()


## Every setting onto one fire.
func _dress(f: Fire) -> void:
	var t: Array = TONES[tone]
	f.core = t[0]
	f.body = t[1]
	f.tip = t[2]
	for key: String in settings:
		if key == "flicker" and f != fire and preset == 0:
			continue
		f.set(key, settings[key])
	f.spark_texture = _sprite(spark_id)
	f.smoke_texture = _sprite(smoke_id)
	if f != fire:
		f.light_shadows = false


static func _sprite(id: String) -> Texture2D:
	if id == "":
		return null
	return ShapePad.texture(id, func(n: String) -> Texture2D:
		return Sprites.get_texture(n if n in Sprites.NAMES else "soft"))


func _set_sprite(which: String, id: String) -> void:
	if which == "spark":
		spark_id = id
	else:
		smoke_id = id
	_dress(fire)
	for s in small:
		_dress(s.get_meta("fire"))


func _apply(key: String, value: Variant) -> void:
	settings[key] = value
	_dress(fire)
	for s in small:
		_dress(s.get_meta("fire"))


func _set_tone(i: int) -> void:
	tone = i
	_dress(fire)
	for s in small:
		_dress(s.get_meta("fire"))
	# the embers under a campfire glow the same colour
	for child in base.get_children():
		if child is MeshInstance3D and child.material_override is StandardMaterial3D and child.material_override.emission_enabled:
			child.material_override.emission = TONES[tone][1]


func pokeable() -> bool:
	return true


func poke_down(pos: Vector2) -> void:
	var at: Variant = ground(pos)
	if at == null:
		return
	_dragging = null
	for s in small:
		if Vector2(s.position.x - at.x, s.position.z - at.z).length() < 0.7:
			_dragging = s
			return
	if Vector2(at.x, at.z).length() < (2.2 if preset == 4 else 1.0):
		return # not on top of the big one
	if small.size() >= MAX_SMALL:
		small[0].queue_free()
		small.remove_at(0)
	var stake := Node3D.new()
	for i in 3:
		var stick := _log(0.6, 0.03)
		stick.rotation.y = i * TAU / 3.0
		stick.position.y = 0.03 + i * 0.03
		stake.add_child(stick)
	var f := Fire.new()
	f.size = 0.35
	f.spread = 0.6
	f.light_energy = 1.6
	f.light_range = 6.0
	f.position.y = 0.05
	stake.add_child(f)
	stake.set_meta("fire", f)
	stake.position = at
	world.add_child(stake)
	_dress(f)
	small.append(stake)
	_dragging = stake


func poke_move(pos: Vector2) -> void:
	if _dragging:
		var at: Variant = ground(pos)
		if at != null:
			_dragging.position = at


func poke_up(_pos: Vector2) -> void:
	_dragging = null


func controls() -> Array:
	var c := look_controls()
	c.append_array([
		{type = "section", label = "Fire"},
		{type = "choice", label = "Preset", options = PRESETS, value = preset, on = _use_preset},
		{type = "slider", label = "Size", min = 0.25, max = 2.5, step = 0.05, value = scale_size, fmt = "%.2fx",
			on = func(v: float) -> void:
				scale_size = v
				fire.size = SHAPES[preset][0] * v},
		{type = "choice", label = "Colour", options = COLOURS, value = tone, on = _set_tone,
			colors = TONES.map(func(t: Array) -> Color: return t[1])},
		{type = "slider", label = "Intensity", min = 0.2, max = 2.0, step = 0.05, value = settings.intensity, fmt = "%.2f",
			on = func(v: float) -> void: _apply("intensity", v)},
		{type = "slider", label = "Halo", min = 0.0, max = 1.0, step = 0.02, value = settings.halo, fmt = "%.2f",
			on = func(v: float) -> void: _apply("halo", v)},
		{type = "toggle", label = "Banded", value = settings.banded, on = func(on: bool) -> void: _apply("banded", on)},
		{type = "section", label = "Motion"},
		{type = "slider", label = "Wind", min = -1.0, max = 1.0, step = 0.05, value = settings.lean, fmt = "%.2f",
			on = func(v: float) -> void: _apply("lean", v)},
		{type = "slider", label = "Speed", min = 0.2, max = 3.0, step = 0.05, value = settings.speed, fmt = "%.2fx",
			on = func(v: float) -> void: _apply("speed", v)},
		{type = "slider", label = "Ragged", min = 0.0, max = 1.5, step = 0.05, value = settings.ragged, fmt = "%.2f",
			on = func(v: float) -> void: _apply("ragged", v)},
		{type = "toggle", label = "Sparks", value = settings.embers, on = func(on: bool) -> void: _apply("embers", on)},
		{type = "toggle", label = "Smoke", value = settings.smoke, on = func(on: bool) -> void: _apply("smoke", on)},
		{type = "section", label = "Sparks and smoke"},
	])
	var sprites := ShapePad.builtins(Sprites.NAMES, Sprites.LABELS, Sprites.get_texture)
	c.append_array(ShapePad.picker_controls("Spark sprite", spark_id,
		func(id: String) -> void: _set_sprite("spark", id), [{id = "", label = "Diamond", tex = null}] + sprites))
	c.append({type = "slider", label = "Spark size", min = 0.5, max = 6.0, step = 0.1, value = settings.spark_size,
		fmt = "%.1fx", on = func(v: float) -> void: _apply("spark_size", v)})
	c.append_array(ShapePad.picker_controls("Smoke sprite", smoke_id,
		func(id: String) -> void: _set_sprite("smoke", id), [{id = "", label = "Puff", tex = null}] + sprites))
	c.append_array([
		{type = "section", label = "Light"},
		{type = "slider", label = "Flicker", min = 0.0, max = 0.5, step = 0.01, value = settings.flicker, fmt = "%.2f",
			on = func(v: float) -> void: _apply("flicker", v)},
		{type = "toggle", label = "Light", value = settings.light, on = func(on: bool) -> void: _apply("light", on)},
		{type = "toggle", label = "Shadows", value = settings.light_shadows,
			on = func(on: bool) -> void:
				settings.light_shadows = on
				fire.light_shadows = on},
		{type = "toggle", label = "Moon", value = true, on = func(on: bool) -> void: sun.visible = on},
		{type = "button", label = "Put out small", on = func() -> void:
			for s in small:
				s.queue_free()
			small.clear()},
	])
	c.append_array(Exporter.controls("%s %s" % [COLOURS[tone], PRESETS[preset]], _export, "fire",
		func(t: String) -> void: say.emit(t)))
	return c


## Sends the big fire's settings to the asset library as a scene: one Fire node (GameCommon's
## component builds its flames, sparks, smoke and light itself), its foot at the scene's origin.
## What it stands on here (logs, stones, a candle) stays in the lab.
func _export(asset_name: String) -> void:
	var made := NodeCopy.fresh(fire, asset_name.to_pascal_case().validate_node_name())
	(made as Node3D).position = Vector3.ZERO
	var file := Exporter.slug(asset_name)
	say.emit(Exporter.save("fire", asset_name, {"tscn": made}, ["godot/fire"],
		"var fire := (load(\"res://assets/fire/%s.tscn\") as PackedScene).instantiate() as Fire\n" % file
		+ "add_child(fire)   # its foot at the node's origin: stand it on your logs or candle\n"
		+ "# change it live like any Fire: fire.size, fire.lean (wind), fire.light...",
		"Fire"))
	made.free()


func help() -> String:
	return ("GameCommon's Fire (scripts/fire.gd): each tongue of flame is a card turned to the camera, cut out of noise "
		+ "streaming upwards in three tones, with sparks and smoke as one MultiMesh and a light that wavers on three "
		+ "slow sines. No particles, no textures, two draw calls and a light per fire.\n\n"
		+ "Sparks and smoke: draw them with a sprite instead of their own shapes (a built-in one, one you draw on the "
		+ "pad, or an imported picture): white ones take the fire's colours. Spark size makes them bigger.\n\n"
		+ "Finger on Poke: tap the ground to light a small fire (up to %d), drag one to move it. Every setting goes to "
		+ "every fire. Shadows makes the big fire's light cast them (costly on phones).") % MAX_SMALL


func hint() -> String:
	return "Pick a preset. Finger: Poke, then tap the ground to light more fires."


func status() -> String:
	return "%s  %.2f m  %s  fires %d  lights %d  %.1f ms" % [PRESETS[preset].to_lower(), fire.size, COLOURS[tone].to_lower(),
		1 + small.size(), (1 + small.size()) if settings.light else 0, frame_ms()]
