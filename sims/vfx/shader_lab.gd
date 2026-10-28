extends Sim3D
## Shader Lab: a live editor for Godot shaders. Type in the code pane (or pick a preset) and the
## preview recompiles 0.4 s after you stop. Every edit is compiled first on a hidden probe
## shader, with a Logger catching the compiler's errors, so a broken shader shows its error and
## line while the last good one keeps running. Uniforms with hints become properties on the
## panel. canvas_item shaders draw on a full quad over the preview (Shadertoy style); spatial
## shaders go on a mesh in the Sim3D viewport.

const DIR := "res://sims/vfx/shader_lab/"
## Uniforms the lab fills in itself; they never show as properties.
const AUTO := ["resolution", "mouse", "since_poke"]
const Sprites := preload("res://sims/vfx/particles/textures.gd")
const PRESETS := [
	{name = "Plasma", file = "plasma"},
	{name = "Metaballs", file = "metaballs"},
	{name = "Fire", file = "fire"},
	{name = "CRT", file = "pixelate_crt"},
	{name = "Voronoi", file = "voronoi"},
	{name = "Ripples", file = "ripples"},
	{name = "Matrix", file = "matrix_rain"},
	{name = "Tunnel", file = "tunnel"},
	{name = "Ocean", file = "ocean", mesh = 3},
	{name = "Toon rim", file = "toon_rim", mesh = 2},
	{name = "Dissolve", file = "dissolve", mesh = 0},
	{name = "Hologram", file = "hologram", mesh = 2},
	{name = "Glass", file = "fresnel_glass", mesh = 0},
	{name = "Rock", file = "triplanar_rock", mesh = 1},
	{name = "Ghost", file = "ghost", mesh = 0},
	{name = "Jelly", file = "jelly", mesh = 0},
	{name = "Sprite scroll", file = "sprite_scroll"},
]
const MESHES := ["Sphere", "Cube", "Torus", "Plane", "Cylinder"]
const NEW_2D := """shader_type canvas_item;
// A new 2D shader. UV runs 0..1 across the preview.
// Filled in for you: resolution (pixels), mouse (UV under your finger), since_poke (seconds since a tap).
uniform vec2 resolution = vec2(512.0);
uniform vec2 mouse = vec2(0.5);

uniform vec3 color_a : source_color = vec3(0.1, 0.2, 0.5);
uniform vec3 color_b : source_color = vec3(1.0, 0.6, 0.2);
uniform float speed : hint_range(0.0, 5.0) = 1.0;

void fragment() {
	float t = 0.5 + 0.5 * sin(TIME * speed + UV.x * 6.28318);
	COLOR = vec4(mix(color_a, color_b, t * UV.y), 1.0);
}
"""
const NEW_3D := """shader_type spatial;
// A new 3D shader. Pick a mesh under Preview; drag the preview to orbit.
uniform vec3 albedo : source_color = vec3(0.8, 0.5, 0.3);
uniform float roughness : hint_range(0.0, 1.0) = 0.4;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

void vertex() {
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
"""
const KEYWORDS := ["shader_type", "render_mode", "uniform", "varying", "const", "in", "out", "inout", "if", "else",
	"for", "while", "do", "break", "continue", "return", "discard", "struct", "group_uniforms", "instance",
	"global", "true", "false", "switch", "case", "default", "flat", "smooth", "lowp", "mediump", "highp"]
const TYPES := ["void", "bool", "int", "uint", "float", "vec2", "vec3", "vec4", "ivec2", "ivec3", "ivec4",
	"uvec2", "uvec3", "uvec4", "bvec2", "bvec3", "bvec4", "mat2", "mat3", "mat4", "sampler2D", "isampler2D",
	"usampler2D", "sampler2DArray", "sampler3D", "samplerCube", "samplerExternalOES"]
const BUILTINS := ["TIME", "PI", "TAU", "E", "UV", "UV2", "COLOR", "VERTEX", "NORMAL", "TANGENT", "BINORMAL",
	"ALBEDO", "ALPHA", "ALPHA_SCISSOR_THRESHOLD", "EMISSION", "ROUGHNESS", "METALLIC", "SPECULAR", "RIM", "RIM_TINT",
	"CLEARCOAT", "CLEARCOAT_ROUGHNESS", "AO", "AO_LIGHT_AFFECT", "NORMAL_MAP", "NORMAL_MAP_DEPTH", "FRAGCOORD",
	"FRONT_FACING", "SCREEN_UV", "SCREEN_PIXEL_SIZE", "POINT_COORD", "POINT_SIZE", "TEXTURE", "TEXTURE_PIXEL_SIZE",
	"VIEW", "LIGHT", "LIGHT_COLOR", "LIGHT_ENERGY", "ATTENUATION", "DIFFUSE_LIGHT", "SPECULAR_LIGHT",
	"MODEL_MATRIX", "VIEW_MATRIX", "INV_VIEW_MATRIX", "PROJECTION_MATRIX", "INV_PROJECTION_MATRIX",
	"MODELVIEW_MATRIX", "CANVAS_MATRIX", "SCREEN_MATRIX", "CAMERA_POSITION_WORLD", "NODE_POSITION_WORLD",
	"INSTANCE_ID", "VERTEX_ID", "INSTANCE_CUSTOM", "CUSTOM0", "CUSTOM1", "SHADOW_VERTEX", "LIGHT_VERTEX",
	"LIGHT_POSITION", "LIGHT_DIRECTION", "LIGHT_IS_DIRECTIONAL", "SPECULAR_SHININESS", "OUTPUT_IS_SRGB"]
