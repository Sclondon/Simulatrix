extends SceneTree
## The shape pad end to end, at a phone's size: opens the Particle Editor, presses + Draw on its
## Sprite picker, draws half a leaf on the pad with touches sent through the real input (Mirror
## makes the whole leaf), checks the touches went to the pad and not to the sim or the panel,
## saves it, checks the emitter now draws it, imports a picture (ink on paper) as a mask, then
## exports the effect into a scratch library and sends it to a fresh project there. Then run the
## check that project holds, which loads the effect in it:
## godot --audio-driver Dummy --path . -s tests/shape_pad_check.gd -- --root=C:/tmp/lib [--shots=C:/tmp/shots]
## godot --headless --audio-driver Dummy --path C:/tmp/lib/fresh -s check_shape.gd

var main: Control
var lib := ""
var shots := ""
var failures := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--root="):
			lib = a.trim_prefix("--root=")
		elif a.begins_with("--shots="):
			shots = a.trim_prefix("--shots=")
	if lib == "":
		lib = ProjectSettings.globalize_path("user://shape_pad_check")
	Exporter.root_override = lib
	ShapeStore.dir_override = lib + "/my_sprites" # not the user's own sprites
	# start clean: no sprites or sent effect from an earlier run
	for d in [lib + "/my_sprites", lib + "/fresh/assets/effects", lib + "/effects"]:
		for file in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d + "/" + file)
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)
	DisplayServer.window_set_size(Vector2i(390, 844))
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		failures += 1


func _snap(name: String) -> void:
	if shots == "":
		return
	await RenderingServer.frame_post_draw
	var file := "%s/%s.png" % [shots, name]
	root.get_texture().get_image().save_png(file)
	print("saved ", file)


