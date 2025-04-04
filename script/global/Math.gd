#sync
class_name Math

func _init() -> void:
	assert(false, "This class should not be instanced!")

static func lerp_factor_frame_rate_independent(_lerp_factor_: float, _dt_: float) -> float:
	# if f is lerp factor, k is reference frame rate, d is real delta time
	# lerp(a, b, f) is frame rate dependent
	# to make it frame rate independent we set f = 1 - r^d with r = (1 - f)^k
	# so lerp(a, b, 0.1) at k = 60fps equivalent to lerp(a, b, 1 - 0.001797^d) at all fps
	return 1.0 - ((1.0 - _lerp_factor_)**60.0)**_dt_

static func calculate_center_of_convex(_convex_: ConvexPolygonShape3D) -> Vector3:
	var center := Vector3.ZERO
	var points := _convex_.points
	for p in points:
		center += p
	return center / points.size()

## Return magnitude of _a_ with sign of _b_
static func copy_signf(_a_: float, _b_: float) -> float:
	return -absf(_a_) if _b_ < 0.0 else absf(_a_)

## Return a non-zero perpendicular vector of vector _u_
static func get_perpendicular_vector(_u_: Vector3) -> Vector3:
	return Vector3(
		copy_signf(_u_.z, _u_.x),
		copy_signf(_u_.z, _u_.y),
		-copy_signf(_u_.x, _u_.z) - copy_signf(_u_.y, _u_.z)
	)

static func screen_position_project_on_plane(_camera_: Camera3D, _screen_position_: Vector2, _plane_point_: Vector3, _plane_normal_: Vector3) -> Vector3:
	var ray_origin := _camera_.project_position(_screen_position_, 1.0)
	var ray_direction := _camera_.project_ray_normal(_screen_position_)
	var delta := _plane_point_ - ray_origin
	var ray_dot_plane := ray_direction.dot(_plane_normal_)
	if ray_dot_plane == 0.0:
		return _plane_point_
	var enter := delta.length() * (delta.normalized().dot(_plane_normal_) / ray_dot_plane)
	return ray_origin + enter * ray_direction

class SecondOrderDynamics extends RefCounted:
	var xp: Vector3
	var y: Vector3 
	var yd: Vector3
	var k1: float
	var k2: float
	var k3: float
	func _init(_f_: float, _z_: float, _r_: float, _x0_: Vector3) -> void:
		# f is frequency, z is damping, r is initial response
		k1 = _z_ / (PI * _f_)
		k2 = 1.0 / ((2.0 * PI * _f_) * (2.0 * PI * _f_))
		k3 = _r_ * _z_ / (2.0 * PI * _f_)
		xp = _x0_
		y = _x0_
		yd = Vector3.ZERO
	func update(_dt_: float, _x_: Vector3, _xd_: Vector3 = Vector3(INF, INF, INF)) -> Vector3:
		if _xd_.x == INF:
			_xd_ = (_x_ - xp) / _dt_
			xp = _x_
		var k2_stable: float = max(k2, _dt_ * _dt_ / 2.0 + _dt_ * k1 / 2.0, _dt_ * k1)
		y = y + _dt_ * yd # p = p + dt * v
		yd = yd + _dt_ * (_x_ + k3 * _xd_ - y - k1 * yd) / k2_stable # v = v + dt * a
		return y
#endsync
