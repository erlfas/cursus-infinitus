class_name WfcWorld
extends RefCounted
## Infinite Wave Function Collapse city.
##
## The world is an unbounded sparse grid of solved cells. It is solved in 8x8
## chunks: every new chunk is constrained by the already-solved cells around it
## so seams always match, and by a pinned Roman street grid (cardo/decumanus
## avenues every AVENUE cells) that guarantees an endless connected road network.
##
## solve_chunk() is a pure static function (no nodes, no world access) so it can
## run on a WorkerThreadPool thread. make_job_input() / commit() run on the main
## thread and are the only places the world dictionary is touched.

const CHUNK := 8
const CHUNK_SHIFT := 3
const CHUNK_MASK := 7
const CELLS := CHUNK * CHUNK
const TILE := 4.0
const AVENUE := 16
const MAX_ATTEMPTS := 12

var seed_text := "ROMA-753"
var cells: Dictionary = {}    # Vector2i (world cell) -> int variant
var chunks: Dictionary = {}   # Vector2i (chunk) -> {"order", "attempts", "fallback"}
var total_attempts := 0
var total_fallback_edges := 0


func _init(p_seed: String = "ROMA-753") -> void:
	seed_text = p_seed
	WfcData.setup()


# ---------------------------------------------------------------------------
# Coordinates
# ---------------------------------------------------------------------------
static func cell_at(pos: Vector3) -> Vector2i:
	return Vector2i(floori((pos.x + TILE * 0.5) / TILE), floori((pos.z + TILE * 0.5) / TILE))


static func chunk_of_cell(c: Vector2i) -> Vector2i:
	return Vector2i(c.x >> CHUNK_SHIFT, c.y >> CHUNK_SHIFT)


static func cell_center(c: Vector2i) -> Vector3:
	return Vector3(c.x * TILE, 0.0, c.y * TILE)


static func pin_kind(c: Vector2i) -> int:
	var ns := posmod(c.x, AVENUE) == 0
	var ew := posmod(c.y, AVENUE) == 0
	if ns and ew:
		return WfcData.PIN_CROSS
	if ns:
		return WfcData.PIN_CARDO
	if ew:
		return WfcData.PIN_DECUMANUS
	return WfcData.PIN_NONE


func is_solved(ch: Vector2i) -> bool:
	return chunks.has(ch)


func variant_at(c: Vector2i) -> int:
	return cells.get(c, -1)


# ---------------------------------------------------------------------------
# Main-thread: snapshot constraints for a chunk
# ---------------------------------------------------------------------------
func make_job_input(ch: Vector2i) -> Dictionary:
	var init_lo := PackedInt64Array()
	var init_hi := PackedInt64Array()
	var outside := PackedInt32Array()
	init_lo.resize(CELLS)
	init_hi.resize(CELLS)
	outside.resize(CELLS * 4)
	outside.fill(-1)
	var base := ch * CHUNK
	for i in CELLS:
		var lx := i & CHUNK_MASK
		var lz := i >> CHUNK_SHIFT
		var wc := base + Vector2i(lx, lz)
		var k := pin_kind(wc)
		var lo: int = WfcData.pin_lo[k]
		var hi: int = WfcData.pin_hi[k]
		for d in 4:
			var dv: Vector2i = WfcData.DIRS[d]
			var nlx := lx + dv.x
			var nlz := lz + dv.y
			if nlx >= 0 and nlx < CHUNK and nlz >= 0 and nlz < CHUNK:
				continue
			var nw := wc + dv
			var od: int = WfcData.OPP[d]
			if cells.has(nw):
				var nv: int = cells[nw]
				outside[i * 4 + d] = nv
				lo &= WfcData.compat_lo[nv * 4 + od]
				hi &= WfcData.compat_hi[nv * 4 + od]
			else:
				var nk := pin_kind(nw)
				if nk != WfcData.PIN_NONE:
					lo &= WfcData.pin_union_lo[nk * 4 + od]
					hi &= WfcData.pin_union_hi[nk * 4 + od]
		init_lo[i] = lo
		init_hi[i] = hi
	return {
		"chunk": ch,
		"seed": seed_text,
		"init_lo": init_lo,
		"init_hi": init_hi,
		"outside": outside,
	}


