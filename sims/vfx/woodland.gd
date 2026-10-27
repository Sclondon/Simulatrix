extends Sim3D
## Painted Wood: a glade built with GameCommon's painted-woodland kit (Scenic Route's Amberwood, after Over
## the Garden Wall). Everything is lit by hand from one sun direction, so moving the sun only changes
## shader parameters (and re-aims the shafts). Tapping a tree shakes leaves off it: those are animated
## here, a ring of BURST cards in one MultiMesh drawn with the kit's leaf shader.

const GROUND := preload("res://sims/vfx/woodland_ground.gdshader")
const GLOW := preload("res://sims/vfx/woodland_glow.gdshader")
const KIND_NAMES := ["Mixed", "Oak", "Tall", "Leaner", "Aspen", "Snag"]
const LEAF_NAMES := ["Own", "Beech", "Oak", "Maple", "Aspen", "Birch"]
const GLADE := 8.5
const BURST := 360

var kinds := 0
var leaf_kind := 0
var tree_count := 22
var falling := 160
var season := 1.0
var sun_turn := 0.2
var sun_height := 0.3
var fog := 0.013
var shafts_on := true
var bushes_on := true
var stream_on := true
var wood_seed := 5

var wood := Node3D.new()
var falling_node := Node3D.new()
var shafts := Node3D.new()
var ground_mat := ShaderMaterial.new()
var glow := MeshInstance3D.new()
var glow_mat := ShaderMaterial.new()
var foliage_mat: ShaderMaterial
var lying_mat: ShaderMaterial
var falling_mat: ShaderMaterial
var bark_mat: ShaderMaterial
var birch_mat: ShaderMaterial
var trees: Array = [] # {pos, top, crown}: the near trees, for poking
var clumps := 0
var gust := 0.0

var _burst := MultiMeshInstance3D.new()
var _leaves: Array = [] # {pos, vel, axis, angle, spin, size, phase, landed}
var _next := 0
var _regen := -1.0


func help() -> String:
	return ("An autumn wood painted after Over the Garden Wall, made of GameCommon's painted-woodland kit. Trees grow "
		+ "from code with leaning, rope-twisted trunks, roots and swirling branches; their leaf clumps are camera-facing "
		+ "cards cut from real leaf outlines (beech, oak, maple, aspen, birch) drawn as SVG when the game starts.\n\n"
		+ "Nothing uses the engine's lights: every shader paints its own light from the sun direction, so turn the sun "
		+ "and watch the bark rims, glowing leaves, sky and shafts follow it.\n\n"
		+ "Tap a tree (Finger: Poke) to shake its leaves down in a gust. Drag to orbit, pinch to zoom.")


func hint() -> String:
	return "Turn the sun, change the season, or poke a tree to shake it."


func status() -> String:
	return "%d trees · %d leaf clumps · %d falling · seed %d" % [trees.size(), clumps, falling, wood_seed]


func pokeable() -> bool:
	return true


func build() -> void:
	poke_mode = true
	sun.visible = false
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.45, 0.32)
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	environment.fog_light_color = Color(0.84, 0.7, 0.5)
	environment.fog_sun_scatter = 0.6
	environment.fog_density = fog
	focus = Vector3(0, 2.6, 0)
	distance = 8.0
	pitch = -0.08
	yaw = 0.4
	# stay in the glade: further out is among the trunks
	min_distance = 2.0
	max_distance = 13.0
	min_pitch = -0.9
	max_pitch = 0.25
	auto_orbit = 0.04
	var quad := QuadMesh.new()
	quad.size = Vector2(46, 46)
	glow.mesh = quad
	glow.material_override = glow_mat
	glow_mat.shader = GLOW
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(glow)
	ground_mat.shader = GROUND
	var plane := PlaneMesh.new()
	plane.size = Vector2(150, 150)
	var ground_node := MeshInstance3D.new()
	ground_node.mesh = plane
	ground_node.material_override = ground_mat
	world.add_child(ground_node)
	world.add_child(wood)
	world.add_child(falling_node)
	world.add_child(shafts)
	_make_burst()
	_regenerate()


