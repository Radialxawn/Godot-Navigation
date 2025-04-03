class_name NavigationTest
extends Node

@onready var _manual_agent: Label = $ui/manual_agent
@onready var _debug: Label = $ui/debug
@onready var _view_agents: MultiMeshInstance3D = $view_agents
@onready var _obstacles_node: Node3D = $obstacles

var _manual_boid_text_base: String

var _navigation_field: NavigationField
var _agents: Dictionary[int, NavigationField.Agent]
var _agents_local: Dictionary[int, NavigationField.Agent]
var _agents_target_changed: bool
var _agents_id_next: int
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
	var position: Vector2
	var position_world: Vector3
	var left_down: bool
	var left_down_position_world: Vector3
	var middle_down: bool
	var middle_cell_id: int
	var spawn_count: int
	var agents_id: Array[int]
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
	_navigation_field.debug_cell = true
	_navigation_field.debug_cell_vector = false
	_navigation_field.cell_grid_get().calculate_flow_field([0])
	_navigation_field.debug_update()
	_input_ready = true

func _agents_spawn_task(_count_: int) -> void:
	for i in _count_:
		_agents[_agents_id_next] = NavigationField.Agent.new()
		_agents_local[_agents_id_next] = NavigationField.Agent.new()
		_agents_id_next += 1

func _agents_spawn(_position_local_: Vector2, _count_: int) -> void:
	var spawn_count := _self_mouse.spawn_count
	var spread := ceili(sqrt(spawn_count))
	var task := ThreadManager.do(self, _agents_spawn_task.bind(_count_), true)
	if task != null:
		print("Spawn %d agent." % [_count_])
		await task.done
		for i in spawn_count:
			var agent_id := _agents_id_next - i - 1
			var agent := _agents[agent_id]
			agent.id = agent_id
			agent.radius = randi_range(40, 50) * 0.005
			@warning_ignore("integer_division")
			agent.position = Vector2(
				_position_local_.x + (i / spread) * 0.3,
				_position_local_.y + (i % spread) * 0.3
			)
			agent.position_speed_max = randi_range(20, 30) * 0.1
			agent.rotation_speed_max = randi_range(20, 30) * 0.1 * PI
			agent.acceleration = randi_range(15, 20) * 0.1
			_agents_local[agent_id].copy_stat(agent)
			_agents_local[agent_id].copy_transform(agent)
		_view_agents.multimesh.instance_count = _agents.size()

func _agents_kill_task(_agents_id_: Array[int]) -> void:
	for agent_id: int in _agents_id_:
		NavigationField.agent_exit(_agents[agent_id], _navigation_field.cell_grid_get())
		_agents.erase(agent_id)
		_agents_local.erase(agent_id)

func _agents_kill(_agents_id_: Array[int]) -> void:
	var kill_count := _agents_id_.size()
	if kill_count == 0:
		return
	var count_after := _agents.size() - kill_count
	var task := ThreadManager.do(self, _agents_kill_task.bind(_agents_id_.duplicate()), true)
	if task != null:
		print("Kill %d agent." % [kill_count])
		await task.done
		_self_mouse.agents_id.clear()
		_view_agents.multimesh.instance_count = count_after

func _agents_process(_dt_: float) -> void:
	var cell_grid := _navigation_field.cell_grid_get()
	for agent: NavigationField.Agent in _agents.values():
		NavigationField.agent_enter(agent, cell_grid)
		NavigationField.agent_move(agent, _dt_)
		NavigationField.agent_avoid_obstacle(cell_grid, _agents, agent.id, _obstacles, _dt_)
	for agent: NavigationField.Agent in _agents.values():
		NavigationField.agent_avoid_other(cell_grid, _agents, agent.id, _dt_)

