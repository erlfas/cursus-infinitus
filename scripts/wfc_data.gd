class_name WfcData
extends RefCounted
## Roman module catalogue (24 base modules) expanded into oriented variants,
## plus precomputed socket-compatibility bitmasks.
## Ported from the HTML generator (BASE_MODULES / VARIANTS / COMPAT).
##
## Variant masks don't fit in one int64 (74 variants), so every mask is a pair
## of ints (lo, hi) holding BITS bits each.

# Directions: 0 = N (-Z), 1 = E (+X), 2 = S (+Z), 3 = W (-X)
const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const OPP := [2, 3, 0, 1]
const BITS := 40

const SOCK_R := 0
const SOCK_A := 1
const SOCK_F := 2
const SOCK_U := 3
const SOCKET_CODES := {"R": 0, "A": 1, "F": 2, "U": 3}

const FAMILIES := ["roads", "aqueducts", "insulae", "domus", "forums", "gardens"]
const FAM_ROADS := 0
const FAM_AQUEDUCTS := 1
const FAM_INSULAE := 2
const FAM_DOMUS := 3
const FAM_FORUMS := 4
const FAM_GARDENS := 5
const FAMILY_LABELS := ["Via", "Aqua", "Insula", "Domus", "Forum", "Horti"]

## Slight road bias so the endless city has more side streets to run along.
const FAMILY_WEIGHT_MULT := {"roads": 1.35}

# Pin kinds used by the infinite city street grid.
const PIN_NONE := 0
const PIN_CARDO := 1      # N-S avenue: road sockets on N and S
const PIN_DECUMANUS := 2  # E-W avenue: road sockets on E and W
const PIN_CROSS := 3      # avenue intersection: road on all four sides