func controls() -> Array:
	return look_controls() + [
		{type = "section", label = "Wood"},
		{type = "choice", label = "Trees", options = KIND_NAMES, value = kinds, on = func(i: int) -> void:
			kinds = i
			_regenerate()},
		{type = "slider", label = "Count", min = 6, max = 40, step = 1, value = tree_count, fmt = "%d",
			on = func(v: float) -> void:
				tree_count = int(v)
				_regenerate_soon()},
		{type = "slider", label = "Seed", min = 1, max = 999, step = 1, value = wood_seed, fmt = "%d",
			on = func(v: float) -> void:
				wood_seed = int(v)
				_regenerate_soon()},
		{type = "button", label = "Regenerate", on = func() -> void:
			wood_seed = randi_range(1, 999)
			_regenerate()},
		{type = "section", label = "Leaves"},
		{type = "choice", label = "Leaf", options = LEAF_NAMES, value = leaf_kind, on = func(i: int) -> void:
			leaf_kind = i
			_regenerate()},
		{type = "slider", label = "Season", min = 0.0, max = 2.0, step = 0.05, value = season, fmt = "%.2f",
			on = func(v: float) -> void:
				season = v
				_apply_season()},
		{type = "slider", label = "Falling", min = 0, max = 500, step = 10, value = falling, fmt = "%d",
			on = func(v: float) -> void:
				falling = int(v)
				_make_falling()},
		{type = "section", label = "Light"},
		{type = "slider", label = "Sun turn", min = -180.0, max = 180.0, step = 1.0, value = rad_to_deg(sun_turn),
			fmt = "%d", unit = "°", on = func(v: float) -> void:
				sun_turn = deg_to_rad(v)
				_apply_sun()},
		{type = "slider", label = "Sun height", min = 4.0, max = 70.0, step = 1.0, value = rad_to_deg(sun_height),
			fmt = "%d", unit = "°", on = func(v: float) -> void:
				sun_height = deg_to_rad(v)
				_apply_sun()},
		{type = "slider", label = "Fog", min = 0.0, max = 0.08, step = 0.002, value = fog, fmt = "%.3f",
			on = func(v: float) -> void:
				fog = v
				environment.fog_density = v},
		{type = "toggle", label = "Shafts", value = shafts_on, on = func(on: bool) -> void:
			shafts_on = on
			shafts.visible = on},
		{type = "section", label = "Extras"},
		{type = "toggle", label = "Bushes", value = bushes_on, on = func(on: bool) -> void:
			bushes_on = on
			_regenerate()},
		{type = "toggle", label = "Stream", value = stream_on, on = func(on: bool) -> void:
			stream_on = on
			_regenerate()},
		{type = "button", label = "Gust", on = func() -> void: _shake(trees.pick_random() if not trees.is_empty() else null)},
	]


# --- the sun -----------------------------------------------------------------

## Towards the sun (the kit's `sun_dir`).
func _sun_dir() -> Vector3:
	return Vector3(sin(sun_turn) * cos(sun_height), sin(sun_height), -cos(sun_turn) * cos(sun_height))


func _sun_color() -> Color:
	# lower is warmer
	return Color(1.0, 0.85, 0.55).lerp(Color(1.0, 0.95, 0.85), smoothstep(0.3, 1.1, sun_height))


func _apply_sun() -> void:
	var dir := _sun_dir()
	var c := _sun_color()
	var c3 := Vector3(c.r, c.g, c.b)
	for node in [wood, falling_node]:
		for g in node.find_children("*", "GeometryInstance3D", true, false):
			var m := (g as GeometryInstance3D).material_override as ShaderMaterial
			if m and m.get_shader_parameter("sun_dir") != null:
				m.set_shader_parameter("sun_dir", dir)
				m.set_shader_parameter("sun_color", c3)
	for m: ShaderMaterial in [lying_mat, falling_mat, foliage_mat]:
		if m:
			m.set_shader_parameter("sun_dir", dir)
			m.set_shader_parameter("sun_color", c3)
	ground_mat.set_shader_parameter("sun_color", c)
	if environment.sky == null:
		environment.sky = Woodland.sky(dir)
		environment.sky.radiance_size = Sky.RADIANCE_SIZE_32
	else:
		(environment.sky.sky_material as ShaderMaterial).set_shader_parameter("sun_dir", dir.normalized())
	environment.background_mode = Environment.BG_SKY
	glow.position = Vector3(0, 2, 0) + dir * 70.0
	glow_mat.set_shader_parameter("color", c.lerp(Color.WHITE, 0.15))
	glow_mat.set_shader_parameter("strength", lerpf(0.75, 0.35, smoothstep(0.2, 1.0, sun_height)))
	environment.fog_light_color = Color(0.84, 0.7, 0.5).lerp(Color(0.75, 0.72, 0.66), smoothstep(0.3, 1.1, sun_height))
	_make_shafts()


