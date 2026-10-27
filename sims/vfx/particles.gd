extends Sim3D
## Particle Editor: build effects out of layered emitters, Unity / Godot style.
## Each emitter is a GPUParticles3D with a ParticleProcessMaterial (so turbulence and
## attractors work in GL Compatibility, and exports are exactly what you see), drawn as a
## textured quad: billboard, stretched along its velocity, or lying flat.
## GL Compatibility has no sub-emitters and no emit_particle(), so an emitter with an
## on-death sub-emitter is simulated here instead (a few dozen particles, ballistic) and
## drawn as a MultiMesh; where each one dies it fires a pooled one-shot copy of the target.
## Effects are plain Dictionaries (see particles/presets.gd), saved as JSON.

const Presets := preload("res://sims/vfx/particles/presets.gd")
const Tex := preload("res://sims/vfx/particles/textures.gd")
const CurveEdit := preload("res://sims/vfx/particles/curve_edit.gd")
const GradientEdit := preload("res://sims/vfx/particles/gradient_edit.gd")
const GRID := preload("res://sims/vfx/particles/grid.gdshader")

const SHAPES := ["point", "sphere", "shell", "hemi", "box", "ring", "disc", "line"]
const SHAPE_LABELS := ["Point", "Sphere", "Shell", "Hemi", "Box", "Ring", "Disc", "Line"]
const MODES := ["billboard", "stretch", "flat"]
const MODE_LABELS := ["Billboard", "Stretch", "Flat"]
const BACKDROPS := ["Dark", "Grey", "Night", "Day"]
const MAX_EMITTERS := 8
const MAX_AMOUNT := 600
const TRACK_CAP := 32 # live particles of an emitter simulated here
const POOL := 6 # one-shot copies of a sub-emitter target
const SAVE_PATH := "user://particle_effects.json"
const C_FACE_HI := Color("46464b")
const C_ACCENT := Color("4f86c6")
const C_INSET := Color("1f1f22")
const C_EDGE := Color("111113")
const DIM_TEXT := Color("9a9aa3")

var fx: Dictionary
var sel := 0
var playing := true
var effect_root := Node3D.new() # the effect; the finger drags it
var runs: Array = [] # per emitter: nodes and materials, see _make_run()
var cycle_t := 0.0
var pending: Array = [] # [time, emitter index] starts waiting for their delay
var backdrop := 0
var show_floor := true
var show_gizmo := true
var glow := true
var floor_mesh := MeshInstance3D.new()
var floor_mat := ShaderMaterial.new()
var gizmo := MeshInstance3D.new()
var noise := FastNoiseLite.new()
var time := 0.0
var root_vel := Vector3.ZERO
var _last_root := Vector3.ZERO
var _drag_off := Vector3.ZERO
var _note := ""
var _note_time := 0.0
var _library: Dictionary = {}


func hint() -> String:
	return "Pick a preset, then open an emitter's modules. Finger: Poke drags the effect about."


func help() -> String:
	return ("An effect is a stack of emitters, each a GPU particle system, shown in the Emitters list "
		+ "(tap to edit, tick to show). Each emitter's settings are grouped into modules like Unity's or Godot's: "
		+ "Emission (how many, how long, bursts), Shape (where they start), Velocity, Forces (gravity, wind, "
		+ "damping, swirl, turbulence, an attractor), Size and Color over life (drag the curve and gradient: "
		+ "tap to add a point or stop, hold one to delete it), Rotation and Renderer (sprite, billboard, "
		+ "stretched or flat, additive or alpha, a light).\n\n"
		+ "Burst emitters fire together every Cycle seconds, each after its Delay. Sub-emitter: when this "
		+ "emitter's particles die they set off another emitter where they died (fireworks).\n\n"
		+ "Library: Save keeps effects on this device; Copy and Paste move them as JSON; Export .tscn writes a "
		+ "Godot scene of GPUParticles3D nodes you can drop into a game (sub-emitters there need Forward+ or "
		+ "Mobile; start delays are in each node's metadata).\n\n"
		+ "Drag to orbit, pinch or scroll to zoom. Set Finger to Poke to drag the effect and see it trail.")


func build() -> void:
	noise.frequency = 3.0
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_color = Color(0.5, 0.52, 0.6)
	environment.ambient_light_energy = 0.35
	environment.glow_enabled = glow
	environment.glow_intensity = 0.5
	environment.glow_bloom = 0.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	environment.glow_hdr_threshold = 1.0
	sun.light_energy = 0.45
	sun.shadow_enabled = false
	floor_mat.shader = GRID
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	floor_mesh.mesh = plane
	floor_mesh.material_override = floor_mat
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(floor_mesh)
	world.add_child(effect_root)
	_build_gizmo()
	_apply_view()
	focus = Vector3(0, 1.0, 0)
	distance = 5.5
	pitch = -0.28
	yaw = 0.5
	max_distance = 30.0
	_library = _read_library()
	set_effect(Presets.effect("Campfire"))


# --- the effect --------------------------------------------------------------

func set_effect(e: Dictionary) -> void:
	fx = _sanitize(e)
	sel = 0
	# frame the effect: [camera distance, height looked at]
	distance = fx.view[0]
	focus = Vector3(effect_root.position.x, fx.view[1], effect_root.position.z)
	_place_camera()
	rebuild()
	restart()
	controls_changed.emit()


func rebuild() -> void:
	for r: Dictionary in runs:
		_free_run(r)
	runs.clear()
	var targets := _targets()
	for i in fx.emitters.size():
		runs.append(_make_run(i, targets))
	for i in runs.size():
		apply(i)


## Which emitters are set off by another's particles dying: {target: source}.
func _targets() -> Dictionary:
	var t := {}
	for i in fx.emitters.size():
		var s := int(fx.emitters[i].sub)
		if s >= 0 and s < fx.emitters.size() and s != i and not t.has(s) and int(fx.emitters[s].sub) < 0:
			t[s] = i
	return t