func commit(result: Dictionary) -> void:
	var ch: Vector2i = result["chunk"]
	var vars: PackedInt32Array = result["variants"]
	var base := ch * CHUNK
	for i in CELLS:
		cells[base + Vector2i(i & CHUNK_MASK, i >> CHUNK_SHIFT)] = vars[i]
	chunks[ch] = {
		"order": result["order"],
		"attempts": result["attempts"],
		"fallback": result["fallback"],
	}
	total_attempts += int(result["attempts"])
	total_fallback_edges += int(result["fallback"])


## Convenience: synchronously solve + commit.
func solve_now(ch: Vector2i) -> void:
	if not is_solved(ch):
		commit(solve_chunk(make_job_input(ch)))


# ---------------------------------------------------------------------------
# Thread-safe solver
# ---------------------------------------------------------------------------
static func solve_chunk(input: Dictionary) -> Dictionary:
	var ch: Vector2i = input["chunk"]
	var seed_s: String = input["seed"]
	var init_lo: PackedInt64Array = input["init_lo"]
	var init_hi: PackedInt64Array = input["init_hi"]
	var outside: PackedInt32Array = input["outside"]

	# Cells boxed in by incompatible solved neighbours (typically a chunk corner
	# touching two older chunks) get relaxed to the least-mismatching variants;
	# the rest of the chunk is still solved by proper WFC.
	var relaxed_edges := 0
	for i in CELLS:
		if init_lo[i] == 0 and init_hi[i] == 0:
			var r := _relax_cell(ch, i, outside)
			init_lo[i] = r[0]
			init_hi[i] = r[1]
			relaxed_edges += int(r[2])

	var attempts := 0
	for attempt in MAX_ATTEMPTS:
		attempts = attempt + 1
		var rng := WfcRng.new(WfcRng.hash_seed("%s|%d|%d|%d" % [seed_s, ch.x, ch.y, attempt]))
		var s := ChunkSolver.new(init_lo, init_hi, outside, rng)
		if s.run():
			return {
				"chunk": ch,
				"variants": s.collapsed,
				"order": s.order,
				"attempts": attempts,
				"fallback": relaxed_edges,
			}

	# Soft fallback: greedy min-mismatch fill. Guarantees the chunk is never empty.
	var rng2 := WfcRng.new(WfcRng.hash_seed("%s|%d|%d|fallback" % [seed_s, ch.x, ch.y]))
	var fb := _fallback_fill(init_lo, init_hi, outside, rng2)
	var order := PackedInt32Array()
	for i in CELLS:
		order.append(i)
	return {
		"chunk": ch,
		"variants": fb[0],
		"order": order,
		"attempts": attempts + 1,
		"fallback": fb[1],
	}


## Mask of the variants with the fewest socket mismatches against solved outside
## neighbours (preferring non-avenue-breaking ones). Returns [lo, hi, mismatches].
static func _relax_cell(ch: Vector2i, i: int, outside: PackedInt32Array) -> Array:
	var socks := WfcData.v_sockets
	var lx := i & CHUNK_MASK
	var lz := i >> CHUNK_SHIFT
	var best := 1 << 30
	var lo := 0
	var hi := 0
	for v in WfcData.variant_count:
		var mm := 0
		for d in 4:
			var nv := outside[i * 4 + d]
			if nv >= 0 and socks[v * 4 + d] != socks[nv * 4 + WfcData.OPP[d]]:
				mm += 1
		if mm < best:
			best = mm
			lo = 0
			hi = 0
		if mm == best:
			if v < WfcData.BITS:
				lo |= 1 << v
			else:
				hi |= 1 << (v - WfcData.BITS)
	# Keep the street grid if any least-mismatch variant satisfies it.
	var k := pin_kind(ch * CHUNK + Vector2i(lx, lz))
	var plo: int = lo & WfcData.pin_lo[k]
	var phi: int = hi & WfcData.pin_hi[k]
	if plo != 0 or phi != 0:
		return [plo, phi, best]
	return [lo, hi, best]