const HINTS := ["source_color", "hint_range", "hint_normal", "hint_default_white", "hint_default_black",
	"hint_screen_texture", "hint_depth_texture", "hint_enum", "filter_nearest", "filter_linear",
	"filter_linear_mipmap", "repeat_enable", "repeat_disable", "instance_index"]

# Palette: the shell's (main.gd), copied here rather than preloading main.gd, which preloads this
const C_BACK := Color("1c1c1e")
const C_FACE := Color("38383c")
const C_FACE_LO := Color("2b2b2f")
const C_EDGE := Color("111113")
const C_ACCENT := Color("4f86c6")
const C_ACCENT_HI := Color("6fa3de")
const DIM_TEXT := Color("9a9aa3")
const C_CODE := Color("17181b")
const C_ERROR := Color("4a1f22")

## Collects the shader compiler's errors while a probe compile runs.
class ErrorCatcher extends Logger:
	var listening := false
	var errors: Array = []
	var mutex := Mutex.new()

	func _log_error(_function: String, _file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if not listening:
			return
		mutex.lock()
		errors.append({line = line, text = code if rationale == "" else rationale, shader = error_type == ERROR_TYPE_SHADER})
		mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func begin() -> void:
		mutex.lock()
		errors.clear()
		listening = true
		mutex.unlock()

	## The errors caught since begin(), the compiler's own first.
	func finish() -> Array:
		mutex.lock()
		listening = false
		var out := errors.filter(func(e: Dictionary) -> bool: return e.shader)
		out.append_array(errors.filter(func(e: Dictionary) -> bool: return not e.shader))
		mutex.unlock()
		return out


var code := CodeEdit.new()
var code_box := VBoxContainer.new()
var toolbar := PanelContainer.new()
var view_buttons: Array[Button] = []
var mode_label := Label.new()
var dot_label := Label.new()
var error_strip := PanelContainer.new()
var error_label := Label.new()
var canvas := ColorRect.new()
var mesh := MeshInstance3D.new()
var grid := MeshInstance3D.new()
var live_shader := Shader.new()
var live_mat := ShaderMaterial.new()
var probe_shader := Shader.new()
var probe_mat := ShaderMaterial.new()
var catcher := ErrorCatcher.new()
var mono := SystemFont.new()

var mode := ""
var title := "Untitled"
var preset := 0
var saved_index := -1
var saved: Array = [] # [{name, code}]
var next_number := 1
var loaded_text := ""
var last_src := ""
var error := {} # {line, text} while the code doesn't compile
var error_line := -1
var uniforms: Array = []
var signature := ""
var values := {}
var defaults := {}
var mesh_index := 0
var spin := true
var show_grid := true
var auto_compile := true
var font_size := 17
var show_code := false # narrow screens show either the code or the preview
var wide := true
var preview := Rect2()
var compile_timer := 0.0
var since_poke := 100.0
var mouse_uv := Vector2(0.5, 0.5)
var taps := {} # touch index -> [start position, start msec]
var note := ""
var note_until := 0
## Under a test runner (tests/*.gd) the lab keeps its own clipboard and save file.
var testing := false
var clip := ""


func help() -> String:
	return ("A live editor for Godot shaders. Pick a preset, or write your own in the code pane: it recompiles 0.4 s "
		+ "after you stop typing (Ctrl+Enter compiles now, Ctrl+S saves). If it doesn't compile, the error and its line "
		+ "show under the code and the last good shader keeps running.\n\n"
		+ "Uniforms become properties: float and int with hint_range(min, max) are sliders, bool is a check box, and "
		+ "vec3/vec4 with source_color is a colour, and sampler2D is a picture: a built-in noise or sprite, one you draw "
		+ "(+ Draw) or an image you import (+ Import). group_uniforms Name; starts a new section.\n\n"
		+ "shader_type canvas_item draws over the whole preview: UV is 0..1, and the lab fills in resolution (pixels), "
		+ "mouse (the UV under your finger) and since_poke (seconds since you tapped). shader_type spatial goes on a mesh: "
		+ "pick it under Preview; drag to orbit, pinch or scroll to zoom, tap to set since_poke.\n\n"
		+ "My shaders are kept on this device. Export sends the shader (and a material with the values set here) "
		+ "to GameCommon's asset library; Send to project... copies it into a game's assets/shaders/.")


func hint() -> String:
	return "Pick a preset and drag its uniforms, or edit the code: it recompiles as you type."


func status() -> String:
	if note != "" and Time.get_ticks_msec() < note_until:
		return note
	var state := "compiled OK"
	if not error.is_empty():
		state = ("line %d: %s" % [error.line, error.text]) if error.line > 0 else str(error.text)
	var dirty := "*" if code.text != loaded_text else ""
	var shown := uniforms.size()
	return "%s · %s%s · %s · %d uniform%s · %.1f ms" % [mode, title, dirty, state, shown, "" if shown == 1 else "s", frame_ms()]


func build() -> void:
	testing = Engine.get_main_loop().get_script() != null
	set_sky(Color("1b1d22"), Color("464b55"), Color("26282d"))
	environment.ambient_light_energy = 0.5
	sun.rotation = Vector3(deg_to_rad(-45), deg_to_rad(-40), 0)
	OS.add_logger(catcher)
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	grid.mesh = plane
	grid.position.y = -1.3
	var grid_mat := ShaderMaterial.new()
	grid_mat.shader = load(DIR + "grid.gdshader")
	grid.material_override = grid_mat
	world.add_child(grid)
	world.add_child(mesh)
	live_mat.shader = live_shader
	# The probe compiles every edit first; assigning it to a material makes its compiles happen at once
	probe_shader.code = NEW_2D
	probe_mat.shader = probe_shader
	mono.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Menlo", "DejaVu Sans Mono", "Courier New", "monospace"])
	_build_ui()
	_load_saved()
	_set_mesh(0)
	load_preset(0)
	_layout()


func _exit_tree() -> void:
	OS.remove_logger(catcher)


# --- the panel ---------------------------------------------------------------

func controls() -> Array:
	var c: Array = [
		{type = "section", label = "Shader"},
		{type = "choice", label = "Preset", options = PRESETS.map(func(p: Dictionary) -> String: return p.name),
			value = preset, on = load_preset},
	]
	var group := "-"
	for u: Dictionary in uniforms:
		if u.group != group:
			group = u.group
			c.append({type = "section", label = "Uniforms" if group == "" else group.capitalize()})
		c.append(_uniform_control(u))
	if mode == "spatial":
		c.append_array([
			{type = "section", label = "Preview"},
			{type = "choice", label = "Mesh", options = MESHES, value = mesh_index, on = _set_mesh},
			{type = "toggle", label = "Spin", value = spin, on = func(on: bool) -> void: spin = on},
			{type = "toggle", label = "Grid", value = show_grid, on = _set_grid},
		])
	c.append({type = "section", label = "File"})
	if not saved.is_empty():
		c.append({type = "choice", label = "My shaders", options = saved.map(func(s: Dictionary) -> String: return s.name),
			value = saved_index, on = _open_saved})
	c.append_array([
		{type = "button", label = "New 2D", on = func() -> void: _new_doc(NEW_2D)},
		{type = "button", label = "New 3D", on = func() -> void: _new_doc(NEW_3D)},
		{type = "button", label = "Save", on = _save},
		{type = "button", label = "Delete", on = _delete},
		{type = "button", label = "Copy", on = _copy},
		{type = "button", label = "Paste", on = _paste},
		{type = "section", label = "Editor"},
		{type = "slider", label = "Font size", min = 10, max = 36, step = 1, value = font_size, fmt = "%d", unit = "px",
			on = func(v: float) -> void: _set_font_size(int(v))},
		{type = "toggle", label = "Auto compile", value = auto_compile, on = func(on: bool) -> void: auto_compile = on},
		{type = "button", label = "Compile", on = func() -> void: _compile(true)},
	])
	c.append_array(Exporter.controls(title, _export, "shaders", _say))
	return c


func _uniform_control(u: Dictionary) -> Dictionary:
	var uname: String = u.name
	var label := uname.capitalize()
	match u.kind:
		"texture":
			return ShapePad.picker_controls(label, values[uname], func(id: String) -> void: _set_value(uname, id),
				picture_builtins())[0]
		"bool":
			return {type = "toggle", label = label, value = values[uname], on = func(on: bool) -> void: _set_value(uname, on)}
		"color":
			return {type = "custom", node = _color_widget(label, values[uname], u.alpha,
				func(c: Color) -> void: _set_value(uname, c))}
		"int":
			return {type = "slider", label = label, min = u.min, max = u.max, step = 1, value = values[uname], fmt = "%d",
				on = func(v: float) -> void: _set_value(uname, int(v))}
	var span: float = u.max - u.min
	var fmt := "%.3f" if span <= 0.5 else ("%.2f" if span <= 20.0 else "%.1f")
	return {type = "slider", label = label, min = u.min, max = u.max, step = u.step, value = values[uname], fmt = fmt,
		on = func(v: float) -> void: _set_value(uname, v)}


## A colour property: a swatch that folds out hue, saturation, value (and alpha) bars.
func _color_widget(label: String, value: Color, alpha: bool, on_change: Callable) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	var name_label := Label.new()
	name_label.text = label
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	var swatch := Button.new()
	swatch.toggle_mode = true
	swatch.custom_minimum_size = Vector2(96, 36)
	swatch.tooltip_text = "Edit colour"
	head.add_child(swatch)
	var bars := VBoxContainer.new()
	bars.add_theme_constant_override("separation", 2)
	bars.hide()
	box.add_child(bars)
	var color := [value]
	var paint := func() -> void:
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			var s := StyleBoxFlat.new()
			s.bg_color = color[0]
			s.border_color = C_ACCENT_HI if state.contains("pressed") else C_EDGE
			s.set_border_width_all(2 if state.contains("pressed") else 1)
			swatch.add_theme_stylebox_override(state, s)
	paint.call()
	swatch.toggled.connect(func(on: bool) -> void: bars.visible = on)
	var channels := ["H", "S", "V", "A"] if alpha else ["H", "S", "V"]
	for ch: String in channels:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		bars.add_child(row)
		var l := Label.new()
		l.text = ch
		l.custom_minimum_size.x = 22
		l.add_theme_color_override("font_color", DIM_TEXT)
		row.add_child(l)
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.001
		s.custom_minimum_size.y = 32
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var c: Color = color[0]
		s.value = {H = c.h, S = c.s, V = c.v, A = c.a}[ch]
		row.add_child(s)
		s.value_changed.connect(func(v: float) -> void:
			var now: Color = color[0]
			match ch:
				"H": now = Color.from_hsv(v, now.s, now.v, now.a)
				"S": now = Color.from_hsv(now.h, v, now.v, now.a)
				"V": now = Color.from_hsv(now.h, now.s, v, now.a)
				"A": now.a = v
			color[0] = now
			paint.call()
			on_change.call(now))
	return box


# --- loading and compiling ---------------------------------------------------

func load_preset(index: int) -> void:
	var p: Dictionary = PRESETS[clampi(index, 0, PRESETS.size() - 1)]
	preset = PRESETS.find(p)
	saved_index = -1
	title = p.name
	if p.has("mesh"):
		_set_mesh(p.mesh)
	var shader: Shader = load(DIR + "presets/" + p.file + ".gdshader")
	_open_text(shader.code)


func _open_text(text: String) -> void:
	values.clear()
	defaults.clear()
	since_poke = 0.0
	code.text = text
	code.clear_undo_history()
	loaded_text = text
	compile_timer = 0.0
	_compile(true)
	controls_changed.emit()


func _compile(force := false) -> void:
	compile_timer = 0.0
	var src := code.text
	if src == last_src and not force:
		return
	last_src = src
	var type := _shader_type(src)
	if type != "canvas_item" and type != "spatial":
		var where := _line_of(src, "shader_type")
		_show_error(where, ("Shader Lab previews canvas_item and spatial shaders, not %s" % type) if type != ""
			else "Start with shader_type canvas_item; or shader_type spatial;")
		return
	catcher.begin()
	probe_shader.code = src
	var errs := catcher.finish()
	if not errs.is_empty():
		var first: Dictionary = errs[0]
		_show_error(first.line, first.text)
		return
	_clear_error()
	# Take the material off whatever shows it while the shader's type may change under it
	canvas.material = null
	mesh.material_override = null
	live_shader.code = src
	_set_mode(type)
	_parse_uniforms(src)
	_apply_values()


func _set_mode(type: String) -> void:
	mode = type
	if type == "canvas_item":
		canvas.material = live_mat
		mode_label.text = "2D  canvas_item"
	else:
		mesh.material_override = live_mat
		mode_label.text = "3D  spatial"
	_layout()


func _shader_type(src: String) -> String:
	var re := RegEx.create_from_string("(?m)^\\s*shader_type\\s+(\\w+)")
	var m := re.search(_strip_comments(src))
	return m.get_string(1) if m else ""


func _line_of(src: String, word: String) -> int:
	var lines := src.split("\n")
	for i in lines.size():
		if lines[i].contains(word):
			return i + 1
	return 1


func _strip_comments(src: String) -> String:
	# keep the newlines, so offsets still line up by line
	var re := RegEx.create_from_string("/\\*[\\s\\S]*?\\*/|//[^\\n]*")
	var out := ""
	var at := 0
	for m in re.search_all(src):
		out += src.substr(at, m.get_start() - at)
		out += "\n".repeat(m.get_string().count("\n"))
		at = m.get_end()
	return out + src.substr(at)


func _show_error(line: int, text: String) -> void:
	error = {line = line, text = text}
	_unmark_error_line()
	if line > 0 and line <= code.get_line_count():
		error_line = line - 1
		code.set_line_background_color(error_line, Color(0.75, 0.2, 0.22, 0.35))
	error_label.text = ("Line %d: %s" % [line, text]) if line > 0 else text
	error_strip.show()
	dot_label.text = "ERROR"
	dot_label.add_theme_color_override("font_color", Color("ff8a8a"))


func _clear_error() -> void:
	error = {}
	_unmark_error_line()
	error_strip.hide()
	dot_label.text = "OK"
	dot_label.add_theme_color_override("font_color", Color("8fd18f"))


func _unmark_error_line() -> void:
	if error_line >= 0 and error_line < code.get_line_count():
		code.set_line_background_color(error_line, Color(0, 0, 0, 0))
	error_line = -1


## Reads the uniforms the panel can show. Rebuilds the panel when the list changes.
func _parse_uniforms(src: String) -> void:
	var text := _strip_comments(src)
	var re := RegEx.create_from_string(
		"group_uniforms(?:\\s+([\\w.]+))?\\s*;|(?<![\\w])(instance\\s+|global\\s+)?uniform\\s+(?:(?:lowp|mediump|highp)\\s+)?(\\w+)\\s+(\\w+)\\s*(?::\\s*([^=;]*?))?\\s*(?:=\\s*([^;]+?))?\\s*;")
	var range_re := RegEx.create_from_string("hint_range\\s*\\(\\s*([-+\\d.eE]+)\\s*,\\s*([-+\\d.eE]+)\\s*(?:,\\s*([-+\\d.eE]+))?\\s*\\)")
	var found: Array = []
	var group := ""
	for m in re.search_all(text):
		if m.get_string(0).begins_with("group_uniforms"):
			group = m.get_string(1)
			continue
		if m.get_string(2) != "":
			continue # instance and global uniforms belong to the scene, not the material
		var type := m.get_string(3)
		var uname := m.get_string(4)
		var hints := m.get_string(5)
		var init := m.get_string(6).strip_edges()
		if uname in AUTO:
			continue
		var u := {name = uname, group = group, type = type, alpha = false}
		var r := range_re.search(hints)
		match type:
			"bool":
				u.kind = "bool"
				u.default = init == "true"
			"int", "uint":
				u.kind = "int"
				u.min = r.get_string(1).to_float() if r else 0.0
				u.max = r.get_string(2).to_float() if r else 10.0
				u.default = int(init.to_float()) if init.is_valid_float() else int(u.min)
			"float":
				u.kind = "float"
				var dflt := init.to_float() if init.is_valid_float() else 0.0
				u.min = r.get_string(1).to_float() if r else minf(0.0, dflt)
				u.max = r.get_string(2).to_float() if r else maxf(1.0, dflt * 2.0)
				u.step = r.get_string(3).to_float() if r and r.get_string(3) != "" else maxf((u.max - u.min) / 500.0, 0.0001)
				u.default = clampf(dflt, u.min, u.max) if init.is_valid_float() else u.min
			"sampler2D":
				# the screen and depth come from the renderer, not from a picture
				if hints.contains("hint_screen_texture") or hints.contains("hint_depth_texture") \
						or hints.contains("hint_normal_roughness_texture"):
					continue
				u.kind = "texture"
				u.default = "noise:perlin" if uname.to_lower().contains("noise") else "sprite:leaf_maple"
			"vec3", "vec4":
				if not hints.contains("source_color"):
					continue
				u.kind = "color"
				u.alpha = type == "vec4"
				u.default = _parse_color(init, u.alpha)
			_:
				continue
		found.append(u)
	uniforms = found
	for u: Dictionary in uniforms:
		var key := "%s:%s" % [u.name, u.kind]
		# a default changed in the code (or a new uniform) takes over; otherwise the panel's value stays
		if not defaults.has(key) or defaults[key] != u.default or not values.has(u.name):
			values[u.name] = u.default
		defaults[key] = u.default
	var sig := mode
	for u: Dictionary in uniforms:
		sig += "|%s %s %s %s %s" % [u.group, u.name, u.kind, u.get("min", ""), u.get("max", "")]
	if sig != signature:
		signature = sig
		controls_changed.emit()


func _parse_color(init: String, alpha: bool) -> Color:
	var nums: Array = []
	for m in RegEx.create_from_string("[-+]?\\d*\\.?\\d+(?:[eE][-+]?\\d+)?").search_all(init):
		nums.append(m.get_string().to_float())
	if init.begins_with("vec") and nums.size() > 0:
		nums.remove_at(0) # the 3 or 4 of vec3/vec4
	if nums.size() == 1:
		return Color(nums[0], nums[0], nums[0], 1.0)
	if nums.size() >= 3:
		return Color(nums[0], nums[1], nums[2], nums[3] if alpha and nums.size() >= 4 else 1.0)
	return Color(1, 1, 1, 1)


func _set_value(uname: String, v: Variant) -> void:
	values[uname] = v
	live_mat.set_shader_parameter(uname, _uniform_value(v))


## What a uniform is set to: the value itself, or for a sampler2D (whose value is a picture's id)
## the texture.
static func _uniform_value(v: Variant) -> Variant:
	return picture(v) if v is String else v


const NOISES := ["perlin", "simplex", "cells", "value", "fbm", "ridged"]
const NOISE_LABELS := ["Perlin", "Simplex", "Cells", "Value", "FBM", "Ridged"]
static var _noises := {}


## A picture for a sampler2D uniform by id: "" none (the shader's default), "noise:<kind>" a
## built-in seamless noise, "sprite:<name>" a particle sprite, "user:<name>" one drawn or imported.
static func picture(id: String) -> Texture2D:
	if id == "":
		return null
	if id.begins_with("noise:"):
		var kind := id.trim_prefix("noise:")
		if not _noises.has(kind):
			var n := FastNoiseLite.new()
			n.seed = 7
			n.frequency = 0.012
			n.fractal_type = FastNoiseLite.FRACTAL_NONE
			match kind:
				"simplex": n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
				"cells":
					n.noise_type = FastNoiseLite.TYPE_CELLULAR
					n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
				"value": n.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
				"fbm":
					n.noise_type = FastNoiseLite.TYPE_PERLIN
					n.fractal_type = FastNoiseLite.FRACTAL_FBM
					n.fractal_octaves = 5
				"ridged":
					n.noise_type = FastNoiseLite.TYPE_PERLIN
					n.fractal_type = FastNoiseLite.FRACTAL_RIDGED
					n.fractal_octaves = 5
				_: n.noise_type = FastNoiseLite.TYPE_PERLIN
			var t := NoiseTexture2D.new()
			t.width = 256
			t.height = 256
			t.seamless = true
			t.generate_mipmaps = true
			t.noise = n
			_noises[kind] = t
		return _noises[kind]
	if id.begins_with("sprite:"):
		var name := id.trim_prefix("sprite:")
		return Sprites.get_texture(name if name in Sprites.NAMES else "soft")
	return ShapeStore.texture(id)


## The pictures a sampler2D uniform can pick besides the user's own: none, the noises, the sprites.
static func picture_builtins() -> Array:
	var out := [{id = "", label = "None", tex = null}]
	for i in NOISES.size():
		out.append({id = "noise:" + NOISES[i], label = NOISE_LABELS[i], tex = picture("noise:" + NOISES[i])})
	for i in Sprites.NAMES.size():
		out.append({id = "sprite:" + Sprites.NAMES[i], label = Sprites.LABELS[i],
			tex = Sprites.get_texture(Sprites.NAMES[i])})
	return out


func _apply_values() -> void:
	for u: Dictionary in uniforms:
		live_mat.set_shader_parameter(u.name, _uniform_value(values[u.name]))
	live_mat.set_shader_parameter("resolution", preview.size.max(Vector2.ONE))
	live_mat.set_shader_parameter("mouse", mouse_uv)
	live_mat.set_shader_parameter("since_poke", since_poke)


# --- files -------------------------------------------------------------------

func _save_path() -> String:
	return "user://shader_lab_test.json" if testing else "user://shader_lab.json"


func _load_saved() -> void:
	if not FileAccess.file_exists(_save_path()):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_save_path()))
	if data is Dictionary:
		saved = data.get("shaders", [])
		next_number = int(data.get("next", saved.size() + 1))


