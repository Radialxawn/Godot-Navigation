class_name NavigationField
extends Node3D

static func spawn(_parent_: Node) -> NavigationField:
	var result := (load("res://navigation/navigation_field.tscn") as PackedScene).instantiate() as NavigationField
	_parent_.add_child(result)
	return result

var _debug_cells: MultiMeshInstance3D
var _debug_cells_vector: MultiMeshInstance3D
var _cell_grid: CellGrid

func _ready() -> void:
	_debug_cells = $debug_cells
	_debug_cells_vector = $debug_cells_vector

func create(_size_: Vector2i, _cell_size_: Vector2, _debug_: bool) -> NavigationField:
	_cell_grid = CellGrid.new(_size_, _cell_size_)
	if not _debug_:
		_debug_cells.queue_free()
		_debug_cells_vector.queue_free()
	else:
		_debug_cells.multimesh.instance_count = _size_.x * _size_.y
		_debug_cells_vector.multimesh.instance_count = _debug_cells.multimesh.instance_count
	return self

func cell_grid_get() -> CellGrid:
	return _cell_grid

func position_set(_position_: Vector3, _anchor_: Vector2) -> void:
	position = Vector3(
		_position_.x - _cell_grid.bound.min_x - _anchor_.x * _cell_grid.bound.x,
		_position_.y,
		_position_.z - _cell_grid.bound.min_y - _anchor_.y * _cell_grid.bound.y,
	)
	_cell_grid.debug_offset = position

static func _agent_neighbors_id_get(_cell_grid_: CellGrid, _agents_: Dictionary[int, Agent], _agent_id_: int) -> int:
	var agent := _agents_[_agent_id_]
	var count := 0
	var count_max := agent.neighbors_id.size()
	var cell := _cell_grid_.cell_get(agent.cell_id)
	for agent_id: int in cell.agents_id:
		if agent_id != agent.id:
			if count < count_max:
				agent.neighbors_id[count] = agent_id
				count += 1
	for neighbor_id: int in cell.neighbors_id:
		var neighbor := _cell_grid_.cell_get(neighbor_id)
		for agent_id: int in neighbor.agents_id:
			if count < count_max:
				agent.neighbors_id[count] = agent_id
				count += 1
	return count

static func agent_exit(_agent_: Agent, _cell_grid_: CellGrid) -> void:
	if _agent_.cell_id != -1:
		_cell_grid_.cell_get(_agent_.cell_id).agents_id.erase(_agent_.id)

static func agent_enter(_agent_: Agent, _cell_grid_: CellGrid) -> void:
	var cell_id := _cell_grid_.cell_id_nearest_get(_agent_.position)
	if cell_id != _agent_.cell_id:
		if _agent_.cell_id != -1:
			_cell_grid_.cell_get(_agent_.cell_id).agents_id.erase(_agent_.id)
		_agent_.cell_id = cell_id
		if cell_id != -1:
			_cell_grid_.cell_get(cell_id).agents_id.append(_agent_.id)

static func agent_move(_agent_: Agent, _dt_: float) -> void:
	var force_move := Vector2.ZERO
	if _agent_.target_ing: # calculate move force
		var delta := _agent_.target - _agent_.position
		var delta_length := delta.length()
		_agent_.target_near = delta_length < _agent_.radius
		if _agent_.target_near or _agent_.target_near_sub: # stop when near target
			_agent_.target_near_sub = false
			_agent_.speed_factor = 0.0
		else:
			if _agent_.safe_direction.length_squared() > 0.0: # have safe direction, move along the safe direction
				force_move = _agent_.safe_direction * _agent_.position_speed_max
			else: # no safe direction, then move with the default direction
				force_move = (delta / delta_length) * _agent_.position_speed_max
			_agent_.speed_factor = minf(_agent_.speed_factor + _agent_.acceleration * _dt_, 1.0)
	_agent_.force_move = force_move
	var dt := _agent_.speed_factor * _dt_
	var direction := Vector2.from_angle(_agent_.rotation)
	var delta_rotation := direction.angle_to(force_move)
	var delta_rotation_sign := signf(delta_rotation)
	var delta_rotation_max_abs := _agent_.rotation_speed_max * dt
	var delta_rotation_real := delta_rotation_sign * minf(delta_rotation_max_abs, delta_rotation_sign * delta_rotation)
	var rotation_predict := wrapf(_agent_.rotation + delta_rotation_real, -PI, PI)
	var position_predict := _agent_.position + Vector2.from_angle(rotation_predict) * (force_move.length() * dt)
	_agent_.rotation_predict = rotation_predict
	_agent_.position_predict = position_predict

