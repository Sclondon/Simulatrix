extends RefCounted
## The particle sprites, drawn in code: white shapes in the alpha channel, so the
## particle colour tints them. 64 px, mipmapped. get_texture(name) caches each one.

const NAMES := ["soft", "hard", "spark", "smoke", "flame", "star", "ring", "drop", "flake", "leaf", "square"]
const LABELS := ["Soft", "Dot", "Spark", "Smoke", "Flame", "Star", "Ring", "Drop", "Flake", "Leaf", "Square"]
const SIZE := 64

static var _cache := {}


static func get_texture(name: String) -> Texture2D:
	if not _cache.has(name):
		var img := _draw(name)
		img.generate_mipmaps()
		_cache[name] = ImageTexture.create_from_image(img)
	return _cache[name]


static func _draw(name: String) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.09
	noise.fractal_octaves = 3
	for y in SIZE:
		for x in SIZE:
			# p runs -1..1 across the sprite, y up
			var p := Vector2((x + 0.5) / SIZE * 2.0 - 1.0, 1.0 - (y + 0.5) / SIZE * 2.0)
			var r := p.length()
			var a := 0.0
			match name:
				"soft":
					a = exp(-r * r * 5.0) * smoothstep(1.0, 0.8, r)
				"hard":
					a = clampf((0.8 - r) * SIZE * 0.5, 0.0, 1.0)
				"spark":
					# a streak along y with a hot middle
					a = exp(-p.x * p.x * 22.0) * smoothstep(1.0, 0.1, absf(p.y))
					a = maxf(a, exp(-r * r * 30.0))
				"smoke":
					var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
					var edge := 0.75 + (n - 0.5) * 0.5
					a = smoothstep(edge, edge - 0.45, r) * (0.55 + 0.45 * n)
				"flame":
					# a teardrop: round below, drawn up to a point
					var t := (p.y + 1.0) * 0.5
					var w := 0.5 * pow(1.0 - t, 0.75) * sqrt(smoothstep(0.0, 0.3, t)) + 0.001
					a = exp(-pow(p.x / w, 2.0) * 2.0) * smoothstep(0.98, 0.7, t) * smoothstep(0.0, 0.15, t)
				"star":
					var arms := exp(-absf(p.x) * 18.0) * smoothstep(1.0, 0.0, absf(p.y))
					arms = maxf(arms, exp(-absf(p.y) * 18.0) * smoothstep(1.0, 0.0, absf(p.x)))
					a = maxf(arms, exp(-r * r * 14.0))
				"ring":
					a = exp(-pow((r - 0.75) * 9.0, 2.0)) + exp(-pow((r - 0.75) * 4.0, 2.0)) * 0.25
				"drop":
					a = exp(-p.x * p.x * 120.0) * smoothstep(1.0, 0.6, absf(p.y))
				"flake":
					var ang := fposmod(atan2(p.y, p.x), PI / 3.0) - PI / 6.0
					var arm := Vector2(cos(ang), sin(ang)) * r
					a = exp(-arm.y * arm.y * 300.0) * smoothstep(0.95, 0.75, r)
					# little side branches
					var b := absf(arm.y) - absf(arm.x - 0.55) * 0.7
					a = maxf(a, exp(-b * b * 400.0) * smoothstep(0.85, 0.6, r) * float(arm.x > 0.3))
					a = maxf(a, smoothstep(0.18, 0.1, r))
				"leaf":
					# an almond with a midrib, tipped
					var w := (1.0 - p.y * p.y) * 0.5
					a = clampf((w - absf(p.x)) * SIZE * 0.4, 0.0, 1.0) * float(absf(p.y) < 0.95)
					a *= 1.0 - exp(-p.x * p.x * 900.0) * 0.5
				"square":
					a = float(absf(p.x) < 0.8 and absf(p.y) < 0.8)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	return img
