extends SceneTree
## Generates the typed model helpers from the command line:
## [codeblock]
## godot --headless --script res://addons/sqlite_orm/generator/generate.gd
## godot --headless --script res://addons/sqlite_orm/generator/generate.gd -- --check
## [/codeblock]
## With --check nothing is written; the exit code is 1 when a helper is missing, stale or
## orphaned, so a pre-commit hook or CI can catch a forgotten run.


func _init() -> void:
    var check: bool = "--check" in OS.get_cmdline_user_args()
    var report: DbCodegen.Report = DbCodegen.run(check)
    for error: String in report.errors:
        printerr("sqlite_orm generator: " + error)
    for path: String in report.changed:
        print(("stale or missing: " if check else "wrote: ") + path)
    for path: String in report.removed:
        print(("orphaned: " if check else "removed: ") + path)
    if check and report.is_current():
        print("sqlite_orm generator: helpers are up to date")
    var failed: bool = not report.errors.is_empty() or (check and not report.is_current())
    quit(1 if failed else 0)
