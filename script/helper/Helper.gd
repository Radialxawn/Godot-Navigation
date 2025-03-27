#sync
class_name _Helper
extends Node

class _DebugShape extends RefCounted:
	var _mmi: MultiMeshInstance3D
	var _empty_count: int
	var transforms: Array[Transform3D]
	var colors: Array[Color]
	func _init(_mmi_: MultiMeshInstance3D) -> void:
		_mmi = _mmi_
	func draw() -> void:
		var draw_count := transforms.size()
		if draw_count > 0:
			_mmi.multimesh.instance_count = draw_count
			_mmi.multimesh.visible_instance_count = draw_count
			for i: int in draw_count:
				_mmi.multimesh.set_instance_transform(i, transforms[i])
				_mmi.multimesh.set_instance_color(i, colors[i])
		transforms.clear()
		colors.clear()
		if draw_count == 0:
			_empty_count += 1
		else:
			_empty_count = 0
		if _empty_count == 10:
			_mmi.multimesh.visible_instance_count = 0

var _debug_shape_spheres: Array[_DebugShape]
var _debug_shape_line: _DebugShape

func _ready() -> void:
	_debug_shape_spheres = [
		_DebugShape.new($debug_shape_sphere_8),
		_DebugShape.new($debug_shape_sphere_16),
		_DebugShape.new($debug_shape_sphere_32),
		_DebugShape.new($debug_shape_sphere_64),
	]
	_debug_shape_line = _DebugShape.new($debug_shape_line)

func _process(_dt_: float) -> void:
	for debug_shape_sphere: _DebugShape in _debug_shape_spheres:
		debug_shape_sphere.draw()
	_debug_shape_line.draw()

func debug_draw_sphere(_position_: Vector3, _radius_: float, _color_: Color) -> void:
	var debug_shape_sphere := _debug_shape_spheres[clampi(int(_radius_ / 0.25), 0, _debug_shape_spheres.size() - 1)]
	debug_shape_sphere.transforms.append(Transform3D.IDENTITY
		.translated(_position_)
		.scaled_local(Vector3(_radius_, _radius_, _radius_))
	)
	debug_shape_sphere.colors.append(_color_)

func debug_draw_line(_from_: Vector3, _to_: Vector3, _size_: float, _color_: Color) -> void:
	var center := (_from_ + _to_) * 0.5
	var line_transform := (Transform3D.IDENTITY
		.translated(center)
		.looking_at(_to_, Math.get_perpendicular_vector(_to_ - _from_))
		.scaled_local(Vector3(_size_, _size_, _from_.distance_to(_to_)))
	)
	_debug_shape_line.transforms.append(line_transform)
	_debug_shape_line.colors.append(_color_)

func overlap_sphere_get_areas(_position_: Vector3, _radius_: float, _mask_: int) -> Array[Dictionary]:
	var shape_rid := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(shape_rid, _radius_)
	var parameter := PhysicsShapeQueryParameters3D.new()
	parameter.collide_with_areas = true
	parameter.collide_with_bodies = false
	parameter.shape_rid = shape_rid
	parameter.transform = Transform3D.IDENTITY.translated(_position_)
	parameter.collision_mask = _mask_
	var space := get_viewport().world_3d.direct_space_state
	var hits := space.intersect_shape(parameter)
	PhysicsServer3D.free_rid(shape_rid)
	return hits

func ray_cast(_from_: Vector3, _offset_: Vector3, _mask_: int, _areas_: bool, _bodys_: bool) -> Dictionary:
	var parameter := PhysicsRayQueryParameters3D.new()
	parameter.collision_mask = _mask_
	parameter.collide_with_areas = _areas_
	parameter.collide_with_bodies = _bodys_
	parameter.from = _from_
	parameter.to = _from_ + _offset_
	parameter.hit_back_faces = false
	var space := get_viewport().world_3d.direct_space_state
	var hit := space.intersect_ray(parameter)
	return hit

static func tween_show_hide_modulate_fade(_value_: bool, _tweener_: Control, _nodes_: Array[Control], _set_visible_: bool, _time_sec_: float) -> Tween:
	var mt := func(_modulate_: Color) -> void:
		for node: Control in _nodes_:
			node.modulate = _modulate_
	var tween := _tweener_.create_tween()
	if _value_:
		if _set_visible_:
			for node: Control in _nodes_:
				node.visible = true
		tween.tween_method(mt, Color(1, 1, 1, 0), Color(1, 1, 1, 1), _time_sec_)
	else:
		tween.tween_method(mt, Color(1, 1, 1, 1), Color(1, 1, 1, 0), _time_sec_)
		tween.finished.connect(func() -> void:
			if _set_visible_:
				for node: Control in _nodes_:
					node.visible = false
				)
	return tween

static func tween_button_pressed(_button_: Control) -> Tween:
	var tween := _button_.create_tween()
	_button_.scale = Vector2(0.8, 0.8)
	tween.tween_property(_button_, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	return tween

static func get_all_child(_target_: Node, _arr_: Array[Node] = []) -> Array[Node]:
	_arr_.push_back(_target_)
	for child: Node in _target_.get_children():
		_arr_ = get_all_child(child,_arr_)
	return _arr_

static func clear_all_child(_target_: Node) -> void:
	for child: Node in _target_.get_children():
		child.queue_free()
#endsync
