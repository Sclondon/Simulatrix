extends RefCounted
## Emitter defaults and the ready-made effects. An effect is
## {name, loop, speed, cycle, emitters: [emitter...]}; an emitter is a flat Dictionary of
## the settings below (JSON-safe: colours as hex, curves and gradients as arrays).

const DEFAULT := {
	name = "Emitter", on = true, delay = 0.0, burst = false,
	amount = 64, lifetime = 1.5, life_rand = 0.2, explosive = 0.0, prewarm = true,
	shape = "point", shape_size = 0.2, shape_y = 1.0, ring_inner = 0.0, offset_y = 0.0, pitch = 0.0,
	tilt = 0.0, heading = 0.0, spread = 20.0, speed = 2.0, speed_rand = 0.3, inherit = 0.0, orbit = 0.0, radial = 0.0,
	gravity = 0.0, wind = 0.0, damping = 0.0, swirl = 0.0, radial_accel = 0.0,
	turb = 0.0, turb_scale = 2.0, turb_speed = 0.5,
	attract = 0.0, attract_x = 0.0, attract_y = 1.5, attract_radius = 3.0,
	size = 0.3, size_rand = 0.3, size_curve = [[0, 1], [1, 1]],
	grad = [[0, "ffffffff"], [1, "ffffff00"]], hue_rand = 0.0, intensity = 1.0,
	angle_rand = 360.0, spin = 0.0, spin_rand = 0.0,
	tex = "soft", mode = "billboard", stretch = 4.0, blend = "add", soft = false, lit = false,
	light = 0.0, light_range = 4.0, flicker = 0.0,
	sub = -1, sub_count = 20,
}

const FIRE := [[0, "fff3b0ff"], [0.25, "ffb030ff"], [0.6, "ff4010c0"], [1, "40100000"]]
const FLAME := [[0, "ffe090a0"], [0.2, "ffa030c0"], [0.55, "ff401090"], [1, "40100000"]]
const SMOKE := [[0, "40404000"], [0.15, "505050a0"], [1, "80808000"]]
const SPARK := [[0, "ffffe0ff"], [0.3, "ffc040ff"], [1, "ff400000"]]

const NAMES := ["Campfire", "Smoke", "Sparks", "Explosion", "Magic burst", "Portal", "Rain", "Snow", "Fireflies",
	"Ghost wisps", "Blood splat", "Confetti", "Lightning sparks", "Waterfall spray", "Dust puff", "Spooky candle",
	"Fireworks"]


## An emitter: the defaults with some settings changed.
static func em(over: Dictionary) -> Dictionary:
	var e := DEFAULT.duplicate(true)
	for k in over:
		e[k] = over[k]
	return e


