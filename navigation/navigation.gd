class_name Navigation
extends Node

@onready var _manual_boid: Label = $ui/manual_boid
@onready var _debug: Label = $ui/debug
@onready var _view_agents: MultiMeshInstance3D = $view_agents
@onready var _obstacles_node: Node3D = $obstacles

var _manual_boid_text_base: String

var _flow_field: FlowField
var _flow_field_debug_vector: bool
var _agents: Array[FlowField.Agent]
var _agents_local: Array[FlowField.Agent]
var _obstacles: Array[FlowField.Obstacle]
var _physics_time_sec_last: float
var _input_ready: bool

class SelfCamera extends RefCounted:
	var camera: Camera3D
	var offset: Vector3
	var position_target: Vector3
	var size_target: float
	func _init(_camera_: Camera3D) -> void:
		camera = _camera_
		offset = camera.global_position
		position_target = camera.global_position
		size_target = camera.size
	func physics_process(_dt_: float) -> void:
		camera.global_position = camera.global_position.lerp(position_target, 0.1)
		camera.size = lerpf(camera.size, size_target, 0.1)
var _self_camera: SelfCamera

class SelfMouse extends RefCounted:
	var position_world: Vector3
	var position: Vector2
	var middle_press_ing: bool
	var middle_cell_index_last: int
	var spawn_count: int
var _self_mouse: SelfMouse

func _ready() -> void:
	Global.render_world.queue_free() # this project is striped from main project
	_flow_field = FlowField.spawn(self).create(Vector2i(10, 30), Vector2(1.0, 1.0), true)
	_flow_field.position_set(Vector3(0.0, 0.0, 0.0), Vector2(0.5, 0.5))
	_view_agents.multimesh.mesh = ($view_agents/creep_1/body as MeshInstance3D).mesh
	for child in _obstacles_node.get_children():
		var collider := child as CollisionShape3D
		if collider.shape is SphereShape3D:
			_obstacles.append(FlowField.ObstacleCircle.new(_flow_field, collider))
		elif collider.shape is BoxShape3D:
			_obstacles.append(FlowField.ObstacleRectangle.new(_flow_field, collider))
	_self_mouse = SelfMouse.new()
	_self_camera = SelfCamera.new($camera)
	_manual_boid_text_base = _manual_boid.text
	_input_change_spawn_count()
	_input_ready = false
	for i in 2: await get_tree().process_frame
	_flow_field_debug_vector = true
	_flow_field.calculate([0])
	_flow_field.debug_update(true, _flow_field_debug_vector)
	_input_ready = true

func _agents_spawn(_count_: int) -> void:
	for i in _count_:
		_agents.append(FlowField.Agent.new())
		_agents_local.append(FlowField.Agent.new())

func _agents_process(_dt_: float) -> void:
	for agent in _agents:
		FlowField.agent_enter(agent, _flow_field)
		FlowField.agent_avoid_obstacle(agent, _flow_field, _dt_)
		FlowField.agent_avoid_other(agent, _flow_field, _dt_)
		FlowField.agent_move(agent, _flow_field, _dt_)

func _physics_process(_dt_: float) -> void:
	if ThreadManager.doable(self):
		if _physics_time_sec_last == 0.0:
			_physics_time_sec_last = Global.physics_time_sec() - _dt_
		var dt := Global.physics_time_sec() - _physics_time_sec_last
		for i in _agents.size():
			_agents[i].copy_stat(_agents_local[i])
			_agents[i].copy_transform(_agents_local[i])
			_agents[i].copy_target(_agents_local[i])
		var task := ThreadManager.do(self, _agents_process.bind(dt), true)
		if task != null:
			await task.done
			for i in _agents.size():
				_agents_local[i].copy_transform(_agents[i])
		_physics_time_sec_last = Global.physics_time_sec()
	if _agents_local.size() == _view_agents.multimesh.instance_count:
		var tf_base := Transform3D.IDENTITY.translated_local(_flow_field.position)
		for i in _agents_local.size():
			var agent_local := _agents_local[i]
			agent_local.position = agent_local.position_next
			var view_radius := agent_local.radius
			var tf := (tf_base
				.translated_local(Vector3(agent_local.position.x, 0.0, agent_local.position.y))
				.rotated_local(Vector3.UP, -agent_local.rotation + PI * 0.5)
				.scaled_local(Vector3(view_radius, view_radius, view_radius))
			)
			_view_agents.multimesh.set_instance_transform(i, tf)
			_view_agents.multimesh.set_instance_custom_data(i,
				Color(wrapf(agent_local.move_distance * 7.5 / agent_local.radius, 30.0, 44.0), wrapi(i, 0, 16) * 0.0625, 0.0)
			)
	_self_camera.physics_process(_dt_)

