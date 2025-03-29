class_name NavigationField
extends Node3D

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
	var index: int
	var x: int
	var y: int
	var tx: int
	var ty: int
	var cost: int
	var cost_best: int
	var visited: bool
	var isolated: bool
	var neighbors_index: PackedInt32Array
	var neighbors_distance: PackedInt32Array
	var vector: Vector2
	var from_center: Vector2
	var position: Vector2
	var agents_index: Array[int]
	var obstacles_index: Array[int]

class CellGrid extends RefCounted:
	var _size: Vector2i
	var _cell_size: Vector2
	var _cells: Array[Cell]
	var bound: Bound
	var cell_size: Vector2:
		get(): return _cell_size
	var cell_count: int:
		get(): return _cells.size()
	func _init(_size_: Vector2i, _cell_size_: Vector2) -> void:
		_size = _size_
		_cell_size = _cell_size_
		bound = Bound.new(_size, _cell_size)
		for y: int in _size.y:
			for x: int in _size.x:
				var cell := Cell.new()
				cell.index = cell_index_get(x, y)
				_cells.append(cell)
				cell.cost = Cell.Cost.DEFAULT
				cell.x = x
				cell.y = y
				cell.position = Vector2(x * _cell_size.x, y * _cell_size.y)
				cell.neighbors_index = neighbors_index_get(x, y)
		for cell in _cells:
			for neighbor_index: int in cell.neighbors_index:
				var neighbor := _cells[neighbor_index]
				var distance := int(sqrt((cell.x - neighbor.x)**2 + (cell.y - neighbor.y)**2) * 10.0)
				cell.neighbors_distance.append(distance)
	func cell_index_get(_x_: int, _y_: int) -> int:
		return _x_ + _size.x * _y_
	func cell_get(_index_: int) -> Cell:
		return _cells[_index_]
	func cell_nearest_get(_position_local_: Vector2) -> Cell:
		var dx := _position_local_.x / _cell_size.x
		if dx <= -0.5 or dx >= (_size.x - 0.5):
			return null
		var dy := _position_local_.y / _cell_size.y
		if dy <= -0.5 or dy >= (_size.y - 0.5):
			return null
		var x := roundi(dx)
		var y := roundi(dy)
		var cell := _cells[cell_index_get(x, y)]
		cell.from_center = Vector2(dx - x, dy - y)
		return cell
	func cell_index_nearest_get(_position_local_: Vector2) -> int:
		var dx := _position_local_.x / _cell_size.x
		if dx <= -0.5 or dx >= (_size.x - 0.5):
			return -1
		var dy := _position_local_.y / _cell_size.y
		if dy <= -0.5 or dy >= (_size.y - 0.5):
			return -1
		var x := roundi(dx)
		var y := roundi(dy)
		return cell_index_get(x, y)
	func cell_group_index_get(_cell_group_index_: Array[int], _depth_: int, _begin_index_: int = 0) -> void:
		for i in range(_begin_index_, _cell_group_index_.size()):
			_begin_index_ += 1
			var cell := _cells[_cell_group_index_[i]]
			for neighbor_index in cell.neighbors_index:
				if not _cell_group_index_.has(neighbor_index):
					_cell_group_index_.append(neighbor_index)
		if _depth_ > 1:
			cell_group_index_get(_cell_group_index_, _depth_ - 1, _begin_index_)
	func calculate(_cell_indexs_: Array[int]) -> void:
		for cell in _cells:
			cell.visited = false
			cell.isolated = true
			cell.cost_best = cell.cost
		var open_list: Array[int] = _cell_indexs_.duplicate()
		for i: int in _cell_indexs_:
			_cells[i].cost_best = 0
			_cells[i].visited = true
		while open_list.size() > 0:
			var cell := _cells[open_list.pop_front()]
			cell.visited = true
			for i: int in cell.neighbors_index.size():
				var neighbor_index := cell.neighbors_index[i]
				var neighbor := _cells[neighbor_index]
				var distance := cell.neighbors_distance[i]
				if not neighbor.cost == Cell.Cost.WALL:
					if neighbor.visited:
						if neighbor.cost_best > cell.cost_best + distance:
							neighbor.cost_best = cell.cost_best + distance
							neighbor.isolated = false
					else:
						neighbor.cost_best = cell.cost_best + distance
						open_list.append(neighbor_index)
						neighbor.visited = true
						neighbor.isolated = false
		for cell in _cells:
			var cost_best_min: int = Cell.Cost.WALL
			for i: int in cell.neighbors_index.size():
				var neighbor := _cells[cell.neighbors_index[i]]
				if neighbor.cost_best < cost_best_min:
					cost_best_min = neighbor.cost_best
					cell.tx = neighbor.x
					cell.ty = neighbor.y
			cell.vector = Vector2(cell.tx - cell.x, cell.ty - cell.y)
	func neighbors_index_get(_x_: int, _y_: int) -> PackedInt32Array:
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
			result.append(cell_index_get(_x_ + xs * xf, _y_ + ys * yf))
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

