class_name Exporter
extends RefCounted
## Sends what a lab made to the asset library, for other projects to take when they choose
## (nothing here changes another game). Run locally, an asset is written into
## GameCommon/library/<kind>/; in a browser, its files are downloaded instead.
##
## Each asset is one or more files named after it, plus `<name>.asset.txt`, which says what it
## is and which GameCommon components a project needs for it. `sh kit.sh asset <kind>/<name>
## <project>` (in GameCommon) copies the files into the project's assets/<kind>/ and installs
## those components. The library's README lists every asset.

const GAMECOMMON := "C:/Projects/GameCommon"

## Set to write somewhere else (tests).
static var root_override := ""


## Where assets go when they can be written: GameCommon's library if it is on this machine,
## else this app's own user data. Empty in a browser (files are downloaded there).
static func library_root() -> String:
	if root_override != "":
		return root_override
	if OS.has_feature("web"):
		return ""
	if DirAccess.dir_exists_absolute(GAMECOMMON):
		return GAMECOMMON + "/library"
	return ProjectSettings.globalize_path("user://library")


## A file name made from what the user typed: lower case, words joined by underscores.
static func slug(text: String) -> String:
	var out := ""
	for c in text.strip_edges().to_lower():
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.trim_prefix("_").trim_suffix("_")
	return out if out != "" else "untitled"


## Writes an asset. `files` maps an extension ("tres", "glb", "png"...) to its content: a
## Resource (saved with ResourceSaver), a Node (packed into a scene), a String or a
## PackedByteArray. `needs` lists GameCommon components ("godot/pine-tree"); `use` is a line or
## two of GDScript showing how a project uses it. Returns a line for the status bar.
static func save(kind: String, name: String, files: Dictionary, needs: Array = [], use := "", lab := "") -> String:
	var base := slug(name)
	var root := library_root()
	var written: Array[String] = []
	var dir := ""
	if root != "":
		dir = "%s/%s" % [root, kind]
		DirAccess.make_dir_recursive_absolute(dir)
	for ext: String in files:
		var file := "%s.%s" % [base, ext]
		var content: Variant = files[ext]
		var ok := false
		if root != "":
			ok = _write(dir + "/" + file, content)
		else:
			ok = _download(file, content)
		if ok:
			written.append(file)
	if written.is_empty():
		return "Export failed"
	var note := PackedStringArray([
		"# %s, made in The Simulatrix%s, %s" % [name, (" (" + lab + ")") if lab != "" else "", Time.get_date_string_from_system()],
		"kind %s" % kind])
	for n in needs:
		note.append("needs %s" % n)
	for f in written:
		note.append("file %s" % f)
	for line in use.split("\n"):
		if line.strip_edges() != "":
			note.append("use %s" % line)
	var note_text := "\n".join(note) + "\n"
	if root != "":
		_write(dir + "/" + base + ".asset.txt", note_text)
		_write_index(root)
		return "Exported %s to %s" % [", ".join(written), dir]
	_download(base + ".asset.txt", note_text)
	return "Downloaded " + ", ".join(written)


## Copies a library asset into a Godot project, the way `kit.sh asset` does: its files into
## <project>/assets/<kind>/, and every component it needs (by the component's FILES.txt) where
## the component keeps them, never overwriting a project's own changed copy of a component file.
## Returns a line for the status bar.
static func send_to_project(kind: String, name: String, project: String) -> String:
	var root := library_root()
	var note_path := "%s/%s/%s.asset.txt" % [root, kind, slug(name)]
	if root == "" or not FileAccess.file_exists(note_path):
		return "Export it first"
	if not FileAccess.file_exists(project + "/project.godot"):
		return "Not a Godot project: " + project
	var copied := 0
	var kept: Array[String] = []
	DirAccess.make_dir_recursive_absolute("%s/assets/%s" % [project, kind])
	for line in FileAccess.get_file_as_string(note_path).split("\n"):
		line = line.strip_edges()
		if line.begins_with("file "):
			var f := line.trim_prefix("file ")
			DirAccess.copy_absolute("%s/%s/%s" % [root, kind, f], "%s/assets/%s/%s" % [project, kind, f])
			copied += 1
		elif line.begins_with("needs "):
			var comp := GAMECOMMON + "/" + line.trim_prefix("needs ")
			for entry in FileAccess.get_file_as_string(comp + "/FILES.txt").split("\n"):
				entry = entry.strip_edges()
				if entry == "" or entry.begins_with("#"):
					continue
				var mine := comp + "/files/" + entry
				var theirs := project + "/" + entry
				if FileAccess.file_exists(theirs) and FileAccess.get_file_as_bytes(theirs) != FileAccess.get_file_as_bytes(mine):
					kept.append(entry) # the project has changed its copy: leave it
					continue
				DirAccess.make_dir_recursive_absolute(theirs.get_base_dir())
				DirAccess.copy_absolute(mine, theirs)
	var out := "Sent %s (%d files) to %s/assets/%s" % [slug(name), copied, project, kind]
	if not kept.is_empty():
		out += "; kept the project's own " + ", ".join(kept)
	return out