static func _fallback_fill(init_lo: PackedInt64Array, init_hi: PackedInt64Array, outside: PackedInt32Array, rng: WfcRng) -> Array:
	var n := WfcData.variant_count
	var socks := WfcData.v_sockets
	var chosen := PackedInt32Array()
	chosen.resize(CELLS)
	chosen.fill(-1)
	var mismatches := 0
	for i in CELLS:
		var lx := i & CHUNK_MASK
		var lz := i >> CHUNK_SHIFT
		var nbr := [-1, -1, -1, -1]
		for d in 4:
			var dv: Vector2i = WfcData.DIRS[d]
			var nlx := lx + dv.x
			var nlz := lz + dv.y
			if nlx >= 0 and nlx < CHUNK and nlz >= 0 and nlz < CHUNK:
				nbr[d] = chosen[(nlz << CHUNK_SHIFT) | nlx]
			else:
				nbr[d] = outside[i * 4 + d]
		var best := 0
		var best_cost := INF
		var best_mm := 0
		for v in n:
			var cost := 0.0
			var mm := 0
			if not WfcData.has_bit(init_lo[i], init_hi[i], v):
				cost += 4.0
			for d in 4:
				var nv: int = nbr[d]
				if nv >= 0 and socks[v * 4 + d] != socks[nv * 4 + WfcData.OPP[d]]:
					cost += 10.0
					mm += 1
			cost -= WfcData.v_weight[v] * 0.05 * rng.next_float()
			if cost < best_cost:
				best_cost = cost
				best = v
				best_mm = mm
		chosen[i] = best
		mismatches += best_mm
	return [chosen, mismatches]


