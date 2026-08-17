"""Rebuild the field hammer as a PS1-style game-ready tool."""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Vector

USER_PROMPT = (
    "creat in blender a hammer with a similar aesthetic and style to the tablet "
    "in C:\\Users\\luigi.manzi\\Documents\\blend also save the model there, "
    "it is meant to be a 3d model for a tool in a game with ps1 style graphics"
)

BLEND_DIR = r"C:\Users\luigi.manzi\Documents\blend"
TEX_DIR = os.path.join(BLEND_DIR, "textures")
sys.path.insert(0, BLEND_DIR)

sys.modules.pop("gen_hammer_atlas", None)
from gen_hammer_atlas import REG, build as build_atlas  # noqa: E402

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
    bsdf.inputs["Metallic"].default_value = 0.08
    bsdf.inputs["Roughness"].default_value = 0.92
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.12
    elif "Specular" in bsdf.inputs:
        bsdf.inputs["Specular"].default_value = 0.12
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


def box(name, center, size, parent, island):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    cx, cy, cz = center
    sx, sy, sz = size
    for v in bm.verts:
        v.co.x = v.co.x * sx + cx
        v.co.y = v.co.y * sy + cy
        v.co.z = v.co.z * sz + cz
    ob = new_obj(name, bm, parent)
    ob["uv_island"] = island
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


def bevel_mesh(ob, width=0.0024, segments=1):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.bevel(
        bm,
        geom=list(bm.edges),
        offset=width,
        offset_type="OFFSET",
        segments=segments,
        affect="EDGES",
        clamp_overlap=True,
    )
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.shade_flat()


def uv_box_project(ob, padding=0.06):
    island = ob.get("uv_island", "HEAD")
    u0, v0, u1, v1 = REG[island]
    du, dv = (u1 - u0), (v1 - v0)
    pu, pv = du * padding, dv * padding
    u0p, v0p, u1p, v1p = u0 + pu, v0 + pv, u1 - pu, v1 - pv
    me = ob.data
    TEXEL = 2.4
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


def uv_cylinder(ob, padding=0.05):
    island = ob.get("uv_island", "HANDLE")
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
                fv = (c.z - z0) / zspan
                fv = min(max(fv, 0.0), 1.0)
                loop[uv_bm].uv = (u0p + fu * (u1p - u0p), v0p + fv * (v1p - v0p))
    bm.to_mesh(me)
    bm.free()


def uv_plate(ob):
    """Front cheek of the nameplate gets the TAC-7 stencil; sides stay olive."""
    u0, v0, u1, v1 = REG["STENCIL"]
    mu0, mv0, mu1, mv1 = REG["HEAD"]
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv_bm = bm.loops.layers.uv.verify()
    front = min(bm.faces, key=lambda f: f.calc_center_median().y)
    for face in bm.faces:
        if face is front:
            xs = [l.vert.co.x for l in face.loops]
            zs = [l.vert.co.z for l in face.loops]
            minx, maxx = min(xs), max(xs)
            minz, maxz = min(zs), max(zs)
            for loop in face.loops:
                fu = (loop.vert.co.x - minx) / max(maxx - minx, 1e-6)
                fv = (loop.vert.co.z - minz) / max(maxz - minz, 1e-6)
                loop[uv_bm].uv = (u0 + fu * (u1 - u0), v0 + fv * (v1 - v0))
        else:
            for loop in face.loops:
                loop[uv_bm].uv = ((mu0 + mu1) * 0.5, (mv0 + mv1) * 0.5)
    bm.to_mesh(me)
    bm.free()


def uv_fit_island(ob, island, axis="xy"):
    u0, v0, u1, v1 = REG[island]
    pad = 0.08
    du, dv = u1 - u0, v1 - v0
    u0p, v0p = u0 + du * pad, v0 + dv * pad
    u1p, v1p = u1 - du * pad, v1 - dv * pad
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv_bm = bm.loops.layers.uv.verify()
    for face in bm.faces:
        if axis == "yz":
            a = [l.vert.co.y for l in face.loops]
            b = [l.vert.co.z for l in face.loops]
            get = lambda c: (c.y, c.z)
        elif axis == "xz":
            a = [l.vert.co.x for l in face.loops]
            b = [l.vert.co.z for l in face.loops]
            get = lambda c: (c.x, c.z)
        else:
            a = [l.vert.co.x for l in face.loops]
            b = [l.vert.co.y for l in face.loops]
            get = lambda c: (c.x, c.y)
        mina, maxa = min(a), max(a)
        minb, maxb = min(b), max(b)
        for loop in face.loops:
            pa, pb = get(loop.vert.co)
            fu = (pa - mina) / max(maxa - mina, 1e-6)
            fv = (pb - minb) / max(maxb - minb, 1e-6)
            loop[uv_bm].uv = (u0p + fu * (u1p - u0p), v0p + fv * (v1p - v0p))
    bm.to_mesh(me)
    bm.free()