# Sockets order: [N (-Z), E (+X), S (+Z), W (-X)]
const BASE_MODULES := [
	# ROADS (Via Romana)
	{"id": "road_straight", "name": "Via Romana (Straight)", "family": "roads", "sockets": ["R", "U", "R", "U"], "weight": 14, "rotations": [0, 1],
		"desc": "Basalt-paved thoroughfare with raised travertine crepidines and milestone markers."},
	{"id": "road_corner", "name": "Via Corner Bend", "family": "roads", "sockets": ["R", "R", "U", "U"], "weight": 9, "rotations": [0, 1, 2, 3],
		"desc": "90-degree paved street turn anchored by a public street-corner fountain shrine."},
	{"id": "road_t", "name": "Via T-Junction", "family": "roads", "sockets": ["R", "R", "U", "R"], "weight": 7, "rotations": [0, 1, 2, 3],
		"desc": "Three-way urban intersection with bronze oil-lamp braziers on the kerb."},
	{"id": "road_cross", "name": "Cardo-Decumanus Cross", "family": "roads", "sockets": ["R", "R", "R", "R"], "weight": 4, "rotations": [0], "solitary": true,
		"desc": "Monumental four-way crossroads crowned by a miniature stone tetrapylon."},
	{"id": "road_gate", "name": "Triumphal Terminus Arch", "family": "roads", "sockets": ["R", "U", "U", "U"], "weight": 4, "rotations": [0, 1, 2, 3],
		"desc": "Single-bay travertine triumphal arch terminating an urban street axis."},

	# AQUEDUCTS (Aqua Claudia)
	{"id": "aqua_straight", "name": "Aqueduct Arcade", "family": "aqueducts", "sockets": ["A", "U", "A", "U"], "weight": 8, "rotations": [0, 1],
		"desc": "Twin-tiered travertine arches carrying an elevated water specus across the district."},
	{"id": "aqua_overpass", "name": "Aqueduct Road Overpass", "family": "aqueducts", "sockets": ["A", "R", "A", "R"], "weight": 7, "rotations": [0, 1],
		"desc": "Grand monumental arch carrying the water channel overhead while a Via passes beneath."},
	{"id": "aqua_corner", "name": "Aqueduct Elbow Pier", "family": "aqueducts", "sockets": ["A", "A", "U", "U"], "weight": 3, "rotations": [0, 1, 2, 3],
		"desc": "Buttressed limestone corner pier redirecting the elevated aqueduct channel."},
	{"id": "aqua_castellum", "name": "Castellum Aquae", "family": "aqueducts", "sockets": ["A", "U", "R", "U"], "weight": 5, "rotations": [0, 1, 2, 3],
		"desc": "Domed settling reservoir and street-facing nymphaeum terminating an aqueduct."},
	{"id": "aqua_spring", "name": "Aqueduct Spring Tower", "family": "aqueducts", "sockets": ["A", "U", "U", "U"], "weight": 3, "rotations": [0, 1, 2, 3],
		"desc": "Elevated masonry intake tower anchoring the start of a city water line."},

	# INSULAE (Roman Apartment Tenements)
	{"id": "insula_street", "name": "Insula Tabernae", "family": "insulae", "sockets": ["U", "U", "R", "U"], "weight": 14, "rotations": [0, 1, 2, 3],
		"desc": "Four-story brick-and-plaster tenement with arched ground-floor shops facing the street."},
	{"id": "insula_corner", "name": "Corner Insula Block", "family": "insulae", "sockets": ["U", "R", "R", "U"], "weight": 9, "rotations": [0, 1, 2, 3],
		"desc": "L-plan urban apartment block wrapping two streets with a corner thermopolium counter."},
	{"id": "insula_horrea", "name": "Horrea Granary Court", "family": "insulae", "sockets": ["U", "U", "U", "U"], "weight": 5, "rotations": [0, 1],
		"desc": "Interior-block brick warehouse and courtyard housing amphorae and grain stores."},

	# DOMUS (Aristocratic Courtyard Villas)
	{"id": "domus_atrium", "name": "Atrium Domus", "family": "domus", "sockets": ["U", "U", "R", "U"], "weight": 10, "rotations": [0, 1, 2, 3],
		"desc": "Patrician residence featuring an open compluvium roof above a sunlit impluvium pool."},
	{"id": "domus_peristyle", "name": "Peristyle Villa Wing", "family": "domus", "sockets": ["U", "U", "U", "U"], "weight": 7, "rotations": [0, 1],
		"desc": "Secluded terracotta portico enclosing a miniature courtyard fountain and frescoed walls."},

	# FORUMS (Civic Plazas & Temples)
	{"id": "forum_plaza", "name": "Forum Marble Plaza", "family": "forums", "sockets": ["F", "F", "F", "F"], "weight": 8, "rotations": [0],
		"desc": "Open travertine civic square with bronze equestrian statue and orator's rostra."},
	{"id": "forum_colonnade", "name": "Forum Street Portico", "family": "forums", "sockets": ["F", "F", "R", "F"], "weight": 8, "rotations": [0, 1, 2, 3],
		"desc": "Stepped Corinthian colonnade opening directly from a Via Romana into the Forum."},
	{"id": "forum_edge", "name": "Forum Colonnade Wall", "family": "forums", "sockets": ["U", "F", "F", "F"], "weight": 8, "rotations": [0, 1, 2, 3],
		"desc": "Marble perimeter stoa framing the northern or lateral edge of a Roman Forum."},
	{"id": "forum_corner", "name": "Forum Corner Stoa", "family": "forums", "sockets": ["U", "U", "F", "F"], "weight": 7, "rotations": [0, 1, 2, 3],
		"desc": "L-shaped colonnaded pavilion turning the corner of an imperial plaza."},
	{"id": "forum_temple", "name": "Capitoline Temple", "family": "forums", "sockets": ["U", "U", "F", "U"], "weight": 5, "rotations": [0, 1, 2, 3], "solitary": true,
		"desc": "Raised-podium hexastyle temple with triangular pediment and glowing altar brazier."},
	{"id": "forum_passage", "name": "Forum Arch Arcade", "family": "forums", "sockets": ["F", "U", "F", "U"], "weight": 4, "rotations": [0, 1],
		"desc": "Twin-sided travertine portico gallery linking adjacent civic plaza courts."},

	# CYPRESS GARDENS (Horti & Sacred Groves)
	{"id": "garden_cypress", "name": "Cypress Grove", "family": "gardens", "sockets": ["U", "U", "U", "U"], "weight": 10, "rotations": [0, 1],
		"desc": "Sculpted Mediterranean garden of slender dark cypresses, stone pines, and gravel walks."},
	{"id": "garden_nymphaeum", "name": "Nymphaeum Park", "family": "gardens", "sockets": ["U", "U", "R", "U"], "weight": 6, "rotations": [0, 1, 2, 3],
		"desc": "Street-facing sacred cypress garden with a semicircular travertine water basin."},
	{"id": "garden_pergola", "name": "Orchard & Pergola", "family": "gardens", "sockets": ["U", "U", "U", "U"], "weight": 6, "rotations": [0, 1],
		"desc": "Timber vine pergola flanked by cypress trees and terracotta olive-oil amphorae."},
]

