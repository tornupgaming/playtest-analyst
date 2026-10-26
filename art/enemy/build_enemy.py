"""Builds the enemy, a round spiky critter in the Kenney Platformer Kit palette.

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


BODY = mat("body", "FF7244")
BELLY = mat("fang", "FFFFFF", 0.4)
SPIKE = mat("spike", "FDE4C7")
EYE = mat("eye", "FFFFFF", 0.4)
PUPIL = mat("pupil", "3D3E4B", 0.4)
FOOT = mat("foot", "B06041")


def smooth(obj, levels=2):
    mod = obj.modifiers.new("subd", "SUBSURF")
    mod.levels = levels
    mod.render_levels = levels
    for p in obj.data.polygons:
        p.use_smooth = True


def add(obj, material):
    obj.data.materials.append(material)
    return obj


parts = []

# Body: a squashed ball.
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.62, location=(0, 0, 0.72), segments=32, ring_count=16)
body = add(bpy.context.object, BODY)
body.scale = (1.0, 0.95, 0.88)
for p in body.data.polygons:
    p.use_smooth = True
parts.append(body)

# Two little fangs under the eyes.
for side in (-1, 1):
    bpy.ops.mesh.primitive_cone_add(vertices=10, radius1=0.06, radius2=0.005, depth=0.14,
                                    location=(side * 0.12, 0.56, 0.6), rotation=(math.pi, 0, 0))
    fang = add(bpy.context.object, BELLY)
    parts.append(fang)

# Spikes over the back and top, in two rings.
for ring, (tilt, count, length) in enumerate([(35, 5, 0.42), (75, 6, 0.36)]):
    for i in range(count):
        spread = 160 if ring == 0 else 200
        yaw = math.radians(-spread / 2 + spread * i / max(1, count - 1))
        t = math.radians(tilt)
        # Direction from body centre, biased to the back (-Y) and top.
        d = Vector((math.sin(yaw) * math.sin(t), -math.cos(yaw) * math.sin(t), math.cos(t)))
        if ring == 0:
            d = Vector((math.sin(yaw) * 0.55, -0.35 - 0.2 * math.cos(yaw), 0.85)).normalized()
        base = Vector((0, 0, 0.72)) + Vector((d.x * 0.6, d.y * 0.58, d.z * 0.52))
        bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=0.15, radius2=0.02, depth=length,
                                        location=base + d * (length * 0.4))
        cone = add(bpy.context.object, SPIKE)
        cone.rotation_mode = "QUATERNION"
        cone.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d)
        for p in cone.data.polygons:
            p.use_smooth = True
        parts.append(cone)

# Eyes: white ovals, pupils looking forward, and angry brows.
for side in (-1, 1):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.17, location=(side * 0.2, 0.5, 0.95), segments=24, ring_count=12)
    eye = add(bpy.context.object, EYE)
    eye.scale = (0.85, 0.5, 1.15)
    for p in eye.data.polygons:
        p.use_smooth = True
    parts.append(eye)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.085, location=(side * 0.18, 0.58, 0.92), segments=16, ring_count=8)
    pupil = add(bpy.context.object, PUPIL)
    pupil.scale = (1.0, 0.5, 1.2)
    for p in pupil.data.polygons:
        p.use_smooth = True
    parts.append(pupil)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(side * 0.21, 0.52, 1.15))
    brow = add(bpy.context.object, PUPIL)
    brow.scale = (0.26, 0.08, 0.07)
    brow.rotation_euler = (0, side * math.radians(28), 0)
    bevel = brow.modifiers.new("bevel", "BEVEL")
    bevel.width = 0.02
    bevel.segments = 3
    parts.append(brow)

# Stubby feet.
for side in (-1, 1):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.2, location=(side * 0.3, 0.12, 0.12), segments=16, ring_count=8)
    foot = add(bpy.context.object, FOOT)
    foot.scale = (1.0, 1.35, 0.6)
    for p in foot.data.polygons:
        p.use_smooth = True
    parts.append(foot)

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
