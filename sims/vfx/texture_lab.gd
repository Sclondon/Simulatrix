extends Sim3D
## Texture Lab: a procedural texture generator. texture_gen.gdshader draws the texture into
## a 512² SubViewport on the GPU (and a second copy as plain height for the 3D previews),
## so every slider is live. Previews: flat, tiled 3x3, on a sphere, or as lit terrain.
## Save PNG renders it again at the export size and downloads (web) or saves it to user://.

const GEN_SHADER := preload("res://sims/vfx/texture_gen.gdshader")
const PREVIEW_SHADER := preload("res://sims/vfx/texture_preview.gdshader")
const TEX := 512
const PLANE := 10.0

const TYPES := ["Value", "Perlin", "Simplex", "Cells", "Voronoi", "FBM", "Ridged", "Billow", "Warp",
	"Wood", "Marble", "Bricks", "Bark", "Clouds", "Ripples", "Caustics"]
## Types that sum octaves (the others ignore Octaves, Lacunarity and Gain)
const FRACTAL := [5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
const PREVIEWS := ["Flat", "Tiled", "Sphere", "Terrain"]
## Ramps as offset/colour stops. The ones after Water are only reached by Auto.
const RAMPS := {
	"Greyscale": [[0.0, "000000"], [1.0, "ffffff"]],
	"Heat": [[0.0, "000000"], [0.3, "7a0b0b"], [0.55, "e8530e"], [0.8, "ffd23f"], [1.0, "ffffff"]],
	"Terrain": [[0.0, "16325e"], [0.36, "3f7cc4"], [0.41, "d9c58f"], [0.46, "6aa548"], [0.64, "3d6e2f"],
		[0.78, "7d6b5a"], [0.9, "b0a89e"], [0.95, "ffffff"]],
	"Lava": [[0.0, "120604"], [0.45, "3a0d06"], [0.62, "b3200b"], [0.8, "ff7b1c"], [1.0, "fff2a8"]],
	"Ice": [[0.0, "0b1d33"], [0.5, "4f8fbf"], [0.8, "bfe6f5"], [1.0, "ffffff"]],
	"Toxic": [[0.0, "0a0f05"], [0.5, "2f5d12"], [0.8, "8ee53f"], [1.0, "e8ff9c"]],
	"Bone": [[0.0, "2a2420"], [0.5, "8f8070"], [0.85, "dcd2bd"], [1.0, "f6f1e4"]],
	"Night": [[0.0, "05060f"], [0.5, "1d2350"], [0.8, "5a4ba3"], [1.0, "d9c8ff"]],
	"Wood": [[0.0, "3b2412"], [0.4, "6e4425"], [0.75, "a8743f"], [1.0, "d4a568"]],
	"Brick": [[0.0, "6f6b63"], [0.22, "9a958b"], [0.3, "4a2a20"], [0.55, "8a3826"], [1.0, "c96a4e"]],
	"Sand": [[0.0, "8c6a3f"], [0.5, "c9a46a"], [1.0, "f0d9a6"]],
	"Water": [[0.0, "06243d"], [0.4, "0f5a7a"], [0.75, "4fc0d0"], [1.0, "eaffff"]],
	"Marble": [[0.0, "2f3a3a"], [0.4, "8a8f8a"], [0.8, "e2ded6"], [1.0, "f7f5f0"]],
	"Bark": [[0.0, "1a110a"], [0.45, "4a3524"], [1.0, "9a8066"]],
	"Sky": [[0.0, "3d6fb6"], [0.45, "6f9fd8"], [0.75, "dfe9f5"], [1.0, "ffffff"]],
}
const RAMP_CHOICES := ["Auto", "Greyscale", "Heat", "Terrain", "Lava", "Ice", "Toxic", "Bone", "Night",
	"Wood", "Brick", "Sand", "Water"]
## What Auto picks for each type
const AUTO_RAMP := {9: "Wood", 10: "Marble", 11: "Brick", 12: "Bark", 13: "Sky", 14: "Sand", 15: "Water"}

var gen_type := 8
var basis := 1
var seed_value := 1234
var tex_scale := 4.0
var octaves := 6
var lacunarity := 2.0
var gain := 0.5
var warp := 0.6
var jitter := 1.0
var rotation_deg := 0.0
var evolve := 0.0
var ramp := 4 # Lava
var view := 0
var contrast := 1.0
var level_lo := 0.0
var level_hi := 1.0
var posterize := 0
var bump := 1.0
var invert := false
var seamless := true
var preview := 0
var relief := 1.5
var tile_edges := false
var export_size := 1024

var gen_vp := SubViewport.new()
var height_vp := SubViewport.new()
var gen_rect := ColorRect.new()
var gen_mat := ShaderMaterial.new()
var height_mat := ShaderMaterial.new()
var ramp_tex := GradientTexture1D.new()
var sphere := MeshInstance3D.new()
var terrain := MeshInstance3D.new()
var sphere_mat := ShaderMaterial.new()
var terrain_mat := ShaderMaterial.new()

var pan := Vector2.ZERO
var zoom := 1.0
var anim_time := 0.0
var _flat_touches := {}
var _pinch2 := 0.0
var _mid2 := Vector2.ZERO
var _dirty := true
var _height_stale := true
var _saving := false
var _msg := ""
var _msg_time := 0.0
var _font: Font


func help() -> String:
	return ("A procedural texture generator running on the GPU. Pick a Type: plain noises (Value, Perlin, "
		+ "Simplex), cell noises (Cells, Voronoi), fractals (FBM, Ridged, Billow, Warp) built on the Basis "
		+ "noise, or material patterns (Wood, Marble, Bricks, Bark, Clouds, Ripples, Caustics).\n\n"
		+ "Scale is how many features cross the tile. Octaves, Lacunarity and Gain shape the fractal sum. "
		+ "Warp bends the domain with more noise; Evolve animates the texture through time.\n\n"
		+ "Output maps the height through a colour ramp (Auto picks one per pattern), with levels, contrast, "
		+ "posterize and a normal-map view. Seamless makes every type tile exactly; check it on Tiled. "
		+ "(Rotation only applies with Seamless off.)\n\n"
		+ "Flat and Tiled: drag to pan, pinch or scroll to zoom. Sphere and Terrain: drag to orbit. "
		+ "Save PNG exports the current view (colour, height or normal) at the chosen size.")


func hint() -> String:
	return "Pick a Type and drag its sliders. Preview shows it tiled, on a sphere or as terrain."


func status() -> String:
	if _msg_time > 0.0:
		return _msg
	var bits: Array[String] = [TYPES[gen_type]]
	if gen_type in FRACTAL or gen_type == 8:
		bits.append("%d oct" % octaves)
	bits.append("seed %d" % seed_value)
	bits.append("%d²" % TEX)
	bits.append("seamless" if seamless else "free")
	bits.append(PREVIEWS[preview])
	if evolve > 0.0:
		bits.append("t %.1f" % anim_time)
	return " · ".join(bits)


func build() -> void:
	_font = load("res://fonts/PixelifySans.ttf") if ResourceLoader.exists("res://fonts/PixelifySans.ttf") \
		else ThemeDB.fallback_font
	_make_gen(gen_vp, gen_mat, gen_rect)
	_make_gen(height_vp, height_mat, ColorRect.new())
	ramp_tex.width = 256

	set_sky(Color("2a2d34"), Color("575b66"), Color("1b1d22"))
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.7
	sun.rotation = Vector3(deg_to_rad(-38), deg_to_rad(-40), 0)
	sun.light_energy = 1.3

	for m: ShaderMaterial in [sphere_mat, terrain_mat]:
		m.shader = PREVIEW_SHADER
		m.set_shader_parameter("albedo_tex", gen_vp.get_texture())
		m.set_shader_parameter("height_tex", height_vp.get_texture())
	sphere_mat.set_shader_parameter("uv_scale", Vector2(2, 1))
	sphere_mat.set_shader_parameter("texel", 1.0 / TEX)
	terrain_mat.set_shader_parameter("texel", 2.0 / TEX)

	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 128
	ball.rings = 64
	sphere.mesh = ball
	sphere.material_override = sphere_mat
	world.add_child(sphere)
	var plane := PlaneMesh.new()
	plane.size = Vector2(PLANE, PLANE)
	plane.subdivide_width = 191
	plane.subdivide_depth = 191
	terrain.mesh = plane
	terrain.material_override = terrain_mat
	world.add_child(terrain)

	_apply_all()
	_set_preview(preview)


func _make_gen(vp: SubViewport, mat: ShaderMaterial, rect: ColorRect) -> void:
	vp.size = Vector2i(TEX, TEX)
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	mat.shader = GEN_SHADER
	rect.size = Vector2(TEX, TEX)
	rect.material = mat
	vp.add_child(rect)
	add_child(vp)


# --- parameters ----------------------------------------------------------------

func _param(name: String, value: Variant) -> void:
	gen_mat.set_shader_parameter(name, value)
	height_mat.set_shader_parameter(name, value)
	_dirty = true


func _apply_all() -> void:
	_param("gen_type", gen_type)
	_param("basis", basis)
	_param("seed", float(seed_value))
	_param("scale", tex_scale)
	_param("octaves", octaves)
	_param("lacunarity", lacunarity)
	_param("gain", gain)
	_param("warp", warp)
	_param("jitter", jitter)
	_param("rotation", deg_to_rad(rotation_deg))
	_param("time", anim_time)
	_param("seamless", seamless)
	_param("invert", invert)
	_param("contrast", contrast)
	_param("level_lo", level_lo)
	_param("level_hi", level_hi)
	_param("posterize", posterize)
	_param("normal_strength", bump)
	_param("tex_size", float(TEX))
	gen_mat.set_shader_parameter("view_mode", view)
	height_mat.set_shader_parameter("view_mode", 1)
	_apply_ramp()
	_apply_relief()


func _ramp_name() -> String:
	if ramp == 0:
		return AUTO_RAMP.get(gen_type, "Greyscale")
	return RAMP_CHOICES[ramp]


func _apply_ramp() -> void:
	var stops: Array = RAMPS[_ramp_name()]
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for s: Array in stops:
		offsets.append(s[0])
		colors.append(Color(s[1]))
	g.offsets = offsets
	g.colors = colors
	ramp_tex.gradient = g
	gen_mat.set_shader_parameter("ramp", ramp_tex)
	# The Terrain ramp's water lies flat at sea level instead of in pits
	terrain_mat.set_shader_parameter("floor_h", 0.39 if _ramp_name() == "Terrain" and view == 0 else 0.0)
	_dirty = true


func _apply_relief() -> void:
	terrain_mat.set_shader_parameter("relief", relief)
	terrain_mat.set_shader_parameter("bump", maxf(relief, 0.05) * TEX / PLANE * 0.5)
	sphere_mat.set_shader_parameter("relief", relief * 0.04)
	sphere_mat.set_shader_parameter("bump", 3.0 + bump * 6.0)


func _ramp_swatch(name: String) -> Color:
	if name == "Auto":
		return Color("7a7a82")
	var stops: Array = RAMPS[name]
	return Color(stops[int(stops.size() * 0.6)][1])


func controls() -> Array:
	var swatches := []
	for n: String in RAMP_CHOICES:
		swatches.append(_ramp_swatch(n))
	return [
		{type = "section", label = "Generator"},
		{type = "choice", label = "Type", options = TYPES, value = gen_type, on = func(i: int) -> void:
			gen_type = i
			_param("gen_type", i)
			_apply_ramp()},
		{type = "choice", label = "Basis", options = ["Value", "Perlin", "Simplex"], value = basis,
			on = func(i: int) -> void:
				basis = i
				_param("basis", i)},
		{type = "slider", label = "Seed", min = 0, max = 9999, step = 1, value = seed_value, fmt = "%d",
			on = func(v: float) -> void:
				seed_value = int(v)
				_param("seed", v)},
		{type = "button", label = "Randomize", on = func() -> void:
			seed_value = randi_range(0, 9999)
			_param("seed", float(seed_value))
			controls_changed.emit()},
		{type = "slider", label = "Scale", min = 1, max = 32, step = 0.5, value = tex_scale, fmt = "%.1f",
			on = func(v: float) -> void:
				tex_scale = v
				_param("scale", v)},
		{type = "slider", label = "Octaves", min = 1, max = 8, step = 1, value = octaves, fmt = "%d",
			on = func(v: float) -> void:
				octaves = int(v)
				_param("octaves", octaves)},
		{type = "slider", label = "Lacunarity", min = 1.5, max = 3.5, step = 0.05, value = lacunarity,
			fmt = "%.2f", on = func(v: float) -> void:
				lacunarity = v
				_param("lacunarity", v)},
		{type = "slider", label = "Gain", min = 0.2, max = 0.8, step = 0.01, value = gain, fmt = "%.2f",
			on = func(v: float) -> void:
				gain = v
				_param("gain", v)},
		{type = "slider", label = "Warp", min = 0, max = 2, step = 0.01, value = warp, fmt = "%.2f",
			on = func(v: float) -> void:
				warp = v
				_param("warp", v)},
		{type = "slider", label = "Jitter", min = 0, max = 1, step = 0.01, value = jitter, fmt = "%.2f",
			on = func(v: float) -> void:
				jitter = v
				_param("jitter", v)},
		{type = "slider", label = "Rotation", min = 0, max = 360, step = 1, value = rotation_deg, fmt = "%d",
			unit = "°", on = func(v: float) -> void:
				rotation_deg = v
				_param("rotation", deg_to_rad(v))},
		{type = "slider", label = "Evolve", min = 0, max = 2, step = 0.05, value = evolve, fmt = "%.2f",
			unit = "/s", on = func(v: float) -> void: evolve = v},

		{type = "section", label = "Output"},
		{type = "choice", label = "Ramp", options = RAMP_CHOICES, colors = swatches, value = ramp,
			on = func(i: int) -> void:
				ramp = i
				_apply_ramp()},
		{type = "choice", label = "View", options = ["Colour", "Height", "Normal"], value = view,
			on = func(i: int) -> void:
				view = i
				gen_mat.set_shader_parameter("view_mode", i)
				_apply_ramp()},
		{type = "slider", label = "Contrast", min = 0.2, max = 3, step = 0.05, value = contrast, fmt = "%.2f",
			on = func(v: float) -> void:
				contrast = v
				_param("contrast", v)},
		{type = "slider", label = "Level low", min = 0, max = 1, step = 0.01, value = level_lo, fmt = "%.2f",
			on = func(v: float) -> void:
				level_lo = v
				_param("level_lo", v)},
		{type = "slider", label = "Level high", min = 0, max = 1, step = 0.01, value = level_hi, fmt = "%.2f",
			on = func(v: float) -> void:
				level_hi = v
				_param("level_hi", v)},
		{type = "slider", label = "Posterize", min = 0, max = 16, step = 1, value = posterize, fmt = "%d",
			on = func(v: float) -> void:
				posterize = int(v)
				_param("posterize", posterize)},
		{type = "slider", label = "Bump", min = 0, max = 4, step = 0.05, value = bump, fmt = "%.2f",
			on = func(v: float) -> void:
				bump = v
				_param("normal_strength", v)
				_apply_relief()},
		{type = "toggle", label = "Invert", value = invert, on = func(on: bool) -> void:
			invert = on
			_param("invert", on)},

		{type = "section", label = "Preview"},
		{type = "choice", label = "Mode", options = PREVIEWS, value = preview, on = _set_preview},
		{type = "slider", label = "Relief", min = 0, max = 4, step = 0.05, value = relief, fmt = "%.2f",
			unit = "m", on = func(v: float) -> void:
				relief = v
				_apply_relief()},
		{type = "toggle", label = "Seamless", value = seamless, on = func(on: bool) -> void:
			seamless = on
			_param("seamless", on)},
		{type = "toggle", label = "Tile edges", value = tile_edges, on = func(on: bool) -> void:
			tile_edges = on
			queue_redraw()},
		{type = "button", label = "Reset view", on = func() -> void: _set_preview(preview)},

		{type = "section", label = "Export"},
		{type = "choice", label = "Size", options = ["512", "1024"], value = 1 if export_size == 1024 else 0,
			on = func(i: int) -> void: export_size = 1024 if i == 1 else 512},
		{type = "button", label = "Save PNG", on = save_png},
	]


func _set_preview(i: int) -> void:
	preview = i
	sphere.visible = i == 2
	terrain.visible = i == 3
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if i >= 2 else SubViewport.UPDATE_DISABLED
	_touches.clear()
	_flat_touches.clear()
	pan = Vector2.ZERO
	zoom = 1.0
	focus = Vector3.ZERO
	if i == 2:
		distance = 3.4
		min_distance = 1.6
		max_distance = 10.0
		pitch = -0.25
		auto_orbit = 0.25
	elif i == 3:
		distance = 13.0
		min_distance = 4.0
		max_distance = 30.0
		pitch = -0.62
		auto_orbit = 0.1
	_place_camera()
	_height_stale = true
	_update_filter()
	queue_redraw()


func _say(text: String) -> void:
	_msg = text
	_msg_time = 6.0


## Renders the current output at the export size and downloads or saves it.
func save_png() -> void:
	if _saving:
		return
	_saving = true
	var n := export_size
	gen_vp.size = Vector2i(n, n)
	gen_rect.size = Vector2(n, n)
	gen_mat.set_shader_parameter("tex_size", float(n))
	gen_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := gen_vp.get_texture().get_image()
	gen_vp.size = Vector2i(TEX, TEX)
	gen_rect.size = Vector2(TEX, TEX)
	gen_mat.set_shader_parameter("tex_size", float(TEX))
	_dirty = true
	_saving = false
	var file := "%s_%d_%d.png" % [TYPES[gen_type].to_lower(), seed_value, n]
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(img.save_png_to_buffer(), file, "image/png")
		_say("Downloaded " + file)
	else:
		DirAccess.make_dir_recursive_absolute("user://textures")
		var path := "user://textures/" + file
		var err := img.save_png(path)
		_say(("Saved " + ProjectSettings.globalize_path(path)) if err == OK else "Save failed (%d)" % err)


# --- frame ---------------------------------------------------------------------

func _process(delta: float) -> void:
	super._process(delta)
	if _msg_time > 0.0:
		_msg_time -= delta
	if evolve > 0.0:
		anim_time += delta * evolve
		_param("time", anim_time)
	if _saving:
		return
	if _dirty:
		_dirty = false
		gen_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_height_stale = true
	if _height_stale and preview >= 2:
		_height_stale = false
		height_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _update_filter() -> void:
	# Zoomed in on the flat views, show texels as crisp squares like a paint program
	var px := _tile_px() / TEX
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if preview < 2 and px > 1.6 \
		else CanvasItem.TEXTURE_FILTER_LINEAR


## Screen size of one tile of the texture in the flat views.
func _tile_px() -> float:
	var fit := minf(size.x, size.y) * 0.84
	return (fit if preview == 0 else fit / 3.0) * zoom


func _draw() -> void:
	if preview >= 2:
		super._draw()
		return
	# A dim checkerboard behind the image, like an empty canvas
	draw_rect(Rect2(Vector2.ZERO, size), Color("26262a"))
	var cell := 16.0
	for y in int(ceil(size.y / cell)):
		for x in int(ceil(size.x / cell)):
			if (x + y) % 2 == 0:
				draw_rect(Rect2(Vector2(x, y) * cell, Vector2(cell, cell)), Color("2d2d32"))
	var tex := gen_vp.get_texture()
	var s := _tile_px()
	var n := 1 if preview == 0 else 3
	var origin := size * 0.5 + pan - Vector2(s, s) * n * 0.5
	var whole := Rect2(origin, Vector2(s, s) * n)
	draw_rect(whole.grow(2.0), Color("0e0e10"))
	for y in n:
		for x in n:
			draw_texture_rect(tex, Rect2(origin + Vector2(x, y) * s, Vector2(s, s)), false)
	if n == 3 and tile_edges:
		for k in range(1, 3):
			var a := origin + Vector2(k * s, 0)
			draw_dashed_line(a, a + Vector2(0, s * 3), Color(1, 1, 1, 0.35), 1.0, 6.0)
			var b := origin + Vector2(0, k * s)
			draw_dashed_line(b, b + Vector2(s * 3, 0), Color(1, 1, 1, 0.35), 1.0, 6.0)
	var label := "%d × %d px   %d%%" % [TEX, TEX, roundi(s / TEX * 100.0)]
	if n == 3:
		label += "   3 × 3 tiles"
	var at := Vector2(whole.position.x, minf(whole.end.y + 24.0, size.y - 8.0))
	draw_string(_font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("9a9aa3"))


# --- input: flat views pan and zoom; 3D views use the orbit camera -----------

func touch_down(index: int, pos: Vector2) -> void:
	if preview >= 2:
		super.touch_down(index, pos)
		return
	_flat_touches[index] = pos
	if _flat_touches.size() == 2:
		_start_pinch2()


func touch_move(index: int, pos: Vector2) -> void:
	if preview >= 2:
		super.touch_move(index, pos)
		return
	if not _flat_touches.has(index):
		return
	var last: Vector2 = _flat_touches[index]
	_flat_touches[index] = pos
	if _flat_touches.size() >= 2:
		var pts: Array = _flat_touches.values()
		var d: float = pts[0].distance_to(pts[1])
		var mid: Vector2 = (pts[0] + pts[1]) * 0.5
		pan += mid - _mid2
		if _pinch2 > 1.0:
			_zoom_at(mid, d / _pinch2)
		_pinch2 = d
		_mid2 = mid
	else:
		pan += pos - last
	queue_redraw()


func touch_up(index: int, pos: Vector2) -> void:
	if preview >= 2:
		super.touch_up(index, pos)
		return
	_flat_touches.erase(index)
	if _flat_touches.size() == 2:
		_start_pinch2()


func _start_pinch2() -> void:
	var pts: Array = _flat_touches.values()
	_pinch2 = pts[0].distance_to(pts[1])
	_mid2 = (pts[0] + pts[1]) * 0.5


func _zoom_at(p: Vector2, factor: float) -> void:
	var z := clampf(zoom * factor, 0.25, 12.0)
	var k := z / zoom
	zoom = z
	var c := size * 0.5 + pan
	pan = p + (c - p) * k - size * 0.5
	_update_filter()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if preview >= 2:
		super._unhandled_input(event)
		return
	if event is InputEventMouseButton and event.pressed:
		var p := get_local_mouse_position()
		if not Rect2(Vector2.ZERO, size).has_point(p):
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(p, 1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(p, 1.0 / 1.15)


func resize(new_size: Vector2) -> void:
	super.resize(new_size)
	_update_filter()
