class_name RomanMeshes
extends RefCounted
## Procedural Roman architecture, ported from buildRomanModuleMesh() in the HTML.
##
## Each module is baked once into a single ArrayMesh (one surface per material)
## plus a list of collision shapes in module-local space. Tiles then cost one
## MeshInstance3D while popping in, and whole chunks get merged afterwards.
##
## Local tile frame: [-2, 2] x [-2, 2], N = -Z, E = +X, S = +Z, W = -X.

const SOLID_MIN_TOP := 0.45   # parts whose top is below this are walk-over decoration
const SOLID_MAX_BOTTOM := 2.3 # parts floating above head height don't need collision

static var mats: Dictionary = {}
static var shape_cache: Dictionary = {}
static var _modules: Dictionary = {}   # id -> {"mesh": ArrayMesh, "shapes": Array[[Shape3D, Transform3D]]}


static func _mat(hex: String, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = rough
	m.metallic = metal
	return m


static func setup() -> void:
	if not mats.is_empty():
		return
	mats["travertine"] = _mat("#eadfcd", 0.85, 0.04)
	mats["marble"] = _mat("#f7f2e9", 0.55, 0.06)
	mats["plaster"] = _mat("#f2e6d5", 0.9, 0.02)
	mats["stuccoWarm"] = _mat("#e6cbb1", 0.88, 0.02)
	mats["brick"] = _mat("#c26a4a", 0.86, 0.03)
	mats["terracotta"] = _mat("#b84a24", 0.78, 0.05)
	mats["terracottaDark"] = _mat("#933617", 0.82, 0.04)
	mats["basalt"] = _mat("#56504b", 0.92, 0.05)
	mats["basaltLight"] = _mat("#736b64", 0.88, 0.04)
	mats["soil"] = _mat("#c9b597", 0.96, 0.0)
	mats["grass"] = _mat("#6b8b55", 0.92, 0.0)
	mats["cypressDark"] = _mat("#1d4b37", 0.88, 0.02)
	mats["cypressMid"] = _mat("#2b6349", 0.85, 0.02)
	mats["wood"] = _mat("#6f4b32", 0.86, 0.03)
	mats["bronze"] = _mat("#c5973d", 0.35, 0.75)
	var water := _mat("#288c80", 0.18, 0.15)
	water.emission_enabled = true
	water.emission = Color("#0c332f")
	water.emission_energy_multiplier = 0.35
	mats["water"] = water
	var win := _mat("#3b2a20", 0.4, 0.0)
	win.emission_enabled = true
	win.emission = Color("#ffb347")
	win.emission_energy_multiplier = 0.15
	mats["windowGlow"] = win
	var fire := _mat("#ff9b26", 0.3, 0.0)
	fire.emission_enabled = true
	fire.emission = Color("#ff6a00")
	fire.emission_energy_multiplier = 0.9
	mats["brazierFire"] = fire
	mats["ground"] = _mat("#b9a383", 0.97, 0.0)


static func prewarm() -> void:
	setup()
	for mod: Dictionary in WfcData.BASE_MODULES:
		get_module(mod["id"])


static func get_module(id: String) -> Dictionary:
	if not _modules.has(id):
		setup()
		var b := Baker.new()
		_build(b, id)
		_modules[id] = {"mesh": b.commit(), "shapes": b.shapes}
	return _modules[id]


## Transform of a tile (cell + variant rotation) in world space.
static func tile_transform(cell: Vector2i, rot: int) -> Transform3D:
	# Clockwise rotation: rot=1 maps local N (-Z) to E (+X) -> rotation.y = -PI/2
	return Transform3D(Basis(Vector3.UP, -rot * PI * 0.5), WfcWorld.cell_center(cell))


# ===========================================================================
# Baker: geometry primitives written straight into per-material SurfaceTools
# ===========================================================================
class Baker:
	var sts: Dictionary = {}     # Material -> SurfaceTool
	var shapes: Array = []       # [Shape3D, Transform3D]

	func _st(mat: Material) -> SurfaceTool:
		if not sts.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			sts[mat] = st
		return sts[mat]

	func commit() -> ArrayMesh:
		var am := ArrayMesh.new()
		for mat: Material in sts:
			var st: SurfaceTool = sts[mat]
			st.commit(am)
			am.surface_set_material(am.get_surface_count() - 1, mat)
		return am

	# Godot treats clockwise winding as front-facing. Orient each triangle so its
	# front side faces along the supplied normals.
	static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
		var face := (b - a).cross(c - a)
		if face.dot(na + nb + nc) > 0.0:
			var t := b; b = c; c = t
			var tn := nb; nb = nc; nc = tn
		st.set_normal(na); st.add_vertex(a)
		st.set_normal(nb); st.add_vertex(b)
		st.set_normal(nc); st.add_vertex(c)

	static func _nbasis(xf: Transform3D) -> Basis:
		return xf.basis.inverse().transposed()

	# ---------------------------------------------------------------- box
	func box(w: float, h: float, d: float, x: float, y: float, z: float, mat_name: String, solid := true) -> void:
		var mat: Material = RomanMeshes.mats[mat_name]
		var xf := Transform3D(Basis(), Vector3(x, y, z))
		_box_xf(_st(mat), Vector3(w, h, d), xf)
		if solid and mat_name != "windowGlow" and mat_name != "water":
			_maybe_shape_box(Vector3(w, h, d), xf)

	static func _box_xf(st: SurfaceTool, size: Vector3, xf: Transform3D) -> void:
		var hx := size.x * 0.5
		var hy := size.y * 0.5
		var hz := size.z * 0.5
		var nbs := _nbasis(xf)
		var faces := [
			[Vector3(1, 0, 0), [Vector3(hx, -hy, -hz), Vector3(hx, hy, -hz), Vector3(hx, hy, hz), Vector3(hx, -hy, hz)]],
			[Vector3(-1, 0, 0), [Vector3(-hx, -hy, hz), Vector3(-hx, hy, hz), Vector3(-hx, hy, -hz), Vector3(-hx, -hy, -hz)]],
			[Vector3(0, 1, 0), [Vector3(-hx, hy, -hz), Vector3(-hx, hy, hz), Vector3(hx, hy, hz), Vector3(hx, hy, -hz)]],
			[Vector3(0, -1, 0), [Vector3(-hx, -hy, hz), Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz), Vector3(hx, -hy, hz)]],
			[Vector3(0, 0, 1), [Vector3(-hx, -hy, hz), Vector3(hx, -hy, hz), Vector3(hx, hy, hz), Vector3(-hx, hy, hz)]],
			[Vector3(0, 0, -1), [Vector3(hx, -hy, -hz), Vector3(-hx, -hy, -hz), Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz)]],
		]
		for f: Array in faces:
			var n: Vector3 = (nbs * (f[0] as Vector3)).normalized()
			var p: Array = f[1]
			var a: Vector3 = xf * (p[0] as Vector3)
			var b: Vector3 = xf * (p[1] as Vector3)
			var c: Vector3 = xf * (p[2] as Vector3)
			var e: Vector3 = xf * (p[3] as Vector3)
			tri(st, a, b, c, n, n, n)
			tri(st, a, c, e, n, n, n)

	func _maybe_shape_box(size: Vector3, xf: Transform3D) -> void:
		var top := xf.origin.y + size.y * 0.5
		var bottom := xf.origin.y - size.y * 0.5
		if top < RomanMeshes.SOLID_MIN_TOP or bottom > RomanMeshes.SOLID_MAX_BOTTOM:
			return
		var key := "b%.3f_%.3f_%.3f" % [size.x, size.y, size.z]
		if not RomanMeshes.shape_cache.has(key):
			var s := BoxShape3D.new()
			s.size = size
			RomanMeshes.shape_cache[key] = s
		shapes.append([RomanMeshes.shape_cache[key], xf])

	# ---------------------------------------------------------------- cylinder
	func cyl(rt: float, rb: float, h: float, x: float, y: float, z: float, mat_name: String, seg := 10, solid := true) -> void:
		var st := _st(RomanMeshes.mats[mat_name])
		var xf := Transform3D(Basis(), Vector3(x, y, z))
		var hy := h * 0.5
		var slope := (rb - rt) / maxf(h, 0.0001)
		var top_c := xf * Vector3(0, hy, 0)
		var bot_c := xf * Vector3(0, -hy, 0)
		for i in seg:
			var a0 := TAU * float(i) / seg
			var a1 := TAU * float(i + 1) / seg
			var c0 := Vector3(cos(a0), 0, sin(a0))
			var c1 := Vector3(cos(a1), 0, sin(a1))
			var t0 := xf * (c0 * rt + Vector3(0, hy, 0))
			var t1 := xf * (c1 * rt + Vector3(0, hy, 0))
			var b0 := xf * (c0 * rb + Vector3(0, -hy, 0))
			var b1 := xf * (c1 * rb + Vector3(0, -hy, 0))
			var n0 := Vector3(c0.x, slope, c0.z).normalized()
			var n1 := Vector3(c1.x, slope, c1.z).normalized()
			if rt > 0.0001:
				tri(st, t0, b0, b1, n0, n0, n1)
				tri(st, t0, b1, t1, n0, n1, n1)
				tri(st, top_c, t0, t1, Vector3.UP, Vector3.UP, Vector3.UP)
			else:
				tri(st, t0, b0, b1, n0, n0, n1)
			if rb > 0.0001:
				tri(st, bot_c, b1, b0, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN)
		if solid:
			var top := y + hy
			var bottom := y - hy
			if top >= RomanMeshes.SOLID_MIN_TOP and bottom <= RomanMeshes.SOLID_MAX_BOTTOM:
				var r := maxf(rt, rb)
				var key := "c%.3f_%.3f" % [r, h]
				if not RomanMeshes.shape_cache.has(key):
					var s := CylinderShape3D.new()
					s.radius = r
					s.height = h
					RomanMeshes.shape_cache[key] = s
				shapes.append([RomanMeshes.shape_cache[key], xf])

	# ---------------------------------------------------------------- sphere
	func sphere(r: float, wseg: int, hseg: int, pos: Vector3, scl: Vector3, mat_name: String, theta_len := PI) -> void:
		var st := _st(RomanMeshes.mats[mat_name])
		var xf := Transform3D(Basis.from_scale(scl), pos)
		var nbs := _nbasis(xf)
		var rows: Array = []
		for iy in hseg + 1:
			var th := theta_len * float(iy) / hseg
			var row: Array = []
			for ix in wseg + 1:
				var ph := TAU * float(ix) / wseg
				var p := Vector3(-cos(ph) * sin(th), cos(th), sin(ph) * sin(th))
				row.append(p)
			rows.append(row)
		for iy in hseg:
			for ix in wseg:
				var p00: Vector3 = rows[iy][ix]
				var p01: Vector3 = rows[iy][ix + 1]
				var p10: Vector3 = rows[iy + 1][ix]
				var p11: Vector3 = rows[iy + 1][ix + 1]
				var n00 := (nbs * p00).normalized()
				var n01 := (nbs * p01).normalized()
				var n10 := (nbs * p10).normalized()
				var n11 := (nbs * p11).normalized()
				if iy > 0:
					tri(st, xf * (p00 * r), xf * (p10 * r), xf * (p01 * r), n00, n10, n01)
				tri(st, xf * (p01 * r), xf * (p10 * r), xf * (p11 * r), n01, n10, n11)
		if theta_len < PI - 0.01:
			# close hemisphere base
			var yb := cos(theta_len)
			var c := xf * Vector3(0, yb * r, 0)
			var last: Array = rows[hseg]
			var nd := (nbs * Vector3.DOWN).normalized()
			for ix in wseg:
				tri(st, c, xf * ((last[ix] as Vector3) * r), xf * ((last[ix + 1] as Vector3) * r), nd, nd, nd)

	# ---------------------------------------------------------------- extrusion
	## Extrude a 2D polygon (XY, Y up) along Z by `depth`, centred on z = 0.
	## Returns the world-space (module-local) triangle soup for optional collision.
	func extrude(points: PackedVector2Array, depth: float, xf: Transform3D, mat_name: String) -> PackedVector3Array:
		var st := _st(RomanMeshes.mats[mat_name])
		var faces := PackedVector3Array()
		var area := 0.0
		for i in points.size():
			var p := points[i]
			var q := points[(i + 1) % points.size()]
			area += p.x * q.y - q.x * p.y
		if area < 0.0:
			points.reverse()
		var hz := depth * 0.5
		var nbs := _nbasis(xf)
		var nf := (nbs * Vector3(0, 0, 1)).normalized()
		var nb := (nbs * Vector3(0, 0, -1)).normalized()
		var idx := Geometry2D.triangulate_polygon(points)
		for t in range(0, idx.size(), 3):
			var p0 := points[idx[t]]
			var p1 := points[idx[t + 1]]
			var p2 := points[idx[t + 2]]
			var f0 := xf * Vector3(p0.x, p0.y, hz)
			var f1 := xf * Vector3(p1.x, p1.y, hz)
			var f2 := xf * Vector3(p2.x, p2.y, hz)
			var b0 := xf * Vector3(p0.x, p0.y, -hz)
			var b1 := xf * Vector3(p1.x, p1.y, -hz)
			var b2 := xf * Vector3(p2.x, p2.y, -hz)
			tri(st, f0, f1, f2, nf, nf, nf)
			tri(st, b0, b1, b2, nb, nb, nb)
			faces.append_array([f0, f1, f2, b0, b1, b2])
		for i in points.size():
			var a := points[i]
			var b := points[(i + 1) % points.size()]
			var dv := b - a
			if dv.length_squared() < 1e-10:
				continue
			var n := (nbs * Vector3(dv.y, -dv.x, 0).normalized()).normalized()
			var p0 := xf * Vector3(a.x, a.y, hz)
			var p1 := xf * Vector3(b.x, b.y, hz)
			var p2 := xf * Vector3(b.x, b.y, -hz)
			var p3 := xf * Vector3(a.x, a.y, -hz)
			tri(st, p0, p1, p2, n, n, n)
			tri(st, p0, p2, p3, n, n, n)
			faces.append_array([p0, p1, p2, p0, p2, p3])
		return faces

	func pitched_roof(w: float, h: float, d: float, x: float, y: float, z: float, mat_name := "terracotta", rot_y := 0.0) -> void:
		var pts := PackedVector2Array([Vector2(-w / 2, 0), Vector2(0, h), Vector2(w / 2, 0)])
		extrude(pts, d, Transform3D(Basis(Vector3.UP, rot_y), Vector3(x, y, z)), mat_name)

	func arch_block(width: float, height: float, depth: float, r: float, x: float, y: float, z: float, mat_name: String, rot_y := 0.0) -> void:
		var hw := width / 2
		var cy := height - r - 0.35
		var pts := PackedVector2Array()
		pts.append(Vector2(-hw, 0))
		pts.append(Vector2(-r, 0))
		var segs := 12
		for k in segs + 1:
			var a := PI - PI * float(k) / segs
			pts.append(Vector2(r * cos(a), cy + r * sin(a)))
		pts.append(Vector2(r, 0))
		pts.append(Vector2(hw, 0))
		pts.append(Vector2(hw, height))
		pts.append(Vector2(-hw, height))
		var faces := extrude(pts, depth, Transform3D(Basis(Vector3.UP, rot_y), Vector3(x, y, z)), mat_name)
		var s := ConcavePolygonShape3D.new()
		s.backface_collision = true
		s.set_faces(faces)
		shapes.append([s, Transform3D()])

	# ---------------------------------------------------------------- composites
	func cypress(x: float, z: float, s := 1.0) -> void:
		cyl(0.08 * s, 0.11 * s, 0.5 * s, x, 0.28 * s, z, "wood", 6)
		cyl(0.04 * s, 0.38 * s, 1.35 * s, x, 1.05 * s, z, "cypressDark", 8)
		cyl(0.02 * s, 0.25 * s, 1.0 * s, x, 1.65 * s, z, "cypressMid", 8, false)

	func stone_pine(x: float, z: float, s := 1.0) -> void:
		cyl(0.09 * s, 0.13 * s, 1.3 * s, x, 0.65 * s, z, "wood", 7)
		cyl(0.62 * s, 0.32 * s, 0.42 * s, x, 1.42 * s, z, "cypressMid", 10, false)
		sphere(0.46 * s, 10, 6, Vector3(x, 1.56 * s, z), Vector3(1.25, 0.48, 1.25), "cypressDark")

	func column(x: float, y: float, z: float, h := 1.35, r := 0.1) -> void:
		box(r * 2.7, 0.1, r * 2.7, x, y + 0.05, z, "marble")
		cyl(r * 0.88, r, h - 0.22, x, y + h / 2, z, "marble", 10)
		box(r * 2.8, 0.12, r * 2.8, x, y + h - 0.06, z, "marble")

	func road_strip(dir: int) -> void:
		match dir:
			0:
				box(1.75, 0.12, 2.0, 0, 0.06, -1.0, "basalt")
				box(0.32, 0.18, 2.0, -1.02, 0.09, -1.0, "travertine")
				box(0.32, 0.18, 2.0, 1.02, 0.09, -1.0, "travertine")
			2:
				box(1.75, 0.12, 2.0, 0, 0.06, 1.0, "basalt")
				box(0.32, 0.18, 2.0, -1.02, 0.09, 1.0, "travertine")
				box(0.32, 0.18, 2.0, 1.02, 0.09, 1.0, "travertine")
			1:
				box(2.0, 0.12, 1.75, 1.0, 0.06, 0, "basalt")
				box(2.0, 0.18, 0.32, 1.0, 0.09, -1.02, "travertine")
				box(2.0, 0.18, 0.32, 1.0, 0.09, 1.02, "travertine")
			3:
				box(2.0, 0.12, 1.75, -1.0, 0.06, 0, "basalt")
				box(2.0, 0.18, 0.32, -1.0, 0.09, -1.02, "travertine")
				box(2.0, 0.18, 0.32, -1.0, 0.09, 1.02, "travertine")

	func brazier(x: float, y: float, z: float) -> void:
		cyl(0.12, 0.08, 0.34, x, y + 0.17, z, "bronze", 8)
		sphere(0.11, 8, 6, Vector3(x, y + 0.38, z), Vector3.ONE, "brazierFire")


