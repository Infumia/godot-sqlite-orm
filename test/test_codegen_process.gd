# GUT asserts take untyped arguments; Godot 4.7 flags every Variant passed to them.
@warning_ignore_start("unsafe_call_argument")
extends DbTestCase
## Running the generator in a child process, as the editor plugin does, and choosing which
## saved scripts trigger it.


func test_arguments() -> void:
    var args: PackedStringArray = DbCodegenProcess.arguments(false)
    assert_has(args, "--headless")
    assert_has(args, DbCodegenProcess.SCRIPT_PATH)
    assert_has(args, ProjectSettings.globalize_path("res://"))
    assert_does_not_have(args, "--check")
    var check: PackedStringArray = DbCodegenProcess.arguments(true)
    assert_eq(check.slice(-2), PackedStringArray(["--", "--check"]))


func test_check_run_in_a_child_process() -> void:
    var result: DbCodegenProcess.Result = DbCodegenProcess.run(true)
    assert_true(result.ok(), result.output)
    assert_false(result.changed_anything())


func test_parse_written_and_removed() -> void:
    var text: String = "\n".join(
        [
            "Godot Engine v4.7",
            "wrote: res://gen/a_db.gd",
            "wrote: res://gen/b_db.gd",
            "removed: res://gen/old_db.gd",
            "ERROR: 3 RID allocations leaked at exit.",
        ]
    )
    var result: DbCodegenProcess.Result = DbCodegenProcess.parse(0, text)
    assert_true(result.ok())
    assert_eq(result.written, PackedStringArray(["res://gen/a_db.gd", "res://gen/b_db.gd"]))
    assert_eq(result.removed, PackedStringArray(["res://gen/old_db.gd"]))
    assert_true(result.changed_anything())


func test_parse_check_mode_lines() -> void:
    var result: DbCodegenProcess.Result = DbCodegenProcess.parse(
        1,
        "stale or missing: res://gen/a_db.gd\norphaned: res://gen/x_db.gd\n",
    )
    assert_false(result.ok())
    assert_eq(result.written, PackedStringArray(["res://gen/a_db.gd"]))
    assert_eq(result.removed, PackedStringArray(["res://gen/x_db.gd"]))
    assert_eq(result.errors, PackedStringArray())


func test_parse_errors() -> void:
    var result: DbCodegenProcess.Result = DbCodegenProcess.parse(
        1,
        "sqlite_orm generator: Item: has no primary key\n",
    )
    assert_false(result.ok())
    assert_eq(result.errors, PackedStringArray(["Item: has no primary key"]))


func test_parse_up_to_date_is_not_an_error() -> void:
    var result: DbCodegenProcess.Result = DbCodegenProcess.parse(
        0,
        "sqlite_orm generator: helpers are up to date\n",
    )
    assert_true(result.ok())
    assert_false(result.changed_anything())


func test_parse_failure_without_a_report() -> void:
    var result: DbCodegenProcess.Result = DbCodegenProcess.parse(1, "SCRIPT ERROR: Parse Error\n")
    assert_false(result.ok())
    assert_eq(result.errors.size(), 1)
    assert_string_contains(result.errors[0], "exited with code 1")
    assert_string_contains(result.errors[0], "Parse Error")


func test_saved_model_scripts_trigger_a_run() -> void:
    assert_true(DbCodegen.is_model_script("res://test/fixtures/models/fx_character.gd"))
    assert_true(DbCodegen.is_model_script("res://test/fixtures/models/fx_hero.gd"))


func test_other_saved_scripts_do_not() -> void:
    assert_false(DbCodegen.is_model_script("res://test/db_test_case.gd"), "not a model")
    assert_false(
        DbCodegen.is_model_script("res://test/fixtures/migrations/mg_player_v1.gd"),
        "excluded",
    )
    assert_false(DbCodegen.is_model_script("res://test/generated/fx_item_db.gd"), "output")
    assert_false(DbCodegen.is_model_script("res://addons/sqlite_orm/db_model.gd"), "addons")
    assert_false(DbCodegen.is_model_script("res://test/fixtures/models/missing.gd"), "missing")
    assert_false(DbCodegen.is_model_script("res://project.godot"), "not a script")


func test_run_on_save_setting_defaults_to_true() -> void:
    var saved: Variant = ProjectSettings.get_setting(DbCodegen.RUN_ON_SAVE_SETTING)
    ProjectSettings.set_setting(DbCodegen.RUN_ON_SAVE_SETTING, null)
    assert_true(DbCodegen.run_on_save_setting())
    ProjectSettings.set_setting(DbCodegen.RUN_ON_SAVE_SETTING, false)
    assert_false(DbCodegen.run_on_save_setting())
    ProjectSettings.set_setting(DbCodegen.RUN_ON_SAVE_SETTING, saved)


func test_the_child_process_loads_no_script_that_is_not_a_model() -> void:
    # FxEventListener names an autoload, which a command-line run does not have.
    var result: DbCodegenProcess.Result = DbCodegenProcess.run(true)
    assert_true(result.ok(), result.output)
    assert_false(result.output.contains("SCRIPT ERROR"), result.output)