func _make_shafts() -> void:
	for child in shafts.get_children():
		child.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = wood_seed
	for i in 6:
		var a := rng.randf() * TAU
		var p := Vector3(cos(a), 0, sin(a)) * rng.randf_range(1.0, GLADE + 4.0)
		Woodland.add_sun_shaft(shafts, p, _sun_dir(), _sun_color(), 18.0, rng.randf_range(2.4, 4.0), i * 2.3, 0.2)


# --- the season --------------------------------------------------------------

## 0 summer, 1 autumn (the kit's own colours), 2 late autumn.
func _apply_season() -> void:
	var summer := [Color(0.55, 0.62, 0.22), Color(0.36, 0.5, 0.16), Color(0.22, 0.36, 0.12)]
	var autumn := [Color(0.93, 0.68, 0.24), Color(0.84, 0.43, 0.13), Color(0.52, 0.24, 0.1)]
	var late := [Color(0.66, 0.44, 0.2), Color(0.52, 0.28, 0.12), Color(0.33, 0.18, 0.09)]
	var cols: Array = []
	for i in 3:
		var c: Color = summer[i].lerp(autumn[i], clampf(season, 0.0, 1.0)) if season <= 1.0 else autumn[i].lerp(late[i], season - 1.0)
		cols.append(c)
	if foliage_mat:
		foliage_mat.set_shader_parameter("gold", cols[0])
		foliage_mat.set_shader_parameter("orange", cols[1])
		foliage_mat.set_shader_parameter("rust", cols[2])
	for m: ShaderMaterial in [lying_mat, falling_mat]:
		if m:
			m.set_shader_parameter("gold", cols[0])
			m.set_shader_parameter("orange", cols[1])
			m.set_shader_parameter("rust", cols[2])
	# litter on the ground: green and sparse in summer
	var lit := clampf(season, 0.0, 1.0)
	ground_mat.set_shader_parameter("litter_a", Color(0.35, 0.36, 0.15).lerp(Color(0.62, 0.36, 0.14), lit))
	ground_mat.set_shader_parameter("litter_c", Color(0.45, 0.45, 0.2).lerp(Color(0.72, 0.52, 0.2), lit))


# --- building the wood -------------------------------------------------------

func _regenerate_soon() -> void:
	_regen = 0.35