func _write_saved() -> void:
	var f := FileAccess.open(_save_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({shaders = saved, next = next_number}, "\t"))


func _new_doc(text: String) -> void:
	preset = -1
	saved_index = -1
	title = "Untitled"
	_open_text(text)
	_say("New shader: edit the code, then Save to keep it")


func _open_saved(index: int) -> void:
	if index < 0 or index >= saved.size():
		return
	saved_index = index
	preset = -1
	title = saved[index].name
	_open_text(saved[index].code)


func _save() -> void:
	if saved_index >= 0 and saved_index < saved.size():
		saved[saved_index].code = code.text
	else:
		saved.append({name = "My shader %d" % next_number, code = code.text})
		next_number += 1
		saved_index = saved.size() - 1
		title = saved[saved_index].name
		preset = -1
	loaded_text = code.text
	_write_saved()
	controls_changed.emit()
	_say("Saved %s" % title)


func _delete() -> void:
	if saved_index < 0 or saved_index >= saved.size():
		_say("Only a saved shader can be deleted")
		return
	var gone: String = saved[saved_index].name
	saved.remove_at(saved_index)
	saved_index = -1
	title = "Untitled"
	_write_saved()
	controls_changed.emit()
	_say("Deleted %s (the code is still in the editor)" % gone)


