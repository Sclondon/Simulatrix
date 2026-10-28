extends "res://sims/vfx/weather_lab.gd"
## Lightning: GameCommon weather's lightning under a storm, over the editor grid. Strike, an auto
## storm and its rate, tap the grid to strike there; the bolt's shape (branching, jaggedness,
## thickness, glow, colour), how long it lasts and its return strokes; cloud-to-ground bolts or
## in-cloud sheet lightning; the flash lighting the grid, the props and the clouds; and the thunder
## as a countdown in the status bar (sound at 343 m/s; no audio).

const KINDS := ["To ground", "In cloud", "Mixed"]
const COLOURS := ["Blue-white", "Violet", "Pink", "Gold", "Green"]
const COLOUR_VALUES := [Color(0.55, 0.6, 1.0), Color(0.68, 0.45, 1.0), Color(1.0, 0.5, 0.82), Color(1.0, 0.78, 0.4), Color(0.5, 1.0, 0.65)]

var kind := 0
var colour := 0
var reach := 600.0
var raining := false


func help() -> String:
	return ("GameCommon's lightning over the editor grid, under a storm. Strike sends a bolt somewhere ahead; in "
		+ "Poke mode, tap the grid to strike right there. Auto storm strikes by itself, as often as the rate says.\n\n"
		+ "A bolt is a jagged line from the cloud base down (midpoint displacement), forking as it goes. Branching "
		+ "is how much it forks, jaggedness how crooked; thickness and glow are its white core and coloured halo. "
		+ "Each strike flickers: return strokes are how many times it comes back to full brightness, duration "
		+ "stretches it all. In cloud is sheet lightning: a crawler flickering along the cloud base and lighting "
		+ "the cloud from inside, with no bolt to the ground.\n\n"
		+ "The flash lights the grid, the props and the clouds (flash light). Count the seconds to the thunder in "
		+ "the status bar (sound travels 343 m/s) to know how far it struck.\n\n"
		+ "Drag to orbit, pinch or wheel to zoom. Export saves this storm as a scene (needs godot/weather).")


func hint() -> String:
	return "Press Strike, or Finger > Poke and tap the grid."


func pokeable() -> bool:
	return true


func export_info() -> Dictionary:
	return {name = "Lightning", lab = "Lightning", use = "weather.strike(target)   # or auto_storm; signal struck(at), thunder_in()"}


func setup() -> void:
	rig.hour = 18.1
	rig.cloud_type = WeatherRig.Clouds.STORM
	rig.cover = 0.8
	rig.base = 650.0
	rig.thickness = 0.9
	rig.storm_at = Vector3(1400, 0, 2600)
	rig.auto_storm = true
	rig.strike_rate = 0.6
	rig.wind = 6.0
	rig.fog = 0.15
	_set_reach(reach)
	with_props = true
	focus = Vector3(0, 6.0, 0)
	distance = 34.0
	yaw = 3.6
	pitch = 0.05


func controls() -> Array:
	var c := look_controls()
	c.append_array([
		{type = "section", label = "Strikes"},
		{type = "button", label = "Strike", on = func() -> void: rig.strike()},
		{type = "choice", label = "Kind", options = KINDS, value = kind, on = func(i: int) -> void:
			kind = i
			rig.in_cloud = [0.0, 1.0, 0.5][i]},
		{type = "toggle", label = "Auto storm", value = rig.auto_storm, on = func(v: bool) -> void: rig.auto_storm = v},
		{type = "slider", label = "Rate", min = 0.0, max = 1.0, step = 0.05, value = rig.strike_rate, fmt = "%.2f",
			on = func(v: float) -> void: rig.strike_rate = v},
		{type = "slider", label = "Distance", min = 100.0, max = 3000.0, step = 50.0, value = reach, fmt = "%.0f", unit = "m",
			on = func(v: float) -> void: _set_reach(v)},
		{type = "section", label = "Bolt"},
		{type = "slider", label = "Branching", min = 0.0, max = 1.0, step = 0.05, value = rig.branching, fmt = "%.2f",
			on = func(v: float) -> void: rig.branching = v},
		{type = "slider", label = "Jaggedness", min = 0.0, max = 0.5, step = 0.01, value = rig.jaggedness, fmt = "%.2f",
			on = func(v: float) -> void: rig.jaggedness = v},
		{type = "slider", label = "Thickness", min = 0.2, max = 4.0, step = 0.05, value = rig.bolt_width, fmt = "%.2f", unit = "×",
			on = func(v: float) -> void: rig.bolt_width = v},
		{type = "slider", label = "Glow", min = 0.0, max = 3.0, step = 0.05, value = rig.bolt_glow, fmt = "%.2f", unit = "×",
			on = func(v: float) -> void: rig.bolt_glow = v},
		{type = "choice", label = "Colour", options = COLOURS, value = colour, on = func(i: int) -> void:
			colour = i
			rig.bolt_color = COLOUR_VALUES[i]},
		{type = "slider", label = "Duration", min = 0.2, max = 4.0, step = 0.05, value = rig.bolt_time, fmt = "%.2f", unit = "×",
			on = func(v: float) -> void: rig.bolt_time = v},
		{type = "slider", label = "Return strokes", min = 1.0, max = 8.0, step = 1.0, value = rig.strokes, fmt = "%.0f",
			on = func(v: float) -> void: rig.strokes = int(v)},
		{type = "slider", label = "Flash light", min = 0.0, max = 3.0, step = 0.05, value = rig.flash_light, fmt = "%.2f", unit = "×",
			on = func(v: float) -> void: rig.flash_light = v},
		{type = "section", label = "Storm"},
		{type = "choice", label = "Clouds", options = ["Storm", "Stratus"], value = 1 if rig.cloud_type == WeatherRig.Clouds.STRATUS else 0,
			on = func(i: int) -> void: rig.cloud_type = WeatherRig.Clouds.STRATUS if i == 1 else WeatherRig.Clouds.STORM},
		{type = "slider", label = "Base", min = 300.0, max = 2500.0, step = 50.0, value = rig.base, fmt = "%.0f", unit = "m",
			on = func(v: float) -> void: rig.base = v},
		{type = "toggle", label = "Rain", value = raining, on = func(v: bool) -> void:
			raining = v
			rig.precip = WeatherRig.Precip.RAIN if v else WeatherRig.Precip.NONE},
	])
	c.append_array(time_controls(false))
	c.append_array(quality_controls())
	c.append_array(export_controls())
	return c


func status() -> String:
	var s := "%d bolts" % rig.bolts
	if rig.bolts > 0:
		s += " · last %.1f km" % rig.thunder_km()
		if rig.thunder_in() > 0.0:
			s += " · thunder in %.1f s" % rig.thunder_in()
		else:
			s += " · thunder heard"
	if rig.auto_storm:
		s += " · auto storm"
	return s + ms()


## Unaimed strikes land between half and one and a half times this far from the camera.
func _set_reach(v: float) -> void:
	reach = v
	rig.strike_range = Vector2(v * 0.5, v * 1.5)


func poke_down(pos: Vector2) -> void:
	var at: Variant = ground(pos)
	if at is Vector3:
		rig.strike(at, kind == 1)