static func agent_avoid_obstacle(_cell_grid_: CellGrid, _agents_: Dictionary[int, Agent], _agent_id_: int, _obstacles_: Array[Obstacle], _dt_: float) -> void:
	var agent := _agents_[_agent_id_]
	var distance_hits: Array[DistanceHit]
	var obstacles_id_visisted: Array[int]
	if agent.cell_id != -1:
		var cell := _cell_grid_.cell_get(agent.cell_id)
		for neighbor_id: int in cell.neighbors_id:
			var neighbor := _cell_grid_.cell_get(neighbor_id)
			for obstacle_id: int in neighbor.obstacles_id:
				if obstacle_id not in obstacles_id_visisted:
					var obstacle := _obstacles_[obstacle_id]
					obstacle.calculate_distance(agent.position_predict, agent.radius, distance_hits)
					obstacles_id_visisted.append(obstacle_id)
	var force_obstacle := Vector2.ZERO
	for distance_hit: DistanceHit in distance_hits:
		force_obstacle -= distance_hit.normal * distance_hit.distance;
	var field_l := _cell_grid_.bound.limit_min.x - (agent.position_predict.x - agent.radius)
	var field_r := _cell_grid_.bound.limit_max.x - (agent.position_predict.x + agent.radius)
	var field_b := _cell_grid_.bound.limit_min.y - (agent.position_predict.y - agent.radius)
	var field_t := _cell_grid_.bound.limit_max.y - (agent.position_predict.y + agent.radius)
	if field_l >= 0.0:
		force_obstacle.x += field_l
	if field_r <= 0.0:
		force_obstacle.x += field_r
	if field_b >= 0.0:
		force_obstacle.y += field_b
	if field_t <= 0.0:
		force_obstacle.y += field_t
	agent.force_obstacle = force_obstacle
	if force_obstacle.x != 0.0 or force_obstacle.y != 0.0:
		agent.position_predict += force_obstacle

static func agent_avoid_other(_cell_grid_: CellGrid, _agents_: Dictionary[int, Agent], _agent_id_: int, _dt_: float) -> void:
	var force_other := Vector2.ZERO
	var agent := _agents_[_agent_id_]
	var neighbors_count := _agent_neighbors_id_get(_cell_grid_, _agents_, _agent_id_)
	agent.safe_direction = Vector2.ZERO
	var obstacle_normal := agent.force_obstacle.normalized()
	var sight := Sight.new(agent.position, agent.rotation, obstacle_normal)
	var ray_hit := RayHit.new()
	var direction_to_target_hit_obstacle := agent.target_ing and agent.position.direction_to(agent.target).dot(obstacle_normal) < -0.5
	var ray_hit_any := direction_to_target_hit_obstacle
	var predict_distance := agent.position.distance_to(agent.position_predict)
	var ray_hit_min_distance: float = predict_distance
	for i: int in neighbors_count:
		var agent_other := _agents_[agent.neighbors_id[i]]
		var delta := agent_other.position_predict - agent.position_predict
		var delta_length_sq := delta.length_squared()
		var delta_length_min := agent.radius + agent_other.radius
		var delta_length_min_sq := delta_length_min * delta_length_min
		if delta_length_sq < delta_length_min_sq: # agent overlap agent, the add force to move the agent out
			var delta_length := sqrt(delta_length_sq)
			var hit_distance := (delta_length_min - delta_length) * 0.5
			if delta_length < 1e-3:
				force_other -= hit_distance * Vector2.from_angle(agent.rotation)
			else:
				force_other -= (hit_distance / delta_length) * delta
		if delta_length_sq < delta_length_min_sq * 4.0:
			sight.check_cheap(agent_other.position_predict)
			if ray_hit.circle_cast_circle(agent.position, agent.position + agent.force_move * predict_distance, agent.radius,
				agent_other.position_predict, agent_other.radius
			):
				if ray_hit.distance < ray_hit_min_distance:
					ray_hit_any = true
					ray_hit_min_distance = ray_hit.distance
			if agent.target_ing and agent_other.target_ing and agent.target.distance_squared_to(agent_other.target) < delta_length_min_sq: # same target
				if agent_other.target_near or agent_other.target_near_sub: # stop when this agent is near an arrived agent
					agent.target_near_sub = true
					agent.speed_factor = 0.0
	if ray_hit_any:
		if ray_hit_min_distance < predict_distance or direction_to_target_hit_obstacle:
			if sight.safe_direction_get(): # there is a safe direction nearest to target direction
				agent.safe_direction = sight.safe_direction
				#agent.debug_draw_ray(agent.safe_direction, _cell_grid_.debug_offset, Color.GREEN)
			else: # no way to move
				agent.speed_factor = 0.0
				#Helper.debug_draw_sphere.call_deferred(Vector3(agent.position.x, 0.0, agent.position.y) + _cell_grid_.debug_offset, agent.radius, Color.BLACK)
	if agent.force_obstacle.length_squared() > 0.0: # if there is obstacle, project force to prevent object clipping
		if force_other.dot(agent.force_obstacle) < 0.0:
			var u := agent.force_obstacle.normalized()
			var n := Vector2(u.y, -u.x)
			force_other = n * force_other.dot(n)
	agent.position_predict += force_other
	# final stage
	agent.move_distance += agent.position.distance_to(agent.position_predict)
	agent.rotation = agent.rotation_predict
	agent.position = agent.position_predict