# ===========================================================================
# Module catalogue geometry (1:1 port of the HTML switch statement)
# ===========================================================================
static func _build(g: Baker, id: String) -> void:
	var base := "travertine" if id.begins_with("forum") else ("grass" if id.begins_with("garden") else "soil")
	g.box(3.96, 0.14, 3.96, 0, -0.07, 0, base)
	const H := PI / 2

	match id:
		"road_straight":
			g.road_strip(0)
			g.road_strip(2)
			g.box(0.3, 0.15, 0.25, -0.4, 0.08, 0, "basaltLight")
			g.box(0.3, 0.15, 0.25, 0.4, 0.08, 0, "basaltLight")
			g.cyl(0.12, 0.14, 0.65, -1.48, 0.34, -0.9, "travertine", 8)
			g.cypress(1.5, 1.1, 0.72)
		"road_corner":
			g.road_strip(0)
			g.road_strip(1)
			g.box(2.38, 0.12, 2.38, 0.16, 0.06, -0.16, "basalt")
			g.box(0.32, 0.18, 2.1, -1.02, 0.09, 0.16, "travertine")
			g.box(2.1, 0.18, 0.32, -0.16, 0.09, 1.02, "travertine")
			g.box(0.75, 0.42, 0.75, -1.35, 0.21, 1.35, "travertine")
			g.box(0.52, 0.36, 0.52, -1.35, 0.25, 1.35, "water")
			g.cypress(1.45, -1.45, 0.75)
		"road_t":
			g.road_strip(0)
			g.road_strip(1)
			g.road_strip(3)
			g.box(1.8, 0.12, 1.8, 0, 0.06, 0, "basalt")
			g.box(4.0, 0.18, 0.32, 0, 0.09, 1.02, "travertine")
			g.brazier(-1.25, 0.16, 1.15)
			g.brazier(1.25, 0.16, 1.15)
		"road_cross":
			g.road_strip(0)
			g.road_strip(1)
			g.road_strip(2)
			g.road_strip(3)
			g.box(1.85, 0.12, 1.85, 0, 0.06, 0, "basalt")
			for p: Vector2 in [Vector2(-1.12, -1.12), Vector2(1.12, -1.12), Vector2(-1.12, 1.12), Vector2(1.12, 1.12)]:
				g.column(p.x, 0.14, p.y, 1.45, 0.12)
			g.brazier(1.38, 0.14, -1.38)
		"road_gate":
			g.road_strip(0)
			g.box(1.75, 0.12, 1.2, 0, 0.06, 0.4, "basalt")
			g.arch_block(3.2, 2.45, 0.95, 0.95, 0, 0, 0.25, "travertine")
			g.box(3.45, 0.45, 1.12, 0, 2.6, 0.25, "marble")
			g.box(0.65, 0.35, 0.45, 0, 3.0, 0.25, "bronze")
			g.cypress(-1.5, 1.45, 0.8)
			g.cypress(1.5, 1.45, 0.8)
		"aqua_straight":
			g.box(0.9, 0.24, 3.98, 0, 0.12, 0, "travertine")
			g.arch_block(2.0, 2.65, 0.86, 0.68, 0, 0.2, -1.0, "travertine", H)
			g.arch_block(2.0, 2.65, 0.86, 0.68, 0, 0.2, 1.0, "travertine", H)
			g.box(0.92, 0.36, 4.0, 0, 3.0, 0, "travertine")
			g.box(0.5, 0.2, 4.0, 0, 3.16, 0, "water")
			g.cypress(-1.35, -0.9, 0.75)
			g.cypress(1.35, 0.9, 0.75)
		"aqua_overpass":
			g.road_strip(1)
			g.road_strip(3)
			g.box(1.9, 0.12, 1.75, 0, 0.06, 0, "basalt")
			g.arch_block(3.98, 2.85, 0.96, 1.25, 0, 0, 0, "travertine", H)
			g.box(0.98, 0.4, 4.0, 0, 3.05, 0, "marble")
			g.box(0.54, 0.2, 4.0, 0, 3.22, 0, "water")
		"aqua_corner":
			g.box(1.15, 2.85, 1.15, 0, 1.42, 0, "travertine")
			g.arch_block(1.5, 2.85, 0.86, 0.48, 0, 0, -1.25, "travertine", H)
			g.arch_block(1.5, 2.85, 0.86, 0.48, 1.25, 0, 0, "travertine")
			g.box(0.92, 0.36, 2.45, 0, 3.0, -0.78, "travertine")
			g.box(2.45, 0.36, 0.92, 0.78, 3.0, 0, "travertine")
			g.box(0.5, 0.2, 2.25, 0, 3.16, -0.88, "water")
			g.box(2.25, 0.2, 0.5, 0.88, 3.16, 0, "water")
			g.cypress(-1.35, 1.35, 0.85)
		"aqua_castellum":
			g.road_strip(2)
			g.arch_block(1.4, 2.85, 0.86, 0.45, 0, 0, -1.3, "travertine", H)
			g.box(0.92, 0.36, 1.5, 0, 3.0, -1.25, "travertine")
			g.box(0.5, 0.2, 1.5, 0, 3.16, -1.25, "water")
			g.box(2.1, 2.6, 1.45, 0, 1.3, -0.1, "brick")
			g.box(2.24, 0.25, 1.6, 0, 2.65, -0.1, "travertine")
			g.pitched_roof(2.25, 0.75, 1.65, 0, 2.77, -0.1, "terracotta")
			g.box(1.5, 0.45, 0.7, 0, 0.22, 0.72, "marble")
			g.box(1.2, 0.35, 0.48, 0, 0.32, 0.72, "water")
		"aqua_spring":
			g.arch_block(1.4, 2.85, 0.86, 0.45, 0, 0, -1.3, "travertine", H)
			g.box(0.92, 0.36, 1.5, 0, 3.0, -1.25, "travertine")
			g.box(0.5, 0.2, 1.5, 0, 3.16, -1.25, "water")
			g.cyl(0.95, 1.15, 2.85, 0, 1.42, 0.25, "travertine", 12)
			g.sphere(0.96, 12, 8, Vector3(0, 2.85, 0.25), Vector3.ONE, "terracotta", PI / 2)
			g.cypress(-1.4, 1.35, 0.8)
			g.cypress(1.4, 1.35, 0.8)
		"insula_street":
			g.box(3.35, 2.9, 2.65, 0, 1.45, -0.45, "brick")
			g.box(3.42, 0.85, 2.72, 0, 0.42, -0.45, "stuccoWarm")
			g.box(3.1, 0.12, 0.6, 0, 0.92, 1.1, "terracottaDark")
			for wx: float in [-1.0, 0.0, 1.0]:
				g.box(0.36, 0.42, 0.08, wx, 1.65, 0.89, "windowGlow")
				g.box(0.36, 0.42, 0.08, wx, 2.4, 0.89, "windowGlow")
			g.pitched_roof(2.95, 0.85, 3.5, 0, 2.9, -0.45, "terracotta", H)
			g.box(3.96, 0.14, 0.9, 0, 0.07, 1.5, "travertine")
		"insula_corner":
			g.box(2.75, 2.7, 2.75, -0.42, 1.35, -0.42, "stuccoWarm")
			g.box(2.8, 0.85, 2.8, -0.42, 0.42, -0.42, "brick")
			g.box(0.36, 0.42, 0.08, -0.9, 1.55, 0.97, "windowGlow")
			g.box(0.36, 0.42, 0.08, 0.15, 1.55, 0.97, "windowGlow")
			g.box(0.08, 0.42, 0.36, 0.97, 1.55, -0.8, "windowGlow")
			g.box(0.08, 0.42, 0.36, 0.97, 2.25, 0.15, "windowGlow")
			g.pitched_roof(2.95, 0.85, 2.95, -0.42, 2.7, -0.42, "terracotta")
			g.box(3.96, 0.14, 0.85, 0, 0.07, 1.52, "travertine")
			g.box(0.85, 0.14, 3.96, 1.52, 0.07, 0, "travertine")
		"insula_horrea":
			g.box(3.3, 1.85, 1.15, 0, 0.92, -1.15, "brick")
			g.box(3.3, 1.85, 1.15, 0, 0.92, 1.15, "brick")
			g.pitched_roof(1.3, 0.65, 3.45, 0, 1.85, -1.15, "terracottaDark", H)
			g.pitched_roof(1.3, 0.65, 3.45, 0, 1.85, 1.15, "terracottaDark", H)
			for p: Vector2 in [Vector2(-0.8, 0), Vector2(-0.4, 0.25), Vector2(0.5, -0.2), Vector2(0.9, 0.1)]:
				g.cyl(0.12, 0.07, 0.42, p.x, 0.21, p.y, "terracotta", 8, false)
		"domus_atrium":
			g.box(3.55, 1.15, 0.8, 0, 0.58, -1.35, "plaster")
			g.box(3.55, 1.15, 0.75, 0, 0.58, 0.95, "plaster")
			g.box(0.8, 1.15, 1.65, -1.38, 0.58, -0.2, "plaster")
			g.box(0.8, 1.15, 1.65, 1.38, 0.58, -0.2, "plaster")
			g.box(3.7, 0.26, 0.95, 0, 1.25, -1.35, "terracotta")
			g.box(3.7, 0.26, 0.9, 0, 1.25, 0.95, "terracotta")
			g.box(0.95, 0.26, 1.65, -1.38, 1.25, -0.2, "terracotta")
			g.box(0.95, 0.26, 1.65, 1.38, 1.25, -0.2, "terracotta")
			g.box(1.5, 0.16, 1.25, 0, 0.08, -0.2, "marble")
			g.box(1.05, 0.18, 0.85, 0, 0.1, -0.2, "water")
			g.box(0.72, 0.85, 0.18, 0, 0.45, 1.35, "wood")
			g.box(3.96, 0.14, 0.65, 0, 0.07, 1.65, "travertine")
		"domus_peristyle":
			g.box(3.4, 0.22, 3.4, 0, 0.11, 0, "travertine")
			g.box(1.8, 0.24, 1.8, 0, 0.13, 0, "grass")
			g.cyl(0.45, 0.45, 0.26, 0, 0.24, 0, "marble", 12)
			g.cyl(0.36, 0.36, 0.28, 0, 0.25, 0, "water", 12, false)
			for p: Vector2 in [Vector2(-1.35, -1.35), Vector2(0, -1.35), Vector2(1.35, -1.35), Vector2(-1.35, 1.35), Vector2(0, 1.35), Vector2(1.35, 1.35), Vector2(-1.35, 0), Vector2(1.35, 0)]:
				g.column(p.x, 0.22, p.y, 1.15, 0.08)
			g.box(3.65, 0.22, 0.75, 0, 1.45, -1.35, "terracotta")
			g.box(3.65, 0.22, 0.75, 0, 1.45, 1.35, "terracotta")
			g.box(0.75, 0.22, 2.0, -1.35, 1.45, 0, "terracotta")
			g.box(0.75, 0.22, 2.0, 1.35, 1.45, 0, "terracotta")
		"forum_plaza":
			g.box(3.96, 0.2, 3.96, 0, 0.1, 0, "marble")
			g.box(1.35, 0.2, 1.35, 0, 0.25, 0, "travertine")
			g.box(0.85, 0.75, 0.85, 0, 0.72, 0, "marble")
			g.cyl(0.24, 0.28, 0.9, 0, 1.5, 0, "bronze", 10)
			g.brazier(-1.1, 0.2, -1.1)
			g.brazier(1.1, 0.2, 1.1)
		"forum_colonnade":
			g.box(3.96, 0.2, 3.96, 0, 0.1, 0, "marble")
			for cx: float in [-1.35, -0.45, 0.45, 1.35]:
				g.column(cx, 0.2, 1.25, 1.75, 0.11)
			g.box(3.7, 0.28, 0.6, 0, 2.08, 1.25, "marble")
			g.pitched_roof(0.85, 0.45, 3.8, 0, 2.22, 1.25, "terracotta", H)
		"forum_edge":
			g.box(3.96, 0.2, 3.96, 0, 0.1, 0, "marble")
			g.box(3.96, 1.9, 0.35, 0, 1.05, -1.6, "travertine")
			for cx: float in [-1.35, -0.45, 0.45, 1.35]:
				g.column(cx, 0.2, -0.85, 1.75, 0.11)
			g.box(3.96, 0.28, 1.15, 0, 2.08, -1.22, "marble")
			g.pitched_roof(1.3, 0.55, 3.98, 0, 2.22, -1.22, "terracotta", H)
		"forum_corner":
			g.box(3.96, 0.2, 3.96, 0, 0.1, 0, "marble")
			g.box(3.96, 1.9, 0.35, 0, 1.05, -1.6, "travertine")
			g.box(0.35, 1.9, 3.96, -1.6, 1.05, 0, "travertine")
			for p: Vector2 in [Vector2(-0.85, -0.85), Vector2(0.25, -0.85), Vector2(1.35, -0.85), Vector2(-0.85, 0.25), Vector2(-0.85, 1.35)]:
				g.column(p.x, 0.2, p.y, 1.75, 0.11)
			g.box(3.96, 0.28, 1.15, 0, 2.08, -1.22, "marble")
			g.box(1.15, 0.28, 3.96, -1.22, 2.08, 0, "marble")
			g.pitched_roof(1.3, 0.55, 3.98, 0, 2.22, -1.22, "terracotta", H)
			g.pitched_roof(1.3, 0.55, 3.98, -1.22, 2.22, 0, "terracotta", 0.0)
		"forum_temple":
			g.box(3.96, 0.2, 3.96, 0, 0.1, 0, "marble")
			g.box(2.85, 0.55, 3.15, 0, 0.45, -0.25, "travertine")
			g.box(2.4, 0.25, 0.65, 0, 0.28, 1.45, "marble")
			g.box(2.15, 1.8, 1.85, 0, 1.62, -0.65, "plaster")
			for cx: float in [-1.02, -0.34, 0.34, 1.02]:
				g.column(cx, 0.72, 0.95, 1.85, 0.11)
			g.box(2.65, 0.26, 2.95, 0, 2.68, -0.2, "marble")
			g.pitched_roof(2.75, 0.88, 3.05, 0, 2.8, -0.2, "terracotta")
			g.brazier(0, 0.2, 1.72)
		"forum_passage":
			g.box(3.96, 0.2, 3.96, 0, 0.1, 0, "marble")
			for cz: float in [-1.1, 0.0, 1.1]:
				g.column(-1.15, 0.2, cz, 1.75, 0.11)
				g.column(1.15, 0.2, cz, 1.75, 0.11)
			g.box(2.75, 0.28, 3.96, 0, 2.08, 0, "marble")
			g.pitched_roof(2.85, 0.72, 3.98, 0, 2.22, 0, "terracotta")
		"garden_cypress":
			g.box(3.45, 0.12, 0.55, 0, 0.06, 0, "soil")
			g.box(0.55, 0.12, 3.45, 0, 0.06, 0, "soil")
			g.cypress(-1.25, -1.25, 1.15)
			g.cypress(1.25, -1.15, 0.95)
			g.cypress(-1.15, 1.2, 1.0)
			g.stone_pine(1.15, 1.15, 1.05)
			g.box(0.8, 0.25, 0.35, 0, 0.15, 0.65, "marble")
		"garden_nymphaeum":
			g.box(3.96, 0.14, 0.65, 0, 0.07, 1.62, "travertine")
			g.cyl(1.15, 1.25, 0.38, 0, 0.22, 0.2, "marble", 14)
			g.cyl(0.92, 0.92, 0.42, 0, 0.23, 0.2, "water", 14, false)
			g.cypress(-1.35, -1.15, 1.1)
			g.cypress(1.35, -1.15, 1.1)
			g.stone_pine(0, -1.25, 1.0)
		"garden_pergola":
			for p: Vector2 in [Vector2(-1.0, -0.8), Vector2(1.0, -0.8), Vector2(-1.0, 0.8), Vector2(1.0, 0.8)]:
				g.cyl(0.08, 0.09, 1.45, p.x, 0.72, p.y, "wood", 6)
			g.box(2.35, 0.12, 0.14, 0, 1.48, -0.8, "wood", false)
			g.box(2.35, 0.12, 0.14, 0, 1.48, 0.8, "wood", false)
			for bx: float in [-0.9, -0.3, 0.3, 0.9]:
				g.box(0.1, 0.1, 1.9, bx, 1.56, 0, "wood", false)
			g.cypress(-1.45, -1.35, 1.05)
			g.cypress(1.45, 1.35, 0.95)
			g.cyl(0.12, 0.08, 0.44, -0.35, 0.22, 0.2, "terracotta", 8, false)
			g.cyl(0.12, 0.08, 0.44, 0.35, 0.22, -0.2, "terracotta", 8, false)
