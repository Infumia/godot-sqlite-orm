# GUT asserts take untyped arguments; Godot 4.7 flags every Variant passed to them.
@warning_ignore_start("unsafe_call_argument")
extends DbTestCase
## Opening, configuring and closing a database.


func test_memory_database_opens_new() -> void:
    var db: Db = open_memory()
    assert_open(db)
    assert_true(db.is_new())
    assert_eq(db.last_error(), "")
    assert_eq(db.schema_problems(), PackedStringArray())


func test_foreign_keys_are_on() -> void:
    var db: Db = open_memory()
    var rows: Array[Dictionary] = db.raw("PRAGMA foreign_keys")
    assert_eq(DbSql.to_int(rows[0]["foreign_keys"]), 1)


func test_tables_and_indexes_are_created() -> void:
    var db: Db = open_memory()
    var tables: Array = []
    for row: Dictionary in db.raw("SELECT name FROM sqlite_master WHERE type = 'table'"):
        tables.append(row["name"])
    for table_name: String in ["_migrations", "items", "characters", "heroes", "gear", "quests"]:
        assert_has(tables, table_name)
    var indexes: Array = []
    for row: Dictionary in db.raw("SELECT name FROM sqlite_master WHERE type = 'index'"):
        indexes.append(row["name"])
    assert_has(indexes, "people_name_surname_unique")
    assert_has(indexes, "gear_hero_id_index")


func test_tables_are_strict() -> void:
    var db: Db = open_memory()
    var rows: Array[Dictionary] = db.raw("PRAGMA table_list('items')")
    assert_eq(DbSql.to_int(rows[0]["strict"]), 1)


func test_file_database_is_created_in_missing_folders() -> void:
    var db: Db = open_file("deep/er/game.db")
    assert_open(db)
    assert_true(FileAccess.file_exists(scratch_path("deep/er/game.db")))
    assert_eq(db.path(), scratch_path("deep/er/game.db"))


func test_path_without_extension_is_used_as_is() -> void:
    var db: Db = open_file("savegame")
    assert_open(db)
    assert_true(FileAccess.file_exists(scratch_path("savegame")))
    assert_false(FileAccess.file_exists(scratch_path("savegame.db")))


func test_reopen_is_not_new_and_keeps_rows() -> void:
    var db: Db = open_file("game.db")
    assert_ok(db.insert(make_item("Sword")), db)
    db.close()
    var again: Db = open_file("game.db")
    assert_open(again)
    assert_false(again.is_new())
    assert_eq(again.select(FxItem).count(), 1)


func test_journal_delete_is_the_default() -> void:
    var db: Db = open_file("game.db")
    var rows: Array[Dictionary] = db.raw("PRAGMA journal_mode")
    assert_eq(str(rows[0]["journal_mode"]), "delete")
    var sync: Array[Dictionary] = db.raw("PRAGMA synchronous")
    assert_eq(DbSql.to_int(sync[0]["synchronous"]), 2, "FULL")


func test_journal_wal_and_close_checkpoints() -> void:
    var options: DbOptions = make_options()
    options.journal = DbOptions.Journal.WAL
    var db: Db = open_file("wal.db", [], [], options)
    var rows: Array[Dictionary] = db.raw("PRAGMA journal_mode")
    assert_eq(str(rows[0]["journal_mode"]), "wal")
    assert_ok(db.insert(make_item("Axe")), db)
    assert_ok(db.checkpoint(), db)
    db.close()
    var wal: String = scratch_path("wal.db-wal")
    assert_true(
        not FileAccess.file_exists(wal) or FileAccess.get_file_as_bytes(wal).is_empty(),
        "the -wal file is empty after close",
    )


func test_busy_timeout_is_set() -> void:
    var options: DbOptions = make_options()
    options.busy_timeout_ms = 1234
    var db: Db = open_memory([], [], options)
    var rows: Array[Dictionary] = db.raw("PRAGMA busy_timeout")
    assert_eq(DbSql.to_int(rows[0].values()[0]), 1234)


func test_database_with_foreign_tables_is_refused() -> void:
    var path: String = scratch_path("foreign.db")
    var raw: SQLite = SQLite.new()
    raw.verbosity_level = SQLite.QUIET
    raw.default_extension = ""
    raw.path = path
    raw.open_db()
    raw.query("CREATE TABLE stranger (id INTEGER PRIMARY KEY)")
    raw.close_db()
    var db: Db = Db.open(path, all_models(), [], make_options())
    _opened.append(db)
    assert_false(db.is_open())
    assert_eq(db.last_error_kind(), Db.ErrorKind.SCHEMA)
    assert_string_contains(db.last_error(), "not made by sqlite_orm")


func test_calls_on_a_closed_database_fail_cleanly() -> void:
    var db: Db = open_memory()
    db.close()
    assert_false(db.is_open())
    assert_failed(db.insert(make_item("Late")), db, Db.ErrorKind.USAGE, "not open")
    assert_eq(db.select(FxItem).all(), [])
    assert_eq(db.select(FxItem).count(), -1)
    assert_failed(
        db.transaction(
            func() -> bool:
                return true,
        ),
        db,
        Db.ErrorKind.USAGE,
    )
    db.close()


func test_close_rolls_back_an_open_transaction() -> void:
    var db: Db = open_file("game.db")
    var ok: bool = db.transaction(
        func() -> bool:
            db.insert(make_item("Ghost"))
            db.close()
            return true,
    )
    assert_failed(ok, db, Db.ErrorKind.USAGE, "closed inside a transaction")
    var again: Db = open_file("game.db")
    assert_eq(again.select(FxItem).count(), 0)


func test_clock_comes_from_options() -> void:
    var db: Db = open_memory()
    assert_eq(db.now(), clock_time())
    advance_clock(5)
    assert_eq(db.now(), clock_time())


func test_query_executed_signal_reports_each_statement() -> void:
    var db: Db = open_memory()
    var seen: Array[String] = []
    var listener: Callable = func(sql: String, _args: Array, ok: bool, usec: int) -> void:
        assert_true(ok)
        assert_true(usec >= 0)
        seen.append(sql)
    db.query_executed.connect(listener)
    db.insert(make_item("Bow"))
    db.query_executed.disconnect(listener)
    assert_eq(seen.size(), 1)
    assert_string_contains(seen[0], "INSERT INTO \"items\"")


func test_open_options_default_to_safe_values() -> void:
    var options: DbOptions = DbOptions.new()
    assert_eq(options.journal, DbOptions.Journal.DELETE)
    assert_true(options.check_integrity)
    assert_true(options.restore_from_backup)
    assert_true(options.backup_before_migrations)
    assert_false(options.strict_schema)
    assert_false(options.log_queries)
    assert_true(options.report_errors)
    var now: int = options.clock.call()
    assert_almost_eq(now, int(Time.get_unix_time_from_system()), 2)