#region Debug
var debug_cell: bool
var debug_cell_vector: bool

func _debug_cell_transform_get(_x_: int, _y_: int) -> Transform3D:
	var cell_size := _cell_grid.cell_size
	return (Transform3D.IDENTITY
		.translated_local(Vector3(_x_ * cell_size.x, -cell_size.x * 0.5, _y_ * cell_size.y))
		.scaled_local(Vector3(cell_size.x, cell_size.x, cell_size.y))
	)

func _debug_cell_transform_vector_get(_x_: int, _y_: int) -> Transform3D:
	var cell := _cell_grid.cell_get(_cell_grid.cell_id_get(_x_, _y_))
	var cell_size := _cell_grid.cell_size
	var p_local := Vector3(cell.x * cell_size.x, 0.0, cell.y * cell_size.y)
	return (Transform3D.IDENTITY
		.translated_local(p_local)
		.scaled_local(Vector3(cell_size.x * 0.6, 0.3, cell_size.y * 0.6))
		.rotated_local(Vector3.DOWN, Vector2.UP.angle_to(cell.vector))
	)

func debug_update() -> void:
	if not is_instance_valid(_debug_cells):
		return
	await get_tree().physics_frame
	_debug_cells_vector.multimesh.visible_instance_count = -1 if debug_cell_vector else 0
	for i: int in _cell_grid.cell_count:
		var cell := _cell_grid.cell_get(i)
		var color_vector := Color.from_hsv(0.3 + cell.cost_best * 0.001, 0.8, 0.8)
		if debug_cell:
			var color_cell := Color(0.4, 0.4, 0.4)
			var tf := _debug_cell_transform_get(cell.x, cell.y)
			if cell.cost == Cell.Cost.WALL:
				tf = tf.translated_local(Vector3(0.0, 0.01, 0.0))
				color_cell = Color(0.38, 0.38, 0.38)
			_debug_cells.multimesh.set_instance_transform(i, tf)
			_debug_cells.multimesh.set_instance_color(i, color_cell)
		if debug_cell_vector:
			var tf := _debug_cell_transform_vector_get(cell.x, cell.y)
			if cell.cost == Cell.Cost.WALL or cell.cost_best == Cell.Cost.DESTINATION:
				tf = tf.scaled_local(Vector3.ZERO)
			_debug_cells_vector.multimesh.set_instance_transform(i, tf)
			_debug_cells_vector.multimesh.set_instance_color(i, color_vector)
#endregion

#region class Grid
class Bound extends RefCounted:
	var min_x: float
	var min_y: float
	var max_x: float
	var max_y: float
	var x: float
	var y: float
	var center_x: float
	var center_y: float
	var limit_min: Vector2
	var limit_max: Vector2
	func _init(_size_: Vector2i, _cell_size_: Vector2) -> void:
		min_x = -_cell_size_.x * 0.5
		min_y = -_cell_size_.y * 0.5
		max_x = (_size_.x - 0.5) * _cell_size_.x
		max_y = (_size_.y - 0.5) * _cell_size_.y
		x = max_x - min_x
		y = max_y - min_y
		center_x = x * 0.5
		center_y = y * 0.5
		var e := 5e-3
		limit_min = Vector2(min_x + e, min_y + e)
		limit_max = Vector2(max_x - e, max_y - e)

