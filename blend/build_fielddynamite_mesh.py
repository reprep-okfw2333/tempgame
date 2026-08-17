"""Build a PS1-style unlit dynamite stick."""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Vector

BLEND_DIR = r"C:\Users\luigi.manzi\Documents\blend"
TEX_DIR = os.path.join(BLEND_DIR, "textures")
sys.path.insert(0, BLEND_DIR)

sys.modules.pop("gen_dynamite_atlas", None)
from gen_dynamite_atlas import REG, build as build_atlas  # noqa: E402

KEEP_NAMES = {"Camera", "KeyLight", "FillKey", "RimLight", "Light", "StudioGround"}


def clear_old():
    to_delete = [o for o in bpy.data.objects if o.name not in KEEP_NAMES]
    for o in to_delete:
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        if m.users == 0:
            bpy.data.meshes.remove(m)
    for m in list(bpy.data.materials):
        if m.name.startswith(("MAT_", "PH_")) and m.users == 0:
            bpy.data.materials.remove(m)


def write_png(path, arr_u8):
    import struct
    import zlib

    import numpy as np

    h, w = arr_u8.shape[:2]
    top = np.flipud(arr_u8)
    raw = b"".join(b"\x00" + top[i].tobytes() for i in range(h))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


def np_to_image(name, arr):
    path = os.path.join(TEX_DIR, name + ".png")
    write_png(path, arr)
    if name in bpy.data.images:
        bpy.data.images.remove(bpy.data.images[name])
    img = bpy.data.images.load(path)
    img.name = name
    img.colorspace_settings.name = "sRGB"
    return img


def make_mat(name, albedo):
    if name in bpy.data.materials:
        bpy.data.materials.remove(bpy.data.materials[name])
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (520, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (220, 0)
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.location = (-200, 80)
    tex.image = albedo
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = 0.02
    bsdf.inputs["Roughness"].default_value = 0.94
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.08
    elif "Specular" in bsdf.inputs:
        bsdf.inputs["Specular"].default_value = 0.08
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    mat.use_backface_culling = True
    return mat


def new_obj(name, bm, parent):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.shade_flat()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.parent = parent
    return ob


def prism(name, z0, z1, r0, r1, sides, parent, island):
    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=sides,
        radius1=r0,
        radius2=r1,
        depth=max(z1 - z0, 1e-4),
    )
    mid = (z0 + z1) * 0.5
    for v in bm.verts:
        v.co.z += mid
    ob = new_obj(name, bm, parent)
    ob["uv_island"] = island
    ob["uv_mode"] = "CYL"
    ob["uv_z0"] = float(z0)
    ob["uv_z1"] = float(z1)
    return ob


def rod(name, p0, p1, r, sides, parent, island):
    bm = bmesh.new()
    direction = Vector(p1) - Vector(p0)
    length = max(direction.length, 1e-5)
    bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=sides,
        radius1=r,
        radius2=r * 0.92,
        depth=length,
    )
    quat = Vector((0.0, 0.0, 1.0)).rotation_difference(direction.normalized())
    mat = quat.to_matrix().to_4x4()
    mat.translation = (Vector(p0) + Vector(p1)) * 0.5
    bmesh.ops.transform(bm, matrix=mat, verts=bm.verts)
    ob = new_obj(name, bm, parent)
    ob["uv_island"] = island
    return ob


def uv_box_project(ob, padding=0.06):
    island = ob.get("uv_island", "PAPER")
    u0, v0, u1, v1 = REG[island]
    du, dv = (u1 - u0), (v1 - v0)
    pu, pv = du * padding, dv * padding
    u0p, v0p, u1p, v1p = u0 + pu, v0 + pv, u1 - pu, v1 - pv
    me = ob.data
    TEXEL = 4.2
    bm = bmesh.new()
    bm.from_mesh(me)
    uv_bm = bm.loops.layers.uv.verify()
    for face in bm.faces:
        n = face.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        if az >= ax and az >= ay:

            def proj(c):
                return c.x, c.y
        elif ax >= ay:

            def proj(c):
                return c.y, c.z
        else:

            def proj(c):
                return c.x, c.z

        for loop in face.loops:
            px, py = proj(loop.vert.co)
            fu = (px * TEXEL) % 1.0
            fv = (py * TEXEL) % 1.0
            if fu < 0:
                fu += 1.0
            if fv < 0:
                fv += 1.0
            loop[uv_bm].uv = (u0p + fu * (u1p - u0p), v0p + fv * (v1p - v0p))
    bm.to_mesh(me)
    bm.free()


