extends SceneTree
## Run inside the fresh project that tests/export_labs.gd fills: loads every asset it was sent
## (listed in sent.txt) the way its use lines say, and lets each build for a few frames.

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		failures += 1


func _run() -> void:
	var stage := Node3D.new()
	get_root().add_child(stage)
	for entry in FileAccess.get_file_as_string("res://sent.txt").split("\n"):
		if entry == "":
			continue
		var kind := entry.get_slice("/", 0)
		var file := entry.get_slice("/", 1)
		var base := "res://assets/%s/%s" % [kind, file]
		if ResourceLoader.exists(base + ".tres") and kind == "trees":
			var shape: Resource = load(base + ".tres")
			var tree: MeshInstance3D = shape.instance()
			stage.add_child(tree)
			_check(tree.mesh != null and tree.mesh.get_surface_count() > 0, "%s: tree from settings (%s)" % [entry, shape.get_class()])
			_check(load(base + ".mesh.res") is Mesh, entry + ": baked mesh")
		elif ResourceLoader.exists(base + ".tscn"):
			var node: Node = (load(base + ".tscn") as PackedScene).instantiate()
			if node is Grass:
				node.area = Rect2(-5, -5, 10, 10)
				stage.add_child(node)
				node.build()
			elif kind == "sand":
				var ground := node.get_node("Ground") as SandGround
				ground.height = func(_x: float, _z: float) -> float: return 0.0
				stage.add_child(node)
			else:
				stage.add_child(node)
			await _frames(5)
			var meshes := node.find_children("*", "GeometryInstance3D", true, false).size() + (1 if node is GeometryInstance3D else 0)
			_check(node.is_inside_tree() and (meshes > 0 or node is GPUParticles3D or node.get_child_count() > 0),
				"%s: scene built (%s, %d drawn things)" % [entry, node.get_class() if node.get_script() == null else node.get_script().get_global_name(), meshes])
		elif ResourceLoader.exists(base + ".material.tres"):
			var mat := load(base + ".material.tres") as ShaderMaterial
			_check(mat != null and mat.shader != null and mat.shader.code != "", entry + ": shader material")
			_check(load(base + ".gdshader") is Shader, entry + ": .gdshader")
		elif ResourceLoader.exists(base + ".png"):
			for part in [".png", ".normal.png", ".height.png"]:
				_check(load(base + part) is Texture2D, entry + ": texture " + part)
		else:
			_check(false, entry + ": nothing to load")
		await _frames(2)
	await _frames(10)
	print("FRESH PROJECT %s" % ("OK" if failures == 0 else "FAILED (%d)" % failures))
	quit(failures)