# ---------------------------------------------------------------------------
# One WFC attempt over a single chunk (MRV + weighted collapse + propagation),
# ported from pickNextMRVCell / chooseWeightedVariant / propagateFrom.
# ---------------------------------------------------------------------------
class ChunkSolver:
	var lo: PackedInt64Array
	var hi: PackedInt64Array
	var outside: PackedInt32Array
	var collapsed := PackedInt32Array()
	var count := PackedInt32Array()
	var entropy := PackedFloat64Array()
	var order := PackedInt32Array()
	var rng: WfcRng
	var propagations := 0

	var n: int
	var bits: int
	var w: PackedFloat64Array
	var logw: PackedFloat64Array
	var fam: PackedInt32Array
	var clo: PackedInt64Array
	var chi: PackedInt64Array

	func _init(init_lo: PackedInt64Array, init_hi: PackedInt64Array, p_outside: PackedInt32Array, p_rng: WfcRng) -> void:
		lo = init_lo.duplicate()
		hi = init_hi.duplicate()
		outside = p_outside
		rng = p_rng
		n = WfcData.variant_count
		bits = WfcData.BITS
		w = WfcData.v_weight
		logw = WfcData.v_logw
		fam = WfcData.v_family
		clo = WfcData.compat_lo
		chi = WfcData.compat_hi
		collapsed.resize(CELLS)
		collapsed.fill(-1)
		count.resize(CELLS)
		entropy.resize(CELLS)
		for i in CELLS:
			_metrics(i)

	func run() -> bool:
		var all := PackedInt32Array()
		for i in CELLS:
			all.append(i)
		if not _propagate(all):
			return false
		while true:
			var target := _pick_mrv()
			if target == -2:
				return false
			if target < 0:
				return true
			var v := _choose(target)
			if v < 0:
				return false
			collapsed[target] = v
			if v < bits:
				lo[target] = 1 << v
				hi[target] = 0
			else:
				lo[target] = 0
				hi[target] = 1 << (v - bits)
			count[target] = 1
			entropy[target] = 0.0
			order.append(target)
			var q := PackedInt32Array()
			q.append(target)
			if not _propagate(q):
				return false
		return true

	func _has(i: int, v: int) -> bool:
		if v < bits:
			return ((lo[i] >> v) & 1) == 1
		return ((hi[i] >> (v - bits)) & 1) == 1

	func _metrics(i: int) -> void:
		if collapsed[i] >= 0:
			count[i] = 1
			entropy[i] = 0.0
			return
		var sw := 0.0
		var swl := 0.0
		var c := 0
		var l := lo[i]
		var h := hi[i]
		for v in n:
			var on: int
			if v < bits:
				on = (l >> v) & 1
			else:
				on = (h >> (v - bits)) & 1
			if on == 1:
				sw += w[v]
				swl += logw[v]
				c += 1
		count[i] = c
		if c <= 1 or sw <= 0.0:
			entropy[i] = 0.0
		else:
			# Shannon entropy in bits
			entropy[i] = maxf(0.01, (log(sw) - swl / sw) / log(2.0))

	## Returns cell index, -1 when everything is collapsed, -2 on contradiction.
	func _pick_mrv() -> int:
		var best := -1
		var best_score := INF
		for i in CELLS:
			if collapsed[i] >= 0:
				continue
			if count[i] == 0:
				return -2
			var jitter := rng.next_float() * 0.0005
			var score := (-10.0 if count[i] == 1 else entropy[i]) + jitter
			if score < best_score:
				best_score = score
				best = i
		return best

	func _neighbor_variant(i: int, d: int) -> int:
		var lx := i & CHUNK_MASK
		var lz := i >> CHUNK_SHIFT
		var dv: Vector2i = WfcData.DIRS[d]
		var nlx := lx + dv.x
		var nlz := lz + dv.y
		if nlx >= 0 and nlx < CHUNK and nlz >= 0 and nlz < CHUNK:
			return collapsed[(nlz << CHUNK_SHIFT) | nlx]
		return outside[i * 4 + d]

	func _choose(i: int) -> int:
		# Neighbour family affinity (forums, gardens, domus and aqueducts cluster)
		var fam_count := [0, 0, 0, 0, 0, 0]
		for d in 4:
			var nv := _neighbor_variant(i, d)
			if nv >= 0:
				fam_count[fam[nv]] += 1
		var cand := PackedInt32Array()
		var cw := PackedFloat64Array()
		var total := 0.0
		for v in n:
			if not _has(i, v):
				continue
			var wv := w[v]
			var f := fam[v]
			var k: int = fam_count[f]
			if k > 0:
				if f == WfcData.FAM_FORUMS:
					wv *= 1.0 + 0.9 * k
				elif f == WfcData.FAM_GARDENS or f == WfcData.FAM_DOMUS:
					wv *= 1.0 + 0.55 * k
				elif f == WfcData.FAM_AQUEDUCTS:
					wv *= 1.0 + 0.35 * k
			cand.append(v)
			cw.append(wv)
			total += wv
		if cand.is_empty():
			return -1
		var r := rng.next_float() * total
		for j in cand.size():
			r -= cw[j]
			if r <= 0.0:
				return cand[j]
		return cand[cand.size() - 1]

	func _propagate(start: PackedInt32Array) -> bool:
		var queue := start.duplicate()
		var inq := PackedByteArray()
		inq.resize(CELLS)
		for s in start:
			inq[s] = 1
		var head := 0
		while head < queue.size():
			var ci := queue[head]
			head += 1
			inq[ci] = 0
			var l := lo[ci]
			var h := hi[ci]
			if l == 0 and h == 0:
				continue
			# Union of allowed neighbour masks over all surviving options, per direction
			var a0l := 0; var a0h := 0
			var a1l := 0; var a1h := 0
			var a2l := 0; var a2h := 0
			var a3l := 0; var a3h := 0
			for v in n:
				var on: int
				if v < bits:
					on = (l >> v) & 1
				else:
					on = (h >> (v - bits)) & 1
				if on == 1:
					var b := v * 4
					a0l |= clo[b]; a0h |= chi[b]
					a1l |= clo[b + 1]; a1h |= chi[b + 1]
					a2l |= clo[b + 2]; a2h |= chi[b + 2]
					a3l |= clo[b + 3]; a3h |= chi[b + 3]
			var cx := ci & CHUNK_MASK
			var cz := ci >> CHUNK_SHIFT
			for d in 4:
				var nx := cx
				var nz := cz
				var al := 0
				var ah := 0
				match d:
					0:
						nz -= 1; al = a0l; ah = a0h
					1:
						nx += 1; al = a1l; ah = a1h
					2:
						nz += 1; al = a2l; ah = a2h
					3:
						nx -= 1; al = a3l; ah = a3h
				if nx < 0 or nx >= CHUNK or nz < 0 or nz >= CHUNK:
					continue
				var ni := (nz << CHUNK_SHIFT) | nx
				if collapsed[ni] >= 0:
					continue
				var nl := lo[ni] & al
				var nh := hi[ni] & ah
				if nl != lo[ni] or nh != hi[ni]:
					lo[ni] = nl
					hi[ni] = nh
					_metrics(ni)
					propagations += 1
					if nl == 0 and nh == 0:
						return false
					if inq[ni] == 0:
						queue.append(ni)
						inq[ni] = 1
		return true