func _regenerate() -> void:
	_regen = -1.0
	for child in wood.get_children():
		child.free()
	trees.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = wood_seed
	var dir := _sun_dir()
	var sc := _sun_color()
	var names: Array = Woodland.KINDS.keys()
	var use: Array = names if kinds == 0 else [names[kinds - 1]]
	var variants: Array = []
	for kind: String in use:
		for k in (2 if kinds == 0 else 3):
			var v := Woodland.variant(kind, wood_seed * 31 + variants.size() * 7 + k)
			if leaf_kind > 0:
				v.leaf = leaf_kind - 1
			variants.append(v)
	var cards: Array = []
	var pools: Array = []
	var placed: Array[Vector3] = []
	# the ring round the glade, near and in full; then more behind, lite, to fill the fog
	var want := tree_count + int(tree_count * 0.8)
	var tries := 0
	while placed.size() < want and tries < 4000:
		tries += 1
		var far := placed.size() >= tree_count
		var a := rng.randf() * TAU
		var r := rng.randf_range(GLADE, GLADE + 14.0) if not far else rng.randf_range(GLADE + 12.0, 52.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if absf(p.x - 1.6 * sin(p.z * 0.09) - 0.8 * sin(p.z * 0.21 + 1.0)) < 2.2:
			continue # keep the path clear
		var ok := true
		for q in placed:
			if q.distance_to(p) < (3.2 if not far else 4.5):
				ok = false
				break
		if not ok:
			continue
		placed.append(p)
		var snag_ok := kinds == 5 or rng.randf() < 0.35
		var v: Dictionary = variants[rng.randi() % variants.size()]
		if v.kind == "snag" and not snag_ok and variants.size() > 1:
			v = variants[(variants.find(v) + 2) % variants.size()]
		# branches reach +X: turn them out over the glade
		var face := atan2(-p.z, -p.x)
		var tr := Transform3D(Basis(Vector3.UP, -face + rng.randf_range(-0.6, 0.6)).scaled(Vector3.ONE * rng.randf_range(0.85, 1.15)), p)
		v["far" if far else "near"].append(tr)
		if not v.bare:
			Woodland.crown_cards(v, tr, rng, 1 if far else 3, cards)
		if not far:
			var top := 0.0
			var reach := 1.5
			var mid := Vector3.ZERO
			for c: Vector4 in v.crowns:
				top = maxf(top, c.y)
				reach = maxf(reach, Vector2(c.x, c.z).length() * 0.7 + c.w)
				mid += Vector3(c.x, c.y, c.z)
			mid = tr * (mid / maxf(v.crowns.size(), 1))
			trees.append({pos = p, top = top * tr.basis.get_scale().x, crown = mid, bare = v.bare})
			if pools.size() < 48:
				pools.append(Vector4(mid.x, mid.z, reach, 0))
	bark_mat = Woodland.material(Woodland.BARK, dir, sc, {"moss": 0.6})
	birch_mat = Woodland.material(Woodland.BARK, dir, sc, {"birch": 1.0})
	Woodland.add_trees(wood, variants, bark_mat, birch_mat)
	foliage_mat = Woodland.material(Woodland.FOLIAGE, dir, sc)
	Woodland.add_leaf_clumps(wood, cards, foliage_mat)
	clumps = cards.size()
	while pools.size() < 48:
		pools.append(Vector4.ZERO)
	ground_mat.set_shader_parameter("trees", PackedVector4Array(pools))
	ground_mat.set_shader_parameter("tree_count", mini(trees.size(), 48))
	if bushes_on:
		var bush := {}
		var bush_kinds: Array = Woodland.BushBuilder.KINDS.keys()
		for i in 12:
			var a := rng.randf() * TAU
			var p := Vector3(cos(a), 0, sin(a)) * rng.randf_range(GLADE - 2.5, GLADE + 4.0)
			var kind: String = bush_kinds[i % bush_kinds.size()]
			if not bush.has(kind):
				bush[kind] = []
			bush[kind].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.4)), p))
		Woodland.add_bushes(wood, bush, dir, sc)
	# leaves lying in the glade
	lying_mat = Woodland.material(Woodland.LEAF, dir, sc)
	var lying: Array = []
	for i in 900:
		var a := rng.randf() * TAU
		var p := Vector3(cos(a), 0, sin(a)) * sqrt(rng.randf()) * (GLADE + 8.0)
		var card := Woodland.leaf_card(rng, p, false)
		lying.append(_own_leaf(card))
	Woodland.add_leaves(wood, lying, lying_mat, AABB(Vector3(-30, -1, -30), Vector3(60, 4, 60)))
	if stream_on:
		var pts: Array[Vector3] = []
		for i in 26:
			var z := -40.0 + i * 2.4
			pts.append(Vector3(GLADE + 3.0 + 2.0 * sin(z * 0.15) + z * 0.12, 0.04, z))
		Woodland.add_stream(wood, pts, 0.7, dir, sc)
	_make_falling()
	_apply_season()
	_apply_sun()


## A leaf card with the chosen leaf shape (custom.x) if one is chosen.
func _own_leaf(card: Array) -> Array:
	if leaf_kind > 0:
		var c: Color = card[1]
		c.r = (leaf_kind - 1 + 0.5) / 5.0
		card[1] = c
	return card


