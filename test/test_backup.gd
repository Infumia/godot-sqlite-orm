# GUT asserts take untyped arguments; Godot 4.7 flags every Variant passed to them.
@warning_ignore_start("unsafe_call_argument")
extends DbTestCase
## Backups, integrity checks and recovery from a damaged file.


func test_backup_writes_a_valid_copy() -> void:
    var db: Db = _game_with_items(["Sword", "Bow"])
    assert_ok(db.backup(scratch_path("copy.db")), db)
    assert_false(FileAccess.file_exists(scratch_path("copy.db.tmp")))
    var copy: Db = Db.open(scratch_path("copy.db"), all_models(), [], make_options())
    _opened.append(copy)
    assert_open(copy)
    assert_eq(copy.select(FxItem).pluck("name"), ["Sword", "Bow"])


func test_backup_uses_the_backup_path_option() -> void:
    var db: Db = _game_with_items(["Axe"], _options_with_backup())
    assert_ok(db.backup(), db)
    assert_true(FileAccess.file_exists(scratch_path("backup/game.db")))


func test_backup_without_a_target_is_a_usage_error() -> void:
    var db: Db = _game_with_items([])
    assert_failed(db.backup(), db, Db.ErrorKind.USAGE, "backup_path")


func test_backup_replaces_the_previous_copy() -> void:
    var db: Db = _game_with_items(["First"], _options_with_backup())
    db.backup()
    db.insert(make_item("Second"))
    assert_ok(db.backup(), db)
    var copy: Db = Db.open(scratch_path("backup/game.db"), all_models(), [], make_options())
    _opened.append(copy)
    assert_eq(copy.select(FxItem).count(), 2)


func test_backup_of_a_memory_database() -> void:
    var db: Db = open_memory()
    db.insert(make_item("Volatile"))
    assert_ok(db.backup(scratch_path("from_memory.db")), db)
    var copy: Db = Db.open(scratch_path("from_memory.db"), all_models(), [], make_options())
    _opened.append(copy)
    assert_eq(copy.select(FxItem).count(), 1)


func test_backup_of_a_closed_database_fails() -> void:
    var db: Db = _game_with_items([])
    db.close()
    assert_failed(db.backup(scratch_path("x.db")), db, Db.ErrorKind.USAGE, "not open")


func test_integrity_checks_on_a_healthy_database() -> void:
    var db: Db = _game_with_items(["Fine"])
    assert_true(db.quick_check())
    assert_eq(db.integrity_check(), PackedStringArray())


func test_garbage_file_without_backup_fails_as_corrupt() -> void:
    var path: String = scratch_path("game.db")
    var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    file.store_buffer(_garbage(8192))
    file.close()
    var db: Db = open_file("game.db")
    expect_engine_errors()
    assert_false(db.is_open())
    assert_eq(db.last_error_kind(), Db.ErrorKind.CORRUPT)
    assert_eq(FileAccess.get_file_as_bytes(path), _garbage(8192), "the bad file is left alone")


func test_corrupt_file_is_restored_from_the_backup() -> void:
    var db: Db = _game_with_items(["Saved"], _options_with_backup())
    db.backup()
    db.insert(make_item("Lost after backup"))
    db.close()
    _overwrite(scratch_path("game.db"), 0, _garbage(100))
    var again: Db = open_file("game.db", [], [], _options_with_backup())
    expect_engine_errors()
    assert_open(again)
    assert_true(again.recovered_from_backup())
    assert_eq(again.select(FxItem).pluck("name"), ["Saved"])
    assert_true(
        FileAccess.file_exists(scratch_path("game.db.corrupt")),
        "the bad file is kept aside",
    )


func test_damaged_pages_fail_the_integrity_check_and_restore() -> void:
    var db: Db = _game_with_items([], _options_with_backup())
    var batch: Array = []
    for i: int in 300:
        batch.append(make_item("item %d with a long name to fill pages" % i))
    db.insert_many(batch)
    db.backup()
    db.close()
    var size: int = FileAccess.get_file_as_bytes(scratch_path("game.db")).size()
    _overwrite(scratch_path("game.db"), size / 2, _garbage(4096))
    var again: Db = open_file("game.db", [], [], _options_with_backup())
    expect_engine_errors()
    assert_open(again)
    assert_true(again.recovered_from_backup())
    assert_eq(again.select(FxItem).count(), 300)