static var _initialized := false
static var variant_count := 0
static var v_module: PackedStringArray
static var v_name: PackedStringArray
static var v_family: PackedInt32Array
static var v_rot: PackedInt32Array
static var v_sockets: PackedInt32Array   # variant * 4 + dir
static var v_weight: PackedFloat64Array
static var v_logw: PackedFloat64Array    # w * ln(w)
static var compat_lo: PackedInt64Array   # variant * 4 + dir -> allowed neighbours in dir
static var compat_hi: PackedInt64Array
static var all_lo := 0
static var all_hi := 0
static var pin_lo: PackedInt64Array      # pin kind -> mask
static var pin_hi: PackedInt64Array
static var pin_union_lo: PackedInt64Array  # pin kind * 4 + dir -> union of compat over the pin mask
static var pin_union_hi: PackedInt64Array
static var module_by_id: Dictionary = {}


static func setup() -> void:
	if _initialized:
		return
	_initialized = true

	for mod: Dictionary in BASE_MODULES:
		module_by_id[mod["id"]] = mod
		var socks: Array = mod["sockets"]
		var rots: Array = mod["rotations"]
		var mult: float = FAMILY_WEIGHT_MULT.get(mod["family"], 1.0)
		for rot: int in rots:
			# Rotate clockwise by rot * 90 deg: [N, E, S, W] -> after 1 CW turn: [W, N, E, S]
			for d in 4:
				v_sockets.append(SOCKET_CODES[socks[(4 + d - rot) % 4]])
			v_module.append(mod["id"])
			v_name.append(mod["name"])
			v_family.append(FAMILIES.find(mod["family"]))
			v_rot.append(rot)
			var w: float = float(mod["weight"]) * mult / float(rots.size())
			v_weight.append(w)
			v_logw.append(w * log(w))
	variant_count = v_module.size()
	assert(variant_count <= BITS * 2, "Too many variants for a 2-word bitset")

	for i in variant_count:
		if i < BITS:
			all_lo |= 1 << i
		else:
			all_hi |= 1 << (i - BITS)

	compat_lo.resize(variant_count * 4)
	compat_hi.resize(variant_count * 4)
	for v in variant_count:
		var solitary: bool = module_by_id[v_module[v]].get("solitary", false)
		for d in 4:
			var opp: int = OPP[d]
			var need := v_sockets[v * 4 + d]
			var lo := 0
			var hi := 0
			for j in variant_count:
				if v_sockets[j * 4 + opp] != need:
					continue
				if solitary and v_module[j] == v_module[v]:
					continue
				if j < BITS:
					lo |= 1 << j
				else:
					hi |= 1 << (j - BITS)
			compat_lo[v * 4 + d] = lo
			compat_hi[v * 4 + d] = hi

	# Street-grid pins
	pin_lo.resize(4)
	pin_hi.resize(4)
	pin_lo[PIN_NONE] = all_lo
	pin_hi[PIN_NONE] = all_hi
	var kinds := {
		PIN_CARDO: [0, 2],
		PIN_DECUMANUS: [1, 3],
		PIN_CROSS: [0, 1, 2, 3],
	}
	for k: int in kinds:
		var lo := 0
		var hi := 0
		for v in variant_count:
			var ok := true
			for d: int in kinds[k]:
				if v_sockets[v * 4 + d] != SOCK_R:
					ok = false
			if ok:
				if v < BITS:
					lo |= 1 << v
				else:
					hi |= 1 << (v - BITS)
		pin_lo[k] = lo
		pin_hi[k] = hi

	pin_union_lo.resize(16)
	pin_union_hi.resize(16)
	for k in 4:
		for d in 4:
			var ulo := 0
			var uhi := 0
			for v in variant_count:
				if has_bit(pin_lo[k], pin_hi[k], v):
					ulo |= compat_lo[v * 4 + d]
					uhi |= compat_hi[v * 4 + d]
			pin_union_lo[k * 4 + d] = ulo
			pin_union_hi[k * 4 + d] = uhi


static func has_bit(lo: int, hi: int, i: int) -> bool:
	if i < BITS:
		return ((lo >> i) & 1) == 1
	return ((hi >> (i - BITS)) & 1) == 1


static func popcount(x: int) -> int:
	var c := 0
	while x != 0:
		x &= x - 1
		c += 1
	return c


static func is_walkable_family(fam: int) -> bool:
	return fam == FAM_ROADS or fam == FAM_FORUMS or fam == FAM_GARDENS


static func find_variant(module_id: String, rot: int) -> int:
	for v in variant_count:
		if v_module[v] == module_id and v_rot[v] == rot:
			return v
	return -1