class Cell extends RefCounted:
	enum Cost {
		DESTINATION = 0,
		DEFAULT = 1,
		GRASS = 2,
		SAND = 4,
		MUD = 8,
		WALL = 65535,
	}
	var id: int
	var x: int
	var y: int
	var tx: int
	var ty: int
	var cost: int
	var cost_best: int
	var visited: bool
	var isolated: bool
	var neighbors_id: PackedInt32Array
	var neighbors_distance: PackedInt32Array
	var vector: Vector2
	var from_center: Vector2
	var position: Vector2
	var agents_id: Array[int]
	var obstacles_id: Array[int]

class CellGrid extends RefCounted:
	var _size: Vector2i
	var _cell_size: Vector2
	var _cells: Array[Cell]
	var bound: Bound
	var cell_size: Vector2:
		get(): return _cell_size
	var cell_count: int:
		get(): return _cells.size()
	var debug_offset: Vector3
	func _init(_size_: Vector2i, _cell_size_: Vector2) -> void:
		_size = _size_
		_cell_size = _cell_size_
		bound = Bound.new(_size, _cell_size)
		for y: int in _size.y:
			for x: int in _size.x:
				var cell := Cell.new()
				cell.id = cell_id_get(x, y)
				_cells.append(cell)
				cell.cost = Cell.Cost.DEFAULT
				cell.x = x
				cell.y = y
				cell.position = Vector2(x * _cell_size.x, y * _cell_size.y)
				cell.neighbors_id = neighbors_id_get(x, y)
		for cell in _cells:
			for neighbor_id: int in cell.neighbors_id:
				var neighbor := _cells[neighbor_id]
				var distance := int(sqrt((cell.x - neighbor.x)**2 + (cell.y - neighbor.y)**2) * 10.0)
				cell.neighbors_distance.append(distance)
	func cell_id_get(_x_: int, _y_: int) -> int:
		return _x_ + _size.x * _y_
	func cell_get(_id_: int) -> Cell:
		return _cells[_id_]
	func cell_nearest_get(_position_local_: Vector2) -> Cell:
		var dx := _position_local_.x / _cell_size.x
		if dx <= -0.5 or dx >= (_size.x - 0.5):
			return null
		var dy := _position_local_.y / _cell_size.y
		if dy <= -0.5 or dy >= (_size.y - 0.5):
			return null
		var x := roundi(dx)
		var y := roundi(dy)
		var cell := _cells[cell_id_get(x, y)]
		cell.from_center = Vector2(dx - x, dy - y)
		return cell
	func cell_id_nearest_get(_position_local_: Vector2) -> int:
		var dx := _position_local_.x / _cell_size.x
		if dx <= -0.5 or dx >= (_size.x - 0.5):
			return -1
		var dy := _position_local_.y / _cell_size.y
		if dy <= -0.5 or dy >= (_size.y - 0.5):
			return -1
		var x := roundi(dx)
		var y := roundi(dy)
		return cell_id_get(x, y)
	func cell_group_id_get(_cell_group_id_: Array[int], _depth_: int, _begin_id_: int = 0) -> void:
		for i in range(_begin_id_, _cell_group_id_.size()):
			_begin_id_ += 1
			var cell := _cells[_cell_group_id_[i]]
			for neighbor_id in cell.neighbors_id:
				if not _cell_group_id_.has(neighbor_id):
					_cell_group_id_.append(neighbor_id)
		if _depth_ > 1:
			cell_group_id_get(_cell_group_id_, _depth_ - 1, _begin_id_)
	func calculate_flow_field(_cell_ids_: Array[int]) -> void:
		for cell in _cells:
			cell.visited = false
			cell.isolated = true
			cell.cost_best = cell.cost
		var open_list: Array[int] = _cell_ids_.duplicate()
		for i: int in _cell_ids_:
			_cells[i].cost_best = 0
			_cells[i].visited = true
		while open_list.size() > 0:
			var cell := _cells[open_list.pop_front()]
			cell.visited = true
			for i: int in cell.neighbors_id.size():
				var neighbor_id := cell.neighbors_id[i]
				var neighbor := _cells[neighbor_id]
				var distance := cell.neighbors_distance[i]
				if not neighbor.cost == Cell.Cost.WALL:
					if neighbor.visited:
						if neighbor.cost_best > cell.cost_best + distance:
							neighbor.cost_best = cell.cost_best + distance
							neighbor.isolated = false
					else:
						neighbor.cost_best = cell.cost_best + distance
						open_list.append(neighbor_id)
						neighbor.visited = true
						neighbor.isolated = false
		for cell in _cells:
			var cost_best_min: int = Cell.Cost.WALL
			for i: int in cell.neighbors_id.size():
				var neighbor := _cells[cell.neighbors_id[i]]
				if neighbor.cost_best < cost_best_min:
					cost_best_min = neighbor.cost_best
					cell.tx = neighbor.x
					cell.ty = neighbor.y
			cell.vector = Vector2(cell.tx - cell.x, cell.ty - cell.y)
	func neighbors_id_get(_x_: int, _y_: int) -> PackedInt32Array:
		var k: int = 0b0101_0100_0111_0011_1111_1100_1101_0001
		if _x_ == 0:
			k = k & 0b0000_0000_0000_0011_1111_1100_1101_0001
		if _x_ == _size.x - 1:
			k = k & 0b0101_0100_0111_0011_0000_0000_0000_0001
		if _y_ == 0:
			k = k & 0b0000_0100_0111_0011_1111_1100_0000_0000
		if _y_ == _size.y - 1:
			k = k & 0b0101_0100_0000_0000_0000_1100_1101_0001
		var result: PackedInt32Array
		for i in range(0, 4*8, 4):
			var ki := (k & (0b1111 << i)) >> i
			if ki == 0:
				continue
			@warning_ignore("integer_division")
			var xs := ((0b1000 & ki) / 0b1000) * 2 - 1
			@warning_ignore("integer_division")
			var xf := (0b0100 & ki) / 0b0100
			@warning_ignore("integer_division")
			var ys := ((0b0010 & ki) / 0b0010) * 2 - 1
			@warning_ignore("integer_division")
			var yf := (0b0001 & ki) / 0b0001
			result.append(cell_id_get(_x_ + xs * xf, _y_ + ys * yf))
		return result
	func clamp_position(_position_local_: Vector2) -> Vector2:
		return _position_local_.clamp(bound.limit_min, bound.limit_max)
	func direction_get(_position_local_: Vector2) -> Vector2:
		var cell := cell_nearest_get(_position_local_)
		if cell != null:
			if cell.cost_best == 0:
				return Vector2(-INF, -INF)
			var direction := cell.vector
			return direction.normalized()
		return Vector2(INF, INF)