func _make_run(i: int, targets: Dictionary) -> Dictionary:
	var r := {
		node = GPUParticles3D.new(), pm = ParticleProcessMaterial.new(), dm = StandardMaterial3D.new(),
		quad = QuadMesh.new(), curve = Curve.new(), curve_tex = CurveTexture.new(), gradient = Gradient.new(),
		grad_tex = GradientTexture1D.new(), light = null, attractor = null, tracked = false, target_of = -1,
		mm = null, parts = [], spawn_acc = 0.0, pool = [], pool_i = 0, points = null,
	}
	r.target_of = targets.get(i, -1)
	var src := int(fx.emitters[i].sub)
	r.tracked = targets.has(src) and targets[src] == i
	var n: GPUParticles3D = r.node
	n.name = "Emitter%d" % i
	n.process_material = r.pm
	n.draw_pass_1 = r.quad
	r.quad.material = r.dm
	r.pm.scale_curve = r.curve_tex
	r.curve_tex.curve = r.curve
	r.pm.color_ramp = r.grad_tex
	r.grad_tex.gradient = r.gradient
	n.local_coords = false
	n.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.layers = 1 | (1 << (i + 1))
	effect_root.add_child(n)
	if r.tracked:
		# drawn from our own list instead: billboards in a MultiMesh
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = QuadMesh.new()
		mm.instance_count = TRACK_CAP
		mm.visible_instance_count = 0
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(mmi)
		r.mm = mmi
	if r.target_of != -1:
		for k in POOL:
			var p := GPUParticles3D.new()
			p.process_material = r.pm
			p.draw_pass_1 = r.quad
			p.one_shot = true
			p.emitting = false
			p.local_coords = false
			p.visibility_aabb = n.visibility_aabb
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			world.add_child(p)
			r.pool.append(p)
	return r


func _free_run(r: Dictionary) -> void:
	r.node.queue_free()
	if r.mm:
		r.mm.queue_free()
	if r.attractor:
		r.attractor.queue_free()
	for p: Node in r.pool:
		p.queue_free()


## Pushes emitter i's settings onto its nodes and materials.
func apply(i: int) -> void:
	var e: Dictionary = fx.emitters[i]
	var r: Dictionary = runs[i]
	var n: GPUParticles3D = r.node
	var pm: ParticleProcessMaterial = r.pm
	var burst: bool = e.burst or not fx.loop
	var amount := clampi(int(e.amount), 1, MAX_AMOUNT)
	if n.amount != amount:
		n.amount = amount
	if not is_equal_approx(n.lifetime, e.lifetime):
		n.lifetime = maxf(e.lifetime, 0.05)
	n.one_shot = burst
	n.explosiveness = e.explosive
	n.preprocess = e.lifetime if e.prewarm and not burst else 0.0
	n.speed_scale = fx.speed if playing else 0.0
	n.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH if e.blend == "mix" else GPUParticles3D.DRAW_ORDER_INDEX
	n.position = Vector3(0, e.offset_y, 0)
	n.rotation_degrees = Vector3(e.pitch, 0, 0)
	var hidden: bool = not e.on or r.tracked or r.target_of != -1
	n.visible = not hidden
	if hidden:
		n.emitting = false

	pm.lifetime_randomness = e.life_rand
	var s: float = e.shape_size
	pm.emission_shape_scale = Vector3(s, s * e.shape_y, s)
	pm.emission_shape_offset = Vector3.ZERO
	match e.shape:
		"point":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
		"sphere", "shell":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE if e.shape == "sphere" \
				else ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
			pm.emission_sphere_radius = 1.0
		"box":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			pm.emission_box_extents = Vector3.ONE
		"ring", "disc":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			pm.emission_ring_axis = Vector3.UP
			pm.emission_ring_radius = 1.0
			pm.emission_ring_inner_radius = e.ring_inner if e.shape == "ring" else 0.0
			pm.emission_ring_height = 1.0 if e.shape == "ring" else 0.0
			pm.emission_ring_cone_angle = 90.0
		"hemi", "line":
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
			pm.emission_point_texture = _points(e.shape)
			pm.emission_point_count = 256

	pm.direction = _direction(e)
	pm.spread = e.spread
	pm.flatness = 0.0
	pm.initial_velocity_min = e.speed * (1.0 - e.speed_rand)
	pm.initial_velocity_max = e.speed
	pm.inherit_velocity_ratio = e.inherit
	pm.orbit_velocity_min = e.orbit
	pm.orbit_velocity_max = e.orbit
	pm.radial_velocity_min = e.radial
	pm.radial_velocity_max = e.radial
	pm.gravity = Vector3(e.wind, e.gravity, 0)
	pm.damping_min = e.damping
	pm.damping_max = e.damping
	pm.tangential_accel_min = e.swirl
	pm.tangential_accel_max = e.swirl
	pm.radial_accel_min = e.radial_accel
	pm.radial_accel_max = e.radial_accel
	pm.turbulence_enabled = e.turb > 0.0
	pm.turbulence_influence_min = e.turb
	pm.turbulence_influence_max = e.turb
	pm.turbulence_noise_scale = e.turb_scale
	pm.turbulence_noise_speed_random = e.turb_speed
	pm.turbulence_noise_speed = Vector3(0, e.turb_speed * 0.5, 0)
	pm.attractor_interaction_enabled = e.attract != 0.0

	pm.scale_min = e.size * (1.0 - e.size_rand)
	pm.scale_max = e.size
	_fill_curve(r.curve, e.size_curve)
	var g := GradientEdit.build(e.grad)
	r.gradient.offsets = g.offsets
	r.gradient.colors = g.colors
	pm.hue_variation_min = -e.hue_rand
	pm.hue_variation_max = e.hue_rand
	pm.angle_min = -e.angle_rand * 0.5
	pm.angle_max = e.angle_rand * 0.5
	pm.angular_velocity_min = e.spin - e.spin_rand
	pm.angular_velocity_max = e.spin + e.spin_rand
	pm.particle_flag_rotate_y = e.mode == "flat"
	pm.particle_flag_align_y = false

	var q: QuadMesh = r.quad
	var dm: StandardMaterial3D = r.dm
	match e.mode:
		"stretch":
			q.orientation = PlaneMesh.FACE_Z
			q.size = Vector2(1.0, e.stretch)
			n.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
			dm.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		"flat":
			q.orientation = PlaneMesh.FACE_Y
			q.size = Vector2.ONE
			n.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
			dm.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		_:
			q.orientation = PlaneMesh.FACE_Z
			q.size = Vector2.ONE
			n.transform_align = GPUParticles3D.TRANSFORM_ALIGN_DISABLED
			dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			dm.billboard_keep_scale = true
	_style(dm, e)

	# a light that follows the emitter
	if e.light > 0.0 and e.on:
		if not r.light:
			r.light = OmniLight3D.new()
			r.light.shadow_enabled = false
			n.add_child(r.light)
		var lc := g.sample(0.25)
		lc.a = 1.0
		r.light.light_color = lc.lightened(0.15)
		r.light.omni_range = e.light_range
		r.light.light_energy = e.light
		r.light.visible = true
	elif r.light:
		r.light.visible = false

	# an attractor in the effect's space, pulling only this emitter's particles
	if e.attract != 0.0:
		if not r.attractor:
			r.attractor = GPUParticlesAttractorSphere3D.new()
			effect_root.add_child(r.attractor)
		r.attractor.position = Vector3(e.attract_x, e.attract_y, 0)
		r.attractor.radius = e.attract_radius
		r.attractor.strength = e.attract
		r.attractor.attenuation = 1.0
		r.attractor.cull_mask = 1 << (i + 1)
	elif r.attractor:
		r.attractor.queue_free()
		r.attractor = null

	if r.mm:
		var m: StandardMaterial3D = dm.duplicate()
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		var mq: QuadMesh = r.mm.multimesh.mesh
		mq.material = m
		r.mm.visible = e.on
	if r.target_of != -1:
		var src: Dictionary = fx.emitters[r.target_of]
		for k in r.pool.size():
			var p: GPUParticles3D = r.pool[k]
			# each burst one colour, stepping round the hue range, as fireworks are
			var pk: ParticleProcessMaterial = pm.duplicate()
			var hue: float = (float(k) / r.pool.size() * 2.0 - 1.0) * e.hue_rand
			pk.hue_variation_min = hue
			pk.hue_variation_max = hue
			p.process_material = pk
			p.amount = clampi(int(src.sub_count), 1, 300)
			p.lifetime = maxf(e.lifetime, 0.05)
			p.explosiveness = 1.0
			p.speed_scale = n.speed_scale
			p.transform_align = n.transform_align
			p.draw_order = n.draw_order
			p.visible = e.on and src.on


