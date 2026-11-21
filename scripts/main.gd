extends Node3D
## Forma Urbis — Endless Run.
## Wires together the infinite WFC world, chunk streaming, the running citizen,
## the chase camera, lighting, HUD and pause menu.
##
## Smoke test: `godot --path . -- --autoshot` runs the citizen on autopilot,
## saves screenshots to user://autoshot_*.png and quits.

const CFG_PATH := "user://forma_urbis.cfg"
const SPAWN_CELL := Vector2i(0, 0)   # avenue crossing (cardo x decumanus)

var seed_text := "ROMA-753"
var lighting := "meridies"

var env: Environment
var sun: DirectionalLight3D
var ground: MeshInstance3D
var citizen: Citizen
var cam: FollowCamera
var streamer: ChunkStreamer
var hud: Hud
var menu: PauseMenu

var _time := 0.0
var _autoshot := false
var _shots_taken := 0


func _ready() -> void:
	_autoshot = "--autoshot" in OS.get_cmdline_user_args()
	_load_settings()
	WfcData.setup()
	RomanMeshes.prewarm()

	_build_environment()
	_build_ground()

	citizen = Citizen.new()
	citizen.name = "Citizen"
	add_child(citizen)

	cam = FollowCamera.new()
	cam.name = "FollowCamera"
	cam.target = citizen
	add_child(cam)
	cam.arm.add_excluded_object(citizen.get_rid())

	streamer = ChunkStreamer.new()
	streamer.name = "City"
	streamer.target = citizen
	add_child(streamer)

	hud = Hud.new()
	hud.citizen = citizen
	hud.streamer = streamer
	add_child(hud)

	menu = PauseMenu.new()
	add_child(menu)
	menu.lighting_changed.connect(_on_lighting_changed)
	menu.seed_changed.connect(_on_seed_changed)
	menu.sync(lighting, seed_text)

	Lighting.apply(lighting, env, sun, citizen)
	_found_city(seed_text)

	if _autoshot:
		citizen.autopilot = true
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = 1.0
	env.fog_depth_begin = 38.0
	env.fog_depth_end = 92.0
	env.fog_depth_curve = 1.4
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_hdr_threshold = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 75.0
	sun.shadow_bias = 0.04
	add_child(sun)


func _build_ground() -> void:
	# Infinite walkable floor + a large earth plane that follows the runner
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(cs)
	add_child(floor_body)

	ground = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(480, 480)
	ground.mesh = plane
	ground.material_override = RomanMeshes.mats["ground"]
	ground.position.y = -0.15
	ground.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(ground)


func _found_city(p_seed: String) -> void:
	seed_text = p_seed
	var world := WfcWorld.new(seed_text)
	streamer.reset(world)
	var spawn_chunk := WfcWorld.chunk_of_cell(SPAWN_CELL)
	streamer.presolve(spawn_chunk, 1)
	# Face along whichever avenue leads away from the crossing (north = -Z)
	citizen.teleport(WfcWorld.cell_center(SPAWN_CELL) + Vector3(0, 0.05, 0), 0.0)
	cam.snap_to_target()
	_save_settings()


func _process(dt: float) -> void:
	_time += dt
	Lighting.animate_water(_time)
	var p := citizen.global_position
	ground.global_position = Vector3(snappedf(p.x, 4.0), -0.15, snappedf(p.z, 4.0))
	streamer.heading = citizen.velocity

	if _autoshot:
		_run_autoshot()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not menu.is_open():
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_lighting_changed(preset: String) -> void:
	lighting = preset
	Lighting.apply(lighting, env, sun, citizen)
	_save_settings()


func _on_seed_changed(p_seed: String) -> void:
	_found_city(p_seed)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK:
		seed_text = str(cfg.get_value("city", "seed", seed_text))
		lighting = str(cfg.get_value("city", "lighting", lighting))
	if not Lighting.PRESETS.has(lighting):
		lighting = "meridies"


func _save_settings() -> void:
	if _autoshot:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("city", "seed", seed_text)
	cfg.set_value("city", "lighting", lighting)
	cfg.save(CFG_PATH)


# ------------------------------------------------------------------ smoke test
func _run_autoshot() -> void:
	var marks := [1.2, 2.5, 9.0, 16.0]
	if _shots_taken < marks.size() and _time >= marks[_shots_taken]:
		var img := get_viewport().get_texture().get_image()
		var path := "user://autoshot_%d.png" % _shots_taken
		img.save_png(path)
		print("AUTOSHOT ", ProjectSettings.globalize_path(path), " t=%.1f dist=%.1fm chunks=%d views=%d fps=%d pos=%s" % [
			_time, citizen.distance_m, streamer.world.chunks.size(), streamer.views.size(),
			Engine.get_frames_per_second(), citizen.global_position])
		_shots_taken += 1
		if _shots_taken == 2:
			# switch to dusk mid-run to exercise the lighting presets
			_on_lighting_changed("vespera")
	if _shots_taken >= marks.size():
		get_tree().quit()
