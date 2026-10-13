class_name DbOptions
extends RefCounted
## Settings for [method Db.open]. Every setting has a safe default.

enum Journal {
    ## One file at rest: every change is written to the database file itself. The right
    ## choice when the file is copied or synced (Steam Cloud).
    DELETE,
    ## Faster writes; changes sit in a "-wal" file beside the database until a checkpoint.
    ## [method Db.close] checkpoints, but a crash leaves the "-wal" file behind.
    WAL,
}

var journal: Journal = Journal.DELETE
## Milliseconds to wait for a lock held by another connection before failing.
var busy_timeout_ms: int = 5000
## Runs PRAGMA quick_check on open, and treats a failure like a file that does not open.
var check_integrity: bool = true
## Where [method Db.backup] writes. Empty: no backups, and no restore on corruption.
var backup_path: String = ""
## When the database is corrupt and [member backup_path] holds a good copy, moves the bad
## file aside (".corrupt" suffix) and opens the copy. See [method Db.recovered_from_backup].
var restore_from_backup: bool = true
## Writes a backup to [member backup_path] before running migrations.
var backup_before_migrations: bool = true
## Compares the models with the real tables after opening. See [method Db.schema_problems].
var check_schema: bool = OS.is_debug_build()
## Fails [method Db.open] when [member check_schema] finds a difference, instead of warning.
var strict_schema: bool = false
## Prints every statement with its values.
var log_queries: bool = false
## Prints errors with push_error. SQL errors are also printed by godot-sqlite itself.
var report_errors: bool = true
## Returns the current Unix time in seconds, for auto_created() and auto_updated() fields.
var clock: Callable = func() -> int:
    return int(Time.get_unix_time_from_system())
