class_name NavigationTest
extends Node

@onready var _manual_agent: Label = $ui/manual_agent
@onready var _debug: Label = $ui/debug
@onready var _view_agents: MultiMeshInstance3D = $view_agents
@onready var _obstacles_node: Node3D = $obstacles

var _manual_boid_text_base: String

var _navigation_field: NavigationField
var _navigation_field_debug_vector: bool
var _agents: Array[NavigationField.Agent]
var _agents_local: Array[NavigationField.Agent]
var _agents_target_changed: bool
var _obstacles: Array[NavigationField.Obstacle]
var _physics_time_sec_last: float
var _input_ready: bool

class SelfCamera extends RefCounted:
	var camera: Camera3D
	var view_index: int
	var views_offset: Array[Vector3]
	var views_rotation: Array[Vector3]
	var position_target: Vector3
	var rotation_target: Vector3
	var size_target: float
	func _init(_camera_: Camera3D) -> void:
		camera = _camera_
		view_index = 0
		views_offset = [camera.global_position, Vector3(0.0, camera.global_position.y, 0.0)]
		views_rotation = [camera.global_rotation, Vector3(-PI * 0.5, 0.0, 0.0)]
		position_target = camera.global_position
		rotation_target = camera.global_rotation
		size_target = camera.size
	func physics_process(_dt_: float) -> void:
		camera.global_position = camera.global_position.lerp(position_target, 0.1)
		camera.global_rotation = camera.global_rotation.lerp(rotation_target, 0.1)
		camera.size = lerpf(camera.size, size_target, 0.1)
	func change_view() -> void:
		view_index = wrapi(view_index + 1, 0, views_offset.size())
	func update_view(_mouse_position_: Vector2) -> void:
		var screen_size := Global.screen_size
		position_target = views_offset[view_index] + Vector3(
			(_mouse_position_.x - screen_size.x * 0.5) * camera.size / screen_size.x, 0.0,
			(_mouse_position_.y - screen_size.y * 0.5) * camera.size / screen_size.x)
		rotation_target = views_rotation[view_index]
var _self_camera: SelfCamera

class SelfMouse extends RefCounted:
	var position_world: Vector3
	var position: Vector2
	var middle_press_ing: bool
	var middle_cell_index_last: int
	var spawn_count: int
	var agent_index: int
	func _init() -> void:
		agent_index = -1
var _self_mouse: SelfMouse

func _ready() -> void:
	Global.render_world.queue_free() # this project is striped from main project
	_navigation_field = NavigationField.spawn(self).create(Vector2i(10, 30), Vector2(1.0, 1.0), true)
	_navigation_field.position_set(Vector3(0.0, 0.0, 0.0), Vector2(0.5, 0.5))
	_view_agents.multimesh.mesh = ($view_agents/creep_1/body as MeshInstance3D).mesh
	for child in _obstacles_node.get_children():
		var collider := child as CollisionShape3D
		if collider.shape is SphereShape3D:
			_obstacles.append(NavigationField.ObstacleCircle.new(_obstacles.size(), _navigation_field, collider))
		elif collider.shape is CapsuleShape3D:
			_obstacles.append(NavigationField.ObstacleCapsule.new(_obstacles.size(), _navigation_field, collider))
		elif collider.shape is BoxShape3D:
			_obstacles.append(NavigationField.ObstacleRectangle.new(_obstacles.size(), _navigation_field, collider))
	_self_mouse = SelfMouse.new()
	_self_camera = SelfCamera.new($camera)
	_manual_boid_text_base = _manual_agent.text
	_input_change_spawn_count()
	_input_ready = false
	for i in 2: await get_tree().process_frame
	_navigation_field_debug_vector = false
	_navigation_field.cell_grid_get().calculate_flow_field([0])
	_navigation_field.debug_update(true, _navigation_field_debug_vector)
	_input_ready = true

func _agents_spawn_task(_count_: int) -> void:
	for i in _count_:
		_agents.append(NavigationField.Agent.new())
		_agents_local.append(NavigationField.Agent.new())

func _agents_spawn(_position_local_: Vector2, _count_: int) -> void:
	var spawn_count := _self_mouse.spawn_count
	var spread := ceili(sqrt(spawn_count))
	var task := ThreadManager.do(self, _agents_spawn_task.bind(_count_), true)
	if task != null:
		print("Spawn %d agent." % [_count_])
		await task.done
		_view_agents.multimesh.instance_count = _agents.size()
		_view_agents.multimesh.visible_instance_count = _agents.size()
		for i in spawn_count:
			var agent_index := _agents.size() - 1 - i
			var agent := _agents[agent_index]
			agent.index = agent_index
			agent.radius = randi_range(40, 50) * 0.005
			@warning_ignore("integer_division")
			agent.position = Vector2(
				_position_local_.x + (i / spread) * 0.3,
				_position_local_.y + (i % spread) * 0.3
			)
			agent.position_speed_max = randi_range(20, 30) * 0.1
			agent.rotation_speed_max = randi_range(20, 30) * 0.1 * PI
			agent.acceleration = randi_range(15, 20) * 0.1
			_agents_local[agent_index].copy_stat(agent)
			_agents_local[agent_index].copy_transform(agent)

