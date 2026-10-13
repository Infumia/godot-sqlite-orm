@tool
extends EditorPlugin
## Regenerates the model helpers when a model is saved, and from Project > Tools.
## The generator runs in a child process on a thread, so the editor stays responsive.

const MENU_ITEM: String = "Regenerate DB Helpers"
## Saves within this many seconds share one run.
const DEBOUNCE_SECONDS: float = 0.4

var _thread: Thread = null
var _timer: Timer = null
## Another run was asked for while one was running.
var _queued: bool = false
## The current run was asked for from the menu, so "nothing changed" is worth saying.
var _from_menu: bool = false


func _enter_tree() -> void:
    _register_settings()
    _timer = Timer.new()
    _timer.one_shot = true
    _timer.wait_time = DEBOUNCE_SECONDS
    add_child(_timer)
    _timer.timeout.connect(_start)
    resource_saved.connect(_on_resource_saved)
    add_tool_menu_item(MENU_ITEM, _on_menu)


func _exit_tree() -> void:
    remove_tool_menu_item(MENU_ITEM)
    resource_saved.disconnect(_on_resource_saved)
    _timer.timeout.disconnect(_start)
    _timer.queue_free()
    _timer = null
    if _thread != null:
        _thread.wait_to_finish()
        _thread = null


func _on_resource_saved(resource: Resource) -> void:
    if not DbCodegen.run_on_save_setting():
        return
    if resource is GDScript and DbCodegen.is_model_script(resource.resource_path):
        _request(false)


func _on_menu() -> void:
    _request(true)


func _request(from_menu: bool) -> void:
    _from_menu = _from_menu or from_menu
    if _thread != null:
        _queued = true
        return
    _timer.start()


func _start() -> void:
    if _thread != null:
        _queued = true
        return
    _thread = Thread.new()
    _thread.start(_work)


func _work() -> DbCodegenProcess.Result:
    var result: DbCodegenProcess.Result = DbCodegenProcess.run(false)
    _finish.call_deferred()
    return result


func _finish() -> void:
    var result: DbCodegenProcess.Result = _thread.wait_to_finish()
    _thread = null
    _report(result)
    if result.changed_anything():
        EditorInterface.get_resource_filesystem().scan()
    _from_menu = false
    if _queued:
        _queued = false
        _request(false)


func _report(result: DbCodegenProcess.Result) -> void:
    var toaster: EditorToaster = EditorInterface.get_editor_toaster()
    if not result.ok():
        for error: String in result.errors:
            push_error("sqlite_orm generator: " + error)
        toaster.push_toast(
            "DB helpers not generated: " + "; ".join(result.errors),
            EditorToaster.SEVERITY_ERROR,
        )
        return
    if result.changed_anything():
        toaster.push_toast(
            "DB helpers: %d written, %d removed" % [result.written.size(), result.removed.size()],
            EditorToaster.SEVERITY_INFO,
        )
    elif _from_menu:
        toaster.push_toast("DB helpers are up to date", EditorToaster.SEVERITY_INFO)


func _register_settings() -> void:
    _add_setting(
        DbCodegen.OUTPUT_DIR_SETTING,
        DbCodegen.DEFAULT_OUTPUT_DIR,
        TYPE_STRING,
        PROPERTY_HINT_DIR,
        "",
    )
    _add_setting(
        DbCodegen.EXCLUDE_SETTING,
        PackedStringArray(["res://addons"]),
        TYPE_PACKED_STRING_ARRAY,
        PROPERTY_HINT_TYPE_STRING,
        "%d/%d:" % [TYPE_STRING, PROPERTY_HINT_DIR],
    )
    _add_setting(DbCodegen.RUN_ON_SAVE_SETTING, true, TYPE_BOOL, PROPERTY_HINT_NONE, "")


func _add_setting(
    setting: String,
    default: Variant,
    type: int,
    hint: int,
    hint_string: String,
) -> void:
    if not ProjectSettings.has_setting(setting):
        ProjectSettings.set_setting(setting, default)
    ProjectSettings.set_initial_value(setting, default)
    ProjectSettings.add_property_info(
        { "name": setting, "type": type, "hint": hint, "hint_string": hint_string }
    )
