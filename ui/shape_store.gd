class_name ShapeStore
extends RefCounted
## The user's own sprites: shapes drawn on the shape pad (ui/shape_pad.gd) or imported images,
## kept as PNGs in user://sprites/ (on the web that is the browser's storage). Every lab's sprite
## picker lists them under Custom. A sprite's id is "user:<name>"; a lab keeps that id in its
## settings and asks texture(id) for what to draw.
##
## Textures are cached and updated in place when a sprite is saved again, so whatever uses one
## (a particle material, a shader uniform) changes at once.

const PREFIX := "user:"
const DIR := "user://sprites"
## The sizes a sprite is kept at (square, so it mipmaps).
const SIZES := [64, 128, 256]

## Set to keep sprites somewhere else (tests).
static var dir_override := ""
static var _cache := {} # name -> ImageTexture
static var _web_callback: Variant = null # the JavaScript callback must outlive the call
static var _web_done := Callable()


static func dir() -> String:
	var d := dir_override if dir_override != "" else DIR
	DirAccess.make_dir_recursive_absolute(d)
	return d


static func is_custom(id: String) -> bool:
	return id.begins_with(PREFIX)


static func id_of(name: String) -> String:
	return PREFIX + name


static func name_of(id: String) -> String:
	return id.trim_prefix(PREFIX)


## The saved sprites' names, newest first.
static func names() -> Array[String]:
	var d := dir()
	var found: Array[String] = []
	for f in DirAccess.get_files_at(d):
		if f.ends_with(".png"):
			found.append(f.get_basename())
	found.sort_custom(func(a: String, b: String) -> bool:
		return FileAccess.get_modified_time("%s/%s.png" % [d, a]) > FileAccess.get_modified_time("%s/%s.png" % [d, b]))
	return found


static func has(name: String) -> bool:
	return FileAccess.file_exists("%s/%s.png" % [dir(), name])


## A sprite's picture (RGBA8), or null.
static func image(name: String) -> Image:
	var path := "%s/%s.png" % [dir(), name]
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


## The texture for a sprite id: a custom one from the store, else whatever `fallback` (a
## Callable taking the id) gives for the lab's own built-in sprites. Null when neither has it.
static func texture(id: String, fallback := Callable()) -> Texture2D:
	if is_custom(id):
		var name := name_of(id)
		if _cache.has(name):
			return _cache[name]
		var img := image(name)
		if img:
			img.generate_mipmaps()
			_cache[name] = ImageTexture.create_from_image(img)
			return _cache[name]
		return null
	if fallback.is_valid():
		return fallback.call(id)
	return null


## Saves a sprite (replacing one of that name). Returns its id.
static func save(name: String, img: Image) -> String:
	name = clean_name(name)
	var copy: Image = img.duplicate()
	copy.clear_mipmaps()
	copy.convert(Image.FORMAT_RGBA8)
	var f := FileAccess.open("%s/%s.png" % [dir(), name], FileAccess.WRITE)
	if f:
		f.store_buffer(copy.save_png_to_buffer())
		f.close()
	copy.generate_mipmaps()
	if _cache.has(name):
		var tex: ImageTexture = _cache[name]
		if Vector2i(tex.get_size()) == copy.get_size():
			tex.update(copy)
		else:
			tex.set_image(copy)
	else:
		_cache[name] = ImageTexture.create_from_image(copy)
	return id_of(name)


static func remove(name: String) -> void:
	DirAccess.remove_absolute("%s/%s.png" % [dir(), name])
	# (the cached texture stays, so anything still drawing it keeps going until it is changed)


## A name for a file: lower case letters, digits and underscores.
static func clean_name(text: String) -> String:
	return Exporter.slug(text)


## A name not yet taken, made from `base` ("leaf", "leaf_2"...).
static func unique_name(base: String) -> String:
	base = clean_name(base)
	if not has(base):
		return base
	var n := 2
	while has("%s_%d" % [base, n]):
		n += 1
	return "%s_%d" % [base, n]


## Sends a sprite to the asset library as kind "sprites" (see sims/exporter.gd).
static func export_to_library(name: String) -> String:
	var img := image(name)
	if img == null:
		return "No sprite called " + name
	var use := "var tex := load(\"res://assets/sprites/%s.png\") as Texture2D\n" % name
	use += "# white with alpha (a mask): tint it with the material's colour, e.g. a particle's albedo_texture"
	return Exporter.save("sprites", name, {"png": img.save_png_to_buffer()}, [], use, "Shape pad")


## The custom sprites among `ids`, as {id: base64 PNG}, to carry inside a lab's JSON.
static func pack(ids: Array) -> Dictionary:
	var out := {}
	for id: Variant in ids:
		if id is String and is_custom(id) and not out.has(id):
			var img := image(name_of(id))
			if img:
				out[id] = Marshalls.raw_to_base64(img.save_png_to_buffer())
	return out


## Saves the sprites a lab's JSON carried (from pack()) that this device doesn't have yet.
static func unpack(packed: Variant) -> void:
	if not packed is Dictionary:
		return
	for id: Variant in packed:
		if not id is String or not is_custom(id) or has(name_of(id)):
			continue
		var img := Image.new()
		if img.load_png_from_buffer(Marshalls.base64_to_raw(str(packed[id]))) == OK:
			save(name_of(id), img)


# --- importing images ------------------------------------------------------------