func _agents_kill_task(_count_: int) -> void:
	for i in range(_agents_local.size() - 1, _agents_local.size() - 1 - _count_, -1):
		NavigationField.agent_exit(_agents[i], _navigation_field.cell_grid_get())
		_agents.remove_at(i)
		_agents_local.remove_at(i)

func _agents_kill(_count_: int) -> void:
	_count_ = mini(_count_, _agents_local.size())
	if _count_ == 0:
		return
	var count_after := _agents_local.size() - _count_
	var task := ThreadManager.do(self, _agents_kill_task.bind(_count_), true)
	if task != null:
		print("Kill %d agent." % [_count_])
		_view_agents.multimesh.instance_count = count_after
		await task.done
		_view_agents.multimesh.visible_instance_count = _agents.size()

func _agents_process(_dt_: float) -> void:
	var cell_grid := _navigation_field.cell_grid_get()
	for agent in _agents:
		NavigationField.agent_enter(agent, cell_grid)
		NavigationField.agent_move(agent, _dt_)
		NavigationField.agent_avoid_obstacle(cell_grid, _agents, agent.index, _obstacles, _dt_)
	for agent in _agents:
		NavigationField.agent_avoid_other(cell_grid, _agents, agent.index, _dt_)

func _physics_process(_dt_: float) -> void:
	_self_camera.physics_process(_dt_)
	if _agents_local.size() == _view_agents.multimesh.instance_count:
		var time_sec := Global.time_sec()
		var tf_base := Transform3D.IDENTITY.translated_local(_navigation_field.position)
		for i in _agents_local.size():
			var agent_local := _agents_local[i]
			var view_radius := agent_local.radius * 2.0
			var tf := (tf_base
				.translated_local(Vector3(agent_local.position.x, 0.0, agent_local.position.y))
				.rotated_local(Vector3.UP, -agent_local.rotation + PI * 0.5)
				.scaled_local(Vector3(view_radius, view_radius, view_radius))
			)
			var gray := 1.0 if i == _self_mouse.agent_index else 0.0
			var flick := pingpong(time_sec, 0.5) if i == _self_mouse.agent_index else 0.0
			var gray_flick := gray + flick
			_view_agents.multimesh.set_instance_transform(i, tf)
			_view_agents.multimesh.set_instance_custom_data(i,
				Color(wrapf(agent_local.move_distance * 7.5 / agent_local.radius, 30.0, 44.0), wrapi(i, 0, 16) * 0.0625, gray_flick)
			)
	if ThreadManager.doable(self):
		if _physics_time_sec_last == 0.0:
			_physics_time_sec_last = Global.physics_time_sec() - _dt_
		var dt := Global.physics_time_sec() - _physics_time_sec_last
		for i in _agents.size():
			_agents[i].copy_stat(_agents_local[i])
			_agents[i].copy_transform(_agents_local[i])
		if _agents_target_changed:
			for i in _agents.size():
				_agents[i].copy_target(_agents_local[i])
			_agents_target_changed = false
		var task := ThreadManager.do(self, _agents_process.bind(dt), true)
		if task != null:
			await task.done
			for i in _agents.size():
				_agents_local[i].copy_transform(_agents[i])
			if not _agents_target_changed:
				for i in _agents.size():
					_agents_local[i].copy_target(_agents[i])
		_physics_time_sec_last = Global.physics_time_sec()

func _process(_dt_: float) -> void:
	_debug.text = "FPS: %d, Agent count: %d, Mem: %.1fMB" % [
		Engine.get_frames_per_second(),
		_agents_local.size(),
		Performance.get_monitor(Performance.MEMORY_STATIC) * 1e-6,
		]

static func _position_get(_camera_: Camera3D, _screen_position_: Vector2) -> Vector3:
	var ro := _camera_.project_position(_screen_position_, 1.0)
	var ru := ro.direction_to(_camera_.project_position(_screen_position_, 100.0))
	var pn := Vector3.UP
	var pp := Vector3.ZERO
	var ro_pp := pp - ro
	var enter := ro_pp.length() * (ro_pp.normalized().dot(pn) / ru.dot(pn))
	return ro + enter * ru

