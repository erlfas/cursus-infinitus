class_name Citizen
extends CharacterBody3D
## The running Roman citizen: procedural low-poly model + procedural run cycle.
## Steering is relative to the follow camera's yaw (set by FollowCamera).

const RUN_SPEED := 6.5
const SPRINT_SPEED := 10.5
const ACCEL := 22.0
const DECEL := 16.0
const JUMP_VELOCITY := 5.2
const GRAVITY := 16.0

var cam_yaw := 0.0
var facing := 0.0
var distance_m := 0.0
var input_enabled := true
var autopilot := false   # used by the --autoshot smoke test
var _auto_t := 0.0

var _phase := 0.0
var _lean := 0.0
var _roll := 0.0
var _model: Node3D
var _body: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _head: Node3D
var _lantern: OmniLight3D


func _ready() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50)
	_build_model()


func set_lantern(on: bool) -> void:
	_lantern.visible = on


func teleport(pos: Vector3, yaw: float) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	facing = yaw
	_model.rotation.y = yaw
	distance_m = 0.0
	reset_physics_interpolation()


# ------------------------------------------------------------------ movement
func _physics_process(dt: float) -> void:
	var input := Vector2.ZERO
	var sprint := false
	var jump := false
	if input_enabled:
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			input.y += 1.0
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			input.y -= 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			input.x += 1.0
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			input.x -= 1.0
		sprint = Input.is_physical_key_pressed(KEY_SHIFT)
		jump = Input.is_physical_key_pressed(KEY_SPACE)
	if autopilot:
		_auto_t += dt
		input = Vector2(sin(_auto_t * 0.35) * 0.35, 1.0)
	input = input.limit_length(1.0)

	var dir := Basis(Vector3.UP, cam_yaw) * Vector3(input.x, 0.0, -input.y)
	var target := dir * (SPRINT_SPEED if sprint else RUN_SPEED)
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var rate := ACCEL if target.length_squared() > 0.01 else DECEL
	hv = hv.move_toward(target, rate * dt)
	velocity.x = hv.x
	velocity.z = hv.z

	if is_on_floor():
		if jump:
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= GRAVITY * dt

	var before := global_position
	move_and_slide()
	var moved := global_position - before
	moved.y = 0.0
	distance_m += moved.length()

	var speed := Vector2(velocity.x, velocity.z).length()
	var prev_facing := facing
	if speed > 0.4:
		facing = lerp_angle(facing, atan2(-velocity.x, -velocity.z), 1.0 - exp(-12.0 * dt))
	var turn_rate := wrapf(facing - prev_facing, -PI, PI) / maxf(dt, 0.0001)
	_animate(dt, speed, turn_rate)