## Asks for an image file and calls done(image: Image, file_name: String). Locally the native file
## dialog; in a browser a file input (the picture is read as bytes there and decoded here).
## Nothing is called when the user cancels.
static func pick_image(done: Callable) -> void:
	if OS.has_feature("web"):
		_pick_web(done)
		return
	if DisplayServer.get_name() == "headless":
		return
	var start := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	DisplayServer.file_dialog_show("Import an image", start, "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
		PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.svg ; Images"]),
		func(ok: bool, paths: PackedStringArray, _filter: int) -> void:
			if not ok or paths.is_empty():
				return
			var img := decode(FileAccess.get_file_as_bytes(paths[0]), paths[0].get_extension())
			if img:
				done.call(img, paths[0].get_file()))


static func _pick_web(done: Callable) -> void:
	_web_done = done
	if _web_callback == null:
		_web_callback = JavaScriptBridge.create_callback(_on_web_file)
	JavaScriptBridge.eval("""
window.simulatrixPickImage = function (callback) {
	var input = document.createElement('input');
	input.type = 'file';
	input.accept = 'image/png,image/jpeg,image/webp,image/svg+xml,.png,.jpg,.jpeg,.webp,.svg';
	input.style.display = 'none';
	document.body.appendChild(input);
	input.onchange = function () {
		var file = input.files && input.files[0];
		document.body.removeChild(input);
		if (!file) { return; }
		var reader = new FileReader();
		reader.onload = function () {
			var url = String(reader.result);
			callback(file.name, url.substring(url.indexOf(',') + 1));
		};
		reader.readAsDataURL(file);
	};
	input.click();
};
""", true)
	var window: Variant = JavaScriptBridge.get_interface("window")
	if window != null:
		window.simulatrixPickImage(_web_callback)


static func _on_web_file(args: Array) -> void:
	if args.size() < 2 or not _web_done.is_valid():
		return
	var file := str(args[0])
	var img := decode(Marshalls.base64_to_raw(str(args[1])), file.get_extension())
	if img:
		_web_done.call(img, file)


## An image from a file's bytes (PNG, JPEG, WebP or SVG), as RGBA8; null if it isn't one.
static func decode(bytes: PackedByteArray, ext: String) -> Image:
	if bytes.is_empty():
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	match ext.to_lower():
		"png": err = img.load_png_from_buffer(bytes)
		"jpg", "jpeg": err = img.load_jpg_from_buffer(bytes)
		"webp": err = img.load_webp_from_buffer(bytes)
		"svg": err = img.load_svg_from_buffer(bytes, 4.0)
	if err != OK:
		# the extension lied: try each
		for f: Callable in [img.load_png_from_buffer, img.load_jpg_from_buffer, img.load_webp_from_buffer]:
			if f.call(bytes) == OK:
				err = OK
				break
	if err != OK or img.is_empty():
		return null
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	return img


## Which way an imported picture becomes a sprite: keep its colours, take its alpha as a white
## mask, or make a mask from how light (or how dark) it is.
const FROM := ["colour", "alpha", "light", "dark"]
const FROM_LABELS := ["Colour", "Alpha", "Light", "Dark"]


## The best guess for a picture: its alpha if it has any, else dark-on-light (ink on paper) or
## light-on-dark by its mean brightness.
static func guess_from(img: Image) -> String:
	if img.detect_alpha() != Image.ALPHA_NONE:
		return "alpha"
	var small: Image = img.duplicate()
	small.resize(16, 16, Image.INTERPOLATE_BILINEAR)
	var sum := 0.0
	for y in 16:
		for x in 16:
			sum += small.get_pixel(x, y).get_luminance()
	return "dark" if sum / 256.0 > 0.5 else "light"


## An imported picture made into a square sprite `size` across: converted by `from` (see FROM),
## trimmed to what is in it (with a little margin) when `trim`, and fitted in the middle.
static func prepare(src: Image, from: String, trim: bool, size: int) -> Image:
	var img: Image = src.duplicate()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	# work at about twice the final size: a photo is far bigger than a sprite
	var work := size * 2
	var big := maxi(img.get_width(), img.get_height())
	if big > work:
		var k := float(work) / big
		img.resize(maxi(int(img.get_width() * k), 1), maxi(int(img.get_height() * k), 1), Image.INTERPOLATE_BILINEAR)
	if from != "colour":
		var data := img.get_data()
		for i in range(0, data.size(), 4):
			var r := data[i] / 255.0
			var g := data[i + 1] / 255.0
			var b := data[i + 2] / 255.0
			var a := data[i + 3] / 255.0
			var lum := 0.2126 * r + 0.7152 * g + 0.0722 * b
			match from:
				"light": a *= clampf((lum - 0.04) / 0.92, 0.0, 1.0)
				"dark": a *= clampf((0.96 - lum) / 0.92, 0.0, 1.0)
			if a < 0.03:
				a = 0.0
			data[i] = 255
			data[i + 1] = 255
			data[i + 2] = 255
			data[i + 3] = int(a * 255.0)
		img = Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)
	var used := Rect2i(Vector2i.ZERO, img.get_size())
	if trim:
		var r := img.get_used_rect()
		if r.size.x > 0 and r.size.y > 0:
			used = r
	var side := maxi(used.size.x, used.size.y)
	if trim:
		side = int(side * 1.08) + 2 # a little room round it, so the soft edge isn't cut
	var square := Image.create(side, side, false, Image.FORMAT_RGBA8)
	square.fill(Color(1, 1, 1, 0) if from != "colour" else Color(0, 0, 0, 0))
	square.blit_rect(img, used, (Vector2i(side, side) - used.size) / 2)
	square.resize(size, size, Image.INTERPOLATE_LANCZOS if side > size else Image.INTERPOLATE_BILINEAR)
	return square
