"""Builds the firefly (creatures/fireflies/): a lightning bug, a Photinus, as it flies, and exports it for Godot.

Run from the project root (Blender 4.3):
    blender --background --python creatures/fireflies/tools/build_firefly.py
then, so that Godot takes up the new model:
    godot --headless --path . --import

Writes creatures/fireflies/models/firefly.glb (about 200 triangles: thousands are drawn at once).

It is ONE UNIT long, head to tail (the game scales it to its size, a centimetre and a half), facing the game's +Z,
back up (+Y), as it flies: its wing cases (elytra) raised and held out, the clear hindwings spread under them, its
legs hanging. One object, its parts told apart by their material's name (FireflyField, creatures/fireflies/
firefly_field.gd, reads them so; the shader colours each and lights the lantern):

    head      the small dark head, half under the shield
    shield    the pronotum: a flat rounded shield over the head, pale, with a rosy patch and a dark spot in the middle
    elytra    the two wing cases, dark, edged pale along their sides
    abdomen   the underside of the abdomen, dusky
    lantern   the last two segments under the abdomen: the light
    wing      the hindwings (a blur as they beat)
    leg       the legs and feelers

All coordinates below are in Godot space (x right, y up, z forward) and turned to Blender's as they are made.
"""

import math
import os

import bmesh
import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
OUT = os.path.join(ROOT, "creatures", "fireflies", "models", "firefly.glb")


def B(p):
    """Godot (x, y, z) to Blender."""
    return Vector((p[0], -p[2], p[1]))


def clear():
    for thing in list(bpy.data.objects):
        bpy.data.objects.remove(thing, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)
    for material in list(bpy.data.materials):
        bpy.data.materials.remove(material)


COLOURS = {
    "head": (0.08, 0.07, 0.06), "shield": (0.7, 0.6, 0.4), "elytra": (0.1, 0.09, 0.08), "abdomen": (0.2, 0.18, 0.14),
    "lantern": (0.9, 0.95, 0.5), "wing": (0.5, 0.5, 0.5), "leg": (0.1, 0.09, 0.08),
}
MATERIALS = {}


def mat(name):
    if name not in MATERIALS:
        made = bpy.data.materials.new(name)
        made.diffuse_color = (*COLOURS[name], 1.0)
        MATERIALS[name] = made
    return MATERIALS[name]


def part(name, build, material):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    build(bm)
    bm.to_mesh(mesh)
    bm.free()
    made = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(made)
    made.data.materials.append(mat(material))
    return made


def face(bm, points):
    verts = [bm.verts.new(B(p)) for p in points]
    return bm.faces.new(verts)


def ball(bm, middle, radii, segments=6, rings=4, cut=None):
    """An ellipsoid; with `cut` (a function of the point), only the part where it is true."""
    middle = Vector(middle)
    rows = []
    for r in range(rings + 1):
        a = math.pi * r / rings
        row = []
        for s in range(segments):
            b = math.tau * s / segments
            row.append(middle + Vector((math.sin(a) * math.cos(b) * radii[0], math.cos(a) * radii[1], math.sin(a) * math.sin(b) * radii[2])))
        rows.append(row)
    for r in range(rings):
        for s in range(segments):
            t = (s + 1) % segments
            if r == 0:
                quad = [rows[0][0], rows[1][t], rows[1][s]]
            elif r == rings - 1:
                quad = [rows[r][s], rows[r][t], rows[rings][0]]
            else:
                quad = [rows[r][s], rows[r][t], rows[r + 1][t], rows[r + 1][s]]
            if cut is None or all(cut(p) for p in quad):
                face(bm, quad)


def tube(bm, points, radius, sides=3):
    rings = []
    for i, p in enumerate(points):
        p = Vector(p)
        ahead = (Vector(points[min(i + 1, len(points) - 1)]) - Vector(points[max(i - 1, 0)])).normalized()
        one = ahead.cross(Vector((0, 1, 0)) if abs(ahead.y) < 0.9 else Vector((1, 0, 0))).normalized()
        two = ahead.cross(one).normalized()
        rings.append([p + (one * math.cos(k * math.tau / sides) + two * math.sin(k * math.tau / sides)) * radius for k in range(sides)])
    for i in range(len(rings) - 1):
        for k in range(sides):
            j = (k + 1) % sides
            face(bm, [rings[i][k], rings[i][j], rings[i + 1][j], rings[i + 1][k]])