func _physics_process(_dt_: float) -> void:
	if _self_mouse.left_down:
		_input_left_mouse_motion(Engine.get_physics_frames() % 2 == 0, false)
	_self_camera.physics_process(_dt_)
	if _agents.size() == _view_agents.multimesh.instance_count:
		var time_sec := Global.time_sec()
		var tf_base := Transform3D.IDENTITY.translated_local(_navigation_field.position)
		var i := 0
		for agent_local_id: int in _agents_local.keys():
			var agent_local := _agents_local[agent_local_id]
			var view_radius := agent_local.radius * 2.0
			var tf := (tf_base
				.translated_local(Vector3(agent_local.position.x, 0.0, agent_local.position.y))
				.rotated_local(Vector3.UP, -agent_local.rotation + PI * 0.5)
				.scaled_local(Vector3(view_radius, view_radius, view_radius))
			)
			var selected := agent_local.id in _self_mouse.agents_id
			var gray := 1.0 if selected else 0.0
			var flick := pingpong(time_sec, 0.5) if selected else 0.0
			var gray_flick := gray + flick
			_view_agents.multimesh.set_instance_transform(i, tf)
			_view_agents.multimesh.set_instance_custom_data(i,
				Color(wrapf(agent_local.move_distance * 7.5 / agent_local.radius, 30.0, 44.0), wrapi(i, 0, 16) * 0.0625, gray_flick)
			)
			i += 1
	if ThreadManager.doable(self):
		if _physics_time_sec_last == 0.0:
			_physics_time_sec_last = Global.physics_time_sec() - _dt_
		var dt := Global.physics_time_sec() - _physics_time_sec_last
		for agent: NavigationField.Agent in _agents.values():
			agent.copy_stat(_agents_local[agent.id])
			agent.copy_transform(_agents_local[agent.id])
		if _agents_target_changed:
			for agent: NavigationField.Agent in _agents.values():
				agent.copy_target(_agents_local[agent.id])
			_agents_target_changed = false
		var task := ThreadManager.do(self, _agents_process.bind(dt), true)
		if task != null:
			await task.done
			for agent_local: NavigationField.Agent in _agents_local.values():
				agent_local.copy_transform(_agents[agent_local.id])
			if not _agents_target_changed:
				for agent_local: NavigationField.Agent in _agents_local.values():
					agent_local.copy_target(_agents[agent_local.id])
		_physics_time_sec_last = Global.physics_time_sec()

func _process(_dt_: float) -> void:
	_debug.text = "FPS: %d, Agent count: %d, Mem: %.1fMB" % [
		Engine.get_frames_per_second(),
		_agents.size(),
		Performance.get_monitor(Performance.MEMORY_STATIC) * 1e-6,
		]
	_self_mouse.position = get_viewport().get_mouse_position()
	_self_mouse.position_world = _screen_position_to_world_position(_self_camera.camera, _self_mouse.position)
	_self_camera.update_view(_self_mouse.position)

static func _screen_position_to_world_position(_camera_: Camera3D, _screen_position_: Vector2) -> Vector3:
	var ro := _camera_.project_position(_screen_position_, 1.0)
	var ru := ro.direction_to(_camera_.project_position(_screen_position_, 100.0))
	var pn := Vector3.UP
	var pp := Vector3.ZERO
	var ro_pp := pp - ro
	var enter := ro_pp.length() * (ro_pp.normalized().dot(pn) / ru.dot(pn))
	return ro + enter * ru

#region Input
func _input(_event_: InputEvent) -> void:
	if not _input_ready:
		return
	if _event_ is InputEventKey:
		var key := _event_ as InputEventKey
		if key.is_released():
			_input_key_released(key.keycode)
	if _event_ is InputEventMouseButton:
		var mouse := _event_ as InputEventMouseButton
		if mouse.is_pressed():
			_input_mouse_button_pressed(mouse)
		if mouse.is_released():
			_input_mouse_button_released(mouse)
	if _event_ is InputEventMouseMotion:
		if _self_mouse.middle_down:
			_input_middle_mouse_motion()

func _input_change_spawn_count() -> void:
	var counts: Array[int] = [1, 10, 50, 100]
	var count_id := 0
	for i in counts.size():
		if _self_mouse.spawn_count == counts[i]:
			count_id = (i + 1) % counts.size()
			break
	_self_mouse.spawn_count = counts[count_id]
	_manual_agent.text = _manual_boid_text_base % [_self_mouse.spawn_count]

func _input_middle_mouse_motion() -> void:
	var p := _navigation_field.to_local(_self_mouse.position_world)
	var p_local := Vector2(p.x, p.z)
	var cell := _navigation_field.cell_grid_get().cell_nearest_get(p_local)
	if cell != null and cell.id != _self_mouse.middle_cell_id:
		if cell.cost == NavigationField.Cell.Cost.WALL:
			cell.cost = NavigationField.Cell.Cost.DEFAULT
		else:
			cell.cost = NavigationField.Cell.Cost.WALL
		_navigation_field.debug_update()
		_self_mouse.middle_cell_id = cell.id

