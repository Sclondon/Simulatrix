extends SceneTree
## Exports from every lab that has an Export section into a scratch library (--root=<dir>) and
## sends each asset to a fresh project there (<dir>/project). Then run tests/export_labs_check.gd
## inside that project to prove each asset builds:
## godot --audio-driver Dummy --path . -s tests/export_labs.gd -- --root=C:/tmp/lib
## godot --headless --audio-driver Dummy --path C:/tmp/lib/project -s check.gd

var main: Control
var lib := ""
var project := ""
var sent: Array[String] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--root="):
			lib = a.trim_prefix("--root=")
	Exporter.root_override = lib
	project = lib + "/project"
	DirAccess.make_dir_recursive_absolute(project)
	var f := FileAccess.open(project + "/project.godot", FileAccess.WRITE)
	f.store_string("config_version=5\n\n[application]\nconfig/name=\"Fresh\"\nconfig/features=PackedStringArray(\"4.7\", \"GL Compatibility\")\n\n[rendering]\nrenderer/rendering_method=\"gl_compatibility\"\nrenderer/rendering_method.mobile=\"gl_compatibility\"\n")
	f.close()
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://tests/export_labs_check.gd"), project + "/check.gd")
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _open(title: String) -> Sim:
	for i in main.SIMS.size():
		if main.SIMS[i].title == title:
			main.open_sim(i)
	await _frames(40)
	return main.sim


func _send(kind: String, asset: String) -> void:
	var line := Exporter.send_to_project(kind, asset, project)
	print("  ", line)
	sent.append(kind + "/" + Exporter.slug(asset))


func _export(sim: Sim, kind: String, asset: String) -> void:
	var lines: Array[String] = []
	var catch := func(t: String) -> void: lines.append(t)
	sim.say.connect(catch)
	if sim.has_method("export_asset"):
		await sim.export_asset(asset)
	else:
		sim._export(asset)
	await _frames(2)
	sim.say.disconnect(catch)
	print("%s: %s" % [asset, lines[-1] if not lines.is_empty() else "(nothing said)"])
	_send(kind, asset)


func _run() -> void:
	await _frames(5)
	var s: Sim = await _open("Tree Lab")
	for pick in [["Fir", "Lab Fir"], ["Oak", "Lab Oak"], ["Painted oak", "Lab Painted Oak"], ["Bush", "Lab Bush"]]:
		s.species = s.SPECIES.find(pick[0])
		s._touch()
		s._rebuild()
		await _frames(5)
		await _export(s, "trees", pick[1])
	s = await _open("Particle Editor")
	await _export(s, "effects", "Lab Campfire")
	s = await _open("Shader Lab")
	await _frames(30)
	await _export(s, "shaders", "Lab Plasma")
	s = await _open("Texture Lab")
	s.export_size = 512
	await _frames(20)
	await _export(s, "textures", "Lab FBM")
	s = await _open("Fire")
	await _export(s, "fire", "Lab Campfire Fire")
	s = await _open("Pond")
	await _export(s, "water", "Lab Pond")
	s = await _open("Grass")
	await _export(s, "grass", "Lab Grass")
	s = await _open("Sand")
	await _export(s, "sand", "Lab Sand")
	var list := FileAccess.open(project + "/sent.txt", FileAccess.WRITE)
	list.store_string("\n".join(sent))
	list.close()
	print("EXPORTED %d" % sent.size())
	quit()
