class_name _ThreadManager
extends Node

class Task extends RefCounted:
	var caller: Node
	var id : int
	signal done
	func _init(_caller_: Node, _id_: int) -> void:
		caller = _caller_
		id = _id_
	func get_processed_element_count() -> int:
		return 1 if is_done() else 0
	func is_done() -> bool:
		return WorkerThreadPool.is_task_completed(id)
	func wait() -> void:
		WorkerThreadPool.wait_for_task_completion(id)

class TaskGroup extends Task:
	func get_processed_element_count() -> int:
		return WorkerThreadPool.get_group_processed_element_count(id)
	func is_done() -> bool:
		return WorkerThreadPool.is_group_task_completed(id)
	func wait() -> void:
		WorkerThreadPool.wait_for_group_task_completion(id)

var _tasks: Array[Task]
var _mutex := Mutex.new()

func doable(_caller_: Node) -> bool:
	for task in _tasks:
		if _caller_ != null and task.caller == _caller_:
			return false
	return true

func do(_caller_: Node, _action_: Callable, _high_priority_ := false, _description_ := "") -> Task:
	if not doable(_caller_):
		return null
	var task_id := WorkerThreadPool.add_task(_action_, _high_priority_, _description_)
	var task := Task.new(_caller_, task_id)
	_mutex.lock()
	_tasks.append(task)
	_mutex.unlock()
	return task

func do_group(_caller_: Node, _action_: Callable, _elements_ : int, _tasks_needed_ := -1, _high_priority_ := false, _description_ := "") -> TaskGroup:
	if not doable(_caller_):
		return null
	var task_group_id := WorkerThreadPool.add_group_task(_action_, _elements_, _tasks_needed_, _high_priority_, _description_)
	var task_group := TaskGroup.new(_caller_, task_group_id)
	_mutex.lock()
	_tasks.append(task_group)
	_mutex.unlock()
	return task_group

func _process(_dt_: float) -> void:
	_mutex.lock()
	var done_tasks := _tasks.filter(func(task: Task) -> bool: return task.is_done())
	for done_task: Task in done_tasks:
		var task : Task = done_task
		task.done.emit()
		_tasks.erase(task)
	_mutex.unlock()