def uv_cylinder(ob, padding=0.04):
    island = ob.get("uv_island", "PAPER")
    u0, v0, u1, v1 = REG[island]
    du, dv = (u1 - u0), (v1 - v0)
    pu, pv = du * padding, dv * padding
    u0p, v0p, u1p, v1p = u0 + pu, v0 + pv, u1 - pu, v1 - pv
    z0 = float(ob.get("uv_z0", 0.0))
    z1 = float(ob.get("uv_z1", 1.0))
    zspan = max(z1 - z0, 1e-6)
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv_bm = bm.loops.layers.uv.verify()
    for face in bm.faces:
        n = face.normal
        if abs(n.z) > 0.72:
            xs = [l.vert.co.x for l in face.loops]
            ys = [l.vert.co.y for l in face.loops]
            minx, maxx = min(xs), max(xs)
            miny, maxy = min(ys), max(ys)
            for loop in face.loops:
                fu = (loop.vert.co.x - minx) / max(maxx - minx, 1e-6)
                fv = (loop.vert.co.y - miny) / max(maxy - miny, 1e-6)
                loop[uv_bm].uv = (u0p + fu * (u1p - u0p), v0p + fv * (v1p - v0p))
        else:
            for loop in face.loops:
                c = loop.vert.co
                fu = (math.atan2(c.y, c.x) / math.tau) % 1.0
                fv = min(max((c.z - z0) / zspan, 0.0), 1.0)
                loop[uv_bm].uv = (u0p + fu * (u1p - u0p), v0p + fv * (v1p - v0p))
    bm.to_mesh(me)
    bm.free()


def build_dynamite(root):
    parts = []

    # dirty red paper body
    body = prism("Body", 0.014, 0.186, 0.0174, 0.0178, 8, root, "PAPER")
    parts.append(body)

    # folded paper ends
    parts.append(prism("Crimp_Bot", 0.000, 0.018, 0.0152, 0.0178, 8, root, "CRIMP"))
    parts.append(prism("Crimp_Top", 0.180, 0.206, 0.0178, 0.0116, 8, root, "CRIMP"))

    # one dirty twine wrap
    parts.append(prism("Twine", 0.090, 0.100, 0.0186, 0.0186, 8, root, "TWINE"))

    # unlit fuse: short stem then a lazy hook. dark cord, no spark
    p0 = (0.000, 0.000, 0.202)
    p1 = (0.006, 0.004, 0.236)
    p2 = (0.022, 0.001, 0.248)
    parts.append(rod("Fuse_A", p0, p1, 0.0026, 6, root, "CORD"))
    parts.append(rod("Fuse_B", p1, p2, 0.0023, 6, root, "CORD"))
    parts.append(rod("Fuse_Tip", p2, (0.026, 0.000, 0.250), 0.0028, 6, root, "CORD"))

    return parts


def assign_uvs(parts):
    for ob in parts:
        if ob.get("uv_mode") == "CYL":
            uv_cylinder(ob)
        else:
            uv_box_project(ob)


def join_parts(parts, mat):
    for p in parts:
        p.data.materials.clear()
        p.data.materials.append(mat)
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = "FieldDynamite"
    body.data.name = "FieldDynamite"
    return body


def ensure_light(name, loc, energy, color, size=0.25):
    if name in bpy.data.objects:
        ob = bpy.data.objects[name]
    else:
        data = bpy.data.lights.new(name, "AREA")
        ob = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(ob)
    ob.location = loc
    ob.data.energy = energy
    ob.data.color = color
    if hasattr(ob.data, "shadow_soft_size"):
        ob.data.shadow_soft_size = size
    if hasattr(ob.data, "size"):
        ob.data.size = size * 2.2
    return ob


def aim_camera(cam, loc, target):
    cam.location = loc
    direction = Vector(target) - Vector(loc)
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def setup_studio():
    if "StudioGround" not in bpy.data.objects:
        bm = bmesh.new()
        bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=0.8)
        me = bpy.data.meshes.new("StudioGround")
        bm.to_mesh(me)
        bm.free()
        g = bpy.data.objects.new("StudioGround", me)
        bpy.context.collection.objects.link(g)
        gm = bpy.data.materials.new("MAT_StudioGround")
        gm.use_nodes = True
        for n in gm.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED":
                n.inputs["Base Color"].default_value = (0.016, 0.016, 0.018, 1)
                n.inputs["Roughness"].default_value = 0.94
        g.data.materials.append(gm)
    g = bpy.data.objects["StudioGround"]
    g.location = (0, 0, -0.004)

    ensure_light("KeyLight", (0.22, -0.26, 0.32), 38.0, (1.0, 0.96, 0.88), 0.14)
    ensure_light("FillKey", (-0.24, -0.16, 0.18), 10.0, (0.75, 0.85, 1.0), 0.28)
    ensure_light("RimLight", (-0.04, 0.28, 0.22), 18.0, (1.0, 0.72, 0.45), 0.10)
    if "Light" in bpy.data.objects:
        bpy.data.objects["Light"].hide_render = True
        bpy.data.objects["Light"].hide_viewport = True

    cam = bpy.data.objects.get("Camera")
    if cam:
        aim_camera(cam, (0.26, -0.36, 0.18), (0.0, 0.0, 0.12))
        if cam.data:
            cam.data.lens = 50
            cam.data.clip_start = 0.01

    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    if hasattr(scene, "eevee") and hasattr(scene.eevee, "use_raytracing"):
        scene.eevee.use_raytracing = True
    scene.view_settings.view_transform = "AgX"
    try:
        scene.view_settings.look = "AgX - Base Contrast"
    except TypeError:
        pass
    scene.view_settings.exposure = -0.28
    world = scene.world
    if world and world.use_nodes:
        for n in world.node_tree.nodes:
            if n.type == "BACKGROUND":
                n.inputs["Color"].default_value = (0.03, 0.032, 0.036, 1)
                n.inputs["Strength"].default_value = 0.35


