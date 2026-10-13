extends SceneTree
## Loads every script under the given folders so parse errors and warnings-as-errors show up.
## godot --headless --script res://tools/check_scripts.gd

## Scripts that name an autoload. A command-line run has no autoloads, so they cannot compile
## here; the GUT run loads them instead.
const SKIPPED: PackedStringArray = ["res://test/fixtures/autoload"]


func _init() -> void:
    var failed: int = 0
    for root: String in ["res://addons/sqlite_orm", "res://test"]:
        for path: String in _scripts(root):
            if _is_skipped(path):
                continue
            var script: Script = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
            if script == null or not script.can_instantiate():
                print("FAILED ", path)
                failed += 1
    print("checked scripts, %d failed" % failed)
    quit(1 if failed > 0 else 0)


func _scripts(root: String) -> PackedStringArray:
    var found: PackedStringArray = []
    if not DirAccess.dir_exists_absolute(root):
        return found
    for file: String in DirAccess.get_files_at(root):
        if file.ends_with(".gd"):
            found.append(root.path_join(file))
    for folder: String in DirAccess.get_directories_at(root):
        found.append_array(_scripts(root.path_join(folder)))
    return found


func _is_skipped(path: String) -> bool:
    for folder: String in SKIPPED:
        if path.begins_with(folder + "/"):
            return true
    return false