def build_hammer(root):
    parts = []
    faces = []

    # one block head, slightly worn striking ends — no plates or stripes
    head = box("Head", (0.0, 0.0, 0.522), (0.124, 0.052, 0.054), root, "HEAD")
    bevel_mesh(head, 0.0060, 1)
    parts.append(head)

    face_l = box("Face_L", (-0.068, 0.0, 0.522), (0.016, 0.044, 0.046), root, "FACE")
    face_r = box("Face_R", (0.068, 0.0, 0.522), (0.016, 0.044, 0.046), root, "FACE")
    bevel_mesh(face_l, 0.0028, 1)
    bevel_mesh(face_r, 0.0028, 1)
    parts.extend([face_l, face_r])
    faces.extend([face_l, face_r])

    # one forged swell where the haft meets the head
    collar = prism("Collar", 0.470, 0.500, 0.0165, 0.0185, 8, root, "HEAD")
    parts.append(collar)

    # one tapered iron haft, origin at the butt
    handle = prism("Handle", 0.000, 0.476, 0.0112, 0.0136, 8, root, "HANDLE")
    parts.append(handle)

    return parts, faces


def assign_uvs(parts, faces):
    face_set = set(faces)
    for ob in parts:
        if ob in face_set:
            uv_fit_island(ob, "FACE", axis="yz")
        elif ob.get("uv_mode") == "CYL":
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
    body.name = "FieldHammer"
    body.data.name = "FieldHammer"
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


def setup_studio():
    if "StudioGround" not in bpy.data.objects:
        bm = bmesh.new()
        bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=1.1)
        me = bpy.data.meshes.new("StudioGround")
        bm.to_mesh(me)
        bm.free()
        g = bpy.data.objects.new("StudioGround", me)
        bpy.context.collection.objects.link(g)
        g.location = (0, 0, -0.01)
        gm = bpy.data.materials.new("MAT_StudioGround")
        gm.use_nodes = True
        nt = gm.node_tree
        for n in nt.nodes:
            if n.type == "BSDF_PRINCIPLED":
                n.inputs["Base Color"].default_value = (0.018, 0.018, 0.02, 1)
                n.inputs["Roughness"].default_value = 0.92
        g.data.materials.append(gm)
    else:
        g = bpy.data.objects["StudioGround"]
        g.location = (0, 0, -0.01)

    ensure_light("KeyLight", (0.36, -0.42, 0.62), 55.0, (1.0, 0.96, 0.88), 0.20)
    ensure_light("FillKey", (-0.40, -0.26, 0.34), 14.0, (0.75, 0.85, 1.0), 0.40)
    ensure_light("RimLight", (-0.08, 0.46, 0.48), 26.0, (1.0, 0.72, 0.45), 0.14)
    if "Light" in bpy.data.objects:
        bpy.data.objects["Light"].hide_render = True
        bpy.data.objects["Light"].hide_viewport = True

    cam = bpy.data.objects.get("Camera")
    if cam:
        aim_camera(cam, (0.72, -0.95, 0.46), (0.0, 0.0, 0.28))
        if cam.data:
            cam.data.lens = 35
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
    scene.view_settings.exposure = -0.30
    world = scene.world
    if world and world.use_nodes:
        for n in world.node_tree.nodes:
            if n.type == "BACKGROUND":
                n.inputs["Color"].default_value = (0.03, 0.032, 0.036, 1)
                n.inputs["Strength"].default_value = 0.35


def frame_hammer():
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
            r3d.view_location = Vector((0.0, 0.0, 0.28))
            r3d.view_distance = 0.92
            r3d.view_rotation = Euler((1.18, 0.0, 0.70), "XYZ").to_quaternion()


def stats():
    ob = bpy.data.objects.get("FieldHammer")
    if not ob:
        print("NO HAMMER")
        return 0
    me = ob.data
    me.calc_loop_triangles()
    tris = len(me.loop_triangles)
    print(f"FieldHammer: verts={len(me.vertices)} faces={len(me.polygons)} tris={tris}")
    return tris


def aim_camera(cam, loc, target):
    cam.location = loc
    direction = Vector(target) - Vector(loc)
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


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
        "shot_hammer_hero": ((0.72, -0.95, 0.46), (0.0, 0.0, 0.28)),
        "shot_hammer_front": ((0.00, -1.35, 0.30), (0.0, 0.0, 0.28)),
        "shot_hammer_side": ((1.35, 0.00, 0.30), (0.0, 0.0, 0.28)),
        "shot_hammer_head": ((0.22, -0.24, 0.58), (0.0, 0.0, 0.53)),
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
    albedo = np_to_image("T_FieldHammer_Atlas", img)
    print("atlas saved", albedo.filepath_raw, img.shape)

    print("=== CLEAR ===")
    clear_old()

    print("=== ROOT ===")
    root = bpy.data.objects.new("FieldHammer_Root", None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.08
    bpy.context.collection.objects.link(root)

    print("=== MESH ===")
    parts, faces = build_hammer(root)
    print("parts", len(parts))

    print("=== UV ===")
    assign_uvs(parts, faces)

    print("=== MAT ===")
    mat = make_mat("MAT_FieldHammer", albedo)

    print("=== JOIN ===")
    body = join_parts(parts, mat)
    body.parent = root
    body.location = (0, 0, 0)
    root.location = (0, 0, 0)

    setup_studio()
    frame_hammer()
    n = stats()

    try:
        albedo.pack()
    except Exception as exc:
        print("pack fail", exc)

    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    root.select_set(True)
    bpy.context.view_layer.objects.active = root
    glb_path = os.path.join(BLEND_DIR, "FieldHammer.glb")
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
    frame_hammer()

    out_blend = os.path.join(BLEND_DIR, "FieldHammer.blend")
    bpy.ops.wm.save_as_mainfile(filepath=out_blend)
    print("SAVED", out_blend)
    return n


if __name__ == "__main__":
    run()