#endregion

#region class Agent
class Agent extends RefCounted:
	var id: int
	var radius: float
	var position: Vector2
	var position_predict: Vector2
	var position_speed_max: float
	var rotation: float
	var rotation_predict: float
	var rotation_speed_max: float
	var acceleration: float
	var force_move: Vector2
	var force_obstacle: Vector2
	var safe_direction: Vector2
	var speed_factor: float
	var move_distance: float
	var target: Vector2
	var target_ing: bool
	var target_near: bool
	var target_near_sub: bool
	var cell_id: int
	var neighbors_id: PackedInt32Array
	func _init() -> void:
		cell_id = -1
		neighbors_id.resize(32)
	func copy_transform(_from_: Agent) -> void:
		position = _from_.position
		rotation = _from_.rotation
		move_distance = _from_.move_distance
	func copy_stat(_from_: Agent) -> void:
		id = _from_.id
		radius = _from_.radius
		position_speed_max = _from_.position_speed_max
		rotation_speed_max = _from_.rotation_speed_max
		acceleration = _from_.acceleration
	func copy_target(_from_: Agent) -> void:
		target = _from_.target
		target_ing = _from_.target_ing
	func debug_draw_ray(_vector_: Vector2, _offset_: Vector3, _color_: Color) -> void:
		var a := Vector3(position.x + _offset_.x, 0.1 + _offset_.y, position.y + _offset_.z)
		var b := Vector3(a.x + _vector_.x, a.y, a.z + _vector_.y)
		Helper.debug_draw_line.call_deferred(a, b, 0.01, _color_)

