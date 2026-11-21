extends SceneTree
## Headless checks for the infinite WFC city.
## Run: godot_console --headless --path . --script tests/test_infinite_wfc.gd

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	WfcData.setup()
	print("variants: ", WfcData.variant_count)

	# PRNG parity with the JS original (values computed with node from the HTML code)
	print("hash_seed(ROMA-753) = ", WfcRng.hash_seed("ROMA-753"))
	var r := WfcRng.new(WfcRng.hash_seed("ROMA-753"))
	print("prng first 3: ", r.next_float(), " ", r.next_float(), " ", r.next_float())

	for seed_s: String in ["ROMA-753", "OSTIA-101", "POMPEII-79", "ARLES-412"]:
		_test_seed(seed_s)

	_test_meshes()

	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("%d FAILURE(S)" % failures)
	quit(1 if failures > 0 else 0)


func _test_seed(seed_s: String) -> void:
	var world := WfcWorld.new(seed_s)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_s)
	var list: Array[Vector2i] = []
	for cz in range(-2, 3):
		for cx in range(-2, 3):
			list.append(Vector2i(cx, cz))
	# random order to simulate arbitrary exploration paths
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := list[i]; list[i] = list[j]; list[j] = t

	var t0 := Time.get_ticks_usec()
	for ch in list:
		world.solve_now(ch)
	var dt_ms := (Time.get_ticks_usec() - t0) / 1000.0

	# seams & sockets
	var mism := 0
	var lo := -16
	var hi := 23
	for z in range(lo, hi + 1):
		for x in range(lo, hi + 1):
			var c := Vector2i(x, z)
			var v := world.variant_at(c)
			check(v >= 0, "cell %s unsolved" % c)
			for d in [1, 2]:
				var nc: Vector2i = c + WfcData.DIRS[d]
				var nv := world.variant_at(nc)
				if nv < 0:
					continue
				if WfcData.v_sockets[v * 4 + d] != WfcData.v_sockets[nv * 4 + WfcData.OPP[d]]:
					mism += 1
			# avenues must be roads
			var k := WfcWorld.pin_kind(c)
			if k != WfcData.PIN_NONE:
				var okp := WfcData.has_bit(WfcData.pin_lo[k], WfcData.pin_hi[k], v)
				if not okp and world.total_fallback_edges == 0:
					check(false, "avenue cell %s not a road (%s)" % [c, WfcData.v_name[v]])

	# BFS over road-socket connectivity from origin: all avenue crossings reachable
	var seen := {Vector2i.ZERO: true}
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		var v := world.variant_at(c)
		for d in 4:
			if WfcData.v_sockets[v * 4 + d] != WfcData.SOCK_R:
				continue
			var nc: Vector2i = c + WfcData.DIRS[d]
			if nc.x < lo or nc.x > hi or nc.y < lo or nc.y > hi or seen.has(nc):
				continue
			seen[nc] = true
			queue.append(nc)
	for cr in [Vector2i(-16, -16), Vector2i(16, 0), Vector2i(0, 16), Vector2i(16, 16)]:
		check(seen.has(cr), "crossing %s not reachable by road (seed %s)" % [cr, seed_s])

	var fam_hist := [0, 0, 0, 0, 0, 0]
	for c: Vector2i in world.cells:
		fam_hist[WfcData.v_family[world.cells[c]]] += 1
	print("seed %-11s 25 chunks in %7.1f ms (%.1f ms/chunk)  attempts=%d  fallback_edges=%d  seam_mismatch=%d  road_reach=%d  families=%s" % [
		seed_s, dt_ms, dt_ms / 25.0, world.total_attempts, world.total_fallback_edges, mism, seen.size(), fam_hist])
	check(mism == world.total_fallback_edges or mism <= world.total_fallback_edges, "seam mismatches exceed fallback count")


func _test_meshes() -> void:
	var t0 := Time.get_ticks_usec()
	RomanMeshes.prewarm()
	var dt_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var verts := 0
	var shapes := 0
	for mod: Dictionary in WfcData.BASE_MODULES:
		var m: Dictionary = RomanMeshes.get_module(mod["id"])
		var am: ArrayMesh = m["mesh"]
		check(am.get_surface_count() > 0, "module %s has no surfaces" % mod["id"])
		for s in am.get_surface_count():
			verts += am.surface_get_array_len(s)
		shapes += (m["shapes"] as Array).size()
	print("meshes baked in %.1f ms, %d verts total, %d collision shapes total" % [dt_ms, verts, shapes])