func _style(dm: StandardMaterial3D, e: Dictionary) -> void:
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if e.lit else BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.vertex_color_use_as_albedo = true
	dm.albedo_texture = Tex.get_texture(e.tex)
	dm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if e.blend == "add" else BaseMaterial3D.BLEND_MODE_MIX
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	dm.disable_receive_shadows = true
	var k: float = e.intensity
	dm.albedo_color = Color(k, k, k, 1.0)
	dm.proximity_fade_enabled = e.soft
	dm.proximity_fade_distance = 0.5
	if e.lit:
		dm.roughness = 1.0
		dm.metallic_specular = 0.0


func _direction(e: Dictionary) -> Vector3:
	var t := deg_to_rad(e.tilt)
	var h := deg_to_rad(e.heading)
	return Vector3(sin(t) * cos(h), cos(t), sin(t) * sin(h))


func _fill_curve(c: Curve, pts: Array) -> void:
	var built := CurveEdit.build(pts)
	c.clear_points()
	for k in built.point_count:
		c.add_point(built.get_point_position(k), built.get_point_left_tangent(k), built.get_point_right_tangent(k))


static var _point_cache := {}


## Emission points for the shapes Godot has no shape for, at unit size.
func _points(shape: String) -> Texture2D:
	if _point_cache.has(shape):
		return _point_cache[shape]
	var img := Image.create(256, 1, false, Image.FORMAT_RGBF)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for k in 256:
		var p := Vector3.ZERO
		if shape == "hemi":
			var v := Vector3(rng.randfn(), absf(rng.randfn()), rng.randfn()).normalized()
			p = v
		else:
			p = Vector3(rng.randf_range(-1.0, 1.0), 0, 0)
		img.set_pixel(k, 0, Color(p.x, p.y, p.z))
	var tex := ImageTexture.create_from_image(img)
	_point_cache[shape] = tex
	return tex


# --- playing -----------------------------------------------------------------

func restart() -> void:
	cycle_t = 0.0
	pending.clear()
	for i in runs.size():
		var r: Dictionary = runs[i]
		r.parts.clear()
		r.spawn_acc = 0.0
		if r.target_of != -1:
			continue
		r.node.emitting = false
		var d: float = fx.emitters[i].delay
		if d > 0.0:
			pending.append([d, i])
		else:
			_start(i)


func _start(i: int) -> void:
	var r: Dictionary = runs[i]
	var e: Dictionary = fx.emitters[i]
	if r.tracked:
		r.spawn_acc = float(e.amount) if e.explosive >= 0.9 else 0.0
		return
	if not e.on:
		return
	r.node.restart()
	r.node.emitting = true


func _has_bursts() -> bool:
	for e: Dictionary in fx.emitters:
		if e.burst:
			return true
	return false