func _process(_dt_: float) -> void:
	_debug.text = "FPS: %d, Agent count: %d" % [
		Engine.get_frames_per_second(),
		_agents_local.size(),
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
	var counts: Array[int] = [1, 10, 50]
	var count_index := 0
	for i in counts.size():
		if _self_mouse.spawn_count == counts[i]:
			count_index = (i + 1) % counts.size()
			break;
	_self_mouse.spawn_count = counts[count_index]
	_manual_boid.text = _manual_boid_text_base % _self_mouse.spawn_count

func _input_middle_mouse() -> void:
	if _self_mouse.middle_press_ing:
		var p := _flow_field.to_local(_self_mouse.position_world)
		var p_local := Vector2(p.x, p.z)
		var cell := _flow_field.cell_nearest_get(p_local)
		if cell != null and cell.index != _self_mouse.middle_cell_index_last:
			if cell.cost == FlowField.Cell.Cost.WALL:
				cell.cost = FlowField.Cell.Cost.DEFAULT
			else:
				cell.cost = FlowField.Cell.Cost.WALL
			_flow_field.debug_update(true, _flow_field_debug_vector)
			_self_mouse.middle_cell_index_last = cell.index

func _input(_event_: InputEvent) -> void:
	if not _input_ready:
		return
	if _event_ is InputEventKey:
		var key := _event_ as InputEventKey
		if key.is_released() and key.keycode == KEY_C:
			_input_change_spawn_count()
		if key.is_released() and key.keycode == KEY_V:
			_flow_field_debug_vector = not _flow_field_debug_vector
			_flow_field.debug_update(true, _flow_field_debug_vector)
	if _event_ is InputEventMouseButton or _event_ is InputEventMouseMotion:
		_self_mouse.position = (_event_ as InputEventMouse).position
		_self_mouse.position_world = _position_get(_self_camera.camera, _self_mouse.position)
		Helper.debug_draw_sphere(_self_mouse.position_world, 0.15, Color.RED)
	if _event_ is InputEventMouseButton:
		var mouse := _event_ as InputEventMouseButton
		if mouse.pressed:
			var p := _flow_field.to_local(_self_mouse.position_world)
			var p_local := Vector2(p.x, p.z)
			match mouse.button_index:
				MOUSE_BUTTON_RIGHT:
					for agent_local in _agents_local:
						agent_local.target = p_local
						agent_local.target_ing = true
					var cell := _flow_field.cell_nearest_get(p_local)
					if cell == null or cell.cost == FlowField.Cell.Cost.WALL:
						return
					var destinations: Array[int] = [cell.index]
					var task := ThreadManager.do(_flow_field, _flow_field.calculate.bind(destinations.duplicate()))
					if task != null:
						await task.done
						_flow_field.debug_update(true, _flow_field_debug_vector)
				MOUSE_BUTTON_MIDDLE:
					_self_mouse.middle_press_ing = true
					_input_middle_mouse()
				MOUSE_BUTTON_LEFT:
					var spawn_count := _self_mouse.spawn_count
					var spread := ceili(sqrt(spawn_count))
					var task := ThreadManager.do(self, _agents_spawn.bind(spawn_count), true)
					if task != null:
						await task.done
						_view_agents.multimesh.instance_count = _agents.size()
						for i in spawn_count:
							var agent_index := _agents.size() - 1 - i
							var agent := _agents[agent_index]
							agent.radius = randi_range(80, 95) * 0.005
							@warning_ignore("integer_division")
							agent.position = Vector2(p_local.x + (i / spread) * 0.3, p_local.y + (i % spread) * 0.3)
							agent.position_next = agent.position
							agent.position_speed_max = randi_range(20, 30) * 0.1
							agent.rotation_speed_max = randi_range(20, 30) * 0.1 * PI
							_agents_local[agent_index].copy_stat(agent)
							_agents_local[agent_index].copy_transform(agent)
				MOUSE_BUTTON_WHEEL_UP:
					_self_camera.size_target = clampf(_self_camera.camera.size - 2.0, 8.0, 35.0)
				MOUSE_BUTTON_WHEEL_DOWN:
					_self_camera.size_target = clampf(_self_camera.camera.size + 2.0, 8.0, 35.0)
		else:
			_self_mouse.middle_press_ing = false
	if _event_ is InputEventMouseMotion:
		_input_middle_mouse()
		var screen_size := Global.screen_size
		var camera_position_new := _self_camera.offset + Vector3(
			(_self_mouse.position.x - screen_size.x * 0.5) * _self_camera.camera.size / screen_size.x, 0.0,
			(_self_mouse.position.y - screen_size.y * 0.5) * _self_camera.camera.size / screen_size.x)
		_self_camera.position_target = _self_camera.camera.global_position.lerp(camera_position_new, 0.1)
