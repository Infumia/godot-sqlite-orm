@tool
class_name DbCodegenProcess
extends RefCounted
## Runs the generator in a separate Godot process and reads its report.
##
## The editor cannot run the generator itself: it does not instantiate scripts without
## @tool, and compiling a model does. A child process runs the same code as the command line.

const SCRIPT_PATH: String = "res://addons/sqlite_orm/generator/generate.gd"
const PREFIX: String = "sqlite_orm generator: "


## The command line arguments that run the generator for this project.
static func arguments(check: bool) -> PackedStringArray:
    var args: PackedStringArray = [
        "--headless",
        "--path",
        ProjectSettings.globalize_path("res://"),
        "--script",
        SCRIPT_PATH,
    ]
    if check:
        args.append_array(["--", "--check"])
    return args


## Runs the generator and waits for it. Call it from a thread to keep the editor responsive.
static func run(check: bool) -> Result:
    var output: Array = []
    var code: int = OS.execute(OS.get_executable_path(), arguments(check), output, true)
    var text: String = ""
    for chunk: Variant in output:
        text += str(chunk)
    return parse(code, text)


## Reads the generator's output.
static func parse(exit_code: int, text: String) -> Result:
    var result: Result = Result.new()
    result.exit_code = exit_code
    result.output = text
    for raw_line: String in text.split("\n"):
        var line: String = raw_line.strip_edges()
        if line.begins_with("wrote: ") or line.begins_with("stale or missing: "):
            result.written.append(line.get_slice(": ", 1))
        elif line.begins_with("removed: ") or line.begins_with("orphaned: "):
            result.removed.append(line.get_slice(": ", 1))
        elif line.begins_with(PREFIX) and not line.ends_with("up to date"):
            result.errors.append(line.trim_prefix(PREFIX))
    if exit_code != 0 and result.errors.is_empty() and result.written.is_empty():
        result.errors.append(
            "the generator exited with code %d:\n%s" % [exit_code, text.strip_edges()]
        )
    return result


## What a run reported.
class Result:
    extends RefCounted

    var exit_code: int = 0
    var written: PackedStringArray = []
    var removed: PackedStringArray = []
    var errors: PackedStringArray = []
    var output: String = ""


    func ok() -> bool:
        return exit_code == 0 and errors.is_empty()


    func changed_anything() -> bool:
        return not written.is_empty() or not removed.is_empty()
