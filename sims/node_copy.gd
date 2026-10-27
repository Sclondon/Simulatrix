class_name NodeCopy
extends RefCounted
## For exports: a fresh node of a component's own class carrying a live node's settings (its
## exported properties and its transform), with none of what the live one built under itself,
## so a saved scene holds only the settings and the component builds itself in the project.


static func fresh(live: Node, node_name := "") -> Node:
	var made: Node = live.get_script().new()
	for p in live.get_property_list():
		var usage: int = p.usage
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE and usage & PROPERTY_USAGE_STORAGE:
			made.set(p.name, live.get(p.name))
	if live is Node3D:
		(made as Node3D).transform = (live as Node3D).transform
	made.name = node_name if node_name != "" else live.name
	return made
