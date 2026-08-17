"""Rebuild the field tablet as a PS1-style game-ready prop."""
import math
import os
import sys
import bmesh
import bpy
from mathutils import Vector, Matrix, Euler

USER_PROMPT = (
    "there is an imcomplete ps1 style low poly fictional tablet model at -> "
    "C:\\Users\\luigi.manzi\\Documents\\blend  polish it and make it game ready, "
    "you can add and remove txtures change the model etc, make it look really good"
)

BLEND_DIR = r"C:\Users\luigi.manzi\Documents\blend"
TEX_DIR = os.path.join(BLEND_DIR, "textures")
sys.path.insert(0, BLEND_DIR)

from gen_tablet_atlas import build as build_atlas, REG, SIZE  # noqa: E402

KEEP_NAMES = {"Camera", "KeyLight", "FillKey", "RimLight", "Light", "StudioGround"}


def clear_old():
    bpy.ops.object.select_all(action="DESELECT")
    to_delete = [o for o in bpy.data.objects if o.name not in KEEP_NAMES]
    for o in to_delete:
        bpy.data.objects.remove(o, do_unlink=True)
    # leftover meshes/mats we own
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


def make_mat(name, albedo, emit=None, emit_strength=2.8):
    if name in bpy.data.materials:
        mat = bpy.data.materials[name]
        bpy.data.materials.remove(mat)
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
    tex.interpolation = "Closest"  # PS1 nearest-neighbor
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = 0.02
    bsdf.inputs["Roughness"].default_value = 0.94
    bsdf.inputs["Specular IOR Level"].default_value = 0.08
    if emit is not None:
        etex = nt.nodes.new("ShaderNodeTexImage")
        etex.location = (-200, -220)
        etex.image = emit
        etex.interpolation = "Closest"
        nt.links.new(etex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emit_strength
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
    ob.pass_index = 0
    return ob


def box(name, center, size, parent, island, extra=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    cx, cy, cz = center
    sx, sy, sz = size
    for v in bm.verts:
        v.co.x = v.co.x * sx + cx
        v.co.y = v.co.y * sy + cy
        v.co.z = v.co.z * sz + cz
    if extra:
        extra(bm)
    ob = new_obj(name, bm, parent)
    ob["uv_island"] = island
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


def dish(name, hub, radius, parent, island, tilt_deg=-28, yaw_deg=18):
    bm = bmesh.new()
    n = 8
    back = bm.verts.new((0.0, 0.014, 0.0))
    rim = []
    lip = []
    for i in range(n):
        a = i / n * math.tau + math.pi / n
        c, s = math.cos(a), math.sin(a)
        rim.append(bm.verts.new((c * radius, -0.003, s * radius)))
        lip.append(bm.verts.new((c * radius * 1.1, 0.005, s * radius * 1.1)))
    for i in range(n):
        bm.faces.new((back, rim[i], rim[(i + 1) % n]))
        bm.faces.new((rim[i], lip[i], lip[(i + 1) % n], rim[(i + 1) % n]))
    # rotate + translate
    rot = Euler((math.radians(tilt_deg), 0.0, math.radians(yaw_deg)), "XYZ").to_matrix().to_4x4()
    rot.translation = Vector(hub)
    bmesh.ops.transform(bm, matrix=rot, verts=bm.verts)
    ob = new_obj(name, bm, parent)
    ob["uv_island"] = island
    return ob, rot, rim, n, radius


def strut(name, p0, p1, thick, parent, island):
    bm = bmesh.new()
    direction = Vector(p1) - Vector(p0)
    length = direction.length
    if length < 1e-6:
        bm.free()
        return None
    mid = (Vector(p0) + Vector(p1)) * 0.5
    bmesh.ops.create_cube(bm, size=1.0)
    # scale to rod
    for v in bm.verts:
        v.co.x *= thick
        v.co.y *= length
        v.co.z *= thick
    # default cube Y is along local Y; rotate Y to direction
    quat = Vector((0, 1, 0)).rotation_difference(direction.normalized())
    mat = quat.to_matrix().to_4x4()
    mat.translation = mid
    bmesh.ops.transform(bm, matrix=mat, verts=bm.verts)
    ob = new_obj(name, bm, parent)
    ob["uv_island"] = island
    return ob


def uv_box_project(ob, padding=0.06):
    island = ob.get("uv_island", "OLIVE")
    u0, v0, u1, v1 = REG[island]
    du, dv = (u1 - u0), (v1 - v0)
    pu, pv = du * padding, dv * padding
    u0p, v0p, u1p, v1p = u0 + pu, v0 + pv, u1 - pu, v1 - pv
    me = ob.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv_layer = me.uv_layers.active
    # need loops
    if not me.polygons:
        return
    # per-face box project using object-space bounds of that face
    # first gather loop uvs via bmesh
    bm = bmesh.new()
    bm.from_mesh(me)
    uv_bm = bm.loops.layers.uv.verify()
    # object bounds for stable scale
    coords = [v.co.copy() for v in bm.verts]
    if not coords:
        bm.free()
        return
    # project each face onto its two dominant axes, fit into island
    for face in bm.faces:
        n = face.normal
        ax = abs(n.x)
        ay = abs(n.y)
        az = abs(n.z)
        if az >= ax and az >= ay:
            def proj(c):
                return c.x, c.y
        elif ax >= ay:
            def proj(c):
                return c.y, c.z
        else:
            def proj(c):
                return c.x, c.z
        pts = [proj(l.vert.co) for l in face.loops]
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        minx, maxx = min(xs), max(xs)
        miny, maxy = min(ys), max(ys)
        # keep aspect inside island, leave a little margin so faces don't stretch wildly
        spanx = max(maxx - minx, 1e-6)
        spany = max(maxy - miny, 1e-6)
        # map the larger faces across more of the island; small faces stay small
        # Use a global scale based on typical body size so texel density is even
        # 0.26m body -> full olive 0.5 UV is too much stretch if we fit each face.
        # Better: world-to-UV scale constant.
    bm.free()

    # redo with constant texel density
    TEXEL = 1.6  # UV units per meter, then placed into island with wrap
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
            # tile within island
            fu = (px * TEXEL) % 1.0
            fv = (py * TEXEL) % 1.0
            if fu < 0:
                fu += 1.0
            if fv < 0:
                fv += 1.0
            loop[uv_bm].uv = (u0p + fu * (u1p - u0p), v0p + fv * (v1p - v0p))
    bm.to_mesh(me)
    bm.free()


def uv_front_screen(ob):
    """Map the front-most face (min Y) to the full SCREEN island."""
    u0, v0, u1, v1 = REG["SCREEN"]
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv_bm = bm.loops.layers.uv.verify()
    # find front face
    front = min(bm.faces, key=lambda f: f.calc_center_median().y)
    # all faces: front gets screen, others get dark metal edge
    mu0, mv0, mu1, mv1 = REG["METAL"]
    for face in bm.faces:
        if face == front:
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


def uv_led(ob, which):
    # LEDS region has 3 pads at local pixel positions
    # pads at x 8,48,88 and y 16 in a 128x64 region
    u0, v0, u1, v1 = REG["LEDS"]
    # pad centers in 0-1 of LEDS
    # region is 128x64 px. pads 28px at x=8/48/88, y=16
    centers = {
        "G": (8 + 14, 16 + 14),
        "A": (48 + 14, 16 + 14),
        "R": (88 + 14, 16 + 14),
    }
    cx, cy = centers[which]
    # LEDS is 0.25 x 0.125 UV, 128 x 64 px
    fu = cx / 128.0
    fv = cy / 64.0
    half = 10 / 128.0
    halfv = 10 / 64.0
    uu0 = u0 + (fu - half) * (u1 - u0) / 1.0
    # wait: fu is already 0-1 of the region
    uu0 = u0 + (fu - half)
    # fu is in 0-1 of 128px region which IS the LEDS uv width 0.25? 
    # REG LEDS is 0.50-0.75 so width 0.25. 128/512=0.25. So 1 px = 1/512 UV.
    # cx is in pixels of the region, not 0-1.
    # Let's do it in absolute UV.
    # LEDS px: x0=256, y0=192  (bottom-left origin) size 128x64
    # pad G: x=256+8+4 to 256+8+24 ...
    # simpler: map whole object to the inner 20px of the pad
    pads_uv = {
        "G": (0.50 + 12 / 512, 0.375 + 20 / 512, 0.50 + 32 / 512, 0.375 + 40 / 512),
        "A": (0.50 + 52 / 512, 0.375 + 20 / 512, 0.50 + 72 / 512, 0.375 + 40 / 512),
        "R": (0.50 + 92 / 512, 0.375 + 20 / 512, 0.50 + 112 / 512, 0.375 + 40 / 512),
    }
    ru0, rv0, ru1, rv1 = pads_uv[which]
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uv_bm = bm.loops.layers.uv.verify()
    # front face
    for face in bm.faces:
        xs = [l.vert.co.x for l in face.loops]
        zs = [l.vert.co.z for l in face.loops]
        minx, maxx = min(xs), max(xs)
        minz, maxz = min(zs), max(zs)
        for loop in face.loops:
            fu = (loop.vert.co.x - minx) / max(maxx - minx, 1e-6)
            fv = (loop.vert.co.z - minz) / max(maxz - minz, 1e-6)
            loop[uv_bm].uv = (ru0 + fu * (ru1 - ru0), rv0 + fv * (rv1 - rv0))
    bm.to_mesh(me)
    bm.free()


def uv_nameplate(ob):
    # crop to the TAC-7 glyph block inside STENCIL
    u0 = 0.25 + 6 / 512.0
    v0 = 0.375 + 32 / 512.0
    u1 = 0.25 + 90 / 512.0
    v1 = 0.375 + 58 / 512.0
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
            uo, vo, u1b, v1b = REG["OLIVE"]
            for loop in face.loops:
                loop[uv_bm].uv = ((uo + u1b) * 0.5, (vo + v1b) * 0.5)
    bm.to_mesh(me)
    bm.free()


def build_tablet(root):
    parts = []

    # --- chassis ---
    body = box("Body", (0, 0.002, 0.086), (0.248, 0.046, 0.172), root, "OLIVE")
    bevel_mesh(body, 0.004, 1)
    parts.append(body)

    # frame bezel around the CRT (four strips — never a solid slab)
    fy = -0.0242
    parts.append(box("Bezel_T", (0.0, fy, 0.152), (0.220, 0.007, 0.012), root, "METAL"))
    parts.append(box("Bezel_B", (0.0, fy, 0.048), (0.220, 0.007, 0.012), root, "METAL"))
    parts.append(box("Bezel_L", (-0.104, fy, 0.100), (0.012, 0.007, 0.092), root, "METAL"))
    parts.append(box("Bezel_R", (0.104, fy, 0.100), (0.012, 0.007, 0.092), root, "METAL"))

    # dark well visible in the 2mm gap between bezel and glass
    parts.append(box("ScreenWell", (0.0, -0.0214, 0.100), (0.196, 0.003, 0.092), root, "METAL"))

    # CRT sits in front of the body, inside the frame
    screen = box("Screen", (0.0, -0.0256, 0.100), (0.188, 0.0020, 0.084), root, "SCREEN")
    parts.append(screen)

    # control deck plate under screen
    deck = box("Deck", (0, -0.022, 0.028), (0.220, 0.006, 0.032), root, "OLIVE")
    bevel_mesh(deck, 0.0015, 1)
    parts.append(deck)

    # d-pad
    parts.append(box("DPad_H", (-0.074, -0.0272, 0.028), (0.032, 0.006, 0.012), root, "RUBBER"))
    parts.append(box("DPad_V", (-0.074, -0.0272, 0.028), (0.012, 0.006, 0.032), root, "RUBBER"))
    parts.append(box("DPad_Nub", (-0.074, -0.0300, 0.028), (0.008, 0.003, 0.008), root, "METAL"))

    # four function keys
    for i, (nm, island) in enumerate(
        (("Key_1", "AMBER"), ("Key_2", "AMBER"), ("Key_3", "RED"), ("Key_4", "METAL"))
    ):
        x = -0.018 + i * 0.028
        parts.append(box(nm, (x, -0.0265, 0.028), (0.020, 0.0045, 0.014), root, island))

    # rubber corner bumpers (front)
    bumper_specs = [
        ("Bump_FL", (-0.122, -0.022, 0.018), (0.018, 0.016, 0.022), "RUBBER"),
        ("Bump_FR", (0.122, -0.022, 0.018), (0.018, 0.016, 0.022), "STRIPES"),
        ("Bump_TL", (-0.122, -0.022, 0.154), (0.018, 0.016, 0.022), "RUBBER"),
        ("Bump_TR", (0.122, -0.022, 0.154), (0.018, 0.016, 0.022), "RUBBER"),
        # rear bumpers
        ("Bump_BL", (-0.122, 0.022, 0.018), (0.016, 0.012, 0.018), "RUBBER"),
        ("Bump_BR", (0.122, 0.022, 0.018), (0.016, 0.012, 0.018), "RUBBER"),
        ("Bump_BTL", (-0.122, 0.022, 0.154), (0.016, 0.012, 0.018), "RUBBER"),
        ("Bump_BTR", (0.122, 0.022, 0.154), (0.016, 0.012, 0.018), "RUBBER"),
    ]
    for nm, c, s, isl in bumper_specs:
        b = box(nm, c, s, root, isl)
        bevel_mesh(b, 0.002, 1)
        parts.append(b)

    # side rails
    rail_l = box("Rail_L", (-0.128, 0.0, 0.086), (0.008, 0.036, 0.110), root, "RUST")
    rail_r = box("Rail_R", (0.128, 0.0, 0.086), (0.008, 0.036, 0.110), root, "STRIPES")
    bevel_mesh(rail_l, 0.0014, 1)
    bevel_mesh(rail_r, 0.0014, 1)
    parts.append(rail_l)
    parts.append(rail_r)

    # left controls
    parts.append(box("Btn_A", (-0.136, 0.0, 0.128), (0.012, 0.016, 0.016), root, "RED"))
    parts.append(box("Btn_B", (-0.136, 0.0, 0.106), (0.012, 0.016, 0.016), root, "AMBER"))
    parts.append(box("Lever_Base", (-0.134, 0.0, 0.068), (0.010, 0.016, 0.014), root, "METAL"))
    # lever thrown forward
    parts.append(box("Lever_Arm", (-0.138, -0.010, 0.068), (0.005, 0.022, 0.008), root, "RUBBER"))
    parts.append(box("Lever_Knob", (-0.138, -0.022, 0.066), (0.010, 0.008, 0.010), root, "AMBER"))

    # right controls
    kn = box("Knob", (0.138, 0.0, 0.128), (0.012, 0.020, 0.020), root, "RUBBER")
    # make knob 8-sided-ish by not beveling much
    bevel_mesh(kn, 0.002, 1)
    parts.append(kn)
    parts.append(box("Knob_Notch", (0.144, -0.008, 0.134), (0.003, 0.004, 0.006), root, "METAL"))
    parts.append(box("Slider_Track", (0.134, 0.0, 0.092), (0.004, 0.012, 0.032), root, "METAL"))
    parts.append(box("Slider_Thumb", (0.138, 0.0, 0.098), (0.010, 0.016, 0.010), root, "AMBER"))
    tg = box("Toggle", (0.138, 0.0, 0.058), (0.010, 0.014, 0.014), root, "RUBBER")
    bevel_mesh(tg, 0.002, 1)
    parts.append(tg)

    # top handle (left) — chunky carry grip
    parts.append(box("Handle_PostL", (-0.096, 0.0, 0.184), (0.014, 0.018, 0.024), root, "METAL"))
    parts.append(box("Handle_PostR", (-0.040, 0.0, 0.184), (0.014, 0.018, 0.024), root, "METAL"))
    hb = box("Handle_Bar", (-0.068, 0.0, 0.200), (0.074, 0.020, 0.016), root, "RUBBER")
    bevel_mesh(hb, 0.0024, 1)
    parts.append(hb)

    plate = None
    spk = None

    # status LEDs on the top bezel, in front of the frame
    led_g = box("LED_G", (-0.090, -0.0292, 0.152), (0.010, 0.0036, 0.007), root, "LEDS")
    led_a = box("LED_A", (-0.076, -0.0292, 0.152), (0.010, 0.0036, 0.007), root, "LEDS")
    led_r = box("LED_R", (-0.062, -0.0292, 0.152), (0.010, 0.0036, 0.007), root, "LEDS")
    parts.extend([led_g, led_a, led_r])

    # screws
    for i, (x, z) in enumerate(((-0.108, 0.148), (0.108, 0.148), (-0.108, 0.050), (0.108, 0.050))):
        sc = box(f"Screw_{i}", (x, -0.0255, z), (0.006, 0.003, 0.006), root, "METAL")
        parts.append(sc)

    # back battery pack
    bat = box("Battery", (0.0, 0.028, 0.078), (0.180, 0.014, 0.100), root, "OLIVE")
    bevel_mesh(bat, 0.003, 1)
    parts.append(bat)
    # battery latch
    parts.append(box("BatLatch", (0.0, 0.036, 0.118), (0.036, 0.006, 0.012), root, "METAL"))
    # vents as thin slots
    for i in range(4):
        parts.append(
            box(f"Vent_{i}", (-0.050 + i * 0.034, 0.0355, 0.062), (0.024, 0.002, 0.006), root, "METAL")
        )

    # bottom feet
    for i, x in enumerate((-0.092, 0.092)):
        for j, y in enumerate((-0.012, 0.014)):
            parts.append(box(f"Foot_{i}{j}", (x, y, 0.003), (0.016, 0.014, 0.006), root, "RUBBER"))

    # bottom ports
    parts.append(box("PortBlock", (0.070, 0.0, 0.004), (0.048, 0.024, 0.008), root, "METAL"))
    parts.append(box("Port_A", (0.056, -0.012, 0.001), (0.010, 0.008, 0.005), root, "BLACK" if False else "METAL"))
    parts.append(box("Port_B", (0.070, -0.012, 0.001), (0.010, 0.008, 0.005), root, "RUBBER"))
    parts.append(box("Port_C", (0.084, -0.012, 0.001), (0.010, 0.008, 0.005), root, "AMBER"))

    # strap loops
    parts.append(box("Loop_L", (-0.126, 0.0, 0.168), (0.006, 0.012, 0.010), root, "METAL"))
    parts.append(box("Loop_R", (0.126, 0.0, 0.168), (0.006, 0.012, 0.010), root, "METAL"))

    # --- antenna ---
    mount = box("Ant_Mount", (0.086, 0.002, 0.180), (0.030, 0.022, 0.014), root, "RUST")
    bevel_mesh(mount, 0.0018, 1)
    parts.append(mount)
    pole = box("Ant_Pole", (0.090, -0.002, 0.196), (0.010, 0.012, 0.022), root, "RUST")
    parts.append(pole)
    hub_pos = (0.094, -0.006, 0.214)
    hub = box("Ant_Hub", hub_pos, (0.014, 0.014, 0.012), root, "METAL")
    parts.append(hub)

    dish_ob, dish_xf, _rim, n, radius = dish("Ant_Dish", hub_pos, 0.040, root, "RUST", -32, 16)
    parts.append(dish_ob)

    # compute 3 rim points in world/local
    rim_local = []
    for i in (0, 3, 5):
        a = i / 8 * math.tau + math.pi / 8
        p = dish_xf @ Vector((math.cos(a) * 0.040, -0.003, math.sin(a) * 0.040))
        rim_local.append(p)
    for i, p in enumerate(rim_local):
        s = strut(f"Ant_Strut_{i}", hub_pos, p, 0.0026, root, "METAL")
        if s:
            parts.append(s)

    # LNB at focus, in front of dish
    lnb_p = dish_xf @ Vector((0.0, -0.034, 0.0))
    lnb = box("Ant_LNB", tuple(lnb_p), (0.010, 0.014, 0.010), root, "METAL")
    parts.append(lnb)
    cap_p = dish_xf @ Vector((0.0, -0.042, 0.0))
    parts.append(box("Ant_LNB_Cap", tuple(cap_p), (0.008, 0.006, 0.008), root, "AMBER"))

    # feed arm
    feed = strut("Ant_Feed", hub_pos, tuple(lnb_p), 0.0024, root, "METAL")
    if feed:
        parts.append(feed)

    return parts, screen, plate, led_g, led_a, led_r, spk


def assign_uvs(parts, screen, plate, led_g, led_a, led_r, spk):
    for ob in parts:
        if ob == screen:
            uv_front_screen(ob)
        elif plate is not None and ob == plate:
            uv_nameplate(ob)
        elif ob == led_g:
            uv_led(ob, "G")
        elif ob == led_a:
            uv_led(ob, "A")
        elif ob == led_r:
            uv_led(ob, "R")
        elif spk is not None and ob == spk:
            # front face to speaker island
            u0, v0, u1, v1 = REG["SPEAKER"]
            me = ob.data
            bm = bmesh.new()
            bm.from_mesh(me)
            uv_bm = bm.loops.layers.uv.verify()
            front = min(bm.faces, key=lambda f: f.calc_center_median().y)
            for face in bm.faces:
                xs = [l.vert.co.x for l in face.loops]
                zs = [l.vert.co.z for l in face.loops]
                minx, maxx = min(xs), max(xs)
                minz, maxz = min(zs), max(zs)
                for loop in face.loops:
                    fu = (loop.vert.co.x - minx) / max(maxx - minx, 1e-6)
                    fv = (loop.vert.co.z - minz) / max(maxz - minz, 1e-6)
                    if face is front:
                        loop[uv_bm].uv = (u0 + fu * (u1 - u0), v0 + fv * (v1 - v0))
                    else:
                        loop[uv_bm].uv = ((u0 + u1) * 0.5, (v0 + v1) * 0.5)
            bm.to_mesh(me)
            bm.free()
        else:
            uv_box_project(ob)


def join_parts(parts, mat_body, mat_screen, screen):
    # two objects: body (everything except screen) and screen
    body_parts = [p for p in parts if p != screen]
    # assign mats first
    for p in body_parts:
        p.data.materials.clear()
        p.data.materials.append(mat_body)
    screen.data.materials.clear()
    screen.data.materials.append(mat_screen)

    bpy.ops.object.select_all(action="DESELECT")
    for p in body_parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = body_parts[0]
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = "FieldTablet_Body"
    body.data.name = "FieldTablet_Body"
    screen.name = "FieldTablet_Screen"
    screen.data.name = "FieldTablet_Screen"
    return body, screen


def setup_origin(body, screen, root):
    # origin at bottom center (0,0,0) already in verts. set object loc 0
    body.location = (0, 0, 0)
    screen.location = (0, 0, 0)
    root.location = (0, 0, 0)


def setup_studio():
    # ground
    if "StudioGround" in bpy.data.objects:
        g = bpy.data.objects["StudioGround"]
        g.location = (0, 0, 0)
        if g.data.materials:
            m = g.data.materials[0]
            if m and m.use_nodes:
                for n in m.node_tree.nodes:
                    if n.type == "BSDF_PRINCIPLED":
                        n.inputs["Base Color"].default_value = (0.018, 0.018, 0.02, 1)
                        n.inputs["Roughness"].default_value = 0.92
    # lights
    def set_light(name, loc, energy, color, size=0.25):
        if name not in bpy.data.objects:
            return
        ob = bpy.data.objects[name]
        ob.location = loc
        if ob.data:
            ob.data.energy = energy
            ob.data.color = color
            if hasattr(ob.data, "shadow_soft_size"):
                ob.data.shadow_soft_size = size

    set_light("KeyLight", (0.28, -0.34, 0.36), 45.0, (1.0, 0.96, 0.88), 0.18)
    set_light("FillKey", (-0.32, -0.22, 0.24), 12.0, (0.75, 0.85, 1.0), 0.35)
    set_light("RimLight", (-0.05, 0.36, 0.28), 22.0, (1.0, 0.72, 0.45), 0.12)
    if "Light" in bpy.data.objects:
        bpy.data.objects["Light"].hide_render = True
        bpy.data.objects["Light"].hide_viewport = True

    cam = bpy.data.objects.get("Camera")
    if cam:
        cam.location = (0.30, -0.34, 0.22)
        cam.rotation_euler = (1.20, 0.0, 0.70)
        if cam.data:
            cam.data.lens = 50
            cam.data.clip_start = 0.01

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.eevee.use_raytracing = True
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Base Contrast"
    scene.view_settings.exposure = -0.35
    # world
    world = scene.world
    if world and world.use_nodes:
        for n in world.node_tree.nodes:
            if n.type == "BACKGROUND":
                n.inputs["Color"].default_value = (0.03, 0.032, 0.036, 1)
                n.inputs["Strength"].default_value = 0.35

    for area in bpy.context.screen.areas:
        if area.type == "VIEW_3D":
            for space in area.spaces:
                if space.type == "VIEW_3D":
                    space.shading.type = "MATERIAL"
                    space.overlay.show_overlays = False
                    space.region_3d.view_perspective = "PERSP"


def frame_tablet():
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
            r3d.view_location = Vector((0.0, 0.0, 0.10))
            r3d.view_distance = 0.46
            r3d.view_rotation = Euler((1.15, 0.0, 0.72), "XYZ").to_quaternion()


def stats():
    total_tris = 0
    for name in ("FieldTablet_Body", "FieldTablet_Screen"):
        ob = bpy.data.objects.get(name)
        if not ob:
            continue
        me = ob.data
        me.calc_loop_triangles()
        tris = len(me.loop_triangles)
        total_tris += tris
        print(f"{name}: verts={len(me.vertices)} faces={len(me.polygons)} tris={tris} mats={list(me.materials)}")
    print("TOTAL TRIS", total_tris)
    return total_tris


def run():
    print("=== GENERATE ATLAS ===")
    img, emit, _ = build_atlas()
    albedo = np_to_image("T_FieldTablet_Atlas", img)
    emission = np_to_image("T_FieldTablet_Emit", emit)
    print("atlas saved", albedo.filepath_raw, img.shape, emit.shape)

    print("=== CLEAR ===")
    clear_old()

    print("=== ROOT ===")
    root = bpy.data.objects.new("FieldTablet", None)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.08
    bpy.context.collection.objects.link(root)

    print("=== MESH ===")
    parts, screen, plate, led_g, led_a, led_r, spk = build_tablet(root)
    print("parts", len(parts))

    print("=== UV ===")
    assign_uvs(parts, screen, plate, led_g, led_a, led_r, spk)

    print("=== MATS ===")
    mat_body = make_mat("MAT_FieldTablet", albedo, emit=emission, emit_strength=0.85)
    mat_screen = make_mat("MAT_FieldTablet_Screen", albedo, emit=emission, emit_strength=3.2)
    # screen also uses atlas albedo so the CRT art is visible even without bloom

    print("=== JOIN ===")
    body, screen = join_parts(parts, mat_body, mat_screen, screen)
    setup_origin(body, screen, root)

    # parent
    body.parent = root
    screen.parent = root

    setup_studio()
    frame_tablet()
    n = stats()

    # pack textures into blend
    for im in (albedo, emission):
        if im:
            try:
                im.pack()
            except Exception as exc:
                print("pack fail", im.name, exc)

    # export glb (game-ready)
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    screen.select_set(True)
    root.select_set(True)
    bpy.context.view_layer.objects.active = root
    glb_path = os.path.join(BLEND_DIR, "FieldTablet.glb")
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

    # also write a copy next to the original Untitled
    out_blend = os.path.join(BLEND_DIR, "FieldTablet.blend")
    bpy.ops.wm.save_as_mainfile(filepath=out_blend)
    print("SAVED", out_blend)
    return n


if __name__ == "__main__":
    run()