func test_no_restore_when_turned_off() -> void:
    var options: DbOptions = _options_with_backup()
    options.restore_from_backup = false
    var db: Db = _game_with_items(["Saved"], options)
    db.backup()
    db.close()
    _overwrite(scratch_path("game.db"), 0, _garbage(100))
    var again: Db = open_file("game.db", [], [], options)
    expect_engine_errors()
    assert_false(again.is_open())
    assert_eq(again.last_error_kind(), Db.ErrorKind.CORRUPT)


func test_corrupt_backup_is_not_used() -> void:
    var db: Db = _game_with_items(["Saved"], _options_with_backup())
    db.backup()
    db.close()
    _overwrite(scratch_path("game.db"), 0, _garbage(100))
    _overwrite(scratch_path("backup/game.db"), 0, _garbage(100))
    var again: Db = open_file("game.db", [], [], _options_with_backup())
    expect_engine_errors()
    assert_false(again.is_open())
    assert_eq(again.last_error_kind(), Db.ErrorKind.CORRUPT)
    assert_false(FileAccess.file_exists(scratch_path("game.db.corrupt")), "nothing was moved")


func test_missing_backup_file_means_no_restore() -> void:
    var options: DbOptions = _options_with_backup()
    _game_with_items(["Saved"], options).close()
    _overwrite(scratch_path("game.db"), 0, _garbage(100))
    var again: Db = open_file("game.db", [], [], options)
    expect_engine_errors()
    assert_false(again.is_open())


func test_empty_file_opens_as_a_new_database() -> void:
    var file: FileAccess = FileAccess.open(scratch_path("game.db"), FileAccess.WRITE)
    file.close()
    var db: Db = open_file("game.db")
    assert_open(db)
    assert_true(db.is_new())


func test_restore_does_not_keep_old_side_files() -> void:
    var options: DbOptions = _options_with_backup()
    var db: Db = _game_with_items(["Saved"], options)
    db.backup()
    db.close()
    var wal: FileAccess = FileAccess.open(scratch_path("game.db-wal"), FileAccess.WRITE)
    wal.store_buffer(_garbage(64))
    wal.close()
    _overwrite(scratch_path("game.db"), 0, _garbage(100))
    var again: Db = open_file("game.db", [], [], options)
    expect_engine_errors()
    assert_open(again)
    var wal_path: String = scratch_path("game.db-wal")
    var stale: bool = (
        FileAccess.file_exists(wal_path) and FileAccess.get_file_as_bytes(wal_path) == _garbage(64)
    )
    assert_false(stale, "the old -wal file does not sit beside the restored database")


func test_integrity_check_can_be_skipped() -> void:
    var options: DbOptions = make_options()
    options.check_integrity = false
    var count: Array[int] = [0]
    var db: Db = Db.new()
    var counter: Callable = func(sql: String, _args: Array, _ok: bool, _usec: int) -> void:
        if sql.contains("quick_check"):
            count[0] += 1
    db.query_executed.connect(counter)
    db._open(scratch_path("game.db"), all_models(), [], options)
    _opened.append(db)
    assert_open(db)
    assert_eq(count[0], 0)


func _options_with_backup() -> DbOptions:
    var options: DbOptions = make_options()
    options.backup_path = scratch_path("backup/game.db")
    return options


func _game_with_items(names: Array[String], options: DbOptions = null) -> Db:
    var db: Db = open_file("game.db", [], [], options)
    assert_open(db)
    for item_name: String in names:
        assert_ok(db.insert(make_item(item_name)), db)
    return db


func _overwrite(path: String, offset: int, bytes: PackedByteArray) -> void:
    var file: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE)
    file.seek(offset)
    file.store_buffer(bytes)
    file.close()


func _garbage(size: int) -> PackedByteArray:
    var bytes: PackedByteArray = PackedByteArray()
    bytes.resize(size)
    for i: int in size:
        bytes[i] = (i * 37 + 11) % 256
    return bytes
