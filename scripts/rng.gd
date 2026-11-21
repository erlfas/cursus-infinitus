class_name WfcRng
extends RefCounted
## Deterministic PRNG ported 1:1 from the HTML generator:
## FNV-1a string hash (hashSeed) + mulberry32 (createPRNG).
## All arithmetic is kept in unsigned 32-bit space so results match the JS version.

const MASK32 := 0xFFFFFFFF

var _a: int = 1


func _init(seed_num: int = 1) -> void:
	_a = seed_num & MASK32
	if _a == 0:
		_a = 1


## Equivalent of JS Math.imul (low 32 bits of a*b), safe against int64 overflow.
static func imul(a: int, b: int) -> int:
	a &= MASK32
	b &= MASK32
	var ah := a >> 16
	var al := a & 0xFFFF
	return ((al * b) + (((ah * b) & 0xFFFF) << 16)) & MASK32


static func hash_seed(s: String) -> int:
	if s.is_empty():
		s = "ROMA-753"
	var h := 2166136261
	for i in s.length():
		h ^= s.unicode_at(i)
		h = imul(h, 16777619)
	return h & MASK32


## Returns a float in [0, 1).
func next_float() -> float:
	_a = (_a + 0x6D2B79F5) & MASK32
	var t := imul(_a ^ (_a >> 15), 1 | _a)
	t = ((t + imul(t ^ (t >> 7), 61 | t)) & MASK32) ^ t
	return float((t ^ (t >> 14)) & MASK32) / 4294967296.0