func _copy() -> void:
	if testing:
		clip = code.text
	else:
		DisplayServer.clipboard_set(code.text)
	_say("Copied the shader")


func _paste() -> void:
	var text := clip if testing else DisplayServer.clipboard_get()
	if text.strip_edges() == "":
		_say("The clipboard is empty, or the browser won't share it: paste into the code pane instead")
		return
	preset = -1
	saved_index = -1
	title = "Pasted"
	_open_text(text)


## Sends the shader that is showing (the last one that compiled) to the asset library: the
## .gdshader, and a .material.tres that carries it with the uniform values set here.
func _export(asset_name: String) -> void:
	if not live_mat.shader or live_mat.shader.code == "":
		_say("Nothing compiled to export yet")
		return
	var file := Exporter.slug(asset_name)
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = live_mat.shader.code
	for u: Dictionary in uniforms:
		mat.set_shader_parameter(u.name, _uniform_value(values[u.name]))
	var target := "a CanvasItem (Sprite2D, ColorRect, TextureRect...)" if mode == "canvas_item" \
		else "a MeshInstance3D (material_override, or a surface's material)"
	var use := "# %s shader, for %s\n" % [mode, target]
	use += "var mat := load(\"res://assets/shaders/%s.material.tres\") as ShaderMaterial   # with the values set in the lab\n" % file
	use += "# or from the bare shader: var mat := ShaderMaterial.new(); mat.shader = load(\"res://assets/shaders/%s.gdshader\")\n" % file
	use += ("$Sprite.material = mat" if mode == "canvas_item" else "$Mesh.material_override = mat")
	_say(Exporter.save("shaders", asset_name, {"gdshader": live_mat.shader.code, "material.tres": mat}, [], use,
		"Shader Lab"))