func set_playing(on: bool) -> void:
	playing = on
	for i in runs.size():
		var s: float = fx.speed if playing else 0.0
		runs[i].node.speed_scale = s
		for p: GPUParticles3D in runs[i].pool:
			p.speed_scale = s


func _process(delta: float) -> void:
	super(delta)
	time += delta
	var p := effect_root.global_position
	root_vel = root_vel.lerp((p - _last_root) / maxf(delta, 0.001), 0.3)
	_last_root = p
	if _note_time > 0.0:
		_note_time -= delta
	if not playing:
		return
	var dt: float = delta * fx.speed
	cycle_t += dt
	for k in range(pending.size() - 1, -1, -1):
		if cycle_t >= pending[k][0]:
			var i: int = pending[k][1]
			pending.remove_at(k)
			_start(i)
	if fx.loop and _has_bursts() and cycle_t >= fx.cycle:
		cycle_t = 0.0
		for i in fx.emitters.size():
			if fx.emitters[i].burst and runs[i].target_of == -1:
				if fx.emitters[i].delay > 0.0:
					pending.append([fx.emitters[i].delay, i])
				else:
					_start(i)
	for i in runs.size():
		var r: Dictionary = runs[i]
		var e: Dictionary = fx.emitters[i]
		if r.light and r.light.visible and e.flicker > 0.0:
			var f := noise.get_noise_2d(time * 6.0, i * 31.0) * 0.5 + 0.5
			r.light.light_energy = e.light * (1.0 - e.flicker * 0.6 + e.flicker * 0.6 * f * 1.4)
		if r.tracked:
			_step_tracked(i, dt)


## The sub-emitter's source: spawn, fly and die here, setting off the target where they die.
func _step_tracked(i: int, dt: float) -> void:
	var r: Dictionary = runs[i]
	var e: Dictionary = fx.emitters[i]
	var cap := mini(int(e.amount), TRACK_CAP)
	if e.on and (fx.loop or cycle_t < e.lifetime + e.delay + 0.1):
		if e.explosive < 0.9:
			r.spawn_acc += dt * float(e.amount) / maxf(e.lifetime, 0.05)
		while r.spawn_acc >= 1.0 and r.parts.size() < cap:
			r.spawn_acc -= 1.0
			r.parts.append(_spawn(r, e))
		if r.parts.size() >= cap:
			r.spawn_acc = minf(r.spawn_acc, 1.0)
	var grav := Vector3(e.wind, e.gravity, 0)
	var target: Dictionary = runs[int(e.sub)] if int(e.sub) >= 0 and int(e.sub) < runs.size() else {}
	var mm: MultiMesh = r.mm.multimesh
	var shown := 0
	for k in range(r.parts.size() - 1, -1, -1):
		var q: Dictionary = r.parts[k]
		q.age += dt
		if q.age >= q.life:
			if not target.is_empty() and not target.pool.is_empty() and e.on:
				var node: GPUParticles3D = target.pool[target.pool_i % target.pool.size()]
				target.pool_i += 1
				node.global_position = q.p
				node.restart()
				node.emitting = true
			r.parts.remove_at(k)
			continue
		q.v += grav * dt
		var sp: float = q.v.length()
		if e.damping > 0.0 and sp > 0.0:
			q.v *= maxf(sp - e.damping * dt, 0.0) / sp
		q.p += q.v * dt
	for q: Dictionary in r.parts:
		var t: float = q.age / q.life
		var sc: float = q.size * maxf(r.curve.sample(t), 0.001)
		mm.set_instance_transform(shown, Transform3D(Basis.from_scale(Vector3.ONE * sc), q.p))
		mm.set_instance_color(shown, r.gradient.sample(t))
		shown += 1
	mm.visible_instance_count = shown


func _spawn(r: Dictionary, e: Dictionary) -> Dictionary:
	var s: float = e.shape_size
	var local := Vector3.ZERO
	match e.shape:
		"sphere":
			local = Vector3(randfn(0, 1), randfn(0, 1), randfn(0, 1)).normalized() * pow(randf(), 1.0 / 3.0)
		"shell":
			local = Vector3(randfn(0, 1), randfn(0, 1), randfn(0, 1)).normalized()
		"hemi":
			local = Vector3(randfn(0, 1), absf(randfn(0, 1)), randfn(0, 1)).normalized()
		"box":
			local = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
		"ring", "disc":
			var a := randf() * TAU
			var inner: float = e.ring_inner if e.shape == "ring" else 0.0
			var rad := sqrt(randf_range(inner * inner, 1.0))
			local = Vector3(cos(a) * rad, 0, sin(a) * rad)
		"line":
			local = Vector3(randf_range(-1, 1), 0, 0)
	local *= Vector3(s, s * e.shape_y, s)
	var xf: Transform3D = r.node.global_transform
	var dir := _direction(e)
	# a random direction within the spread cone
	var cone := deg_to_rad(e.spread) * sqrt(randf())
	var side := dir.cross(Vector3.RIGHT if absf(dir.y) > 0.9 else Vector3.UP).normalized()
	var d2 := dir.rotated(side, cone).rotated(dir, randf() * TAU)
	var speed: float = lerpf(e.speed * (1.0 - e.speed_rand), e.speed, randf())
	var v: Vector3 = xf.basis * d2 * speed + root_vel * e.inherit
	if e.radial != 0.0 and local.length() > 0.001:
		v += xf.basis * local.normalized() * e.radial
	return {p = xf * local, v = v, age = 0.0, life = maxf(e.lifetime * (1.0 - randf() * e.life_rand), 0.05),
		size = lerpf(e.size * (1.0 - e.size_rand), e.size, randf())}


# --- view --------------------------------------------------------------------

