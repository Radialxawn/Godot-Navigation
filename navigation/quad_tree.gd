class_name QuadTree
extends RefCounted

class Point extends RefCounted:
	var id: int
	var x: float
	var y: float
	func _init(_id_: int, _x_: float, _y_: float) -> void:
		id = _id_
		x = _x_
		y = _y_

## This rectangle anchor is not at center but at top left corner
class Rectangle extends RefCounted:
	var x: float
	var y: float
	var w: float
	var h: float
	func _init(_x_: float, _y_: float, _w_: float, _h_: float) -> void:
		x = _x_
		y = _y_
		w = _w_
		h = _h_
	func contain(_point_: Point) -> bool:
		return (
			(x <= _point_.x && _point_.x < x + w) &&
			(y <= _point_.y && _point_.y < y + h)
		)
	func intersect(_range_: Rectangle) -> bool:
		return not (
			(x + w < _range_.x || _range_.x + _range_.w < x) ||
			(y + h < _range_.y || _range_.y + _range_.h < y)
		)
	static func from_two_point(_a_: Vector2, _b_: Vector2) -> Rectangle:
		return Rectangle.new(minf(_a_.x, _b_.x), minf(_a_.y, _b_.y), absf(_b_.x - _a_.x), absf(_b_.y - _a_.y))

var bound: Rectangle
var capacity: int
var points: Array[Point]
var divided: bool
var top_l: QuadTree
var top_r: QuadTree
var bot_l: QuadTree
var bot_r: QuadTree

func _init(_bound_: Rectangle, _capacity_: int) -> void:
	bound = _bound_
	capacity = _capacity_
	points = []
	divided = false

func _subdivide() -> void:
	var x := bound.x
	var y := bound.y
	var wh := bound.w * 0.5
	var hh := bound.h * 0.5
	top_l = QuadTree.new(Rectangle.new(x, y, wh, hh), capacity)
	top_r = QuadTree.new(Rectangle.new(x + wh, y, wh, hh), capacity)
	bot_l = QuadTree.new(Rectangle.new(x, y + hh, wh, hh), capacity)
	bot_r = QuadTree.new(Rectangle.new(x + wh, y + hh, wh, hh), capacity)
	divided = true

func insert(_point_: Point) -> bool:
	if not bound.contain(_point_):
		return false
	if points.size() < capacity:
		points.append(_point_);
		return true
	else:
		if not divided:
			_subdivide()
	if top_l.insert(_point_):
		return true
	elif top_r.insert(_point_):
		return true
	elif bot_l.insert(_point_):
		return true
	elif bot_r.insert(_point_):
		return true
	return false

func query(_range_: Rectangle, _found_id_: Dictionary[int, bool]) -> bool:
	if not bound.intersect(_range_):
		return false
	else:
		for p: Point in points:
			if _range_.contain(p):
				_found_id_[p.id] = true;
	if divided:
		top_r.query(_range_, _found_id_)
		top_l.query(_range_, _found_id_)
		bot_r.query(_range_, _found_id_)
		bot_l.query(_range_, _found_id_)
	return _found_id_.size() > 0
