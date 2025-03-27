extends Node

var _tree: SceneTree
var _root: Window
var _ui_scenes: Array[Control]

var _render_world: RenderWorld
var render_world: RenderWorld:
	get():
		return _render_world

const _SCREEN_SIZE_PORTRAIT: Vector2 = Vector2(540.0, 960.0)
const _SCREEN_SIZE_LANDSCAPE: Vector2 = Vector2(_SCREEN_SIZE_PORTRAIT.y, _SCREEN_SIZE_PORTRAIT.x)
var screen_orientation: DisplayServer.ScreenOrientation = DisplayServer.SCREEN_PORTRAIT
var screen_size: Vector2:
	get():
		return (_SCREEN_SIZE_PORTRAIT if screen_orientation == DisplayServer.SCREEN_PORTRAIT
			else _SCREEN_SIZE_LANDSCAPE)
var screen_size_factor: Vector2
signal screen_orientation_set_done(_orientation_: DisplayServer.ScreenOrientation, _size_: Vector2)

@onready var is_editor: bool = OS.has_feature("editor")
@onready var is_debug_build: bool = OS.is_debug_build()

var _time_usec_last: int
var _time_sec: float
func time_sec() -> float: return _time_sec

var _physics_time_usec_last: int
var _physics_time_sec: float
func physics_time_sec() -> float: return _physics_time_sec

func _ready() -> void:
	_tree = get_tree()
	_root = _tree.root
	if is_editor:
		screen_size_factor = _SCREEN_SIZE_PORTRAIT / Vector2(DisplayServer.window_get_size())
	else:
		screen_size_factor = _SCREEN_SIZE_PORTRAIT / Vector2(DisplayServer.screen_get_size())
	_time_usec_last = Time.get_ticks_usec()
	_render_world = (load("res://render/render_world.tscn") as PackedScene).instantiate()
	add_child.call_deferred(_render_world)
	await _render_world.ready
	_render_world.initialzie()

func _process(_dt_: float) -> void:
	_time_sec += ((Time.get_ticks_usec() - _time_usec_last)) * 1e-6 * Engine.time_scale
	_time_usec_last = Time.get_ticks_usec()

func _physics_process(_dt_: float) -> void:
	_physics_time_sec += ((Time.get_ticks_usec() - _physics_time_usec_last)) * 1e-6 * Engine.time_scale
	_physics_time_usec_last = Time.get_ticks_usec()

func ui_scenes_add(_value_: Control) -> void:
	var order: int = 2**32
	#if _value_ is _Console: order = 13
	#elif _value_ is _Earn: order = 12
	#elif _value_ is _SPopup: order = 11
	#elif _value_ is SceneMain: order = 10
	#elif _value_ is SceneLoadIng: order = 9
	#elif _value_ is SceneSetting: order = 8
	#elif _value_ is SceneShop: order = 7
	#elif _value_ is SceneMainMenu: order = 6
	#elif _value_ is SceneGameMenu: order = 5
	assert(order != 2**32, "somthing wrong, please check scene order here")
	_ui_scenes.append(_value_)
	_value_.z_index = order
	ui_scenes_sort()

func ui_scenes_sort() -> void:
	if _ui_scenes.size() < 2:
		return
	_ui_scenes.sort_custom(func(_a_: Control, _b_: Control) -> bool: return _a_.z_index < _b_.z_index)
	for ui_scene: Control in _ui_scenes:
		ui_scene.move_to_front.call_deferred()

func screen_orientation_set(_value_: DisplayServer.ScreenOrientation) -> void:
	screen_orientation = _value_
	var size: Vector2 = screen_size
	if is_editor:
		_root.size = size
	else:
		DisplayServer.screen_set_orientation(_value_)
	_root.content_scale_size = size
	_root.content_scale_aspect = (
		Window.CONTENT_SCALE_ASPECT_KEEP_WIDTH if _value_ == DisplayServer.SCREEN_PORTRAIT
		else Window.CONTENT_SCALE_ASPECT_KEEP_HEIGHT
		)
	screen_orientation_set_done.emit(_value_, size)