def frame_dynamite():
    for area in bpy.context.screen.areas:
        if area.type != "VIEW_3D":
            continue
        for space in area.spaces:
            if space.type != "VIEW_3D":
                continue
            space.shading.type = "MATERIAL"
            space.shading.studiolight_intensity = 1.35
            space.shading.use_scene_lights = False
            space.shading.use_scene_world = False
            space.overlay.show_overlays = False
            r3d = space.region_3d
            r3d.view_perspective = "PERSP"
            r3d.view_location = Vector((0.0, 0.0, 0.12))
            r3d.view_distance = 0.42
            r3d.view_rotation = Euler((1.18, 0.0, 0.70), "XYZ").to_quaternion()


def stats():
    ob = bpy.data.objects.get("FieldDynamite")
    if not ob:
        print("NO DYNAMITE")
        return 0
    me = ob.data
    me.calc_loop_triangles()
    tris = len(me.loop_triangles)
    print(f"FieldDynamite: verts={len(me.vertices)} faces={len(me.polygons)} tris={tris}")
    return tris


def render_shots():
    scene = bpy.context.scene
    scene.render.resolution_x = 960
    scene.render.resolution_y = 720
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    cam = bpy.data.objects.get("Camera")
    if not cam:
        return
    shots = {
        "shot_dynamite_hero": ((0.26, -0.36, 0.18), (0.0, 0.0, 0.12)),
        "shot_dynamite_front": ((0.00, -0.52, 0.13), (0.0, 0.0, 0.12)),
        "shot_dynamite_side": ((0.52, 0.00, 0.13), (0.0, 0.0, 0.12)),
        "shot_dynamite_top": ((0.10, -0.12, 0.30), (0.0, 0.0, 0.21)),
    }
    for name, (loc, target) in shots.items():
        aim_camera(cam, loc, target)
        path = os.path.join(TEX_DIR, name + ".png")
        scene.render.filepath = path
        try:
            bpy.ops.render.render(write_still=True)
            print("RENDERED", path)
        except Exception as exc:
            print("render fail", name, exc)


def run():
    print("=== GENERATE ATLAS ===")
    img, _ = build_atlas()
    albedo = np_to_image("T_FieldDynamite_Atlas", img)
    print("atlas saved", albedo.filepath_raw, img.shape)

    print("=== CLEAR ===")
    clear_old()

    print("=== ROOT ===")
    root = bpy.data.objects.new("FieldDynamite_Root", None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.04
    bpy.context.collection.objects.link(root)

    print("=== MESH ===")
    parts = build_dynamite(root)
    print("parts", len(parts))

    print("=== UV ===")
    assign_uvs(parts)

    print("=== MAT ===")
    mat = make_mat("MAT_FieldDynamite", albedo)

    print("=== JOIN ===")
    body = join_parts(parts, mat)
    body.parent = root
    body.location = (0, 0, 0)
    root.location = (0, 0, 0)

    setup_studio()
    frame_dynamite()
    n = stats()

    try:
        albedo.pack()
    except Exception as exc:
        print("pack fail", exc)

    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    root.select_set(True)
    bpy.context.view_layer.objects.active = root
    glb_path = os.path.join(BLEND_DIR, "FieldDynamite.glb")
    bpy.ops.export_scene.gltf(
        filepath=glb_path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_yup=True,
    )
    print("EXPORTED", glb_path)

    render_shots()
    frame_dynamite()

    out_blend = os.path.join(BLEND_DIR, "FieldDynamite.blend")
    bpy.ops.wm.save_as_mainfile(filepath=out_blend)
    print("SAVED", out_blend)
    return n


if __name__ == "__main__":
    run()
