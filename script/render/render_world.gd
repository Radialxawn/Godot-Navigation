class_name RenderWorld
extends Node

const LIMIT_FPS := Vector3(30, 120, 1)
const LIMIT_SKY := Vector3(0, 1, 1)
const LIMIT_MSAA := Vector3(0, 2, 1)
const LIMIT_SHADOW := Vector3(0, 2, 1)
const LIMIT_RENDER_SCALE := Vector3(30, 200, 10)

enum ShadowDistanceType {
	MAIN_MENU,
	GAME,
}

func initialzie() -> void:
	pass

func quality_fps_max_set(_value_: int) -> void:
	pass

func quality_shadow_set(_value_: int) -> void:
	pass

func quality_sky_set(_value_: int) -> void:
	pass

func quality_render_scale_set(_viewports_: Array[Viewport], _value_: int) -> void:
	pass

func quality_msaa_set(_viewports_: Array[Viewport], _value_: int) -> void:
	pass

func shadow_distance_set(_type_: ShadowDistanceType) -> void:
	pass