# ------------------------------------------------------------------ model
static func _mat(hex: String, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = rough
	return m


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 12
	m.rings = 4
	return m


static func _cyl(rt: float, rb: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = 14
	return m


static func _box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = s
	return m


static func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 14
	m.rings = 8
	return m


func _build_model() -> void:
	var tunic := _mat("#b84a24")
	var toga := _mat("#f2e6d5", 0.9)
	var skin := _mat("#c98f6b", 0.7)
	var hair := _mat("#3b2a20", 0.9)
	var leather := _mat("#6f4b32")
	var bronze := _mat("#c5973d", 0.35)
	bronze.metallic = 0.75
	var laurel := _mat("#2b6349")

	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	_body = Node3D.new()
	_model.add_child(_body)

	# legs (pivot at hip)
	_leg_l = Node3D.new()
	_leg_l.position = Vector3(-0.11, 0.9, 0)
	_body.add_child(_leg_l)
	_leg_r = Node3D.new()
	_leg_r.position = Vector3(0.11, 0.9, 0)
	_body.add_child(_leg_r)
	for leg: Node3D in [_leg_l, _leg_r]:
		_part(leg, _capsule(0.075, 0.86), skin, Vector3(0, -0.43, 0))
		_part(leg, _box(Vector3(0.13, 0.06, 0.24)), leather, Vector3(0, -0.86, -0.04))
		_part(leg, _cyl(0.085, 0.085, 0.05), leather, Vector3(0, -0.72, 0))   # sandal strap

	# torso: tunic skirt, chest, belt, toga sash
	_part(_body, _cyl(0.21, 0.3, 0.5), tunic, Vector3(0, 1.02, 0))
	_part(_body, _capsule(0.19, 0.62), tunic, Vector3(0, 1.36, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.8))
	_part(_body, _cyl(0.215, 0.215, 0.06), leather, Vector3(0, 1.12, 0))
	_part(_body, _box(Vector3(0.12, 0.72, 0.36)), toga, Vector3(0.0, 1.33, 0.0), Vector3(0, 0, 0.62))
	_part(_body, _sphere(0.035), bronze, Vector3(-0.15, 1.56, -0.13))  # fibula brooch

	# head
	_head = Node3D.new()
	_head.position = Vector3(0, 1.68, 0)
	_body.add_child(_head)
	_part(_head, _cyl(0.06, 0.07, 0.12), skin, Vector3(0, -0.1, 0))
	_part(_head, _sphere(0.13), skin, Vector3(0, 0.03, 0))
	_part(_head, _sphere(0.135), hair, Vector3(0, 0.07, 0.02), Vector3.ZERO, Vector3(1.0, 0.75, 1.0))
	_part(_head, _box(Vector3(0.05, 0.05, 0.06)), skin, Vector3(0, 0.02, -0.14))  # nose
	var wreath := TorusMesh.new()
	wreath.inner_radius = 0.12
	wreath.outer_radius = 0.155
	_part(_head, wreath, laurel, Vector3(0, 0.09, 0.0))

	# arms (pivot at shoulder)
	_arm_l = Node3D.new()
	_arm_l.position = Vector3(-0.26, 1.55, 0)
	_body.add_child(_arm_l)
	_arm_r = Node3D.new()
	_arm_r.position = Vector3(0.26, 1.55, 0)
	_body.add_child(_arm_r)
	for arm: Node3D in [_arm_l, _arm_r]:
		_part(arm, _sphere(0.085), tunic, Vector3(0, -0.02, 0))
		_part(arm, _capsule(0.06, 0.62), skin, Vector3(0, -0.3, 0))

	_lantern = OmniLight3D.new()
	_lantern.light_color = Color("#ffb347")
	_lantern.light_energy = 2.2
	_lantern.omni_range = 9.0
	_lantern.shadow_enabled = false
	_lantern.position = Vector3(0.0, 2.3, 0.4)
	_lantern.visible = false
	_model.add_child(_lantern)


func _animate(dt: float, speed: float, turn_rate: float) -> void:
	var amt := clampf(speed / RUN_SPEED, 0.0, 1.6)
	var airborne := not is_on_floor()
	_phase += dt * (5.0 + speed * 1.15)
	var swing := sin(_phase)
	var k := 1.0 - exp(-14.0 * dt)
	var leg_amp := 0.95 * minf(amt, 1.2)
	var arm_amp := 0.8 * minf(amt, 1.2)
	if airborne:
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.9, k)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, -0.35, k)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -1.6, k)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -1.4, k)
	else:
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, swing * leg_amp, k)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, -swing * leg_amp, k)
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -swing * arm_amp, k)
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, swing * arm_amp, k)
	_arm_l.rotation.z = lerpf(_arm_l.rotation.z, -0.12 - 0.1 * amt, k)
	_arm_r.rotation.z = lerpf(_arm_r.rotation.z, 0.12 + 0.1 * amt, k)

	var bob := absf(cos(_phase)) * 0.08 * minf(amt, 1.2) if not airborne else 0.0
	_body.position.y = lerpf(_body.position.y, bob, k)
	_head.rotation.x = lerpf(_head.rotation.x, 0.12 * amt, k)

	_lean = lerpf(_lean, -0.16 * amt, k * 0.6)
	_roll = lerpf(_roll, clampf(-turn_rate * 0.05 * amt, -0.35, 0.35), k * 0.5)
	_model.rotation = Vector3(_lean, facing, _roll)
