class_name ChunkStreamer
extends Node3D
## Streams the endless city around a target (the running citizen).
##
## * Solves chunks on a WorkerThreadPool thread, one at a time, nearest first and
##   biased toward the runner's heading.
## * Builds solved chunks: tiles pop up one by one in the exact order the WFC
##   solver collapsed them, so you can watch the algorithm crystallise the city.
## * Once a chunk has fully appeared its tiles are merged into a single mesh.
## * Collision only exists near the runner; far chunks are unloaded (their solved
##   cells stay in memory, so the city is unchanged when you return).

const SOLVE_R := 3
const BUILD_R := 2
const COLLIDE_R := 1
const UNLOAD_R := 3
const REVEAL_STEP := 0.028   # seconds between tile pop-ins (collapse order)
const POP_SPEED := 4.5       # animT rate from the original

var world: WfcWorld
var target: Node3D
var heading := Vector3.FORWARD

var views: Dictionary = {}   # Vector2i -> ChunkView
var _task_id := -1
var _task_input: Dictionary
var _task_result: Dictionary
var _task_start_us := 0
var last_solve_ms := 0.0
var pending_solves := 0


class ChunkView:
	var root: Node3D
	var tiles: Array = []       # [{mi, xf, delay}]
	var t := 0.0
	var reveal_end := 0.0
	var merged := false
	var body: StaticBody3D = null


func _ready() -> void:
	# tile pop-in animation is driven from _process; don't physics-interpolate it
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func reset(p_world: WfcWorld) -> void:
	_finish_task(false)
	for ch: Vector2i in views:
		(views[ch] as ChunkView).root.queue_free()
	views.clear()
	world = p_world


## Synchronously solve and build a square of chunks (used at spawn).
func presolve(center: Vector2i, radius: int) -> void:
	for r in radius + 1:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) == r:
					world.solve_now(center + Vector2i(dx, dz))


static func chunk_at(pos: Vector3) -> Vector2i:
	return WfcWorld.chunk_of_cell(WfcWorld.cell_at(pos))


func _process(dt: float) -> void:
	if world == null or target == null:
		return
	var pc := chunk_at(target.global_position)
	_finish_task(true)
	if _task_id < 0:
		_start_next_solve(pc)
	_build_next(pc)
	_animate(dt)
	_update_collision(pc)
	_unload(pc)


# ---------------------------------------------------------------- solving
func _priority(ch: Vector2i, pc: Vector2i) -> float:
	var d := Vector2(ch - pc)
	var dist := d.length()
	if dist < 0.01:
		return -10.0
	var h := Vector2(heading.x, heading.z)
	var bias := 0.0
	if h.length_squared() > 0.01:
		bias = d.normalized().dot(h.normalized()) * 0.75
	return dist - bias


func _start_next_solve(pc: Vector2i) -> void:
	var best := Vector2i.ZERO
	var best_p := INF
	var count := 0
	for dz in range(-SOLVE_R, SOLVE_R + 1):
		for dx in range(-SOLVE_R, SOLVE_R + 1):
			var ch := pc + Vector2i(dx, dz)
			if world.is_solved(ch):
				continue
			count += 1
			var p := _priority(ch, pc)
			if p < best_p:
				best_p = p
				best = ch
	pending_solves = count
	if count == 0:
		return
	_task_input = world.make_job_input(best)
	_task_start_us = Time.get_ticks_usec()
	_task_id = WorkerThreadPool.add_task(_run_task, false, "wfc chunk")


func _run_task() -> void:
	_task_result = WfcWorld.solve_chunk(_task_input)


func _finish_task(only_if_done: bool) -> void:
	if _task_id < 0:
		return
	if only_if_done and not WorkerThreadPool.is_task_completed(_task_id):
		return
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	last_solve_ms = (Time.get_ticks_usec() - _task_start_us) / 1000.0
	if only_if_done and world != null and _task_result.get("chunk") == _task_input.get("chunk"):
		world.commit(_task_result)
	_task_result = {}


# ---------------------------------------------------------------- building
func _build_next(pc: Vector2i) -> void:
	var best := Vector2i.ZERO
	var best_p := INF
	var found := false
	for dz in range(-BUILD_R, BUILD_R + 1):
		for dx in range(-BUILD_R, BUILD_R + 1):
			var ch := pc + Vector2i(dx, dz)
			if views.has(ch) or not world.is_solved(ch):
				continue
			var p := _priority(ch, pc)
			if p < best_p:
				best_p = p
				best = ch
				found = true
	if found:
		_build_chunk(best)