var cell_grid: CellGrid
var _debug: bool
@onready var _debug_cells: MultiMeshInstance3D = $debug_cells
@onready var _debug_cells_vector: MultiMeshInstance3D = $debug_cells_vector

static func spawn(_parent_: Node) -> NavigationField:
	var result := (load("res://navigation/navigation_field.tscn") as PackedScene).instantiate() as NavigationField
	_parent_.add_child(result)
	return result

func create(_size_: Vector2i, _cell_size_: Vector2, _debug_: bool) -> NavigationField:
	cell_grid = CellGrid.new(_size_, _cell_size_)
	_debug = _debug_
	if not _debug_:
		_debug_cells.queue_free()
		_debug_cells_vector.queue_free()
	else:
		_debug_cells.multimesh.instance_count = _size_.x * _size_.y
		_debug_cells_vector.multimesh.instance_count = _debug_cells.multimesh.instance_count
	return self

func position_set(_position_: Vector3, _anchor_: Vector2) -> void:
	position = Vector3(
		_position_.x - cell_grid.bound.min_x - _anchor_.x * cell_grid.bound.x,
		_position_.y,
		_position_.z - cell_grid.bound.min_y - _anchor_.y * cell_grid.bound.y,
	)

#region Agents
class Agent extends RefCounted:
	var index: int
	var radius: float
	var radius_other: float
	var position: Vector2
	var position_predict: Vector2
	var position_speed_max: float
	var rotation: float
	var rotation_predict: float
	var rotation_speed_max: float
	var acceleration: float
	var force_obstacle: Vector2
	var force_other: Vector2
	var speed_factor: float
	var move_distance: float
	var target: Vector2
	var target_ing: bool
	var cell_index: int
	var neighbors_index: PackedInt32Array
	func _init() -> void:
		cell_index = -1
		neighbors_index.resize(32)
	func copy_transform(_from_: Agent) -> void:
		position = _from_.position
		rotation = _from_.rotation
		move_distance = _from_.move_distance
	func copy_stat(_from_: Agent) -> void:
		index = _from_.index
		radius = _from_.radius
		radius_other = _from_.radius_other
		position_speed_max = _from_.position_speed_max
		rotation_speed_max = _from_.rotation_speed_max
		acceleration = _from_.acceleration
	func copy_target(_from_: Agent) -> void:
		target = _from_.target
		target_ing = _from_.target_ing

class DistanceHit extends RefCounted:
	var distance: float
	var normal: Vector2