func _say(text: String) -> void:
	note = text
	note_until = Time.get_ticks_msec() + 4000


# --- the preview -------------------------------------------------------------

func _set_grid(on: bool) -> void:
	show_grid = on
	grid.visible = on and mesh_index != 3


func _set_mesh(index: int) -> void:
	mesh_index = index
	mesh.rotation = Vector3.ZERO
	match index:
		0:
			var m := SphereMesh.new()
			m.radius = 1.0
			m.height = 2.0
			m.radial_segments = 96
			m.rings = 48
			mesh.mesh = m
		1:
			var m := BoxMesh.new()
			m.size = Vector3.ONE * 1.6
			m.subdivide_width = 16
			m.subdivide_height = 16
			m.subdivide_depth = 16
			mesh.mesh = m
		2:
			var m := TorusMesh.new()
			m.inner_radius = 0.45
			m.outer_radius = 1.1
			m.rings = 96
			m.ring_segments = 32
			mesh.mesh = m
			mesh.rotation.x = deg_to_rad(65)
		3:
			var m := PlaneMesh.new()
			m.size = Vector2(8, 8)
			m.subdivide_width = 160
			m.subdivide_depth = 160
			mesh.mesh = m
		4:
			var m := CylinderMesh.new()
			m.top_radius = 0.8
			m.bottom_radius = 0.8
			m.height = 2.0
			m.radial_segments = 64
			m.rings = 16
			mesh.mesh = m
	grid.visible = show_grid and index != 3
	if index == 3:
		distance = 9.0
		pitch = -0.5
	else:
		distance = 4.2
		pitch = -0.3
	_place_camera()