static func effect(name: String) -> Dictionary:
	var fx := {name = name, loop = true, speed = 1.0, cycle = 3.0, view = [5.5, 1.0], emitters = []}
	var list: Array = fx.emitters
	match name:
		"Campfire":
			fx.view = [4.2, 0.9]
			list.append(em({name = "Flames", amount = 44, lifetime = 0.9, shape = "disc", shape_size = 0.35,
				spread = 8.0, speed = 1.1, gravity = 1.6, turb = 0.25, turb_scale = 1.5, turb_speed = 1.0,
				size = 0.55, size_curve = [[0, 0.35], [0.25, 1], [1, 0.1]], grad = FLAME, tex = "flame",
				intensity = 1.1, angle_rand = 16.0, light = 2.5, light_range = 7.0, flicker = 0.5}))
			list.append(em({name = "Embers", amount = 28, lifetime = 2.2, life_rand = 0.5, shape = "disc", shape_size = 0.3,
				spread = 25.0, speed = 1.6, speed_rand = 0.5, gravity = 0.5, turb = 0.5, turb_scale = 1.0,
				size = 0.05, grad = [[0, "ffd070ff"], [0.7, "ff6020ff"], [1, "ff200000"]], tex = "hard", intensity = 2.5}))
			list.append(em({name = "Smoke", amount = 26, lifetime = 4.0, shape = "disc", shape_size = 0.3, offset_y = 0.8,
				spread = 10.0, speed = 0.7, gravity = 0.25, wind = 0.3, turb = 0.3, turb_scale = 3.0,
				size = 1.8, size_curve = [[0, 0.25], [1, 1]], grad = [[0, "30303000"], [0.15, "404040a0"], [1, "80808000"]],
				tex = "smoke", blend = "mix", soft = true, spin = 20.0, spin_rand = 20.0}))
		"Smoke":
			fx.view = [7.0, 1.8]
			list.append(em({name = "Column", amount = 60, lifetime = 5.0, shape = "disc", shape_size = 0.4,
				spread = 12.0, speed = 1.0, gravity = 0.3, wind = 0.45, turb = 0.35, turb_scale = 3.0,
				size = 2.6, size_curve = [[0, 0.2], [1, 1]],
				grad = [[0, "2a2a2a00"], [0.1, "343434d0"], [0.6, "5e5e5e80"], [1, "8a8a8a00"]],
				tex = "smoke", blend = "mix", soft = true, spin = 15.0, spin_rand = 15.0}))
			list.append(em({name = "Wisps", amount = 20, lifetime = 3.0, shape = "disc", shape_size = 0.5,
				spread = 30.0, speed = 0.8, gravity = 0.4, wind = 0.45, turb = 0.6, turb_scale = 1.2,
				size = 1.0, size_curve = [[0, 0.3], [1, 1]], grad = [[0, "60606000"], [0.3, "70707050"], [1, "90909000"]],
				tex = "smoke", blend = "mix", soft = true, spin = 30.0}))
		"Sparks":
			list.append(em({name = "Sparks", amount = 140, lifetime = 0.9, life_rand = 0.5, offset_y = 1.0, tilt = 60.0,
				spread = 25.0, speed = 7.0, speed_rand = 0.5, gravity = -9.8, damping = 0.5, size = 0.06,
				mode = "stretch", stretch = 6.0, tex = "spark", grad = SPARK, intensity = 3.0,
				light = 1.0, light_range = 3.0, flicker = 0.8}))
			list.append(em({name = "Hot spot", amount = 6, lifetime = 0.2, offset_y = 1.0, speed = 0.0, size = 0.6,
				grad = [[0, "fff0b0ff"], [1, "ff902000"]], intensity = 1.5}))
		"Explosion":
			fx.view = [8.0, 1.5]
			fx.cycle = 3.5
			list.append(em({name = "Flash", burst = true, amount = 2, explosive = 1.0, lifetime = 0.3, offset_y = 0.6,
				speed = 0.0, size = 4.0, size_rand = 0.0, size_curve = [[0, 0.3], [0.3, 1], [1, 0.8]],
				grad = [[0, "ffffffff"], [1, "ffd08000"]], intensity = 2.0, light = 6.0, light_range = 12.0}))
			list.append(em({name = "Fireball", burst = true, amount = 40, explosive = 1.0, lifetime = 1.1, offset_y = 0.6,
				shape = "sphere", shape_size = 0.4, spread = 180.0, speed = 3.0, speed_rand = 0.6, damping = 4.0,
				gravity = 1.2, size = 1.5, size_curve = [[0, 0.3], [0.2, 1], [1, 0.6]],
				grad = [[0, "fff0c0ff"], [0.3, "ff9020ff"], [0.7, "a02000a0"], [1, "20000000"]], tex = "smoke",
				intensity = 1.6, spin = 40.0, spin_rand = 30.0}))
			list.append(em({name = "Smoke", burst = true, delay = 0.35, amount = 30, explosive = 0.8, lifetime = 3.2,
				offset_y = 0.7, shape = "sphere", shape_size = 0.6, spread = 180.0, speed = 1.8, damping = 1.5,
				gravity = 0.5, size = 2.4, size_curve = [[0, 0.4], [1, 1]], grad = [[0, "20202000"], [0.25, "302a26b0"], [1, "60606000"]],
				tex = "smoke", blend = "mix", soft = true, spin = 20.0, spin_rand = 20.0}))
			list.append(em({name = "Debris", burst = true, amount = 60, explosive = 1.0, lifetime = 1.6, life_rand = 0.4,
				offset_y = 0.5, spread = 70.0, speed = 9.0, speed_rand = 0.6, gravity = -9.8, size = 0.07, mode = "stretch",
				stretch = 5.0, tex = "spark", grad = SPARK, intensity = 3.0}))
			list.append(em({name = "Shockwave", burst = true, amount = 1, explosive = 1.0, lifetime = 0.6, offset_y = 0.05,
				speed = 0.0, size = 7.0, size_rand = 0.0, size_curve = [[0, 0.05], [1, 1]], angle_rand = 0.0,
				grad = [[0, "ffe0a0c0"], [1, "ff804000"]], tex = "ring", mode = "flat"}))
		"Magic burst":
			fx.cycle = 2.4
			list.append(em({name = "Stars", burst = true, amount = 60, explosive = 1.0, lifetime = 1.5, life_rand = 0.4,
				offset_y = 1.2, shape = "sphere", shape_size = 0.1, spread = 180.0, speed = 4.0, speed_rand = 0.5,
				damping = 3.5, gravity = -0.6, size = 0.22, size_curve = [[0, 1], [0.6, 0.8], [1, 0]], tex = "star",
				spin = 180.0, spin_rand = 120.0, grad = [[0, "ffffffff"], [0.4, "c080ffff"], [1, "4040ff00"]],
				hue_rand = 0.12, intensity = 2.0}))
			list.append(em({name = "Glitter", burst = true, delay = 0.1, amount = 90, explosive = 0.7, lifetime = 1.8,
				life_rand = 0.5, offset_y = 1.2, shape = "sphere", shape_size = 1.2, spread = 180.0, speed = 0.3,
				turb = 0.5, turb_scale = 1.0, size = 0.06, tex = "hard",
				grad = [[0, "ffffff00"], [0.2, "a0f0ffff"], [1, "6060ff00"]], intensity = 2.5}))
			list.append(em({name = "Ring", burst = true, amount = 1, explosive = 1.0, lifetime = 0.7, offset_y = 0.03,
				speed = 0.0, size = 4.0, size_rand = 0.0, size_curve = [[0, 0.1], [1, 1]], angle_rand = 0.0, tex = "ring",
				mode = "flat", grad = [[0, "d0a0ffff"], [1, "6040ff00"]], intensity = 1.6}))
			list.append(em({name = "Core", burst = true, amount = 2, explosive = 1.0, lifetime = 0.5, offset_y = 1.2,
				speed = 0.0, size = 2.2, size_rand = 0.0, size_curve = [[0, 0.2], [0.2, 1], [1, 0]],
				grad = [[0, "ffffffff"], [1, "a060ff00"]], intensity = 1.5, light = 3.0, light_range = 6.0}))
		"Portal":
			fx.view = [5.5, 1.4]
			list.append(em({name = "Rim", amount = 160, lifetime = 1.6, shape = "ring", shape_size = 1.2, ring_inner = 0.92,
				shape_y = 0.0, offset_y = 1.4, pitch = 90.0, spread = 180.0, speed = 0.15, orbit = 0.35, turb = 0.15,
				size = 0.16, size_curve = [[0, 0], [0.2, 1], [1, 0]], grad = [[0, "a0f0ffff"], [0.5, "8060ffff"], [1, "ff40c000"]],
				intensity = 2.0, light = 2.0, light_range = 5.0, flicker = 0.2}))
			list.append(em({name = "Swirl", amount = 120, lifetime = 1.4, shape = "ring", shape_size = 1.1, ring_inner = 0.3,
				shape_y = 0.0, offset_y = 1.4, pitch = 90.0, spread = 180.0, speed = 0.05, orbit = 0.6, radial = -0.6,
				size = 0.1, size_curve = [[0, 1], [1, 0]], tex = "spark", grad = [[0, "6080ff00"], [0.3, "60c0ffff"], [1, "ffffff00"]],
				intensity = 1.8}))
			list.append(em({name = "Void", amount = 6, lifetime = 1.2, offset_y = 1.4, pitch = 90.0, speed = 0.0, size = 2.3,
				size_rand = 0.1, angle_rand = 360.0, spin = 60.0, tex = "smoke", mode = "flat", blend = "mix",
				grad = [[0, "10002000"], [0.3, "100830e0"], [0.7, "100830e0"], [1, "10002000"]]}))
			list.append(em({name = "Motes", amount = 30, lifetime = 2.5, shape = "sphere", shape_size = 1.6, offset_y = 1.4,
				spread = 180.0, speed = 0.2, radial_accel = -1.0, turb = 0.4, size = 0.05, tex = "hard",
				grad = [[0, "c0a0ff00"], [0.3, "c0a0ffff"], [1, "ffffff00"]], intensity = 2.0}))
		"Rain":
			fx.view = [8.0, 1.5]
			list.append(em({name = "Drops", amount = 420, lifetime = 0.8, life_rand = 0.1, shape = "box", shape_size = 3.5,
				shape_y = 0.01, offset_y = 6.0, tilt = 180.0, spread = 2.0, speed = 14.0, speed_rand = 0.1, gravity = -5.0,
				wind = 1.0, size = 0.035, size_rand = 0.2, mode = "stretch", stretch = 12.0, tex = "drop",
				grad = [[0, "d0e4ffd0"], [1, "c0d8ffa0"]], intensity = 1.4, blend = "add"}))
			list.append(em({name = "Splashes", amount = 160, lifetime = 0.3, life_rand = 0.3, shape = "box", shape_size = 3.5,
				shape_y = 0.0, offset_y = 0.02, spread = 60.0, speed = 1.2, speed_rand = 0.5, gravity = -6.0, size = 0.05,
				tex = "hard", grad = [[0, "e0f0ffc0"], [1, "e0f0ff00"]], blend = "add"}))
			list.append(em({name = "Ripples", amount = 70, lifetime = 0.5, shape = "box", shape_size = 3.5, shape_y = 0.0,
				offset_y = 0.01, speed = 0.0, size = 0.35, size_rand = 0.4, size_curve = [[0, 0.1], [1, 1]], angle_rand = 0.0,
				tex = "ring", mode = "flat", grad = [[0, "d0e8ff90"], [1, "d0e8ff00"]]}))
		"Snow":
			fx.view = [8.0, 1.6]
			list.append(em({name = "Flakes", amount = 320, lifetime = 7.0, shape = "box", shape_size = 3.5, shape_y = 0.01,
				offset_y = 4.5, tilt = 180.0, spread = 10.0, speed = 0.6, gravity = -0.35, turb = 0.4, turb_scale = 2.0,
				size = 0.09, size_rand = 0.5, tex = "flake", spin = 60.0, spin_rand = 60.0,
				grad = [[0, "ffffff00"], [0.08, "ffffffff"], [0.9, "ffffffff"], [1, "ffffff00"]], blend = "mix"}))
			list.append(em({name = "Near flakes", amount = 60, lifetime = 6.0, shape = "box", shape_size = 3.0, shape_y = 0.01,
				offset_y = 4.5, tilt = 180.0, spread = 10.0, speed = 0.8, gravity = -0.4, turb = 0.5, turb_scale = 1.5,
				size = 0.16, size_rand = 0.4, tex = "soft",
				grad = [[0, "ffffff00"], [0.1, "ffffffe0"], [0.9, "ffffffe0"], [1, "ffffff00"]], blend = "mix"}))
		"Fireflies":
			fx.view = [5.0, 1.0]
			var blink := [[0, "c0ff4000"], [0.15, "d8ff60ff"], [0.3, "60a02000"], [0.55, "60a02000"], [0.7, "d8ff60ff"],
				[0.85, "60a02000"], [1, "c0ff4000"]]
			list.append(em({name = "Fireflies", amount = 40, lifetime = 6.0, life_rand = 0.4, shape = "box", shape_size = 2.5,
				shape_y = 0.3, offset_y = 1.0, spread = 180.0, speed = 0.2, turb = 0.6, turb_scale = 1.5, turb_speed = 0.3,
				size = 0.09, size_rand = 0.2, grad = blink, intensity = 4.0}))
			list.append(em({name = "Glow", amount = 40, lifetime = 6.0, life_rand = 0.4, shape = "box", shape_size = 2.5,
				shape_y = 0.3, offset_y = 1.0, spread = 180.0, speed = 0.2, turb = 0.6, turb_scale = 1.5, turb_speed = 0.3,
				size = 0.5, size_rand = 0.2, grad = [[0, "80c02000"], [0.2, "80c02060"], [0.4, "80c02000"], [0.6, "80c02060"],
				[1, "80c02000"]], intensity = 1.8, light = 0.6, light_range = 4.0, flicker = 0.4}))
		"Ghost wisps":
			list.append(em({name = "Wisps", amount = 40, lifetime = 4.0, shape = "ring", shape_size = 1.2, ring_inner = 0.6,
				shape_y = 0.0, offset_y = 0.3, spread = 30.0, speed = 0.4, gravity = 0.3, orbit = 0.12, turb = 0.5,
				size = 1.0, size_curve = [[0, 0], [0.3, 1], [1, 0.2]], grad = [[0, "80fff000"], [0.3, "a0ffe870"], [1, "4080ff00"]],
				tex = "smoke", intensity = 1.2, spin = 30.0, spin_rand = 20.0}))
			list.append(em({name = "Trails", amount = 60, lifetime = 2.5, shape = "ring", shape_size = 1.2, ring_inner = 0.8,
				shape_y = 0.0, offset_y = 0.3, spread = 20.0, speed = 0.6, gravity = 0.5, orbit = 0.15, turb = 0.3,
				size = 0.06, mode = "stretch", stretch = 5.0, tex = "spark", grad = [[0, "c0fff000"], [0.3, "c0fff0c0"], [1, "60a0ff00"]],
				intensity = 1.6}))
			list.append(em({name = "Haze", amount = 8, lifetime = 5.0, shape = "disc", shape_size = 1.0, offset_y = 0.05,
				speed = 0.05, size = 3.0, size_rand = 0.3, mode = "flat", tex = "smoke", spin = 10.0,
				grad = [[0, "40a09000"], [0.5, "40a09040"], [1, "40a09000"]], light = 1.0, light_range = 5.0}))
		"Blood splat":
			fx.cycle = 2.6
			list.append(em({name = "Droplets", burst = true, amount = 70, explosive = 1.0, lifetime = 1.2, life_rand = 0.3,
				offset_y = 1.3, tilt = 60.0, heading = 0.0, spread = 50.0, speed = 4.0, speed_rand = 0.6, gravity = -9.8,
				size = 0.07, mode = "stretch", stretch = 3.0, tex = "hard", grad = [[0, "b00010ff"], [1, "600008ff"]], blend = "mix"}))
			list.append(em({name = "Mist", burst = true, amount = 20, explosive = 1.0, lifetime = 0.6, offset_y = 1.3, tilt = 60.0,
				spread = 40.0, speed = 2.0, damping = 3.0, size = 0.6, size_curve = [[0, 0.4], [1, 1]], tex = "smoke",
				grad = [[0, "a0001090"], [1, "a0001000"]], blend = "mix"}))
			list.append(em({name = "Pools", burst = true, delay = 0.35, amount = 16, explosive = 1.0, lifetime = 2.2,
				shape = "disc", shape_size = 1.2, offset_y = 0.02, speed = 0.0, size = 0.5, size_rand = 0.6,
				size_curve = [[0, 0.3], [0.1, 1], [1, 1]], grad = [[0, "8a0010ff"], [0.8, "5a0008ff"], [1, "40000400"]],
				tex = "smoke", mode = "flat", blend = "mix"}))
		"Confetti":
			fx.view = [9.0, 2.2]
			fx.cycle = 4.0
			list.append(em({name = "Confetti", burst = true, amount = 160, explosive = 0.9, lifetime = 3.6, life_rand = 0.3,
				spread = 35.0, speed = 9.0, speed_rand = 0.4, gravity = -3.0, damping = 2.5, turb = 0.3, size = 0.1,
				size_rand = 0.3, tex = "square", hue_rand = 0.5, grad = [[0, "ff4060ff"], [0.85, "ff4060ff"], [1, "ff406000"]],
				blend = "mix", spin = 400.0, spin_rand = 300.0}))
			list.append(em({name = "Streamers", burst = true, amount = 24, explosive = 0.9, lifetime = 3.6, spread = 30.0,
				speed = 8.0, speed_rand = 0.3, gravity = -2.0, damping = 2.0, turb = 0.4, size = 0.14, mode = "stretch",
				stretch = 4.0, tex = "square", hue_rand = 0.5, grad = [[0, "40c0ffff"], [0.85, "40c0ffff"], [1, "40c0ff00"]],
				blend = "mix"}))
		"Lightning sparks":
			list.append(em({name = "Arcs", amount = 50, lifetime = 0.25, explosive = 0.8, offset_y = 1.0, shape = "shell",
				shape_size = 0.3, spread = 180.0, speed = 5.0, speed_rand = 0.7, damping = 6.0, size = 0.05, mode = "stretch",
				stretch = 8.0, tex = "spark", grad = [[0, "ffffffff"], [0.3, "a0d0ffff"], [1, "4060ff00"]], intensity = 3.0,
				light = 2.0, light_range = 5.0, flicker = 1.0}))
			list.append(em({name = "Glow", amount = 6, lifetime = 0.12, explosive = 0.5, offset_y = 1.0, speed = 0.0, size = 0.9,
				size_rand = 0.5, grad = [[0, "c0e0ffff"], [1, "4060ff00"]], intensity = 1.6}))
			list.append(em({name = "Crackle", amount = 14, lifetime = 0.15, explosive = 0.6, offset_y = 1.0, shape = "sphere",
				shape_size = 0.6, speed = 0.0, size = 0.3, size_rand = 0.5, tex = "star", grad = [[0, "ffffffff"], [1, "80b0ff00"]],
				intensity = 2.0}))
		"Waterfall spray":
			fx.view = [6.5, 1.3]
			list.append(em({name = "Sheet", amount = 320, lifetime = 0.9, shape = "line", shape_size = 1.2, offset_y = 2.6,
				tilt = 95.0, heading = 90.0, spread = 4.0, speed = 2.0, speed_rand = 0.15, gravity = -9.8, size = 0.12,
				mode = "stretch", stretch = 3.0, tex = "soft", grad = [[0, "e0f4ffc0"], [1, "b0d8ff80"]], blend = "mix"}))
			list.append(em({name = "Mist", amount = 50, lifetime = 2.5, shape = "box", shape_size = 1.2, shape_y = 0.1,
				offset_y = 0.3, spread = 80.0, speed = 1.0, gravity = 0.2, turb = 0.3, size = 1.5, size_curve = [[0, 0.3], [1, 1]],
				tex = "smoke", grad = [[0, "ffffff00"], [0.2, "ffffff60"], [1, "ffffff00"]], blend = "mix", soft = true, spin = 20.0}))
			list.append(em({name = "Droplets", amount = 90, lifetime = 0.8, shape = "box", shape_size = 1.2, shape_y = 0.1,
				offset_y = 0.2, spread = 60.0, speed = 3.0, speed_rand = 0.5, gravity = -9.8, size = 0.04, tex = "hard",
				grad = [[0, "ffffffe0"], [1, "c0e0ff00"]]}))
		"Dust puff":
			fx.cycle = 2.0
			list.append(em({name = "Dust", burst = true, amount = 24, explosive = 1.0, lifetime = 1.6, shape = "disc",
				shape_size = 0.3, offset_y = 0.1, spread = 15.0, speed = 0.3, radial = 2.5, damping = 3.0, size = 0.9,
				size_curve = [[0, 0.3], [1, 1]], grad = [[0, "b09a7a00"], [0.1, "b09a7ac0"], [1, "c0aa8a00"]], tex = "smoke",
				blend = "mix", soft = true, spin = 20.0, spin_rand = 20.0}))
			list.append(em({name = "Pebbles", burst = true, amount = 10, explosive = 1.0, lifetime = 0.7, offset_y = 0.05,
				tilt = 30.0, spread = 40.0, speed = 3.0, gravity = -9.8, size = 0.05, tex = "square",
				grad = [[0, "6a5038ff"], [1, "6a5038ff"]], blend = "mix", spin = 300.0}))
		"Spooky candle":
			fx.view = [2.6, 1.1]
			list.append(em({name = "Flame", amount = 18, lifetime = 0.5, offset_y = 1.0, spread = 6.0, speed = 0.25,
				gravity = 0.6, size = 0.24, size_rand = 0.15, size_curve = [[0, 0.5], [0.3, 1], [1, 0.2]],
				grad = [[0, "c0ffd0ff"], [0.4, "40ff90ff"], [1, "1040a000"]], tex = "flame", angle_rand = 10.0,
				intensity = 1.6, light = 1.4, light_range = 4.0, flicker = 0.6}))
			list.append(em({name = "Wisp", amount = 22, lifetime = 2.5, offset_y = 1.15, spread = 10.0, speed = 0.3,
				gravity = 0.3, turb = 0.5, turb_scale = 1.0, size = 0.4, size_curve = [[0, 0.2], [1, 1]],
				grad = [[0, "60ff9000"], [0.2, "80a0ff60"], [1, "8040ff00"]], tex = "smoke", spin = 40.0}))
			list.append(em({name = "Motes", amount = 16, lifetime = 3.0, shape = "sphere", shape_size = 0.6, offset_y = 1.2,
				spread = 180.0, speed = 0.1, turb = 0.5, size = 0.04, tex = "hard",
				grad = [[0, "80ffa000"], [0.5, "80ffa0ff"], [1, "80ffa000"]], intensity = 2.0}))
		"Fireworks":
			fx.view = [14.0, 4.5]
			list.append(em({name = "Rockets", amount = 4, lifetime = 1.3, life_rand = 0.25, shape = "disc", shape_size = 0.8,
				spread = 12.0, speed = 11.0, speed_rand = 0.15, gravity = -6.0, size = 0.2, size_rand = 0.0,
				grad = [[0, "fff0c0ff"], [1, "ffa040ff"]], intensity = 2.0, sub = 1, sub_count = 70}))
			list.append(em({name = "Burst", amount = 70, explosive = 1.0, lifetime = 1.6, life_rand = 0.3, spread = 180.0,
				speed = 5.0, speed_rand = 0.2, damping = 1.5, gravity = -2.0, size = 0.08, mode = "stretch", stretch = 3.0,
				tex = "spark", hue_rand = 0.5, grad = [[0, "ffffffff"], [0.2, "ff60c0ff"], [1, "ff206000"]], intensity = 3.0}))
	return fx