def join(things, name):
    bpy.ops.object.select_all(action="DESELECT")
    for thing in things:
        thing.select_set(True)
    bpy.context.view_layer.objects.active = things[0]
    bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    joined.data.name = name
    return joined


def firefly():
    things = []
    things.append(part("head", lambda bm: ball(bm, (0.0, -0.02, 0.4), (0.09, 0.07, 0.07), 6, 4), "head"))
    # The shield over the head: a flat dome, wider than long, its front edge over the head.
    things.append(part("shield", lambda bm: ball(bm, (0.0, 0.03, 0.33), (0.16, 0.06, 0.13), 8, 4, lambda p: p.z > -0.005), "shield"))

    # The abdomen under the wing cases, and the lantern at its tip.
    things.append(part("abdomen", lambda bm: ball(bm, (0.0, -0.02, 0.0), (0.13, 0.07, 0.3), 8, 5), "abdomen"))
    things.append(part("lantern", lambda bm: ball(bm, (0.0, -0.035, -0.27), (0.1, 0.055, 0.12), 8, 4), "lantern"))

    def elytra(bm):
        # Each wing case: a long shallow half shell from the shoulder, raised and held out as it flies.
        for side in (1, -1):
            root = Vector((0.04 * side, 0.03, 0.22))
            out = Vector((0.55 * side, 0.55, -1.0)).normalized()
            across = Vector((side, -0.35, 0.0)).normalized()
            length = 0.62
            rows = []
            for k in range(5):
                t = k / 4
                at = root + out * length * t
                width = 0.13 * math.sin(math.pi * (0.15 + 0.85 * t)) ** 0.6
                bulge = Vector((0.0, 0.03, 0.0)) * math.sin(math.pi * t)
                rows.append([at - across * width * 0.2 + bulge * 0.5, at + across * width * 0.5 + bulge, at + across * width + bulge * 0.3])
            for k in range(4):
                for j in range(2):
                    quad = [rows[k][j], rows[k + 1][j], rows[k + 1][j + 1], rows[k][j + 1]]
                    if side < 0:
                        quad.reverse()
                    face(bm, quad)
    things.append(part("elytra", elytra, "elytra"))

    def wings(bm):
        # The clear hindwings, spread out to the sides under the wing cases.
        for side in (1, -1):
            root = (0.05 * side, 0.02, 0.18)
            outline = [(0.15, 0.24), (0.42, 0.2), (0.6, 0.08), (0.62, -0.06), (0.48, -0.16), (0.25, -0.1), (0.1, 0.02)]
            pts = [root] + [(x * side, 0.02 + 0.06 * x, z) for x, z in outline]
            for k in range(1, len(pts) - 1):
                tri = [pts[0], pts[k], pts[k + 1]]
                if side < 0:
                    tri.reverse()
                face(bm, tri)
    things.append(part("wing", wings, "wing"))

    def legs(bm):
        for side in (1, -1):
            for hip_z, reach in ((0.3, 0.12), (0.18, 0.02), (0.08, -0.1)):
                hip = (0.05 * side, -0.06, hip_z)
                knee = (0.17 * side, -0.1, hip_z + reach * 0.5)
                foot = (0.2 * side, -0.24, hip_z + reach)
                tube(bm, [hip, knee, foot], 0.012)
            # A feeler, out and forward from the head.
            tube(bm, [(0.04 * side, 0.0, 0.45), (0.12 * side, 0.06, 0.6), (0.2 * side, 0.08, 0.75)], 0.01)
    things.append(part("legs", legs, "leg"))
    return join(things, "firefly")


def build():
    clear()
    made = firefly()
    print("BUILT firefly: %d triangles" % sum(len(p.vertices) - 2 for p in made.data.polygons))
    bpy.ops.object.select_all(action="DESELECT")
    made.select_set(True)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_animations=False,
                              use_selection=True, export_materials="EXPORT")


build()