func _layout() -> void:
	var bar_h := 40.0
	wide = size.x >= 640.0 and size.x > size.y * 1.15
	toolbar.position = Vector2.ZERO
	toolbar.size = Vector2(size.x, bar_h)
	for i in view_buttons.size():
		view_buttons[i].visible = not wide
		view_buttons[i].set_pressed_no_signal((i == 0) == show_code)
	var body := Rect2(0, bar_h, size.x, maxf(size.y - bar_h, 1.0))
	var code_rect := Rect2()
	preview = Rect2()
	if wide:
		var w := floorf(body.size.x * 0.48)
		code_rect = Rect2(body.position, Vector2(w, body.size.y))
		preview = Rect2(body.position + Vector2(w, 0), Vector2(body.size.x - w, body.size.y))
	elif show_code:
		code_rect = body
	else:
		preview = body
	code_box.visible = code_rect.size.x > 0.0
	# a hidden pane keeps its full size, so the code and error strip keep sensible widths
	if not code_box.visible:
		code_rect = body
	code_box.position = code_rect.position
	code_box.size = code_rect.size
	canvas.position = preview.position
	canvas.size = preview.size
	canvas.visible = mode == "canvas_item" and preview.size.x > 0.0
	var show_3d := mode == "spatial" and preview.size.x > 0.0
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if show_3d else SubViewport.UPDATE_DISABLED
	viewport.size = Vector2i(preview.size.max(Vector2.ONE))
	camera.keep_aspect = Camera3D.KEEP_WIDTH if preview.size.y > preview.size.x else Camera3D.KEEP_HEIGHT
	live_mat.set_shader_parameter("resolution", preview.size.max(Vector2.ONE))
	queue_redraw()


