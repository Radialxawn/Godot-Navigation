@tool
class_name EditorSync
extends EditorScript

class _FromTo extends RefCounted:
	var folder: String
	var from: String
	var to: String
	var folder_global: String
	var folder_global_target: String
	var valid: bool
	var files: Array[String]
	var files_path_from: Array[String]
	var files_path_to: Array[String]
	func _init(_folder_: String) -> void:
		folder = _folder_
		var from_to: Array[String] = ["Godot-Game-Total-Run/Total Run", "Godot-Navigation"]
		folder_global = ProjectSettings.globalize_path(_folder_).get_base_dir()
		if folder_global.contains(from_to[1]):
			from_to.reverse()
			valid = true
		else:
			valid = true
		from = from_to[0]
		to = from_to[1]
		folder_global_target = folder_global.replace(from, to)
	func files_get(_extensions_: Array[String]) -> int:
		files.clear()
		files_path_from.clear()
		files_path_to.clear()
		for file: String in DirAccess.get_files_at(folder):
			if not file.get_extension() in _extensions_:
				continue
			files.append(file)
			files_path_from.append("%s/%s" % [folder_global, file])
			files_path_to.append("%s/%s" % [folder_global_target, file])
		return files_path_from.size()

func _run() -> void:
	var from_to := _FromTo.new("res://")
	assert(from_to.valid, "Can't sync from %s to %s" % [from_to.from, from_to.to])
	assert(DirAccess.dir_exists_absolute(from_to.folder_global_target), "Wrong target: %s" % from_to.folder_global_target)
	for i: int in from_to.files_get(["gd"]):
		if from_to.files[i] == "editor_sync.gd":
			if DirAccess.copy_absolute(from_to.files_path_from[i], from_to.files_path_to[i]) == OK:
				print("Sync from [%s] to [%s]: %s" % [from_to.from, from_to.to, from_to.files[i]])
	_sync_script("res://navigation/", true)
	_sync_scene("res://navigation/")
	_sync_script("res://script/helper/", false)
	_sync_scene("res://script/helper/")
	_sync_script("res://script/global/", false)
	_sync_shader("res://shader/spatial_debug/")

static func _sync_script_sync_data_get(_source_file_: String, _result_: Array[String]) -> bool:
	_result_.clear()
	var stage := 0
	var file := FileAccess.open(_source_file_, FileAccess.READ)
	while not file.eof_reached():
		var line := file.get_line()
		var line_trimmed := line.strip_edges()
		if line_trimmed.begins_with("#sync"):
			stage += 1
		elif line_trimmed.begins_with("#endsync"):
			stage += 1
			break
		elif stage > 0:
			_result_.append(line)
	file.close()
	return stage == 2 and _result_.size() > 0

static func _sync_script_combine_data_get(_source_data_: Array[String], _destination_file_: String, _result_: Array[String]) -> bool:
	_result_.clear()
	var stage := 0
	var file := FileAccess.open(_destination_file_, FileAccess.READ)
	while not file.eof_reached():
		var line := file.get_line()
		var line_trimmed := line.strip_edges()
		if line_trimmed.begins_with("#sync"):
			_result_.append(line)
			_result_.append_array(_source_data_)
			stage += 1
		elif line_trimmed.begins_with("#endsync"):
			_result_.append(line)
			stage += 1
		elif stage == 2:
			_result_.append(line)
	file.close()
	return stage == 2

static func _sync_script_trim_and_save(_data_: Array[String], _destination_file_: String) -> void:
	for i in range(_data_.size() - 1, 0, -1):
		if _data_[i].strip_edges() == "":
			_data_.remove_at(i)
		else:
			break
	var file := FileAccess.open(_destination_file_, FileAccess.WRITE)
	for line in _data_:
		file.store_line(line)
	file.close()

func _sync_scene(_folder_: String) -> void:
	var from_to := _FromTo.new(_folder_)
	assert(from_to.valid, "Can't sync from %s to %s" % [from_to.from, from_to.to])
	assert(DirAccess.dir_exists_absolute(from_to.folder_global_target), "Wrong target: %s" % from_to.folder_global_target)
	for i: int in from_to.files_get(["tscn"]):
		var path_from := from_to.files_path_from[i]
		var path_to := from_to.files_path_to[i]
		if DirAccess.copy_absolute(path_from, path_to) == OK:
			print("Scene sync from [%s] to [%s]: %s" % [from_to.from, from_to.to, from_to.files[i]])

func _sync_shader(_folder_: String) -> void:
	var from_to := _FromTo.new(_folder_)
	assert(from_to.valid, "Can't sync from %s to %s" % [from_to.from, from_to.to])
	assert(DirAccess.dir_exists_absolute(from_to.folder_global_target), "Wrong target: %s" % from_to.folder_global_target)
	for i: int in from_to.files_get(["gdshader"]):
		var path_from := from_to.files_path_from[i]
		var path_to := from_to.files_path_to[i]
		if DirAccess.copy_absolute(path_from, path_to) == OK:
			print("Shader sync from [%s] to [%s]: %s" % [from_to.from, from_to.to, from_to.files[i]])

func _sync_script(_folder_: String, _full_: bool) -> void:
	var from_to := _FromTo.new(_folder_)
	assert(from_to.valid, "Can't sync from %s to %s" % [from_to.from, from_to.to])
	assert(DirAccess.dir_exists_absolute(from_to.folder_global_target), "Wrong target: %s" % from_to.folder_global_target)
	for i: int in from_to.files_get(["gd"]):
		if _full_:
			if DirAccess.copy_absolute(from_to.files_path_from[i], from_to.files_path_to[i]) == OK:
				print("Script full sync from [%s] to [%s]: %s" % [from_to.from, from_to.to, from_to.files[i]])
		else:
			var sync_data: Array[String]
			if not _sync_script_sync_data_get(from_to.files_path_from[i], sync_data):
				continue
			var path_to := from_to.files_path_to[i]
			var combine_data: Array[String]
			if not _sync_script_combine_data_get(sync_data, path_to, combine_data):
				assert(false, "%s missing #sync or #endsync" % [path_to])
				continue
			_sync_script_trim_and_save(combine_data, path_to)
			print("Script sync from [%s] to [%s]: %s" % [from_to.from, from_to.to, from_to.files[i]])