func _apply_view() -> void:
	environment.glow_enabled = glow
	floor_mesh.visible = show_floor
	gizmo.visible = show_gizmo
	match backdrop:
		0:
			set_sky(Color("141416"), Color("141416"), Color("141416")) # a flat sky: glow greys a plain colour
			floor_mat.set_shader_parameter("base", Color(0.13, 0.13, 0.14))
			floor_mat.set_shader_parameter("line_color", Color(0.26, 0.26, 0.29))
			sun.light_energy = 0.45
		1:
			set_sky(Color("4a4a50"), Color("4a4a50"), Color("4a4a50"))
			floor_mat.set_shader_parameter("base", Color(0.32, 0.32, 0.34))
			floor_mat.set_shader_parameter("line_color", Color(0.44, 0.44, 0.47))
			sun.light_energy = 0.8
		2:
			set_sky(Color("05070f"), Color("1c2238"), Color("0a0b10"))
			floor_mat.set_shader_parameter("base", Color(0.07, 0.08, 0.1))
			floor_mat.set_shader_parameter("line_color", Color(0.15, 0.17, 0.22))
			sun.light_energy = 0.15
		3:
			set_sky(Color("3a6ea5"), Color("c9d6e3"))
			floor_mat.set_shader_parameter("base", Color(0.38, 0.4, 0.36))
			floor_mat.set_shader_parameter("line_color", Color(0.5, 0.52, 0.48))
			sun.light_energy = 1.1


func _build_gizmo() -> void:
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.render_priority = 10
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for axis: Array in [[Vector3.RIGHT, Color(1, 0.35, 0.35, 0.9)], [Vector3.UP, Color(0.45, 1, 0.45, 0.9)],
			[Vector3.BACK, Color(0.45, 0.6, 1, 0.9)]]:
		im.surface_set_color(axis[1])
		im.surface_add_vertex(Vector3.ZERO)
		im.surface_add_vertex(axis[0] * 0.6)
	im.surface_set_color(Color(1, 1, 1, 0.45))
	for k in 32:
		for a in [k, k + 1]:
			var ang: float = a * TAU / 32.0
			im.surface_add_vertex(Vector3(cos(ang), 0, sin(ang)) * 0.4 + Vector3(0, 0.01, 0))
	im.surface_end()
	gizmo.mesh = im
	gizmo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	effect_root.add_child(gizmo)


# --- finger: drag the effect about ---------------------------------------------

func pokeable() -> bool:
	return true


func poke_down(pos: Vector2) -> void:
	var g: Variant = ground(pos, 0.0)
	if g == null:
		return
	_drag_off = effect_root.position - g # the effect follows the finger by how far it moves


func poke_move(pos: Vector2) -> void:
	var g: Variant = ground(pos, 0.0)
	if g == null:
		return
	var p: Vector3 = g + _drag_off
	p.y = 0.0
	effect_root.position = p.limit_length(12.0)


# --- status ------------------------------------------------------------------