func resize(new_size: Vector2) -> void:
	size = new_size
	_layout()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_BACK)
	if mode == "spatial" and preview.size.x > 0.0:
		draw_texture_rect(viewport.get_texture(), preview, false)


func _process(delta: float) -> void:
	super._process(delta)
	if compile_timer > 0.0:
		compile_timer -= delta
		if compile_timer <= 0.0:
			_compile()
	since_poke += delta
	live_mat.set_shader_parameter("since_poke", since_poke)
	if mode == "spatial" and spin and mesh_index != 3:
		mesh.rotate_y(delta * 0.35)


func touch_down(index: int, pos: Vector2) -> void:
	if not preview.has_point(pos):
		return
	taps[index] = [pos, Time.get_ticks_msec()]
	if mode == "canvas_item":
		_set_mouse(pos)
	else:
		super.touch_down(index, pos)


func touch_move(index: int, pos: Vector2) -> void:
	if not taps.has(index):
		return
	if mode == "canvas_item":
		_set_mouse(pos)
	else:
		super.touch_move(index, pos)


func touch_up(index: int, pos: Vector2) -> void:
	if not taps.has(index):
		return
	var start: Array = taps[index]
	taps.erase(index)
	if pos.distance_to(start[0]) < 12.0 and Time.get_ticks_msec() - int(start[1]) < 350:
		since_poke = 0.0
	if mode != "canvas_item":
		super.touch_up(index, pos)


func _set_mouse(pos: Vector2) -> void:
	mouse_uv = ((pos - preview.position) / preview.size.max(Vector2.ONE)).clamp(Vector2.ZERO, Vector2.ONE)
	live_mat.set_shader_parameter("mouse", mouse_uv)


# --- the code pane -----------------------------------------------------------

