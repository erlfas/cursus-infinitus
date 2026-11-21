class_name FollowCamera
extends Node3D
## Third-person chase camera. Mouse (when captured) orbits; while running without
## mouse input the camera eases back behind the citizen. A SpringArm3D keeps the
## camera from clipping into buildings.

const HEIGHT := 1.55

var target: Citizen
var yaw := 0.0
var pitch := -0.3
var distance := 6.0
var mouse_sensitivity := 0.0032

var arm: SpringArm3D
var camera: Camera3D
var _pitch_node: Node3D
var _idle := 10.0


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_pitch_node = Node3D.new()
	add_child(_pitch_node)
	arm = SpringArm3D.new()
	arm.spring_length = distance
	arm.margin = 0.25
	var sph := SphereShape3D.new()
	sph.radius = 0.3
	arm.shape = sph
	_pitch_node.add_child(arm)
	camera = Camera3D.new()
	camera.fov = 64.0
	camera.near = 0.08
	camera.far = 260.0
	arm.add_child(camera)
	camera.make_current()


func snap_to_target() -> void:
	if target:
		yaw = target.facing
		global_position = target.global_position + Vector3(0, HEIGHT, 0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		yaw -= mm.relative.x * mouse_sensitivity
		pitch = clampf(pitch - mm.relative.y * mouse_sensitivity, -1.25, 0.3)
		_idle = 0.0
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = clampf(distance * 0.9, 2.5, 16.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = clampf(distance * 1.1, 2.5, 16.0)


func _process(dt: float) -> void:
	if target == null:
		return
	var goal := target.get_global_transform_interpolated().origin + Vector3(0, HEIGHT, 0)
	global_position = global_position.lerp(goal, 1.0 - exp(-18.0 * dt))
	_idle += dt
	var hs := Vector2(target.velocity.x, target.velocity.z).length()
	if _idle > 1.2 and hs > 1.5:
		yaw = lerp_angle(yaw, target.facing, 1.0 - exp(-1.4 * dt))
	rotation = Vector3(0, yaw, 0)
	_pitch_node.rotation = Vector3(pitch, 0, 0)
	arm.spring_length = lerpf(arm.spring_length, distance, 1.0 - exp(-8.0 * dt))
	target.cam_yaw = yaw