class Obstacle extends RefCounted:
	var index: int
	var position: Vector2
	var rotation: float
	var cells_index: Array[int]
	func _init(_index_: int, _flow_field_: NavigationField, _collider_: CollisionShape3D) -> void:
		index = _index_
		var position_local := _flow_field_.to_local(_collider_.global_position)
		position = Vector2(position_local.x, position_local.z)
		var cell_index := _flow_field_.cell_grid.cell_index_nearest_get(_flow_field_.cell_grid.clamp_position(position))
		if cell_index != -1:
			cells_index.append(cell_index)
			_flow_field_.cell_grid.cell_group_index_get(cells_index, 2)
	func calculate_distance(_position_: Vector2, _radius_: float, _distance_hits_: Array[DistanceHit]) -> bool:
		return false
	static func circle_rectangle_overlap(_cp_: Vector2, _cr_: float, _rp_: Vector2, _rs_: Vector2) -> bool:
		var cpl := _cp_ - _rp_
		var tpl := cpl
		var rsh := _rs_ * 0.5
		if cpl.x < -rsh.x:
			tpl.x = -rsh.x
		elif cpl.x > rsh.x:
			tpl.x = rsh.x
		if cpl.y < -rsh.y:
			tpl.y = -rsh.y
		elif cpl.y > rsh.y:
			tpl.y = rsh.y
		return cpl.distance_squared_to(tpl) <= _cr_ * _cr_
	static func rectangle_rectangle_overlap(_ap_: Vector2, _as_: Vector2, _ar_: float,
											_bp_: Vector2, _bs_: Vector2, _br_: float) -> bool:
		var ash := _as_ * 0.5
		var bsh := _bs_ * 0.5
		var a: Array[Vector2] = [
			_ap_ + Vector2(-ash.x, -ash.y).rotated(_ar_),
			_ap_ + Vector2(+ash.x, -ash.y).rotated(_ar_),
			_ap_ + Vector2(+ash.x, +ash.y).rotated(_ar_),
			_ap_ + Vector2(-ash.x, +ash.y).rotated(_ar_),
		]
		var b: Array[Vector2] = [
			_bp_ + Vector2(-bsh.x, -bsh.y).rotated(_br_),
			_bp_ + Vector2(+bsh.x, -bsh.y).rotated(_br_),
			_bp_ + Vector2(+bsh.x, +bsh.y).rotated(_br_),
			_bp_ + Vector2(-bsh.x, +bsh.y).rotated(_br_),
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
	func _init(_index_: int, _flow_field_: NavigationField, _collider_: CollisionShape3D) -> void:
		super._init(_index_, _flow_field_, _collider_)
		var sphere := _collider_.shape as SphereShape3D
		radius = sphere.radius
		for cell_index in cells_index:
			var cell := _flow_field_.cell_grid.cell_get(cell_index)
			if Obstacle.circle_rectangle_overlap(position, radius, cell.position, _flow_field_.cell_grid.cell_size):
				cell.obstacles_index.append(index)
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

class ObstacleRectangle extends Obstacle:
	var size: Vector2
	func _init(_index_: int, _flow_field_: NavigationField, _collider_: CollisionShape3D) -> void:
		super._init(_index_, _flow_field_, _collider_)
		var box := _collider_.shape as BoxShape3D
		size = Vector2(box.size.x, box.size.z)
		var right_local := _collider_.global_transform.basis.x
		rotation = Vector2(right_local.x, right_local.z).angle()
		for cell_index in cells_index:
			var cell := _flow_field_.cell_grid.cell_get(cell_index)
			if Obstacle.rectangle_rectangle_overlap(position, size, rotation, cell.position, _flow_field_.cell_grid.cell_size, 0.0):
				cell.obstacles_index.append(index)
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

static func agent_neighbors_index_get(_cell_grid_: CellGrid, _agents_: Array[Agent], _agent_index_: int) -> int:
	var agent := _agents_[_agent_index_]
	var index := 0
	var count_max := agent.neighbors_index.size()
	var cell := _cell_grid_.cell_get(agent.cell_index)
	for agent_index: int in cell.agents_index:
		if agent_index != agent.index:
			if index < count_max:
				agent.neighbors_index[index] = agent_index
				index += 1
	for neighbor_index: int in cell.neighbors_index:
		var neighbor := _cell_grid_.cell_get(neighbor_index)
		for agent_index: int in neighbor.agents_index:
			if index < count_max:
				agent.neighbors_index[index] = agent_index
				index += 1
	return index

static func agent_enter(_agent_: Agent, _cell_grid_: CellGrid) -> void:
	var cell_index := _cell_grid_.cell_index_nearest_get(_agent_.position)
	if cell_index != _agent_.cell_index:
		if _agent_.cell_index != -1:
			_cell_grid_.cell_get(_agent_.cell_index).agents_index.erase(_agent_.index)
		_agent_.cell_index = cell_index
		if cell_index != -1:
			_cell_grid_.cell_get(cell_index).agents_index.append(_agent_.index)

static func agent_force_move(_agent_: Agent, _cell_grid_: CellGrid, _dt_: float) -> void:
	var force_move := Vector2.ZERO
	if _agent_.target_ing:
		var delta := _agent_.target - _agent_.position
		var delta_length := delta.length()
		if delta_length > _agent_.radius:
			force_move = (delta / delta_length) * _agent_.position_speed_max
			_agent_.speed_factor = minf(_agent_.speed_factor + _agent_.acceleration * _dt_, 1.0)
		else:
			_agent_.speed_factor = 0.0
	var dt := _agent_.speed_factor * _dt_
	var direction := Vector2.from_angle(_agent_.rotation)
	var delta_rotation := direction.angle_to(force_move)
	var delta_rotation_sign := signf(delta_rotation)
	var delta_rotation_max_abs := _agent_.rotation_speed_max * dt
	var delta_rotation_real := delta_rotation_sign * minf(delta_rotation_max_abs, delta_rotation_sign * delta_rotation)
	var rotation_predict := wrapf(_agent_.rotation + delta_rotation_real, -PI, PI)
	var position_predict := _agent_.position + Vector2.from_angle(rotation_predict) * (force_move.length() * dt)
	_agent_.rotation_predict = rotation_predict
	_agent_.position_predict = _cell_grid_.clamp_position(position_predict)

static func agent_force_obstacle(_cell_grid_: CellGrid, _agents_: Array[Agent], _agent_index_: int, _obstacles_: Array[Obstacle], _dt_: float) -> void:
	var agent := _agents_[_agent_index_]
	var distance_hits: Array[DistanceHit]
	var obstacles_index_visisted: Array[int]
	if agent.cell_index != -1:
		var cell := _cell_grid_.cell_get(agent.cell_index)
		for neighbor_index: int in cell.neighbors_index:
			var neighbor := _cell_grid_.cell_get(neighbor_index)
			for obstacle_index: int in neighbor.obstacles_index:
				if obstacle_index not in obstacles_index_visisted:
					var obstacle := _obstacles_[obstacle_index]
					obstacle.calculate_distance(agent.position_predict, agent.radius, distance_hits)
					obstacles_index_visisted.append(obstacle_index)
	var force_obstacle := Vector2.ZERO
	for hit: DistanceHit in distance_hits:
		force_obstacle -= hit.normal * hit.distance;
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
	if force_obstacle.length_squared() > 0.0:
		agent.position_predict += force_obstacle
		agent.rotation_predict = (agent.position_predict - agent.position).angle()

static func agent_force_other(_cell_grid_: CellGrid, _agents_: Array[Agent], _agent_index_: int, _dt_: float) -> void:
	#calculate agent force other and check if it is surronded
	#predict nearby agent next position with velocity and calculate the approximate avoid direction that nearest to target position
	#prevent other agents from pushing this agent into the obstacle, if they tend to do so, give force obstacle back to other agent.force_other
	var force_other := Vector2.ZERO
	var agent := _agents_[_agent_index_]
	var neighbors_count := agent_neighbors_index_get(_cell_grid_, _agents_, _agent_index_)
	for i: int in neighbors_count:
		var agent_other := _agents_[agent.neighbors_index[i]]
		var delta := agent_other.position_predict - agent.position_predict
		var delta_length_sq := delta.length_squared()
		var delta_length_min := agent.radius_other + agent_other.radius_other
		if delta_length_sq < delta_length_min * delta_length_min:
			var delta_length := sqrt(delta_length_sq)
			var hit_distance := (delta_length_min - delta_length)
			if delta_length < 1e-3:
				force_other -= hit_distance * Vector2.from_angle(agent.rotation)
			else:
				force_other -= (hit_distance / delta_length) * delta
	agent.force_other = force_other
	#test
	agent.move_distance += agent.position.distance_to(agent.position_predict)
	agent.rotation = agent.rotation_predict
	agent.position = agent.position_predict
	#test

static func agent_move(_agent_: Agent, _cell_grid_: CellGrid, _dt_: float) -> void:
	var force_move := Vector2.ZERO
	var dt := _agent_.speed_factor * _dt_
	var direction_face := Vector2.from_angle(_agent_.rotation)
	if force_move.dot(_agent_.force_obstacle) < 0.0:
		var n := _agent_.force_obstacle.normalized()
		var ul := Vector2(n.y, -n.x)
		var ur := Vector2(-n.y, n.x)
		var u := ul if force_move.dot(ul) > force_move.dot(ur) else ur
		if direction_face.dot(u) < 0.0:
			u = -u
		_agent_.force_other = _agent_.force_other.project(u)
		force_move = force_move.length() * u
	var force := _agent_.force_obstacle + _agent_.force_other + force_move
	var force_magnitude := clampf(force.length(), -_agent_.position_speed_max, _agent_.position_speed_max)
	var delta_rotation_target := direction_face.angle_to(force)
	var rotation_sign := signf(delta_rotation_target)
	var delta_rotation := _agent_.rotation_speed_max * dt
	var rotation_next := wrapf(_agent_.rotation + rotation_sign * minf(delta_rotation, rotation_sign * delta_rotation_target), -PI, PI)
	var direction_next := Vector2.from_angle(rotation_next)
	_agent_.rotation = rotation_next
	_agent_.position = _cell_grid_.clamp_position(_agent_.position + _agent_.velocity * dt)
	_agent_.move_distance += _agent_.position.distance_to(_agent_.position_next)
#endregion

#region debug
func _debug_cell_transform_get(_x_: int, _y_: int) -> Transform3D:
	var cell_size := cell_grid.cell_size
	return (Transform3D.IDENTITY
		.translated_local(Vector3(_x_ * cell_size.x, -cell_size.x * 0.5, _y_ * cell_size.y))
		.scaled_local(Vector3(cell_size.x, cell_size.x, cell_size.y))
	)

func _debug_cell_transform_vector_get(_x_: int, _y_: int) -> Transform3D:
	var cell := cell_grid.cell_get(cell_grid.cell_index_get(_x_, _y_))
	var cell_size := cell_grid.cell_size
	var p_local := Vector3(cell.x * cell_size.x, 0.0, cell.y * cell_size.y)
	return (Transform3D.IDENTITY
		.translated_local(p_local)
		.scaled_local(Vector3(cell_size.x * 0.6, 0.3, cell_size.y * 0.6))
		.rotated_local(Vector3.DOWN, Vector2.UP.angle_to(cell.vector))
	)

func debug_update(_cell_: bool, _cell_vector_: bool) -> void:
	if not _debug:
		return
	await get_tree().physics_frame
	_debug_cells_vector.multimesh.visible_instance_count = -1 if _cell_vector_ else 0
	for i: int in cell_grid.cell_count:
		var cell := cell_grid.cell_get(i)
		var color_vector := Color.from_hsv(0.3 + cell.cost_best * 0.001, 0.8, 0.8)
		if _cell_:
			var color_cell := Color(0.4, 0.4, 0.4)
			var tf := _debug_cell_transform_get(cell.x, cell.y)
			if cell.cost == Cell.Cost.WALL:
				tf = tf.translated_local(Vector3(0.0, 0.01, 0.0))
				color_cell = Color(0.38, 0.38, 0.38)
			_debug_cells.multimesh.set_instance_transform(i, tf)
			_debug_cells.multimesh.set_instance_color(i, color_cell)
		if _cell_vector_:
			var tf := _debug_cell_transform_vector_get(cell.x, cell.y)
			if cell.cost == Cell.Cost.WALL or cell.cost_best == Cell.Cost.DESTINATION:
				tf = tf.scaled_local(Vector3.ZERO)
			_debug_cells_vector.multimesh.set_instance_transform(i, tf)
			_debug_cells_vector.multimesh.set_instance_color(i, color_vector)
#endregion