func _build_ui() -> void:
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.color = Color.BLACK
	add_child(canvas)

	code_box.add_theme_constant_override("separation", 0)
	add_child(code_box)
	code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	code.syntax_highlighter = _highlighter()
	code.add_theme_font_override("font", mono)
	code.add_theme_font_size_override("font_size", font_size)
	var bg := StyleBoxFlat.new()
	bg.bg_color = C_CODE
	bg.border_color = C_EDGE
	bg.border_width_right = 1
	bg.content_margin_left = 6
	bg.content_margin_top = 4
	code.add_theme_stylebox_override("normal", bg)
	code.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	code.add_theme_stylebox_override("read_only", bg)
	code.add_theme_color_override("font_color", Color("d4d4d8"))
	code.add_theme_color_override("current_line_color", Color(1, 1, 1, 0.04))
	code.add_theme_color_override("line_number_color", Color("5d606a"))
	code.add_theme_color_override("caret_color", C_ACCENT_HI)
	code.add_theme_color_override("selection_color", Color(0.31, 0.52, 0.78, 0.4))
	code.add_theme_color_override("word_highlighted_color", Color(1, 1, 1, 0.08))
	code.add_theme_color_override("brace_mismatch_color", Color("ff8a8a"))
	code.gutters_draw_line_numbers = true
	code.highlight_current_line = true
	code.highlight_all_occurrences = true
	code.indent_automatic = true
	code.auto_brace_completion_enabled = true
	code.auto_brace_completion_highlight_matching = true
	code.minimap_draw = false
	code.scroll_past_end_of_file = true
	code.caret_blink = true
	code.add_comment_delimiter("//", "", true)
	code.add_comment_delimiter("/*", "*/")
	code.text_changed.connect(func() -> void:
		if auto_compile:
			compile_timer = 0.4)
	code_box.add_child(code)

	var strip_style := StyleBoxFlat.new()
	strip_style.bg_color = C_ERROR
	strip_style.border_color = Color("a8474b")
	strip_style.border_width_top = 1
	strip_style.content_margin_left = 10
	strip_style.content_margin_right = 10
	strip_style.content_margin_top = 4
	strip_style.content_margin_bottom = 4
	error_strip.add_theme_stylebox_override("panel", strip_style)
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# two lines at most, clipped, so wrapping never changes the minimum size of the code pane
	error_label.clip_text = true
	error_label.custom_minimum_size.y = 44
	error_label.add_theme_font_size_override("font_size", 17)
	error_label.add_theme_color_override("font_color", Color("ffc4c4"))
	error_strip.add_child(error_label)
	error_strip.hide()
	code_box.add_child(error_strip)

	var bar := StyleBoxFlat.new()
	bar.bg_color = C_FACE_LO
	bar.border_color = C_EDGE
	bar.border_width_bottom = 1
	bar.content_margin_left = 10
	bar.content_margin_right = 6
	bar.content_margin_top = 3
	bar.content_margin_bottom = 3
	toolbar.add_theme_stylebox_override("panel", bar)
	add_child(toolbar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	toolbar.add_child(row)
	var group := ButtonGroup.new()
	for i in 2:
		var b := Button.new()
		b.text = ["Code", "Preview"][i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = (i == 0) == show_code
		b.custom_minimum_size = Vector2(80, 32)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(func() -> void:
			show_code = i == 0
			_layout())
		row.add_child(b)
		view_buttons.append(b)
	mode_label.add_theme_font_size_override("font_size", 17)
	mode_label.add_theme_color_override("font_color", DIM_TEXT)
	mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(mode_label)
	dot_label.add_theme_font_size_override("font_size", 17)
	dot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(dot_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	for spec in [["A-", func() -> void: _set_font_size(font_size - 2)], ["A+", func() -> void: _set_font_size(font_size + 2)],
			["Run", func() -> void: _compile(true)]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(44, 32)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(spec[1])
		row.add_child(b)


func _set_font_size(px: int) -> void:
	font_size = clampi(px, 10, 36)
	code.add_theme_font_size_override("font_size", font_size)


func _highlighter() -> CodeHighlighter:
	var h := CodeHighlighter.new()
	h.number_color = Color("b5cea8")
	h.symbol_color = Color("a8adb8")
	h.function_color = Color("dcdcaa")
	h.member_variable_color = Color("d4d4d8")
	for w in KEYWORDS:
		h.add_keyword_color(w, Color("d18bd8"))
	for w in TYPES:
		h.add_keyword_color(w, Color("6fb3e0"))
	for w in BUILTINS:
		h.add_keyword_color(w, Color("e5a35b"))
	for w in HINTS:
		h.add_keyword_color(w, Color("8fc28a"))
	h.add_color_region("//", "", Color("6a737d"), true)
	h.add_color_region("/*", "*/", Color("6a737d"))
	return h


## Main's _input steps through sims on Left/Right and closes on Escape, and runs before the code
## pane sees a key, so while the code has focus those keys are handled here and marked as used.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed) or not code.has_focus():
		return
	var k := event as InputEventKey
	match k.keycode:
		KEY_LEFT, KEY_RIGHT:
			_move_caret(k.keycode == KEY_RIGHT, k.shift_pressed, k.is_command_or_control_pressed())
		KEY_ESCAPE:
			code.release_focus()
		KEY_S when k.is_command_or_control_pressed():
			_save()
		KEY_ENTER when k.is_command_or_control_pressed():
			_compile(true)
		_:
			return
	get_viewport().set_input_as_handled()


func _move_caret(right: bool, extend: bool, by_word: bool) -> void:
	var line := code.get_caret_line()
	var col := code.get_caret_column()
	if code.has_selection() and not extend:
		# an arrow without shift drops the selection at the side it points to
		if right:
			line = code.get_selection_to_line()
			col = code.get_selection_to_column()
		else:
			line = code.get_selection_from_line()
			col = code.get_selection_from_column()
		code.deselect()
		code.set_caret_line(line)
		code.set_caret_column(col)
		return
	var origin_line := code.get_selection_origin_line() if code.has_selection() else line
	var origin_col := code.get_selection_origin_column() if code.has_selection() else col
	var text := code.get_line(line)
	if right:
		if col >= text.length():
			if line < code.get_line_count() - 1:
				line += 1
				col = 0
		elif by_word:
			while col < text.length() and not _is_word(text[col]):
				col += 1
			while col < text.length() and _is_word(text[col]):
				col += 1
		else:
			col += 1
	else:
		if col <= 0:
			if line > 0:
				line -= 1
				col = code.get_line(line).length()
		elif by_word:
			while col > 0 and not _is_word(text[col - 1]):
				col -= 1
			while col > 0 and _is_word(text[col - 1]):
				col -= 1
		else:
			col -= 1
	code.deselect()
	code.set_caret_line(line)
	code.set_caret_column(col)
	if extend and (origin_line != line or origin_col != col):
		code.select(origin_line, origin_col, line, col)


func _is_word(c: String) -> bool:
	return c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")
