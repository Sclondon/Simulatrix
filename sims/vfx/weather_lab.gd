extends Sim3D
## What the weather labs (Cloud Lab, Rain, Snow, Lightning) share: GameCommon's WeatherRig over
## the editor grid the other labs stand on (weather_grid.gdshader, which takes the weather: wet,
## puddles, snow, cloud shadows), primitive props that show the wet and the snow (rig.weathered),
## common rows (time, wind, quality) and an Export that saves the rig's settings as a scene.
## Each lab extends this and sets the rig up in setup().

const GRID := preload("res://sims/vfx/weather_grid.gdshader")
const Sprites := preload("res://sims/vfx/particles/textures.gd")
const TYPES := ["Cumulus", "Stratus", "Storm", "Cirrus", "Altocumulus"]

var rig := WeatherRig.new()
var floor_mesh := MeshInstance3D.new()
var floor_mat := ShaderMaterial.new()
var props := Node3D.new()
## Set in setup(): stand primitive props on the grid.
var with_props := false
## The picked sprite for each of the rig's sprite textures ("" built in, "user:<name>" a drawn one).
var sprite_ids := {}


## Override: set the rig's settings before it starts (it is not in the tree yet).
func setup() -> void:
	pass


## Override: the default name and the lab's title for Export, and a line on using the asset.
func export_info() -> Dictionary:
	return {name = "Weather", lab = "Weather", use = ""}


## Re-applies every setting (for scripts that set the rig's exports directly).
func refresh() -> void:
	rig.refresh()


func build() -> void:
	focus = Vector3(0, 1.0, 0)
	distance = 15.0
	yaw = 0.55
	pitch = -0.28
	min_distance = 3.0
	max_distance = 80.0
	max_pitch = 0.6
	camera.near = 0.1
	camera.far = 22000.0
	sun.directional_shadow_max_distance = 60.0
	rig.sun = sun
	rig.environment = environment
	setup()
	world.add_child(rig)
	floor_mat.shader = GRID
	floor_mat.set_shader_parameter("noise_tex", Daylight.cloud_noise())
	var plane := PlaneMesh.new()
	plane.size = Vector2(30000, 30000)
	floor_mesh.mesh = plane
	floor_mesh.material_override = floor_mat
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	floor_mesh.extra_cull_margin = 1000.0
	world.add_child(floor_mesh)
	rig.register(floor_mat)
	world.add_child(props)
	if with_props:
		add_props()


func _process(delta: float) -> void:
	super(delta)
	# The floor goes wherever the camera is (the grid is drawn in world space, so it stays put), and
	# far off it is the sky just under the horizon, so they meet without an edge
	var cam := camera.global_position
	floor_mesh.position = Vector3(roundf(cam.x), 0.0, roundf(cam.z))
	if rig.sky_material and not rig.day.is_empty():
		var under := rig.horizon_color() * (0.3 + 0.7 * (1.0 - float(rig.day.night)))
		rig.sky_material.set_shader_parameter("ground", rig.horizon_color())
		floor_mat.set_shader_parameter("far_color", under)


# --- props -------------------------------------------------------------------

## Primitive shapes round the middle of the grid, for the wet and the snow to show on; the rain
## splashes and the hail bounces land on their tops too (a height map given to the rig).
func add_props() -> void:
	var tints := [Color(0.85, 0.5, 0.28), Color(0.3, 0.62, 0.66), Color(0.82, 0.8, 0.74), Color(0.7, 0.32, 0.32),
		Color(0.45, 0.5, 0.62), Color(0.55, 0.6, 0.38)]
	var mats: Array[ShaderMaterial] = []
	for t in tints:
		mats.append(rig.weathered(false, 1.0, t, false))
	# shape, size, position (centre), material: [kind, size Vector3, x, z, mat]
	var specs := [
		["box", Vector3(1.6, 1.6, 1.6), -2.6, -1.2, 0],
		["box", Vector3(0.8, 3.2, 0.8), 1.4, -3.4, 2],
		["sphere", Vector3(1.0, 1.0, 1.0), 2.6, 0.8, 1],
		["cylinder", Vector3(0.6, 1.1, 0.6), -0.4, 2.4, 3],
		["box", Vector3(3.0, 0.45, 0.9), -0.2, -0.2, 4],
		["capsule", Vector3(0.45, 1.8, 0.45), 4.2, -2.2, 5],
		["cylinder", Vector3(1.1, 0.35, 1.1), -4.2, 2.6, 2],
	]
	var n := 96
	var rect := Rect2(-12, -12, 24, 24)
	var img := Image.create(n, n, false, Image.FORMAT_RF)
	for s in specs:
		var kind: String = s[0]
		var sz: Vector3 = s[1]
		var mi := MeshInstance3D.new()
		var top := sz.y
		match kind:
			"box":
				var m := BoxMesh.new()
				m.size = sz
				mi.mesh = m
				mi.position = Vector3(s[2], sz.y * 0.5, s[3])
			"sphere":
				var m := SphereMesh.new()
				m.radius = sz.x
				m.height = sz.x * 2.0
				m.radial_segments = 24
				m.rings = 12
				mi.mesh = m
				mi.position = Vector3(s[2], sz.x, s[3])
				top = sz.x * 2.0
			"cylinder":
				var m := CylinderMesh.new()
				m.top_radius = sz.x
				m.bottom_radius = sz.x
				m.height = sz.y
				m.radial_segments = 20
				mi.mesh = m
				mi.position = Vector3(s[2], sz.y * 0.5, s[3])
			"capsule":
				var m := CapsuleMesh.new()
				m.radius = sz.x
				m.height = sz.y
				mi.mesh = m
				mi.position = Vector3(s[2], sz.y * 0.5, s[3])
		mi.material_override = mats[s[4]]
		props.add_child(mi)
		# the prop's top in the splash height map
		for y in n:
			for x in n:
				var wx := rect.position.x + (x + 0.5) * rect.size.x / n
				var wz := rect.position.y + (y + 0.5) * rect.size.y / n
				var dx: float = wx - s[2]
				var dz: float = wz - s[3]
				var h := 0.0
				match kind:
					"box":
						if absf(dx) < sz.x * 0.5 and absf(dz) < sz.z * 0.5:
							h = top
					"sphere":
						var r2 := sz.x * sz.x - dx * dx - dz * dz
						if r2 > 0.0:
							h = sz.x + sqrt(r2)
					_:
						var r2 := sz.x * sz.x - dx * dx - dz * dz
						if r2 > 0.0:
							h = top if kind == "cylinder" else top - sz.x + sqrt(r2)
				if h > img.get_pixel(x, y).r:
					img.set_pixel(x, y, Color(h, 0, 0))
	rig.set_ground(ImageTexture.create_from_image(img), rect)


