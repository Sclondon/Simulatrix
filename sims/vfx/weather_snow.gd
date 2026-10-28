extends "res://sims/vfx/weather_lab.gd"
## Snow: GameCommon weather's GPU snow (or hail) over the editor grid, with props for it to settle
## on. Flake size, flutter and drift, fall speed, the wind; how fast it lies and builds up on the
## grid and on top of the props, and how fast it melts after.

var overcast := 0.7


func help() -> String:
	return ("GameCommon's snow on the editor grid. Flakes tumble down, flutter side to side and drift on the "
		+ "wind; all of them placed on the GPU in a box round the camera. Hail falls fast as pellets and bounces "
		+ "where it lands, on the grid and on top of the props.\n\n"
		+ "Snow settles on whatever faces up: patchy at first, the flat tops first, then a blanket over the grid "
		+ "lines. Depth sets how deep it lies now; settling is how fast it builds while it snows, melt how fast it "
		+ "goes after (faster by day, and in rain). Clear takes it all away.\n\n"
		+ "Drag to orbit, pinch or wheel to zoom. Export saves this snow as a scene (needs godot/weather).")


func hint() -> String:
	return "Drag to orbit. Watch the snow build on the props; try Kind > Hail."


func export_info() -> Dictionary:
	return {name = "Snow", lab = "Snow", use = "$Ground.material_override = weather.ground_material()   # snow lies on it\nthing.material_override = weather.weathered(false, 1.0, Color.WHITE, false)   # snow on top"}


func setup() -> void:
	rig.hour = 13.0
	rig.cloud_type = WeatherRig.Clouds.STRATUS
	rig.cover = overcast
	rig.base = 900.0
	rig.precip = WeatherRig.Precip.SNOW
	rig.intensity = 0.7
	rig.wind = 2.5
	rig.snow_depth = 0.12
	rig.settle_rate = 1.5
	with_props = true


func controls() -> Array:
	var c: Array = [
		{type = "section", label = "Snow"},
		{type = "choice", label = "Kind", options = ["Snow", "Hail", "None"],
			value = [2, 2, 0, 1][rig.precip], on = func(i: int) -> void:
				rig.precip = [WeatherRig.Precip.SNOW, WeatherRig.Precip.HAIL, WeatherRig.Precip.NONE][i]},
		{type = "slider", label = "Intensity", min = 0.05, max = 1.0, step = 0.05, value = rig.intensity, fmt = "%.2f",
			on = func(v: float) -> void: rig.intensity = v},
		{type = "slider", label = "Flake size", min = 0.2, max = 4.0, step = 0.05, value = rig.flake_size, fmt = "%.2f", unit = "×",
			on = func(v: float) -> void: rig.flake_size = v},
		{type = "slider", label = "Flutter", min = 0.0, max = 4.0, step = 0.05, value = rig.flutter, fmt = "%.2f", unit = "×",
			on = func(v: float) -> void: rig.flutter = v},
		{type = "slider", label = "Fall speed", min = 0.2, max = 3.0, step = 0.05, value = rig.fall_speed, fmt = "%.2f", unit = "×",
			on = func(v: float) -> void: rig.fall_speed = v},
	]
	c.append_array(sprite_controls("Flake sprite", "flake_texture", "Soft dot"))
	c.append_array([
		{type = "section", label = "Wind"},
	])
	c.append_array(wind_controls(20.0))
	c.append_array([
		{type = "section", label = "Lying snow"},
		{type = "slider", label = "Depth", min = 0.0, max = 1.0, step = 0.05, value = rig.snow_depth, fmt = "%.2f",
			on = func(v: float) -> void: rig.snow_depth = v},
		{type = "slider", label = "Settling", min = 0.0, max = 5.0, step = 0.05, value = rig.settle_rate, fmt = "%.2f", unit = "×",
			on = func(v: float) -> void: rig.settle_rate = v},
		{type = "slider", label = "Melt", min = 0.0, max = 5.0, step = 0.05, value = rig.melt, fmt = "%.2f", unit = "×",
			on = func(v: float) -> void: rig.melt = v},
		{type = "toggle", label = "Ground takes it", value = rig.settle, on = func(v: bool) -> void: rig.settle = v},
		{type = "button", label = "Clear", on = func() -> void:
			rig.dry()
			controls_changed.emit()},
		{type = "section", label = "Sky"},
		{type = "slider", label = "Overcast", min = 0.0, max = 1.0, step = 0.05, value = overcast, fmt = "%.2f",
			on = func(v: float) -> void:
				overcast = v
				rig.cover = v},
	])
	c.append_array(time_controls(false))
	c.append_array(quality_controls())
	c.append_array(export_controls())
	return c


func status() -> String:
	var s := ""
	match rig.precip:
		WeatherRig.Precip.SNOW: s = "snow %d%%" % roundi(rig.intensity * 100.0)
		WeatherRig.Precip.HAIL: s = "hail %d%%" % roundi(rig.intensity * 100.0)
		_: s = "melting" if rig.snow_depth > 0.0 else "clear"
	s += " · lying %.0f cm" % (rig.snow_depth * 25.0)
	s += " · wind %.0f m/s from %d°" % [rig.wind, roundi(rig.wind_from)]
	return s + ms()