func _touch(pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.position = root.get_final_transform() * pos
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.position = root.get_final_transform() * pos
	e.relative = root.get_final_transform().basis_xform(rel)
	Input.parse_input_event(e)


func _find(node: Node, test: Callable) -> Node:
	for c in node.get_children():
		if test.call(c):
			return c
		var found := _find(c, test)
		if found:
			return found
	return null


func _run() -> void:
	await _frames(5)
	for i in main.SIMS.size():
		if main.SIMS[i].title == "Particle Editor":
			main.open_sim(i)
	await _frames(30)
	var sim: Sim = main.sim
	var picker: Node = _find(main.panel_box, func(n: Node) -> bool: return n.has_method("draw_new"))
	_check(picker != null, "the Particle Editor's Renderer has a sprite picker")
	if picker == null:
		quit(1)
		return
	var editor: Node = picker.draw_new()
	await _frames(10)
	var pad: ShapePad = editor.pad
	_check(pad.is_visible_in_tree() and pad.get_global_rect().size.x > 300.0,
		"+ Draw opens the pad big on a phone (%d px across)" % int(pad.get_global_rect().size.x))
	pad.tool = "shape"
	pad.mirror = true
	pad.feather = 1.0

	# half a leaf, the right side: from the tip down round the edge to the stem, up the middle
	var half := PackedVector2Array()
	for k in 25:
		var t := k / 24.0
		var y := lerpf(10.0, 118.0, t)
		half.append(Vector2(64.0 + sin(t * PI) * 40.0 * (1.0 - t * 0.3), y))
	for k in 6:
		half.append(Vector2(64.0, lerpf(112.0, 16.0, k / 5.0)))
	var scroll_before: int = main.panel_scroll.scroll_vertical
	var poke_root: Vector3 = sim.effect_root.position
	var to_global := func(c: Vector2) -> Vector2:
		return pad.get_global_transform() * pad.to_screen(c)
	var last: Vector2 = to_global.call(half[0])
	_touch(last, true)
	await _frames(2)
	var touched_sim: bool = not main.active.is_empty()
	for k in range(1, half.size()):
		var p: Vector2 = to_global.call(half[k])
		_drag(p, p - last)
		last = p
		await _frames(1)
		touched_sim = touched_sim or not main.active.is_empty()
	_touch(last, false)
	await _frames(4)
	var img := pad.result()
	var mid: float = img.get_pixel(64, 64).a
	var left := img.get_pixel(40, 64).a # the mirrored half
	var corner := img.get_pixel(4, 4).a
	_check(mid > 0.9 and left > 0.9 and corner < 0.01,
		"drawing round half a leaf fills the whole leaf (middle %.2f, mirrored side %.2f, corner %.2f)" % [mid, left, corner])
	_check(not touched_sim, "the strokes never reached the sim")
	_check(sim.effect_root.position == poke_root, "the effect didn't move")
	_check(main.panel_scroll.scroll_vertical == scroll_before, "the panel didn't scroll")
	await _frames(2)
	await _snap("shape_pad_leaf")

	# the brush and the eraser
	pad.tool = "brush"
	pad.brush = 4.0
	pad.begin_stroke(Vector2(20, 20))
	pad.extend_stroke(Vector2(30, 30))
	pad.end_stroke()
	_check(pad.result().get_pixel(25, 25).a > 0.5 and pad.result().get_pixel(128 - 25, 25).a > 0.5,
		"the brush paints both sides with Mirror on")
	pad.tool = "erase"
	pad.begin_stroke(Vector2(64, 64))
	pad.end_stroke()
	_check(pad.paint.get_pixel(64, 64).a < 0.1, "the eraser rubs out")
	pad.undo()
	pad.undo()
	_check(pad.paint.get_pixel(64, 64).a > 0.9 and pad.paint.get_pixel(25, 25).a < 0.1, "undo takes both back")

	editor.name_edit.text = "Test Leaf"
	editor.save()
	await _frames(5)
	var e: Dictionary = sim.fx.emitters[sim.sel]
	_check(e.tex == "user:test_leaf", "saving picks it for the emitter (%s)" % e.tex)
	var drawn: Texture2D = sim.runs[sim.sel].dm.albedo_texture if e.mode != "tumble" else null
	_check(drawn != null and drawn == ShapeStore.texture("user:test_leaf"), "the emitter draws the new sprite")
	_check(FileAccess.file_exists(ShapeStore.dir() + "/test_leaf.png"), "it is kept as a PNG")
	await _frames(40)
	await _snap("particles_custom_leaf")

	# import: ink on paper becomes a white mask, trimmed and fitted
	var paper := Image.create(300, 200, false, Image.FORMAT_RGBA8)
	paper.fill(Color(0.95, 0.94, 0.9))
	for y in range(60, 140):
		for x in range(170, 250):
			if Vector2(x - 210, y - 100).length() < 38.0:
				paper.set_pixel(x, y, Color(0.05, 0.05, 0.08))
	var ed2: Node = ShapePad.open_editor(main, "", func(_id: String) -> void: pass)
	await _frames(5)
	ed2.take_import(paper, "ink_blot.jpg")
	var made: Image = ed2.pad.result()
	_check(ed2._from == "dark", "an opaque light picture is read as dark ink (%s)" % ed2._from)
	_check(made.get_pixel(64, 64).a > 0.9 and made.get_pixel(3, 3).a < 0.05 and made.get_pixel(64, 64).r > 0.99,
		"the import is a white mask, trimmed to the blot and centred")
	await _snap("shape_pad_import")
	ed2.cancel()
	await _frames(3)

	# export, and send to a fresh project
	var project := lib + "/fresh"
	DirAccess.make_dir_recursive_absolute(project)
	var f := FileAccess.open(project + "/project.godot", FileAccess.WRITE)
	f.store_string("config_version=5\n\n[application]\nconfig/name=\"Fresh\"\nconfig/features=PackedStringArray(\"4.7\", \"GL Compatibility\")\n\n[rendering]\nrenderer/rendering_method=\"gl_compatibility\"\nrenderer/rendering_method.mobile=\"gl_compatibility\"\n")
	f.close()
	var said: Array[String] = []
	sim.say.connect(func(t: String) -> void: said.append(t))
	sim._export("Leaf Shape FX")
	print("  ", sim.status())
	print("  ", Exporter.send_to_project("effects", "Leaf Shape FX", project))
	_check(FileAccess.file_exists(project + "/assets/effects/leaf_shape_fx.tscn"), "the effect was sent to the fresh project")
	_check(FileAccess.file_exists(project + "/assets/effects/leaf_shape_fx.sprite_test_leaf.png"), "with the sprite's PNG beside it")
	var json := FileAccess.get_file_as_string(project + "/assets/effects/leaf_shape_fx.json")
	_check(json.contains("\"sprites\"") and json.contains("user:test_leaf"), "the JSON carries the sprite")
	var check := FileAccess.open(project + "/check_shape.gd", FileAccess.WRITE)
	check.store_string(CHECK)
	check.close()
	print("SHAPE PAD %s" % ("OK" if failures == 0 else "FAILED (%d)" % failures))
	quit(failures)


const CHECK := """extends SceneTree
# Loads the exported effect in this fresh project and checks its emitter draws the drawn leaf.
func _initialize() -> void:
	var scene := load("res://assets/effects/leaf_shape_fx.tscn") as PackedScene
	if scene == null:
		print("SHAPE EFFECT FAILED: no scene")
		quit(1)
		return
	var fx := scene.instantiate()
	root.add_child(fx)
	var found := 0
	for n in fx.find_children("*", "GPUParticles3D", true, false):
		var mesh: Mesh = n.draw_pass_1
		var mat: Material = mesh.surface_get_material(0) if mesh else null
		var tex: Texture2D = null
		if mat is StandardMaterial3D:
			tex = mat.albedo_texture
		elif mat is ShaderMaterial:
			tex = mat.get_shader_parameter("tex")
		if tex and tex.get_width() == 128:
			var img := tex.get_image()
			img.decompress()
			if img.get_pixel(64, 64).a > 0.9 and img.get_pixel(4, 4).a < 0.05:
				found += 1
				print("%s draws the leaf (%dx%d)" % [n.name, tex.get_width(), tex.get_height()])
	print("SHAPE EFFECT %s" % ("OK" if found > 0 else "FAILED"))
	quit(0 if found > 0 else 1)
"""