func _make_falling() -> void:
	for child in falling_node.get_children():
		child.free()
	if falling <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = wood_seed + 99
	falling_mat = Woodland.material(Woodland.LEAF, _sun_dir(), _sun_color(), {"falling": 1.0})
	var cards: Array = []
	for i in falling:
		var a := rng.randf() * TAU
		var p := Vector3(cos(a), 0, sin(a)) * sqrt(rng.randf()) * (GLADE + 10.0)
		cards.append(_own_leaf(Woodland.leaf_card(rng, p, true)))
	Woodland.add_leaves(falling_node, cards, falling_mat, AABB(Vector3(-30, -2, -30), Vector3(60, 20, 60)))
	_apply_season()


# --- poking: shaking leaves off a tree -----------------------------------------

func _make_burst() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(1, 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = plane
	mm.instance_count = BURST
	for i in BURST:
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -10, 0)))
	_burst.multimesh = mm
	_burst.custom_aabb = AABB(Vector3(-60, -2, -60), Vector3(120, 30, 120))
	world.add_child(_burst)
	for i in BURST:
		_leaves.append({})


func poke_down(pos: Vector2) -> void:
	var r := ray(pos)
	var best: Variant = null
	var best_d := 2.5
	for t: Dictionary in trees:
		# distance from the ray to the tree's trunk-and-crown line
		for at: Vector3 in [t.pos + Vector3(0, 1.5, 0), t.crown]:
			var to: Vector3 = at - r.from
			var along: float = maxf(to.dot(r.dir), 0.0)
			var d: float = (r.from + r.dir * along).distance_to(at) / maxf(along * 0.08, 1.0)
			if d < best_d:
				best_d = d
				best = t
	_shake(best)


func _shake(t: Variant) -> void:
	gust = 1.0
	if t == null or t.bare:
		return
	# drawn as the lying leaves are (the cards are moved here, not in the shader)
	_burst.material_override = lying_mat
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var mm := _burst.multimesh
	for i in 70:
		var k := _next
		_next = (_next + 1) % BURST
		var start: Vector3 = t.crown + Vector3(rng.randf_range(-2.5, 2.5), rng.randf_range(-1.5, 2.0), rng.randf_range(-2.5, 2.5))
		_leaves[k] = {pos = start, vel = Vector3(rng.randf_range(-0.6, 1.6), rng.randf_range(0.0, 1.2), rng.randf_range(-0.8, 0.8)),
			axis = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(),
			angle = rng.randf() * TAU, spin = rng.randf_range(2.0, 6.0), size = rng.randf_range(0.14, 0.26),
			phase = rng.randf() * TAU, landed = false}
		var c := Color((leaf_kind - 1 + 0.5) / 5.0 if leaf_kind > 0 else rng.randf(), rng.randf(), rng.randf_range(0.6, 1.0), rng.randf())
		mm.set_instance_custom_data(k, c)


func _process(delta: float) -> void:
	super(delta)
	if _regen > 0.0:
		_regen -= delta
		if _regen <= 0.0:
			_regenerate()
	gust = maxf(gust - delta * 0.4, 0.0)
	if foliage_mat:
		foliage_mat.set_shader_parameter("sway", 1.0 + gust * 6.0)
	var mm := _burst.multimesh
	var t := Time.get_ticks_msec() / 1000.0
	for i in BURST:
		var l: Dictionary = _leaves[i]
		if l.is_empty() or l.landed:
			continue
		# drift down at a leaf's slow terminal speed, swinging side to side, blown along by the gust
		l.vel.y = move_toward(l.vel.y, -1.1, delta * 3.0)
		l.vel.x = move_toward(l.vel.x, 0.6 + gust * 2.0, delta)
		var swing := Vector3(cos(t * 2.2 + l.phase), 0, sin(t * 1.7 + l.phase)) * 0.9
		l.pos += (l.vel + swing) * delta
		l.angle += l.spin * delta
		var basis := Basis(l.axis, l.angle)
		if l.pos.y <= 0.03:
			l.pos.y = 0.03
			l.landed = true
			basis = Basis(Vector3.UP, l.angle)
		mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * l.size), l.pos))
