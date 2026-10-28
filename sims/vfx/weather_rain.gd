extends "res://sims/vfx/weather_lab.gd"
## Rain: GameCommon weather's GPU rain over the editor grid, with props to get wet. The drops'
## size, streak length and fall speed, the splash crowns, the wind that slants them; on the grid
## (weather_grid.gdshader) the wet darkening, puddles that mirror the sky and ring with drops,
## and how fast it all wets and dries; the overcast over it.

var overcast := 0.75


func help() -> String:
	return ("GameCommon's rain on the editor grid. Drops are streaks along the way they fall (motion blur), placed "
		+ "on the GPU in a box round the camera; drop size thickens them, streak lengthens them, and the wind "
		+ "slants them. Splashes are little crowns where drops land, on the grid and on top of the props.\n\n"
		+ "The grid takes the rain: it darkens and turns glossy, then puddles gather (they mirror the sky and "
		+ "ring with drops). Wet sets how wet it is now; wetting and drying are how fast it changes; puddles is "
		+ "how much of the wet pools. The props darken too. Dry ground clears it all at once.\n\n"
		+ "Overcast is the stratus deck over it, dimming the light.\n\n"
		+ "Drag to orbit, pinch or wheel to zoom. Export saves this rain as a scene (needs godot/weather).")


func hint() -> String:
	return "Drag to orbit. Turn the wind up, or the drops bigger."


func export_info() -> Dictionary:
	return {name = "Rain", lab = "Rain", use = "$Ground.material_override = weather.ground_material()   # wets, puddles\nthing.material_override = weather.weathered(false, 1.0, Color.WHITE, false)   # darkens wet"}


func setup() -> void:
	rig.hour = 14.0
	rig.cloud_type = WeatherRig.Clouds.STRATUS
	rig.cover = overcast
	rig.base = 900.0
	rig.precip = WeatherRig.Precip.RAIN
	rig.intensity = 0.7
	rig.wind = 4.0
	rig.wet = 0.35
	with_props = true


func controls() -> Array:
	var c: Array = [
		{type = "section", label = "Rain"},
		{type = "slider", label = "Intensity", min = 0.05, max = 1.0, step = 0.05, value = rig.intensity, fmt = "%.2f",
			on = func(v: float) -> void: rig.intensity = v},
		{type = "slider", label = "Drop size", min = 0.2, max = 4.0, step = 0.05, value = rig.drop_size, fmt = "%.2f", unit = "×",
			on = func(v: float) -> void: rig.drop_size = v},
		{type = "slider", label = "Streak", min = 0.05, max = 3.0, step = 0.05, value = rig.rain_streak, fmt = "%.2f", unit = "m",
			on = func(v: float) -> void: rig.rain_streak = v},
		{type = "slider", label = "Fall speed", min = 0.2, max = 3.0, step = 0.05, value = rig.fall_speed, fmt = "%.2f", unit = "×",
			on = func(v: float) -> void: rig.fall_speed = v},
		{type = "slider", label = "Splashes", min = 0.0, max = 3.0, step = 0.05, value = rig.splashes, fmt = "%.2f", unit = "×",
			on = func(v: float) -> void: rig.splashes = v},
		{type = "toggle", label = "Raining", value = rig.precip == WeatherRig.Precip.RAIN, on = func(v: bool) -> void:
			rig.precip = WeatherRig.Precip.RAIN if v else WeatherRig.Precip.NONE},
	]
	c.append_array(sprite_controls("Drop sprite", "drop_texture", "Streak"))
	c.append_array(sprite_controls("Splash sprite", "splash_texture", "Crown"))
	c.append_array([
		{type = "section", label = "Wind"},
	])
	c.append_array(wind_controls())
	c.append_array([
		{type = "section", label = "Ground"},
		{type = "slider", label = "Wet", min = 0.0, max = 1.0, step = 0.05, value = rig.wet, fmt = "%.2f",
			on = func(v: float) -> void: rig.wet = v},
		{type = "slider", label = "Puddles", min = 0.0, max = 2.0, step = 0.05, value = rig.puddles, fmt = "%.2f",
			on = func(v: float) -> void: rig.puddles = v},
		{type = "slider", label = "Wetting", min = 0.0, max = 5.0, step = 0.05, value = rig.settle_rate, fmt = "%.2f", unit = "×",
			on = func(v: float) -> void: rig.settle_rate = v},
		{type = "slider", label = "Drying", min = 0.0, max = 5.0, step = 0.05, value = rig.dry_rate, fmt = "%.2f", unit = "×",
			on = func(v: float) -> void: rig.dry_rate = v},
		{type = "toggle", label = "Ground takes it", value = rig.settle, on = func(v: bool) -> void: rig.settle = v},
		{type = "button", label = "Dry ground", on = func() -> void:
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
	var s := "rain %d%%" % roundi(rig.intensity * 100.0) if rig.precip == WeatherRig.Precip.RAIN else "dry spell"
	s += " · wet %d%%" % roundi(rig.wet * 100.0)
	if rig.wet > 0.4 and rig.puddles > 0.0:
		s += " · puddles"
	s += " · wind %.0f m/s from %d°" % [rig.wind, roundi(rig.wind_from)]
	return s + ms()