class Sight extends RefCounted:
	var position: Vector2
	var rotation: float
	var safe_direction: Vector2
	var _valid_mask: int
	var _face: Vector2
	var _obstacle_normal: Vector2
	const PI2: float = PI * 2.0
	const ARC_COUNT_HALF_I: int = 4 # this max value is 32, equal to int bit count / 2
	const ARC_COUNT_I: int = ARC_COUNT_HALF_I * 2
	const ARC_COUNT_F: float = ARC_COUNT_I
	const ARC_RAD: float = PI2 / ARC_COUNT_F
	const SAFE_DIRECTION_DOT_OBSTACLE_NORMAL: float = cos(ARC_RAD * 0.6)
	func _init(_position_: Vector2, _rotation_: float, _obstacle_normal_: Vector2) -> void:
		position = _position_
		rotation = _rotation_
		_face = Vector2.from_angle(rotation)
		_obstacle_normal = _obstacle_normal_
	func _direction_get(_id_: int) -> Vector2:
		return Vector2.from_angle(rotation + ARC_RAD * (_id_ + 0.5))
	func check_cheap(_target_: Vector2) -> void:
		var u := _target_ - position
		var rad := _face.angle_to(u)
		if rad < 0.0:
			rad += PI2
		var arc_id := int(floor(rad / ARC_RAD)) % ARC_COUNT_I
		_valid_mask = _valid_mask | (1 << arc_id)
	func check(_target_: Vector2, _target_radius_: float) -> void:
		var u := _target_ - position
		var u_l_sq := u.length_squared()
		if u_l_sq < 1e-8:
			return
		var rad := _face.angle_to(u)
		if rad < 0.0:
			rad += PI2
		var a := atan(_target_radius_ / sqrt(u_l_sq))
		var arc_id_l := int(floor(wrapf(rad - a, 0.0, PI2) / ARC_RAD)) % ARC_COUNT_I
		var arc_id_r := int(floor(wrapf(rad + a, 0.0, PI2) / ARC_RAD)) % ARC_COUNT_I
		_valid_mask = _valid_mask | ((1 << arc_id_l) | (1 << arc_id_r))
	func safe_direction_get() -> bool:
		for i: int in ARC_COUNT_HALF_I:
			var ir := ARC_COUNT_I - i - 1
			if (_valid_mask & (1 << i)) == 0:
				safe_direction = _direction_get(i)
				var dot := safe_direction.dot(_obstacle_normal)
				if dot == 0.0 or dot > SAFE_DIRECTION_DOT_OBSTACLE_NORMAL:
					return true
			if (_valid_mask & (1 << ir)) == 0:
				safe_direction = _direction_get(ir)
				var dot := safe_direction.dot(_obstacle_normal)
				if dot == 0.0 or dot > SAFE_DIRECTION_DOT_OBSTACLE_NORMAL:
					return true
				return true
		return false
	func debug_draw(_offset_: Vector3) -> void:
		var a := Vector3(_offset_.x + position.x, _offset_.y + 0.1, _offset_.z + position.y)
		var b := Vector3.ZERO
		for i: int in ARC_COUNT_I:
			var u := _direction_get(i)
			b = Vector3(a.x + u.x, a.y, a.z + u.y)
			var color := Color.from_hsv(i * 0.5 / ARC_COUNT_F, 0.8, 0.8)
			if (_valid_mask & (1 << i)) > 0:
				color = Color.BLACK
			Helper.debug_draw_line.call_deferred(a, b, 0.01, color)
		b = Vector3(a.x + _face.x, a.y, a.z + _face.y)
		Helper.debug_draw_line.call_deferred(a, b, 0.01, Color.BLACK)

class RayHit extends RefCounted:
	var distance: float
	var direction: Vector2
	func circle_cast_circle(_ray_start_: Vector2, _ray_end_: Vector2, _ray_radius_: float,
		_circle_origin_: Vector2, _circle_radius_: float
	) -> float:
		var se := _ray_end_ - _ray_start_
		var sel := se.length()
		if sel < 1e-8:
			return false
		var u := Vector2(se.x / sel, se.y / sel)
		var n := Vector2(u.y, -u.x)
		direction = u
		var cp := _circle_origin_ - _ray_start_
		var cpl := Vector2(cp.dot(u), cp.dot(n))
		var tpl := Vector2(clampf(cpl.x, 0.0, sel), 0.0)
		var r_sum := _ray_radius_ + _circle_radius_
		var r_sum_sq := r_sum * r_sum
		var d_sq := tpl.distance_squared_to(cpl)
		if d_sq < r_sum_sq:
			distance = cpl.x - sqrt(r_sum_sq - cpl.y * cpl.y)
			return distance > 0.0
		return false
#endregion

#region class Obstacle
class DistanceHit extends RefCounted:
	var distance: float
	var normal: Vector2

