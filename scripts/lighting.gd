class_name Lighting
extends RefCounted
## Daylight presets ported from applyLightingToThree(): meridies, vespera, nox.

const PRESETS := {
	"meridies": {
		"label": "Meridies (Sunlit)",
		"bg": "#e9dcc8", "fog": "#eadfcd",
		"sun": "#fff0d6", "sun_energy": 1.2, "sun_pos": Vector3(24, 34, 18),
		"ambient": "#f6e8d4", "ambient_energy": 0.42,
		"window": 0.08, "brazier": 0.6, "lantern": false, "exposure": 0.92,
	},
	"vespera": {
		"label": "Vespera (Golden Dusk)",
		"bg": "#dec0a4", "fog": "#d9b493",
		"sun": "#ff9f59", "sun_energy": 1.3, "sun_pos": Vector3(32, 16, -16),
		"ambient": "#ffc99e", "ambient_energy": 0.42,
		"window": 1.2, "brazier": 2.0, "lantern": false, "exposure": 1.0,
	},
	"nox": {
		"label": "Nox (Lantern Night)",
		"bg": "#211916", "fog": "#1d1714",
		"sun": "#88a8d8", "sun_energy": 0.45, "sun_pos": Vector3(-18, 28, -22),
		"ambient": "#465878", "ambient_energy": 0.35,
		"window": 3.0, "brazier": 4.0, "lantern": true, "exposure": 1.15,
	},
}
const ORDER := ["meridies", "vespera", "nox"]

static var water_base := 0.35


static func apply(preset: String, env: Environment, sun: DirectionalLight3D, citizen: Citizen) -> void:
	var p: Dictionary = PRESETS.get(preset, PRESETS["meridies"])
	env.background_color = Color(p["bg"])
	env.fog_light_color = Color(p["fog"])
	env.ambient_light_color = Color(p["ambient"])
	env.ambient_light_energy = p["ambient_energy"]
	env.tonemap_exposure = p["exposure"]
	sun.light_color = Color(p["sun"])
	sun.light_energy = p["sun_energy"]
	var sp: Vector3 = p["sun_pos"]
	sun.basis = Basis.looking_at(-sp.normalized(), Vector3.UP)
	(RomanMeshes.mats["windowGlow"] as StandardMaterial3D).emission_energy_multiplier = p["window"]
	(RomanMeshes.mats["brazierFire"] as StandardMaterial3D).emission_energy_multiplier = p["brazier"]
	water_base = 0.35 if preset != "nox" else 0.8
	if citizen:
		citizen.set_lantern(p["lantern"])


## Water shimmer (from the original main loop).
static func animate_water(time_s: float) -> void:
	var m: StandardMaterial3D = RomanMeshes.mats["water"]
	m.emission_energy_multiplier = water_base * (0.7 + 0.34 * sin(time_s * 2.5))
