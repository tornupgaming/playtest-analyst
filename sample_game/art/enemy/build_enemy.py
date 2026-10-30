"""Builds the enemy, a grumpy toadstool in the Kenney Platformer Kit palette. Its soft,
spotted cap says "jump on me", the way a Goomba does; spikes would say the opposite.

    blender -b -P art/enemy/build_enemy.py -- art/enemy/enemy.glb [preview.png]

Origin at its feet, facing +Z (Godot's model front), about 1.5 m tall.
"""
import math
import sys

import bpy
from mathutils import Vector

out = sys.argv[sys.argv.index("--") + 1]
preview = sys.argv[sys.argv.index("--") + 2] if len(sys.argv) > sys.argv.index("--") + 2 else None

bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, hex_color, rough=0.8):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    c = tuple(int(hex_color[i:i + 2], 16) / 255 for i in (0, 2, 4))
    # The palette is sRGB; Blender wants linear.
    bsdf.inputs["Base Color"].default_value = (*[x ** 2.2 for x in c], 1)
    bsdf.inputs["Roughness"].default_value = rough
    return m


CAP = mat("cap", "F2564B", 0.6)
SPOT = mat("spot", "FDE4C7")
STEM = mat("stem", "FDE4C7")
EYE = mat("eye", "FFFFFF", 0.4)
PUPIL = mat("pupil", "3D3E4B", 0.4)
FOOT = mat("foot", "B06041")


def ball(radius, location, scale, material, segments=24):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=location, segments=segments, ring_count=segments // 2)
    obj = add(bpy.context.object, material)
    obj.scale = scale
    for p in obj.data.polygons:
        p.use_smooth = True
    parts.append(obj)
    return obj


def add(obj, material):
    obj.data.materials.append(material)
    return obj


parts = []

# Stem: a plump cream body that carries the face.
body = ball(0.48, (0, 0, 0.6), (1.0, 0.92, 1.12), STEM, 32)

# Cap: a wide, soft dome. Round and spot-covered so it reads as safe to stomp.
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.74, location=(0, 0, 1.08), segments=40, ring_count=20)
cap = add(bpy.context.object, CAP)
cap.scale = (1.0, 1.0, 0.6)
# Flatten the underside so it sits on the stem like a mushroom cap, with a rim.
for v in cap.data.vertices:
    if v.co.z < -0.15:
        v.co.z = -0.15 - (v.co.z + 0.15) * 0.15
for p in cap.data.polygons:
    p.use_smooth = True
parts.append(cap)

# Cream spots on the cap, flattened onto its surface.
for x, y, r in [(0.0, 0.0, 0.18), (0.38, 0.22, 0.13), (-0.38, 0.22, 0.13), (0.27, -0.38, 0.14),
                (-0.27, -0.38, 0.14), (0.0, 0.46, 0.11), (0.56, -0.07, 0.09), (-0.56, -0.07, 0.09)]:
    d = Vector((x, y, 0.0))
    # Height on the cap's ellipsoid at (x, y).
    h = 0.74 * 0.6 * math.sqrt(max(0.0, 1.0 - (x * x + y * y) / 0.74 ** 2))
    normal = Vector((x / 0.74 ** 2, y / 0.74 ** 2, h / (0.74 * 0.6) ** 2)).normalized()
    spot = ball(r, (x, y, 1.08 + h - 0.01), (1.0, 1.0, 0.3), SPOT, 16)
    spot.rotation_mode = "QUATERNION"
    spot.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(normal)

# Eyes: white ovals under the cap rim, pupils looking forward, and angry brows.
for side in (-1, 1):
    ball(0.15, (side * 0.17, 0.4, 0.66), (0.85, 0.5, 1.15), EYE)
    ball(0.075, (side * 0.15, 0.47, 0.63), (1.0, 0.5, 1.2), PUPIL, 16)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(side * 0.18, 0.43, 0.86))
    brow = add(bpy.context.object, PUPIL)
    brow.scale = (0.22, 0.07, 0.06)
    brow.rotation_euler = (0, side * math.radians(25), 0)
    bevel = brow.modifiers.new("bevel", "BEVEL")
    bevel.width = 0.02
    bevel.segments = 3
    parts.append(brow)

# Stubby feet.
for side in (-1, 1):
    ball(0.2, (side * 0.26, 0.1, 0.12), (1.0, 1.35, 0.6), FOOT, 16)

# Join into one mesh, then turn so the face looks along +Z in Godot (Blender -Y is
# glTF +Z after the Y-up conversion, so the face, built along +Y, needs a half turn).
for obj in parts:
    for mod in obj.modifiers:
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
bpy.ops.object.select_all(action="DESELECT")
for obj in parts:
    obj.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
body.name = "Enemy"
body.rotation_euler = (0, 0, math.pi)
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True)

if preview:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = scene.render.resolution_y = 512
    scene.render.film_transparent = True
    bpy.ops.object.camera_add(location=(2.6, -3.2, 2.2))
    cam = bpy.context.object
    cam.rotation_euler = (Vector((0, 0, 0.7)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), 0, math.radians(30)))
    bpy.context.object.data.energy = 4
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.2
    scene.world = world
    scene.render.filepath = preview
    bpy.ops.render.render(write_still=True)