class Obstacle extends RefCounted:
	var id: int
	var position: Vector2
	var rotation: float
	var cells_id: Array[int]
	func _init(_id_: int, _flow_field_: NavigationField, _collider_: CollisionShape3D) -> void:
		id = _id_
		var position_local := _flow_field_.to_local(_collider_.global_position)
		position = Vector2(position_local.x, position_local.z)
		var cell_id := _flow_field_._cell_grid.cell_id_nearest_get(_flow_field_._cell_grid.clamp_position(position))
		if cell_id != -1:
			cells_id.append(cell_id)
			_flow_field_._cell_grid.cell_group_id_get(cells_id, 2)
	func calculate_distance(_position_: Vector2, _radius_: float, _distance_hits_: Array[DistanceHit]) -> bool:
		return false
	static func circle_rectangle_overlap(_cp_: Vector2, _cr_: float, _rp_: Vector2, _rs_: Vector2, _r_rad_: float) -> bool:
		var cpl := (_cp_ - _rp_).rotated(-_r_rad_)
		var tpl := cpl
		var inside := true
		var sh := _rs_ * 0.5
		if cpl.x < -sh.x:
			tpl.x = -sh.x
			inside = false
		elif cpl.x > sh.x:
			tpl.x = sh.x
			inside = false
		if cpl.y < -sh.y:
			tpl.y = -sh.y
			inside = false
		elif cpl.y > sh.y:
			tpl.y = sh.y
			inside = false
		if inside:
			var dx := sh.x - absf(cpl.x)
			var dy := sh.y - absf(cpl.y)
			if dx < dy:
				tpl.x = signf(cpl.x) * sh.x
			else:
				tpl.y = signf(cpl.y) * sh.y
		return inside or tpl.distance_squared_to(cpl) <= _cr_ * _cr_
	static func capsule_rectangle_overlap(_cp_: Vector2, _cr_: float, _cd_: float, _c_rad_: float, _rp_: Vector2, _rs_: Vector2, _r_rad_: float) -> bool:
		var cc_delta := Vector2.from_angle(_c_rad_) * (_cd_ * 0.5)
		return (
			circle_rectangle_overlap(_cp_ + cc_delta, _cr_, _rp_, _rs_, _r_rad_) or
			circle_rectangle_overlap(_cp_ - cc_delta, _cr_, _rp_, _rs_, _r_rad_) or
			rectangle_rectangle_overlap(_cp_, Vector2(_cd_, _cr_ * 2.0), _c_rad_, _rp_, _rs_, _r_rad_)
		)
	static func rectangle_rectangle_overlap(_ap_: Vector2, _as_: Vector2, _a_rad_: float,
											_bp_: Vector2, _bs_: Vector2, _b_rad_: float) -> bool:
		var ash := _as_ * 0.5
		var bsh := _bs_ * 0.5
		var a: Array[Vector2] = [
			_ap_ + Vector2(-ash.x, -ash.y).rotated(_a_rad_),
			_ap_ + Vector2(+ash.x, -ash.y).rotated(_a_rad_),
			_ap_ + Vector2(+ash.x, +ash.y).rotated(_a_rad_),
			_ap_ + Vector2(-ash.x, +ash.y).rotated(_a_rad_),
		]
		var b: Array[Vector2] = [
			_bp_ + Vector2(-bsh.x, -bsh.y).rotated(_b_rad_),
			_bp_ + Vector2(+bsh.x, -bsh.y).rotated(_b_rad_),
			_bp_ + Vector2(+bsh.x, +bsh.y).rotated(_b_rad_),
			_bp_ + Vector2(-bsh.x, +bsh.y).rotated(_b_rad_),
		]
		return _rectangle_rectangle_overlap_pair(a, b) and _rectangle_rectangle_overlap_pair(b, a)
	static func _rectangle_rectangle_overlap_pair(_a_: Array[Vector2], _b_: Array[Vector2]) -> bool:
		for i: int in 2:
			var au := (_a_[i + 1] - _a_[i]).normalized();
			var an := Vector2(au.y, -au.x);
			var a_min_temp := _a_[i].dot(an);
			var a_max_temp := _a_[i + 2].dot(an);
			var a_min := minf(a_min_temp, a_max_temp);
			var a_max := maxf(a_min_temp, a_max_temp);
			var b_min := +1e8;
			var b_max := -1e8;
			for j: int in 4:
				var dot := _b_[j].dot(an);
				b_min = minf(b_min, dot);
				b_max = maxf(b_max, dot);
			if a_max < b_min or b_max < a_min:
				return false
		return true