# --- rows the labs share --------------------------------------------------------

func time_controls(cycle := true) -> Array:
	var c: Array = [
		{type = "slider", label = "Hour", min = 0.0, max = 24.0, step = 0.25, value = rig.hour, fmt = "%05.2f", unit = "h",
			on = func(v: float) -> void: rig.hour = v},
	]
	if cycle:
		c.append({type = "toggle", label = "Day cycle", value = rig.day_speed > 0.0,
			on = func(v: bool) -> void: rig.day_speed = 0.2 if v else 0.0})
	return c


func wind_controls(max_wind := 25.0) -> Array:
	return [
		{type = "slider", label = "Wind", min = 0.0, max = max_wind, step = 0.5, value = rig.wind, fmt = "%.1f", unit = "m/s",
			on = func(v: float) -> void: rig.wind = v},
		{type = "slider", label = "From", min = 0.0, max = 360.0, step = 5.0, value = rig.wind_from, fmt = "%.0f", unit = "°",
			on = func(v: float) -> void: rig.wind_from = v},
	]


func quality_controls() -> Array:
	return [
		{type = "section", label = "View"},
		{type = "choice", label = "Quality", options = ["Low", "Medium", "High"], value = rig.quality,
			on = func(i: int) -> void: rig.quality = i},
		{type = "toggle", label = "Props", value = props.visible, on = func(v: bool) -> void: props.visible = v},
	]


## A sprite picker (ui/shape_pad.gd) for one of the rig's sprite textures (drop_texture,
## splash_texture, flake_texture): the built-in shape, the particle sprites, or one drawn or imported.
func sprite_controls(label: String, prop: String, default_label: String) -> Array:
	return ShapePad.picker_controls(label, sprite_ids.get(prop, ""), func(id: String) -> void:
		sprite_ids[prop] = id
		rig.set(prop, _sprite_tex(id)),
		[{id = "", label = default_label, tex = null}] + ShapePad.builtins(Sprites.NAMES, Sprites.LABELS, Sprites.get_texture))


static func _sprite_tex(id: String) -> Texture2D:
	if id == "":
		return null
	return ShapePad.texture(id, func(n: String) -> Texture2D:
		return Sprites.get_texture(n if n in Sprites.NAMES else "soft"))


func export_controls() -> Array:
	var info := export_info()
	return Exporter.controls(info.name, _export, "weather", func(line: String) -> void: say.emit(line))


## " · 12.3 ms"
func ms() -> String:
	return " · %.1f ms" % frame_ms()


# --- export ------------------------------------------------------------------

func _export(name: String) -> void:
	# A fresh rig carrying every setting (not the running one, so none of what it built goes too);
	# a picked sprite goes inside the scene
	var out := WeatherRig.new()
	out.name = Exporter.slug(name).to_pascal_case()
	for p in rig.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and p.usage & PROPERTY_USAGE_STORAGE \
				and (p.type != TYPE_OBJECT or rig.get(p.name) is Texture2D):
			out.set(p.name, rig.get(p.name))
	var slug := Exporter.slug(name)
	var info := export_info()
	var use := ("var weather := (load(\"res://assets/weather/%s.tscn\") as PackedScene).instantiate() as WeatherRig\n" % slug
		+ "weather.sun = $Sun   # or leave it to make its own; it drives the WorldEnvironment's sky and fog\n"
		+ "add_child(weather)")
	if info.use != "":
		use += "\n" + info.use
	say.emit(Exporter.save("weather", name, {"tscn": out}, ["godot/weather"], use, info.lab))
	out.free()