func _input_change_spawn_count() -> void:
	var counts: Array[int] = [1, 10, 50, 100]
	var count_index := 0
	for i in counts.size():
		if _self_mouse.spawn_count == counts[i]:
			count_index = (i + 1) % counts.size()
			break;
	_self_mouse.spawn_count = counts[count_index]
	_manual_agent.text = _manual_boid_text_base % [_self_mouse.spawn_count, _self_mouse.spawn_count]

func _input_middle_mouse() -> void:
	if _self_mouse.middle_press_ing:
		var p := _navigation_field.to_local(_self_mouse.position_world)
		var p_local := Vector2(p.x, p.z)
		var cell := _navigation_field.cell_grid_get().cell_nearest_get(p_local)
		if cell != null and cell.index != _self_mouse.middle_cell_index_last:
			if cell.cost == NavigationField.Cell.Cost.WALL:
				cell.cost = NavigationField.Cell.Cost.DEFAULT
			else:
				cell.cost = NavigationField.Cell.Cost.WALL
			_navigation_field.debug_update(true, _navigation_field_debug_vector)
			_self_mouse.middle_cell_index_last = cell.index

func _input(_event_: InputEvent) -> void:
	if not _input_ready:
		return
	if _event_ is InputEventKey:
		var key := _event_ as InputEventKey
		if key.is_released() and key.keycode == KEY_C:
			_input_change_spawn_count()
		if key.is_released() and key.keycode == KEY_V:
			_navigation_field_debug_vector = not _navigation_field_debug_vector
			_navigation_field.debug_update(true, _navigation_field_debug_vector)
		if key.is_released() and key.keycode == KEY_B:
			_self_camera.change_view()
			_self_camera.update_view(_self_mouse.position)
		if key.is_released() and key.keycode == KEY_S:
			if _agents_local.size() > 0:
				_self_mouse.agent_index = (_self_mouse.agent_index + 1) % _agents_local.size()
		if key.is_released() and key.keycode == KEY_D:
			_agents_kill(_self_mouse.spawn_count)
	if _event_ is InputEventMouseButton or _event_ is InputEventMouseMotion:
		_self_mouse.position = (_event_ as InputEventMouse).position
		_self_mouse.position_world = _position_get(_self_camera.camera, _self_mouse.position)
		Helper.debug_draw_sphere(_self_mouse.position_world, 0.075, Color.RED)
	if _event_ is InputEventMouseButton:
		var mouse := _event_ as InputEventMouseButton
		if mouse.pressed:
			var p := _navigation_field.to_local(_self_mouse.position_world)
			var p_local := Vector2(p.x, p.z)
			match mouse.button_index:
				MOUSE_BUTTON_RIGHT:
					for agent_local in _agents_local:
						var state := 0
						if _self_mouse.agent_index != -1:
							if agent_local.index == _self_mouse.agent_index:
								agent_local.target = p_local
								agent_local.target_ing = true
								state = 1
						else:
							agent_local.target = p_local
							agent_local.target_ing = true
							state = 2
						if state == 1 or state == 2:
							Helper.debug_draw_line(
								Vector3(agent_local.position.x, 0.1, agent_local.position.y) + _navigation_field.cell_grid_get().debug_offset,
								p + _navigation_field.cell_grid_get().debug_offset,
								0.01,
								Color.GREEN
							)
						if state == 1:
							break
					_agents_target_changed = true
					var cell := _navigation_field.cell_grid_get().cell_nearest_get(p_local)
					if cell == null or cell.cost == NavigationField.Cell.Cost.WALL:
						return
					var destinations: Array[int] = [cell.index]
					var task := ThreadManager.do(_navigation_field, _navigation_field.cell_grid_get().calculate_flow_field.bind(destinations.duplicate()))
					if task != null:
						await task.done
						_navigation_field.debug_update(true, _navigation_field_debug_vector)
				MOUSE_BUTTON_MIDDLE:
					_self_mouse.middle_press_ing = true
					_input_middle_mouse()
				MOUSE_BUTTON_LEFT:
					_agents_spawn(p_local, _self_mouse.spawn_count)
				MOUSE_BUTTON_WHEEL_UP:
					_self_camera.size_target = clampf(_self_camera.camera.size - 2.0, 8.0, 35.0)
				MOUSE_BUTTON_WHEEL_DOWN:
					_self_camera.size_target = clampf(_self_camera.camera.size + 2.0, 8.0, 35.0)
		else:
			_self_mouse.middle_press_ing = false
	if _event_ is InputEventMouseMotion:
		_input_middle_mouse()
		_self_camera.update_view(_self_mouse.position)