func status() -> String:
	if _note_time > 0.0:
		return _note
	var total := 0
	for i in runs.size():
		var e: Dictionary = fx.emitters[i]
		if not e.on:
			continue
		if runs[i].tracked:
			total += runs[i].parts.size()
		elif runs[i].target_of != -1:
			total += int(fx.emitters[runs[i].target_of].sub_count) * POOL
		else:
			total += int(e.amount)
	var draws := RenderingServer.viewport_get_render_info(viewport.get_viewport_rid(),
		RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	return "%s · %d emitters · %d particles max · %d draws · %.1f ms%s" % [fx.name, fx.emitters.size(), total, draws,
		frame_ms(), "" if playing else " · paused"]


func _say(text: String) -> void:
	_note = text
	_note_time = 6.0


# --- the panel ---------------------------------------------------------------

func controls() -> Array:
	var c := look_controls()
	var e: Dictionary = fx.emitters[sel]
	c.append_array([
		{type = "section", label = "Effect"},
		{type = "custom", node = _effect_header()},
		{type = "toggle", label = "Play", value = playing, on = set_playing},
		{type = "button", label = "Restart", on = restart},
		{type = "toggle", label = "Loop", value = fx.loop, on = func(v: bool) -> void:
			fx.loop = v
			for i in runs.size():
				apply(i)
			restart()},
		{type = "slider", label = "Speed", min = 0.1, max = 3.0, step = 0.05, value = fx.speed, fmt = "%.2f", unit = "x",
			on = func(v: float) -> void:
				fx.speed = v
				set_playing(playing)},
		{type = "slider", label = "Cycle", min = 0.5, max = 10.0, step = 0.1, value = fx.cycle, unit = "s",
			on = func(v: float) -> void: fx.cycle = v},

		{type = "section", label = "Emitters"},
		{type = "custom", node = _emitter_list()},
		{type = "button", label = "Add", on = _add_emitter},
		{type = "button", label = "Duplicate", on = _duplicate_emitter},
		{type = "button", label = "Delete", on = _delete_emitter},
		{type = "button", label = "Up", on = _move_emitter.bind(-1)},

		{type = "section", label = "Emission  -  " + e.name},
		{type = "toggle", label = "Burst", value = e.burst, on = _set_bool.bind("burst", true)},
		{type = "toggle", label = "Prewarm", value = e.prewarm, on = _set_bool.bind("prewarm", true)},
		_slider("Amount", "amount", 1, MAX_AMOUNT, 1, "%d"),
		_slider("Lifetime", "lifetime", 0.05, 10.0, 0.05, "%.2f", "s"),
		_slider("Life random", "life_rand", 0.0, 1.0, 0.01, "%.2f"),
		_slider("Explosive", "explosive", 0.0, 1.0, 0.01, "%.2f"),
		_slider("Delay", "delay", 0.0, 5.0, 0.05, "%.2f", "s"),

		{type = "section", label = "Shape"},
		{type = "choice", label = "Shape", options = SHAPE_LABELS, value = maxi(SHAPES.find(e.shape), 0),
			on = func(k: int) -> void: _put("shape", SHAPES[k])},
		_slider("Size", "shape_size", 0.0, 5.0, 0.01, "%.2f", "m"),
		_slider("Height", "shape_y", 0.0, 2.0, 0.01, "%.2f", "x"),
		_slider("Inner", "ring_inner", 0.0, 1.0, 0.01, "%.2f"),
		_slider("Offset Y", "offset_y", -1.0, 6.0, 0.05, "%.2f", "m"),
		_slider("Pitch", "pitch", -180.0, 180.0, 1.0, "%d", "°"),

		{type = "section", label = "Velocity"},
		_slider("Tilt", "tilt", 0.0, 180.0, 1.0, "%d", "°"),
		_slider("Heading", "heading", 0.0, 360.0, 1.0, "%d", "°"),
		_slider("Spread", "spread", 0.0, 180.0, 1.0, "%d", "°"),
		_slider("Speed", "speed", 0.0, 20.0, 0.05, "%.2f", "m/s"),
		_slider("Speed random", "speed_rand", 0.0, 1.0, 0.01, "%.2f"),
		_slider("Inherit", "inherit", 0.0, 1.0, 0.01, "%.2f"),
		_slider("Orbit", "orbit", -2.0, 2.0, 0.01, "%.2f", "rev/s"),
		_slider("Radial", "radial", -5.0, 5.0, 0.05, "%.2f", "m/s"),

		{type = "section", label = "Forces"},
		_slider("Gravity", "gravity", -20.0, 10.0, 0.1, "%.1f", "m/s²"),
		_slider("Wind", "wind", -10.0, 10.0, 0.1, "%.1f", "m/s²"),
		_slider("Damping", "damping", 0.0, 10.0, 0.05, "%.2f"),
		_slider("Swirl", "swirl", -10.0, 10.0, 0.1, "%.1f"),
		_slider("Radial accel", "radial_accel", -10.0, 10.0, 0.1, "%.1f"),
		_slider("Turbulence", "turb", 0.0, 1.0, 0.01, "%.2f"),
		_slider("Turb scale", "turb_scale", 0.2, 10.0, 0.1, "%.1f"),
		_slider("Turb speed", "turb_speed", 0.0, 4.0, 0.05, "%.2f"),
		_slider("Attractor", "attract", -20.0, 20.0, 0.5, "%.1f"),
		_slider("Attractor Y", "attract_y", 0.0, 5.0, 0.05, "%.2f", "m"),
		_slider("Attractor X", "attract_x", -4.0, 4.0, 0.05, "%.2f", "m"),
		_slider("Attractor r", "attract_radius", 0.5, 8.0, 0.1, "%.1f", "m"),

		{type = "section", label = "Size over life"},
		_slider("Size", "size", 0.01, 8.0, 0.01, "%.2f", "m"),
		_slider("Size random", "size_rand", 0.0, 1.0, 0.01, "%.2f"),
		{type = "custom", node = _curve_widget()},

		{type = "section", label = "Color over life"},
		{type = "custom", node = _gradient_widget()},
		_slider("Intensity", "intensity", 0.0, 4.0, 0.05, "%.2f", "x"),
		_slider("Hue random", "hue_rand", 0.0, 1.0, 0.01, "%.2f"),

		{type = "section", label = "Rotation"},
		_slider("Angle random", "angle_rand", 0.0, 360.0, 1.0, "%d", "°"),
		_slider("Spin", "spin", -720.0, 720.0, 5.0, "%d", "°/s"),
		_slider("Spin random", "spin_rand", 0.0, 720.0, 5.0, "%d", "°/s"),

		{type = "section", label = "Renderer"},
		{type = "choice", label = "Sprite", options = Tex.LABELS, value = maxi(Tex.NAMES.find(e.tex), 0),
			on = func(k: int) -> void: _put("tex", Tex.NAMES[k])},
		{type = "choice", label = "Mode", options = MODE_LABELS, value = maxi(MODES.find(e.mode), 0),
			on = func(k: int) -> void: _put("mode", MODES[k])},
		_slider("Stretch", "stretch", 1.0, 20.0, 0.1, "%.1f", "x"),
		{type = "choice", label = "Blend", options = ["Additive", "Alpha"], value = 0 if e.blend == "add" else 1,
			on = func(k: int) -> void: _put("blend", "add" if k == 0 else "mix")},
		{type = "toggle", label = "Soft", value = e.soft, on = _set_bool.bind("soft", false)},
		{type = "toggle", label = "Lit", value = e.lit, on = _set_bool.bind("lit", false)},
		_slider("Light", "light", 0.0, 8.0, 0.1, "%.1f"),
		_slider("Light range", "light_range", 0.5, 15.0, 0.1, "%.1f", "m"),
		_slider("Flicker", "flicker", 0.0, 1.0, 0.01, "%.2f"),

		{type = "section", label = "Sub-emitter"},
		_sub_choice(),
		_slider("Count", "sub_count", 1, 200, 1, "%d"),

		{type = "section", label = "Library"},
		{type = "custom", node = _library_widget()},
		{type = "button", label = "Save", on = _save_effect},
		{type = "button", label = "Copy JSON", on = _copy_json},
		{type = "button", label = "Paste JSON", on = _paste_json},
		{type = "button", label = "Export .tscn", on = _export_tscn},

		{type = "section", label = "View"},
		{type = "choice", label = "Backdrop", options = BACKDROPS, value = backdrop, on = func(k: int) -> void:
			backdrop = k
			_apply_view()},
		{type = "toggle", label = "Floor", value = show_floor, on = func(v: bool) -> void:
			show_floor = v
			_apply_view()},
		{type = "toggle", label = "Gizmo", value = show_gizmo, on = func(v: bool) -> void:
			show_gizmo = v
			_apply_view()},
		{type = "toggle", label = "Glow", value = glow, on = func(v: bool) -> void:
			glow = v
			_apply_view()},
	])
	return c


func _slider(label: String, key: String, lo: float, hi: float, step: float, fmt: String, unit := "") -> Dictionary:
	var d := {type = "slider", label = label, min = lo, max = hi, step = step, value = float(fx.emitters[sel][key]),
		fmt = fmt, on = func(v: float) -> void: _put(key, v)}
	if unit != "":
		d.unit = unit
	return d


func _put(key: String, v: Variant) -> void:
	fx.emitters[sel][key] = v
	if key == "sub_count" and runs[sel].tracked:
		apply(int(fx.emitters[sel].sub))
	apply(sel)


func _set_bool(v: bool, key: String, replay: bool) -> void:
	fx.emitters[sel][key] = v
	apply(sel)
	if replay:
		restart()


func _sub_choice() -> Dictionary:
	var names := ["None"]
	var ids := [-1]
	for i in fx.emitters.size():
		if i != sel:
			names.append(fx.emitters[i].name)
			ids.append(i)
	var cur := ids.find(int(fx.emitters[sel].sub))
	return {type = "choice", label = "On death", options = names, value = maxi(cur, 0), on = func(k: int) -> void:
		fx.emitters[sel].sub = ids[k]
		rebuild()
		restart()}


func _curve_widget() -> Control:
	var w := CurveEdit.new(fx.emitters[sel].size_curve)
	w.changed.connect(func(pts: Array) -> void: _put("size_curve", pts))
	return w


func _gradient_widget() -> Control:
	var w := GradientEdit.new(fx.emitters[sel].grad)
	w.changed.connect(func(st: Array) -> void: _put("grad", st))
	return w


func _effect_header() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	box.add_child(name_row)
	var nl := Label.new()
	nl.text = "Name"
	nl.custom_minimum_size.x = 80
	name_row.add_child(nl)
	var edit := LineEdit.new()
	edit.text = fx.name
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size.y = 38
	edit.add_theme_stylebox_override("normal", _inset())
	edit.add_theme_stylebox_override("focus", _inset(C_ACCENT))
	edit.text_changed.connect(func(t: String) -> void: fx.name = t.strip_edges() if t.strip_edges() != "" else "Untitled")
	name_row.add_child(edit)
	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 8)
	box.add_child(preset_row)
	var pl := Label.new()
	pl.text = "Preset"
	pl.custom_minimum_size.x = 80
	preset_row.add_child(pl)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.custom_minimum_size.y = 38
	opt.fit_to_longest_item = false
	opt.clip_text = true
	opt.add_item("Load a preset...", 0)
	for k in Presets.NAMES.size():
		opt.add_item(Presets.NAMES[k], k + 1)
	opt.select(0)
	opt.item_selected.connect(func(idx: int) -> void:
		if idx > 0:
			set_effect(Presets.effect(Presets.NAMES[idx - 1])))
	preset_row.add_child(opt)
	return box