class ObstacleCircle extends Obstacle:
	var radius: float
	func _init(_id_: int, _flow_field_: NavigationField, _collider_: CollisionShape3D) -> void:
		super._init(_id_, _flow_field_, _collider_)
		var sphere := _collider_.shape as SphereShape3D
		radius = sphere.radius
		for cell_id in cells_id:
			var cell := _flow_field_._cell_grid.cell_get(cell_id)
			if Obstacle.circle_rectangle_overlap(position, radius, cell.position, _flow_field_._cell_grid.cell_size, 0.0):
				cell.obstacles_id.append(id)
				cell.cost = Cell.Cost.WALL
	func calculate_distance(_position_: Vector2, _radius_: float, _distance_hits_: Array[DistanceHit]) -> bool:
		var delta := _position_ - position
		var delta_length_sq := delta.length_squared()
		var delta_length_min := radius + _radius_
		if delta_length_sq <= delta_length_min * delta_length_min:
			var distance_hit := DistanceHit.new()
			_distance_hits_.append(distance_hit)
			distance_hit.distance = sqrt(delta_length_sq) - delta_length_min
			distance_hit.normal = delta.normalized()
			return true
		return false

class ObstacleCapsule extends Obstacle:
	var radius: float
	var distance: float
	func _init(_id_: int, _flow_field_: NavigationField, _collider_: CollisionShape3D) -> void:
		super._init(_id_, _flow_field_, _collider_)
		var capsule := _collider_.shape as CapsuleShape3D
		radius = capsule.radius
		distance = capsule.height - radius * 2.0
		var face_local := _collider_.global_transform.basis.x
		rotation = Vector2(face_local.x, face_local.z).angle() + PI * 0.5
		for cell_id in cells_id:
			var cell := _flow_field_._cell_grid.cell_get(cell_id)
			if Obstacle.capsule_rectangle_overlap(position, radius, distance, rotation, cell.position, _flow_field_._cell_grid.cell_size, 0.0):
				cell.obstacles_id.append(id)
				cell.cost = Cell.Cost.WALL
	func calculate_distance(_position_: Vector2, _radius_: float, _distance_hits_: Array[DistanceHit]) -> bool:
		var cpl := (_position_ - position).rotated(-rotation)
		var dh := distance * 0.5
		var tpl := Vector2(clampf(cpl.x, -dh, dh), 0.0)
		var r_sum := radius + _radius_
		var d_sq := tpl.distance_squared_to(cpl)
		var hit := d_sq <= r_sum * r_sum
		if hit:
			var distance_hit := DistanceHit.new()
			_distance_hits_.append(distance_hit)
			distance_hit.distance = sqrt(d_sq) - r_sum
			distance_hit.normal = (cpl - tpl).rotated(rotation).normalized()
		return hit

class ObstacleRectangle extends Obstacle:
	var size: Vector2
	func _init(_id_: int, _flow_field_: NavigationField, _collider_: CollisionShape3D) -> void:
		super._init(_id_, _flow_field_, _collider_)
		var box := _collider_.shape as BoxShape3D
		size = Vector2(box.size.x, box.size.z)
		var face_local := _collider_.global_transform.basis.x
		rotation = Vector2(face_local.x, face_local.z).angle()
		for cell_id in cells_id:
			var cell := _flow_field_._cell_grid.cell_get(cell_id)
			if Obstacle.rectangle_rectangle_overlap(position, size, rotation, cell.position, _flow_field_._cell_grid.cell_size, 0.0):
				cell.obstacles_id.append(id)
				cell.cost = Cell.Cost.WALL
	func calculate_distance(_position_: Vector2, _radius_: float, _distance_hits_: Array[DistanceHit]) -> bool:
		var cpl := (_position_ - position).rotated(-rotation)
		var tpl := cpl
		var inside := true
		var sh := size * 0.5
		if cpl.x < -sh.x:
			tpl.x = -sh.x
			inside = false
		elif cpl.x > sh.x:
			tpl.x = sh.x
			inside = false
		if cpl.y < -sh.y:
			tpl.y = -sh.y
			inside = false
		elif cpl.y > sh.y:
			tpl.y = sh.y
			inside = false
		if inside:
			var dx := sh.x - absf(cpl.x)
			var dy := sh.y - absf(cpl.y)
			if dx < dy:
				tpl.x = signf(cpl.x) * sh.x
			else:
				tpl.y = signf(cpl.y) * sh.y
		var d_sq := tpl.distance_squared_to(cpl)
		var hit := inside or d_sq <= _radius_ * _radius_
		if hit:
			var distance_hit := DistanceHit.new()
			_distance_hits_.append(distance_hit)
			if inside:
				distance_hit.distance = -sqrt(d_sq) - _radius_
				distance_hit.normal = (tpl - cpl).rotated(rotation).normalized()
			else:
				distance_hit.distance = sqrt(d_sq) - _radius_
				distance_hit.normal = (cpl - tpl).rotated(rotation).normalized()
		return hit
#endregion