func _build_chunk(ch: Vector2i) -> void:
	var view := ChunkView.new()
	view.root = Node3D.new()
	view.root.name = "Chunk_%d_%d" % [ch.x, ch.y]
	add_child(view.root)
	var info: Dictionary = world.chunks[ch]
	var order: PackedInt32Array = info["order"]
	var rank := PackedInt32Array()
	rank.resize(WfcWorld.CELLS)
	for k in order.size():
		rank[order[k]] = k
	var base := ch * WfcWorld.CHUNK
	for i in WfcWorld.CELLS:
		var cell := base + Vector2i(i & WfcWorld.CHUNK_MASK, i >> WfcWorld.CHUNK_SHIFT)
		var v: int = world.cells[cell]
		var mi := MeshInstance3D.new()
		mi.mesh = RomanMeshes.get_module(WfcData.v_module[v])["mesh"]
		var xf := RomanMeshes.tile_transform(cell, WfcData.v_rot[v])
		mi.transform = Transform3D(xf.basis * Basis.from_scale(Vector3(1, 0.01, 1)), xf.origin)
		mi.visible = false
		view.root.add_child(mi)
		var delay := rank[i] * REVEAL_STEP
		view.tiles.append({"mi": mi, "xf": xf, "delay": delay, "cell": cell})
		view.reveal_end = maxf(view.reveal_end, delay)
	views[ch] = view


func _animate(dt: float) -> void:
	var merges_left := 1
	for ch: Vector2i in views:
		var view: ChunkView = views[ch]
		if view.merged:
			continue
		view.t += dt
		for tile: Dictionary in view.tiles:
			var mi: MeshInstance3D = tile["mi"]
			var local_t: float = view.t - float(tile["delay"])
			if local_t < 0.0:
				continue
			var a := minf(1.0, 0.05 + local_t * POP_SPEED)
			var sy := 1.0 if a >= 1.0 else maxf(0.01, a * (1.0 + 0.14 * sin(a * PI)))
			var xf: Transform3D = tile["xf"]
			mi.visible = true
			mi.transform = Transform3D(xf.basis * Basis.from_scale(Vector3(1, sy, 1)), xf.origin)
		if merges_left > 0 and view.t > view.reveal_end + 1.0 / POP_SPEED + 0.05:
			_merge(view)
			merges_left -= 1


func _merge(view: ChunkView) -> void:
	var sts: Dictionary = {}
	for tile: Dictionary in view.tiles:
		var mi: MeshInstance3D = tile["mi"]
		var mesh: ArrayMesh = mi.mesh
		var xf: Transform3D = tile["xf"]
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			if not sts.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				sts[mat] = st
			(sts[mat] as SurfaceTool).append_from(mesh, s, xf)
		mi.queue_free()
	var am := ArrayMesh.new()
	for mat: Material in sts:
		(sts[mat] as SurfaceTool).commit(am)
		am.surface_set_material(am.get_surface_count() - 1, mat)
	var merged := MeshInstance3D.new()
	merged.mesh = am
	view.root.add_child(merged)
	view.merged = true


# ---------------------------------------------------------------- collision
func _update_collision(pc: Vector2i) -> void:
	for ch: Vector2i in views:
		var view: ChunkView = views[ch]
		var dist := maxi(absi(ch.x - pc.x), absi(ch.y - pc.y))
		if dist <= COLLIDE_R and view.body == null:
			view.body = _make_body(ch)
			view.root.add_child(view.body)
		elif dist > COLLIDE_R + 1 and view.body != null:
			view.body.queue_free()
			view.body = null


func _make_body(ch: Vector2i) -> StaticBody3D:
	var body := StaticBody3D.new()
	var base := ch * WfcWorld.CHUNK
	for i in WfcWorld.CELLS:
		var cell := base + Vector2i(i & WfcWorld.CHUNK_MASK, i >> WfcWorld.CHUNK_SHIFT)
		var v: int = world.cells[cell]
		var shapes: Array = RomanMeshes.get_module(WfcData.v_module[v])["shapes"]
		if shapes.is_empty():
			continue
		var txf := RomanMeshes.tile_transform(cell, WfcData.v_rot[v])
		for entry: Array in shapes:
			var owner_id := body.create_shape_owner(body)
			body.shape_owner_add_shape(owner_id, entry[0])
			body.shape_owner_set_transform(owner_id, txf * (entry[1] as Transform3D))
	return body


func _unload(pc: Vector2i) -> void:
	var drop: Array[Vector2i] = []
	for ch: Vector2i in views:
		if maxi(absi(ch.x - pc.x), absi(ch.y - pc.y)) > UNLOAD_R:
			drop.append(ch)
	for ch in drop:
		(views[ch] as ChunkView).root.queue_free()
		views.erase(ch)


func _exit_tree() -> void:
	_finish_task(false)