func _emitter_list() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	for i in fx.emitters.size():
		var e: Dictionary = fx.emitters[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		box.add_child(row)
		var eye := CheckBox.new()
		eye.button_pressed = e.on
		eye.custom_minimum_size = Vector2(40, 38)
		eye.toggled.connect(func(v: bool) -> void:
			e.on = v
			apply(i)
			if v:
				_start(i))
		row.add_child(eye)
		var b := Button.new()
		var tag := ""
		if runs[i].tracked:
			tag = "  > " + fx.emitters[int(e.sub)].name
		elif runs[i].target_of != -1:
			tag = "  (sub)"
		elif e.burst:
			tag = "  (burst)"
		b.text = "%d  %s%s" % [i + 1, e.name, tag]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 38
		b.clip_text = true
		if i == sel:
			var s := StyleBoxFlat.new()
			s.bg_color = C_ACCENT
			s.border_color = C_EDGE
			s.set_border_width_all(1)
			s.content_margin_left = 10
			b.add_theme_stylebox_override("normal", s)
			b.add_theme_stylebox_override("hover", s)
			b.add_theme_color_override("font_color", Color.WHITE)
		b.pressed.connect(func() -> void:
			sel = i
			controls_changed.emit())
		row.add_child(b)
	return box


func _library_widget() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	if _library.is_empty():
		var l := Label.new()
		l.text = "No saved effects yet."
		l.add_theme_color_override("font_color", DIM_TEXT)
		box.add_child(l)
	for key: String in _library:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		box.add_child(row)
		var b := Button.new()
		b.text = key
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 36
		b.clip_text = true
		b.pressed.connect(func() -> void:
			set_effect(_library[key])
			_say("Loaded " + key))
		row.add_child(b)
		var x := Button.new()
		x.text = "x"
		x.custom_minimum_size = Vector2(40, 36)
		x.pressed.connect(func() -> void:
			_library.erase(key)
			_write_library()
			controls_changed.emit())
		row.add_child(x)
	return box


func _inset(edge := C_EDGE) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = C_INSET
	s.border_color = edge
	s.set_border_width_all(1)
	s.content_margin_left = 8
	s.content_margin_right = 8
	return s


# --- emitter list actions ----------------------------------------------------

func _add_emitter() -> void:
	if fx.emitters.size() >= MAX_EMITTERS:
		_say("Up to %d emitters" % MAX_EMITTERS)
		return
	fx.emitters.append(Presets.em({name = "Emitter %d" % (fx.emitters.size() + 1), offset_y = 1.0}))
	_after_list_change(fx.emitters.size() - 1)


func _duplicate_emitter() -> void:
	if fx.emitters.size() >= MAX_EMITTERS:
		_say("Up to %d emitters" % MAX_EMITTERS)
		return
	var copy: Dictionary = fx.emitters[sel].duplicate(true)
	copy.name = "%s copy" % copy.name
	copy.sub = -1
	fx.emitters.insert(sel + 1, copy)
	_fix_subs(sel + 1, 1)
	_after_list_change(sel + 1)


func _delete_emitter() -> void:
	if fx.emitters.size() <= 1:
		_say("An effect needs one emitter")
		return
	fx.emitters.remove_at(sel)
	for e: Dictionary in fx.emitters:
		if int(e.sub) == sel:
			e.sub = -1
	_fix_subs(sel, -1)
	_after_list_change(mini(sel, fx.emitters.size() - 1))


func _move_emitter(step: int) -> void:
	var to := sel + step
	if to < 0 or to >= fx.emitters.size():
		return
	var a: Dictionary = fx.emitters[sel]
	fx.emitters[sel] = fx.emitters[to]
	fx.emitters[to] = a
	for e: Dictionary in fx.emitters:
		if int(e.sub) == sel:
			e.sub = to
		elif int(e.sub) == to:
			e.sub = sel
	_after_list_change(to)


## Emitters after `from` moved by `step` places: keep sub-emitter links pointing at them.
func _fix_subs(from: int, step: int) -> void:
	for e: Dictionary in fx.emitters:
		if int(e.sub) >= from:
			e.sub = int(e.sub) + step


func _after_list_change(new_sel: int) -> void:
	sel = clampi(new_sel, 0, fx.emitters.size() - 1)
	rebuild()
	restart()
	controls_changed.emit()


# --- save, load, copy, export -----------------------------------------------

func _sanitize(src: Dictionary) -> Dictionary:
	var out := {name = String(src.get("name", "Untitled")), loop = bool(src.get("loop", true)),
		speed = clampf(float(src.get("speed", 1.0)), 0.1, 3.0), cycle = clampf(float(src.get("cycle", 3.0)), 0.5, 10.0),
		view = [5.5, 1.0], emitters = []}
	var view: Variant = src.get("view")
	if view is Array and view.size() == 2:
		out.view = [clampf(float(view[0]), 1.0, 30.0), clampf(float(view[1]), 0.0, 10.0)]
	var list: Array = src.get("emitters", [])
	for item: Variant in list.slice(0, MAX_EMITTERS):
		if not item is Dictionary:
			continue
		var e := Presets.DEFAULT.duplicate(true)
		for k: String in item:
			if e.has(k) and typeof(item[k]) in [TYPE_FLOAT, TYPE_INT, TYPE_BOOL, TYPE_STRING, TYPE_ARRAY]:
				e[k] = item[k]
		e.sub = int(e.sub)
		e.amount = clampi(int(e.amount), 1, MAX_AMOUNT)
		out.emitters.append(e)
	if out.emitters.is_empty():
		out.emitters.append(Presets.em({}))
	return out


func _read_library() -> Dictionary:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	return data if data is Dictionary else {}


func _write_library() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_library))