func _input_left_mouse_motion(_process_select_: bool, _debug_print_: bool) -> void:
	var corner_a := _self_mouse.left_down_position_world
	var corner_b := _self_mouse.position_world
	var diagonal := corner_b - corner_a
	var corner_c := Vector3(corner_a.x, corner_a.y, corner_a.z + diagonal.z)
	var corner_d := Vector3(corner_a.x + diagonal.x, corner_a.y, corner_a.z)
	Helper.debug_draw_line(corner_a, corner_c, 0.02, Color.RED);
	Helper.debug_draw_line(corner_b, corner_c, 0.02, Color.RED);
	Helper.debug_draw_line(corner_a, corner_d, 0.02, Color.RED);
	Helper.debug_draw_line(corner_b, corner_d, 0.02, Color.RED);
	if not _process_select_:
		return
	var bound := _navigation_field.cell_grid_get().bound
	var kd_tree := KDTree.new(KDTree.Rectangle.new(0.0, 0.0, bound.x, bound.y), 4)
	for agent_local: NavigationField.Agent in _agents_local.values():
		kd_tree.insert(KDTree.Point.new(agent_local.id, agent_local.position.x, agent_local.position.y))
	var corner_a_local := _navigation_field.to_local(corner_a)
	var corner_b_local := _navigation_field.to_local(corner_b)
	var rectangle := KDTree.Rectangle.from_two_point(Vector2(corner_a_local.x, corner_a_local.z), Vector2(corner_b_local.x, corner_b_local.z))
	_self_mouse.agents_id.clear()
	if kd_tree.query(rectangle, _self_mouse.agents_id) and _debug_print_:
		if _self_mouse.agents_id.size() > 0:
			print("%d agents selected" % _self_mouse.agents_id.size())

func _input_key_released(_key_code_: int) -> void:
	match _key_code_:
		KEY_C:
			_input_change_spawn_count()
		KEY_V:
			_navigation_field.debug_cell_vector = not _navigation_field.debug_cell_vector
			_navigation_field.debug_update()
		KEY_B:
			_self_camera.change_view()
			_self_camera.update_view(_self_mouse.position)
		KEY_S:
			var p := _navigation_field.to_local(_self_mouse.position_world)
			_agents_spawn(Vector2(p.x, p.z), _self_mouse.spawn_count)
		KEY_D:
			_agents_kill(_self_mouse.agents_id)

func _input_mouse_button_pressed(_mouse_: InputEventMouseButton) -> void:
	var p := _navigation_field.to_local(_self_mouse.position_world)
	var p_grid := Vector2(p.x, p.z)
	match _mouse_.button_index:
		MOUSE_BUTTON_LEFT:
			_self_mouse.left_down_position_world = _self_mouse.position_world
			_self_mouse.left_down = true
		MOUSE_BUTTON_RIGHT:
			for agent_local: NavigationField.Agent in _agents_local.values():
				if _self_mouse.agents_id.size() > 0 and agent_local.id not in _self_mouse.agents_id:
					continue
				agent_local.target = p_grid
				agent_local.target_ing = true
				Helper.debug_draw_line(
					Vector3(agent_local.position.x, 0.1, agent_local.position.y) + _navigation_field.cell_grid_get().debug_offset,
					p + _navigation_field.cell_grid_get().debug_offset,
					0.01,
					Color.GREEN
				)
			_agents_target_changed = true
			var cell := _navigation_field.cell_grid_get().cell_nearest_get(p_grid)
			if cell == null or cell.cost == NavigationField.Cell.Cost.WALL:
				return
			var destinations: Array[int] = [cell.id]
			var task := ThreadManager.do(_navigation_field, _navigation_field.cell_grid_get().calculate_flow_field.bind(destinations.duplicate()))
			if task != null:
				await task.done
				_navigation_field.debug_update()
		MOUSE_BUTTON_MIDDLE:
			_self_mouse.middle_down = true
			_input_middle_mouse_motion()
		MOUSE_BUTTON_WHEEL_UP:
			_self_camera.size_target = clampf(_self_camera.camera.size - 2.0, 8.0, 35.0)
		MOUSE_BUTTON_WHEEL_DOWN:
			_self_camera.size_target = clampf(_self_camera.camera.size + 2.0, 8.0, 35.0)

func _input_mouse_button_released(_mouse_: InputEventMouseButton) -> void:
	match _mouse_.button_index:
		MOUSE_BUTTON_LEFT:
			_input_left_mouse_motion(true, true)
			_self_mouse.left_down = false
		MOUSE_BUTTON_MIDDLE:
			_self_mouse.middle_down = false
#endregion
