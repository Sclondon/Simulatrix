extends SceneTree
## Exports a pine (generator settings, baked mesh, glTF) to a scratch library given by
## --root=<dir>, the way Tree Lab does, checks the files and the asset note are there, then sends it
## to a fresh project the way "Send to project..." does.
## godot --headless --audio-driver Dummy --path . -s tests/export_check.gd -- --root=C:/tmp/lib


func _initialize() -> void:
	var root := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--root="):
			root = a.trim_prefix("--root=")
	Exporter.root_override = root
	var pine := PineTree.new()
	pine.height = 9.0
	pine.droop = 0.7
	pine.seed = 42
	var tree := pine.instance()
	var holder := Node3D.new()
	holder.name = "SpookyFir"
	holder.add_child(tree)
	var glb := GLTFDocument.new()
	var state := GLTFState.new()
	glb.append_from_scene(holder, state)
	var glb_bytes := glb.generate_buffer(state)
	var line := Exporter.save("trees", "Spooky Fir", {"tres": pine, "mesh.res": tree.mesh, "glb": glb_bytes},
		["godot/pine-tree"], "var tree := (load(\"res://assets/trees/spooky_fir.tres\") as PineTree).instance()\nadd_child(tree)",
		"Tree Lab")
	print(line)
	var ok := true
	for f in ["spooky_fir.tres", "spooky_fir.mesh.res", "spooky_fir.glb", "spooky_fir.asset.txt", "../README.md"]:
		var there := FileAccess.file_exists(root + "/trees/" + f)
		print(("ok   " if there else "FAIL ") + f)
		ok = ok and there
	holder.free()
	# and send it to a fresh project the way "Send to project..." does
	var project := root + "/newgame"
	DirAccess.make_dir_recursive_absolute(project)
	var f := FileAccess.open(project + "/project.godot", FileAccess.WRITE)
	f.store_string("config_version=5\n")
	f.close()
	print(Exporter.send_to_project("trees", "Spooky Fir", project))
	for p in ["assets/trees/spooky_fir.tres", "assets/trees/spooky_fir.glb", "scripts/pine_tree.gd"]:
		var there := FileAccess.file_exists(project + "/" + p)
		print(("ok   " if there else "FAIL ") + p)
		ok = ok and there
	print("EXPORT %s" % ("OK" if ok else "FAILED"))
	quit(0 if ok else 1)