func _save_effect() -> void:
	_library[fx.name] = fx.duplicate(true)
	_write_library()
	_say("Saved %s (%d in your library)" % [fx.name, _library.size()])
	controls_changed.emit()


func _copy_json() -> void:
	DisplayServer.clipboard_set(JSON.stringify(fx, "  "))
	_say("Copied %s as JSON" % fx.name)


func _paste_json() -> void:
	var json := JSON.new() # an instance, so text that isn't JSON doesn't log an error
	var data: Variant = json.data if json.parse(DisplayServer.clipboard_get()) == OK else null
	if not data is Dictionary or not data.has("emitters"):
		_say("The clipboard has no effect JSON in it")
		return
	set_effect(data)
	_say("Pasted " + fx.name)


func _export_tscn() -> void:
	var safe: String = fx.name.to_snake_case().validate_filename()
	if safe == "":
		safe = "effect"
	var out := Node3D.new()
	out.name = fx.name.to_pascal_case().validate_node_name()
	var made := {}
	for i in runs.size():
		var e: Dictionary = fx.emitters[i]
		var r: Dictionary = runs[i]
		if not e.on:
			continue
		var n: GPUParticles3D = r.node.duplicate()
		n.name = ("%s%d" % [String(e.name).to_pascal_case(), i + 1]).validate_node_name()
		n.visible = true
		n.speed_scale = fx.speed
		n.emitting = r.target_of == -1
		n.one_shot = (e.burst or not fx.loop) and r.target_of == -1
		if r.target_of != -1:
			n.amount = clampi(int(fx.emitters[r.target_of].sub_count), 1, 300)
		if e.delay > 0.0:
			n.set_meta("start_delay", e.delay)
		if r.tracked:
			var pm: ParticleProcessMaterial = r.pm.duplicate()
			pm.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_AT_END
			pm.sub_emitter_amount_at_end = int(e.sub_count)
			n.process_material = pm
		out.add_child(n)
		made[i] = n
		if r.attractor:
			var a: Node3D = r.attractor.duplicate()
			a.name = "%sAttractor" % n.name
			out.add_child(a)
	for i: int in made:
		if runs[i].tracked and made.has(int(fx.emitters[i].sub)):
			made[i].sub_emitter = made[i].get_path_to(made[int(fx.emitters[i].sub)])
	_own(out, out)
	var packed := PackedScene.new()
	packed.pack(out)
	out.free()
	DirAccess.make_dir_recursive_absolute("user://exports")
	var path := "user://exports/%s.tscn" % safe
	var err := ResourceSaver.save(packed, path)
	if err != OK:
		_say("Export failed (%s)" % error_string(err))
		return
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var bytes := FileAccess.get_file_as_bytes(path)
		Engine.get_singleton("JavaScriptBridge").download_buffer(bytes, safe + ".tscn", "text/plain")
		_say("Downloading %s.tscn" % safe)
	else:
		_say("Exported to " + ProjectSettings.globalize_path(path))


func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)