## Asks for a project folder (the native folder picker) and sends the asset there.
static func pick_project_and_send(kind: String, name: String, done: Callable) -> void:
	DisplayServer.file_dialog_show("Send to which Godot project?", "C:/Projects", "", false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_DIR, PackedStringArray(),
		func(ok: bool, paths: PackedStringArray, _filter: int) -> void:
			if ok and not paths.is_empty():
				done.call(send_to_project(kind, name, paths[0])))


## Opens the library folder (or this kind's folder) in the file browser, where it can be written.
static func open_folder(kind := "") -> void:
	var root := library_root()
	if root == "":
		return
	var dir := root if kind == "" else root + "/" + kind
	DirAccess.make_dir_recursive_absolute(dir)
	OS.shell_open(dir)


## The Export section for a lab's properties: a name, Export, and (locally) Send to project...
## and Open folder. `on_export` is called with the name typed and should call save();
## `say` shows a line in the lab's status (a Callable taking a String).
static func controls(default_name: String, on_export: Callable, kind := "", say := Callable()) -> Array:
	var field := LineEdit.new()
	field.text = default_name
	field.placeholder_text = "Asset name"
	field.custom_minimum_size.y = 44
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Name"
	label.custom_minimum_size.x = 70
	row.add_child(label)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	var out: Array = [
		{type = "section", label = "Export"},
		{type = "custom", node = row},
		{type = "button", label = "Export", on = func() -> void: on_export.call(field.text)},
	]
	if library_root() != "":
		out.append({type = "button", label = "Send to project...", on = func() -> void:
			pick_project_and_send(kind, field.text, func(line: String) -> void:
				if say.is_valid():
					say.call(line))})
		out.append({type = "button", label = "Open folder", on = func() -> void: open_folder(kind)})
	return out


static func _write(path: String, content: Variant) -> bool:
	if content is Node:
		var packed := PackedScene.new()
		_own(content, content)
		if packed.pack(content) != OK:
			return false
		return ResourceSaver.save(packed, path) == OK
	if content is Resource:
		return ResourceSaver.save(content, path) == OK
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	if content is PackedByteArray:
		f.store_buffer(content)
	else:
		f.store_string(str(content))
	return true


## Packing a scene keeps only nodes owned by its root.
static func _own(node: Node, root: Node) -> void:
	for c in node.get_children():
		c.owner = root
		_own(c, root)


static func _download(file: String, content: Variant) -> bool:
	if not OS.has_feature("web"):
		return false
	var bytes: PackedByteArray
	if content is PackedByteArray:
		bytes = content
	elif content is String:
		bytes = (content as String).to_utf8_buffer()
	else:
		# a Resource or a scene: write it to a temporary file and send that
		var tmp := "user://export_tmp." + file.get_extension()
		if not _write(tmp, content):
			return false
		bytes = FileAccess.get_file_as_bytes(tmp)
	JavaScriptBridge.download_buffer(bytes, file)
	return true


## Rewrites the library's README list from the asset notes on disk.
static func _write_index(root: String) -> void:
	var lines := PackedStringArray()
	var kinds := DirAccess.get_directories_at(root)
	kinds.sort()
	for kind in kinds:
		var notes := Array(DirAccess.get_files_at(root + "/" + kind)).filter(func(f: String) -> bool:
			return f.ends_with(".asset.txt"))
		if notes.is_empty():
			continue
		notes.sort()
		lines.append("\n## %s\n" % kind.capitalize())
		lines.append("| Asset | Files | Needs | Made |")
		lines.append("| --- | --- | --- | --- |")
		for note: String in notes:
			var name := note.trim_suffix(".asset.txt")
			var files := PackedStringArray()
			var needs := PackedStringArray()
			var made := ""
			for line in FileAccess.get_file_as_string("%s/%s/%s" % [root, kind, note]).split("\n"):
				if line.begins_with("file "):
					files.append("`%s`" % line.trim_prefix("file "))
				elif line.begins_with("needs "):
					needs.append("`%s`" % line.trim_prefix("needs "))
				elif line.begins_with("# "):
					made = line.get_slice(", ", line.get_slice_count(", ") - 1)
			lines.append("| %s/%s | %s | %s | %s |" % [kind, name, " ".join(files), " ".join(needs), made])
	var head := FileAccess.get_file_as_string(root + "/README.md")
	var cut := head.find("<!-- assets -->")
	if cut == -1:
		head = HEADER
		cut = head.find("<!-- assets -->")
	_write(root + "/README.md", head.substr(0, cut) + "<!-- assets -->\n" + "\n".join(lines) + "\n")


const HEADER := """# Asset library

Things made in The Simulatrix (Simulatrix/, a local tool) for any project to take: trees, effects, shaders,
textures, configured water, fire, grass... Nothing here reaches a game until you copy it in:

```
sh kit.sh asset trees/spooky_fir /c/Projects/SomeGame   # copies the asset into SomeGame/assets/trees/
                                                         # and installs the GameCommon components it needs
```

Each asset is its files plus `<name>.asset.txt`: what it is, `needs` (components), `file`s, and `use` lines showing
how a project uses it. Exporting again under the same name replaces the asset here; a project keeps its own copy
until you run `kit.sh asset` again. The list below is rewritten by the Simulatrix on every export.

<!-- assets -->
"""
