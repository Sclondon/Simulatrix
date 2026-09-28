extends Sim
## Ripple tank: tap to add wave sources and watch them interfere.

const MAX_SOURCES := 8

var wavelength := 60.0
var frequency := 0.8 # cycles per second
var view := 0 # 0 waves, 1 intensity
var setup := 0 # 0 free sources, 1 double slit
var slit_gap := 140.0
var in_phase := true

var sources: Array[Vector2] = []
var phases: Array[float] = []
var drags := {} # touch index -> source index
var phase_time := 0.0
var tank := ColorRect.new()


func help() -> String:
	return "A ripple tank, like the ones in physics class.\n\nTap to drop a wave source, up to eight. Drag one to move it. Where crests meet crests, the waves add up. Where a crest meets a trough, they cancel and you get a still line.\n\nSwitch View to Brightness to see the time-averaged pattern. Double slit sends a flat wave through two gaps, which is the classic experiment that showed light is a wave."


func hint() -> String:
	return "Tap to add wave sources, drag to move them"


func controls() -> Array:
	return [
		{type = "choice", label = "Setup", options = ["Free", "Double slit"], value = setup,
			on = func(v: int) -> void:
				setup = v
				_apply()},
		{type = "choice", label = "View", options = ["Waves", "Brightness"], value = view,
			on = func(v: int) -> void:
				view = v
				_apply()},
		{type = "slider", label = "Wavelength", min = 20.0, max = 160.0, step = 1.0, value = wavelength, fmt = "%.0f px",
			on = func(v: float) -> void:
				wavelength = v
				_apply()},
		{type = "slider", label = "Frequency", min = 0.0, max = 3.0, step = 0.05, value = frequency, fmt = "%.2f Hz",
			on = func(v: float) -> void: frequency = v},
		{type = "slider", label = "Slit gap", min = 30.0, max = 400.0, step = 2.0, value = slit_gap, fmt = "%.0f px",
			on = func(v: float) -> void:
				slit_gap = v
				_apply()},
		{type = "toggle", label = "In phase", value = in_phase, on = func(v: bool) -> void:
			in_phase = v
			_apply()},
		{type = "button", label = "Two sources", on = func() -> void:
			sources = [size * 0.5 + Vector2(-70, 0), size * 0.5 + Vector2(70, 0)]
			_reset_phases()},
		{type = "button", label = "Clear", on = func() -> void:
			sources.clear()
			_reset_phases()},
	]


func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://sims/waves.gdshader")
	tank.material = mat
	tank.show_behind_parent = true
	tank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tank)
	tank.size = size
	sources = [size * 0.5 + Vector2(-70, 0), size * 0.5 + Vector2(70, 0)]
	_reset_phases()


func resize(new_size: Vector2) -> void:
	var old := size
	size = new_size
	for i in sources.size():
		sources[i] += (size - old) * 0.5
	tank.size = size
	_apply()


func _reset_phases() -> void:
	phases.clear()
	for i in sources.size():
		phases.append(0.0 if in_phase else randf())
	_apply()


func _apply() -> void:
	if phases.size() != sources.size():
		_reset_phases()
		return
	var mat := tank.material as ShaderMaterial
	if not mat:
		return
	var packed: Array[Vector4] = []
	for i in MAX_SOURCES:
		if i < sources.size():
			var ph := 0.0 if in_phase else phases[i]
			packed.append(Vector4(sources[i].x, sources[i].y, ph, 1.0))
		else:
			packed.append(Vector4.ZERO)
	mat.set_shader_parameter("size", size)
	mat.set_shader_parameter("count", sources.size())
	mat.set_shader_parameter("sources", packed)
	mat.set_shader_parameter("wavelength", wavelength)
	mat.set_shader_parameter("mode", view)
	mat.set_shader_parameter("slit", setup)
	mat.set_shader_parameter("barrier_x", _barrier_x())
	mat.set_shader_parameter("slit_gap", slit_gap)
	mat.set_shader_parameter("slit_width", maxf(wavelength * 0.25, 10.0))
	queue_redraw()


func _barrier_x() -> float:
	return size.x * 0.28


func _process(delta: float) -> void:
	phase_time = fmod(phase_time + delta * frequency, 1000.0)
	(tank.material as ShaderMaterial).set_shader_parameter("phase_time", phase_time)


func touch_down(index: int, pos: Vector2) -> void:
	if setup == 1:
		drags[index] = -1 # dragging vertically adjusts the slit gap
		return
	for i in sources.size():
		if sources[i].distance_to(pos) < 40.0 and not drags.values().has(i):
			drags[index] = i
			return
	if sources.size() >= MAX_SOURCES:
		sources.pop_front()
		phases.pop_front()
		for key in drags:
			drags[key] -= 1
	sources.append(pos)
	phases.append(randf())
	drags[index] = sources.size() - 1
	_apply()


func touch_move(index: int, pos: Vector2) -> void:
	if not drags.has(index):
		return
	var i: int = drags[index]
	if setup == 1:
		slit_gap = clampf(absf(pos.y - size.y * 0.5) * 2.0, 30.0, 400.0)
		_apply()
	elif i >= 0 and i < sources.size():
		sources[i] = pos
		_apply()


func touch_up(index: int, _pos: Vector2) -> void:
	drags.erase(index)


func _draw() -> void:
	if setup == 1:
		return
	for i in sources.size():
		var p := sources[i]
		draw_circle(p, 9.0, Color(1, 1, 1, 0.9))
		draw_arc(p, 16.0, 0, TAU, 24, Color(1, 1, 1, 0.5), 2.0, true)
