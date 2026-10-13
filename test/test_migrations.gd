# GUT asserts take untyped arguments; Godot 4.7 flags every Variant passed to them.
@warning_ignore_start("unsafe_call_argument")
extends DbTestCase
## Versioned migrations: what runs, in which order, and what happens when one fails.

const DIR: String = "res://test/fixtures/migrations/"


func test_new_database_records_versions_without_running_them() -> void:
    var db: Db = open_file("game.db", [MgPlayerV1], [_m("m_run_counter.gd")])
    assert_open(db)
    assert_true(db.is_new())
    assert_eq(_applied(db), [1])
    assert_true(db.select(MgPlayerV1).count() == 0, "the players table still exists")


func test_pending_migration_runs_on_an_old_database() -> void:
    _v1_with_players()
    var db: Db = _v2()
    assert_open(db)
    assert_false(db.is_new())
    assert_eq(_applied(db), [1])
    var ada: MgPlayerV2 = db.select(MgPlayerV2).where("name", "=", "Ada").first()
    assert_eq(ada.xp, 30)
    assert_null(ada.title)
    assert_eq(db.schema_problems(), PackedStringArray())


func test_applied_migrations_do_not_run_again() -> void:
    _v1_with_players()
    _v2().close()
    var db: Db = _v2()
    var queries: int = 0
    assert_open(db)
    queries = db.raw("SELECT applied_at FROM _migrations").size()
    assert_eq(queries, 1)


func test_migrations_run_in_version_order_whatever_the_list_order() -> void:
    _v1_with_players()
    var db: Db = open_file(
        "game.db",
        [MgPlayerV3, MgPetV3],
        [_m("m2_rename_and_pets.gd"), _m("m1_add_xp.gd")],
    )
    assert_open(db)
    assert_eq(_applied(db), [1, 2])
    var ada: MgPlayerV3 = db.select(MgPlayerV3).where("nickname", "=", "Ada").first()
    assert_eq(ada.xp, 30)


func test_migrations_across_several_releases() -> void:
    _v1_with_players()
    _v2().close()
    var db: Db = _v3()
    assert_open(db)
    assert_eq(_applied(db), [1, 2])
    var bob: MgPlayerV3 = db.select(MgPlayerV3).where("nickname", "=", "Bob").first()
    var pet: MgPetV3 = MgPetV3.new()
    pet.owner_id = bob.id
    assert_ok(db.insert(pet), db)
    var owner: MgPlayerV3 = db.select(MgPlayerV3).with("pets").where("id", "=", bob.id).first()
    assert_eq(owner.pets.size(), 1)


func test_add_column_from_the_model() -> void:
    _v1_with_players()
    var db: Db = open_file("game.db", [MgPlayerV2], [_m("m1_add_xp_from_model.gd")])
    assert_open(db)
    assert_eq(db.schema_problems(), PackedStringArray())
    var bob: MgPlayerV2 = db.select(MgPlayerV2).where("name", "=", "Bob").first()
    assert_eq(bob.xp, 30)


func test_create_table_from_the_model() -> void:
    _v1_with_players()
    _v2().close()
    var db: Db = open_file(
        "game.db",
        [MgPlayerV3, MgPetV3],
        [_m("m1_add_xp.gd"), _m("m2_pets_from_model.gd")],
    )
    assert_open(db)
    assert_eq(db.schema_problems(), PackedStringArray())
    var pet: MgPetV3 = MgPetV3.new()
    pet.owner_id = 1
    assert_ok(db.insert(pet), db)


func test_model_step_needs_the_model_in_the_list() -> void:
    _v1_with_players()
    var db: Db = open_file("game.db", [MgPlayerV1], [_m("m1_add_xp_from_model.gd")])
    assert_false(db.is_open())
    assert_eq(db.last_error_kind(), Db.ErrorKind.MIGRATION)
    assert_string_contains(db.last_error(), "migration 1: MgPlayerV2 is not in the model list")


func test_applied_at_comes_from_the_clock() -> void:
    _v1_with_players()
    advance_clock(77)
    var db: Db = _v2()
    var rows: Array[Dictionary] = db.raw("SELECT applied_at FROM _migrations")
    assert_eq(DbSql.to_int(rows[0]["applied_at"]), 1_077)


func test_failing_migration_rolls_back_and_stops() -> void:
    _v1_with_players()
    _v3().close()
    var db: Db = open_file(
        "game.db",
        [MgPlayerV3, MgPetV3],
        [_m("m1_add_xp.gd"), _m("m2_rename_and_pets.gd"), _m("m3_fail.gd")],
    )
    assert_false(db.is_open())
    assert_eq(db.last_error_kind(), Db.ErrorKind.MIGRATION)
    assert_string_contains(db.last_error(), "migration 3: not today")
    var again: Db = _v3()
    assert_eq(_applied(again), [1, 2])
    var ada: MgPlayerV3 = again.select(MgPlayerV3).where("nickname", "=", "Ada").first()
    assert_eq(ada.xp, 30, "the UPDATE before fail() was rolled back")


func test_failing_sql_in_a_migration_is_reported_as_migration() -> void:
    _v1_with_players()
    _v3().close()
    var db: Db = open_file(
        "game.db",
        [MgPlayerV3, MgPetV3],
        [_m("m1_add_xp.gd"), _m("m2_rename_and_pets.gd"), _m("m3_bad_sql.gd")],
    )
    expect_engine_errors("no such table")
    assert_false(db.is_open())
    assert_eq(db.last_error_kind(), Db.ErrorKind.MIGRATION)
    assert_string_contains(db.last_error(), "migration 3: no such table: nowhere")


func test_migration_that_breaks_references_is_rolled_back() -> void:
    _v1_with_players()
    _v3().close()
    var db: Db = open_file(
        "game.db",
        [MgPlayerV3, MgPetV3],
        [_m("m1_add_xp.gd"), _m("m2_rename_and_pets.gd"), _m("m3_breaks_references.gd")],
    )
    assert_false(db.is_open())
    assert_string_contains(db.last_error(), "migration 3 leaves 1 broken references")
    var again: Db = _v3()
    assert_eq(again.select(MgPetV3).count(), 0)
    var fk: Array[Dictionary] = again.raw("PRAGMA foreign_keys")
    assert_eq(DbSql.to_int(fk[0]["foreign_keys"]), 1, "foreign keys are back on")


func test_foreign_keys_are_on_after_successful_migrations() -> void:
    _v1_with_players()
    var db: Db = _v2()
    var fk: Array[Dictionary] = db.raw("PRAGMA foreign_keys")
    assert_eq(DbSql.to_int(fk[0]["foreign_keys"]), 1)


func test_rebuild_table_keeps_rows_renames_and_changes_types() -> void:
    _v1_with_players()
    var v3: Db = _v3()
    var pet: MgPetV3 = MgPetV3.new()
    pet.owner_id = 1
    v3.insert(pet)
    v3.close()
    var db: Db = open_file(
        "game.db",
        [MgPlayerRebuilt, MgPetRebuilt],
        [_m("m1_add_xp.gd"), _m("m2_rename_and_pets.gd"), _m("m3_rebuild.gd")],
    )
    assert_open(db)
    assert_eq(db.schema_problems(), PackedStringArray())
    var ada: MgPlayerRebuilt = db.select(MgPlayerRebuilt).where("display", "=", "Ada").first()
    assert_eq(ada.xp, 30.0)
    assert_eq(typeof(ada.xp), TYPE_FLOAT)
    assert_eq(ada.level, 1, "a new column takes its default")
    assert_eq(db.select(MgPetRebuilt).count(), 1, "rows pointing at the rebuilt table survive")
    var indexes: Array[Dictionary] = db.raw("PRAGMA index_list('players')")
    assert_eq(indexes.size(), 1, "the unique index is created again")
    db.delete(ada)
    assert_eq(db.select(MgPetRebuilt).count(), 0, "the cascade still points at players")


func test_add_unique_fails_on_existing_duplicates() -> void:
    _v1_with_players(["Ada", "Ada"])
    _v3().close()
    var db: Db = open_file(
        "game.db",
        [MgPlayerUnique, MgPetUnique],
        [_m("m1_add_xp.gd"), _m("m2_rename_and_pets.gd"), _m("m3_unique.gd")],
    )
    expect_engine_errors("UNIQUE")
    assert_false(db.is_open())
    assert_eq(db.last_error_kind(), Db.ErrorKind.MIGRATION)
    assert_string_contains(db.last_error(), "UNIQUE constraint failed")


func test_add_unique_without_duplicates() -> void:
    _v1_with_players()
    _v3().close()
    var db: Db = open_file(
        "game.db",
        [MgPlayerUnique, MgPetUnique],
        [_m("m1_add_xp.gd"), _m("m2_rename_and_pets.gd"), _m("m3_unique.gd")],
    )
    assert_open(db)
    var clone: MgPlayerUnique = MgPlayerUnique.new()
    clone.nickname = "Ada"
    assert_failed(db.insert(clone), db, Db.ErrorKind.UNIQUE)
    expect_engine_errors("UNIQUE")


func test_drop_column_and_query_in_a_migration() -> void:
    _v1_with_players()
    _v3().close()
    var options: DbOptions = make_options()
    options.check_schema = false
    var db: Db = open_file(
        "game.db",
        [MgPlayerV3, MgPetV3],
        [_m("m1_add_xp.gd"), _m("m2_rename_and_pets.gd"), _m("m3_drop_title.gd")],
        options,
    )
    assert_open(db)
    var columns: Array = []
    for row: Dictionary in db.raw("PRAGMA table_info('players')"):
        columns.append(row["name"])
    assert_does_not_have(columns, "title")


func test_out_of_order_version_is_refused() -> void:
    _v1_with_players()
    var late: Db = open_file("game.db", [MgPlayerV2], [_m("m1_add_xp.gd"), _m("m5_late.gd")])
    assert_open(late)
    late.close()
    var db: Db = open_file(
        "game.db",
        [MgPlayerV2],
        [_m("m1_add_xp.gd"), _m("m4_noop.gd"), _m("m5_late.gd")],
    )
    assert_false(db.is_open())
    assert_eq(db.last_error_kind(), Db.ErrorKind.MIGRATION)
    assert_string_contains(db.last_error(), "migration 4 is not applied but 5 is")


func test_database_from_a_newer_build_is_refused() -> void:
    _v1_with_players()
    _v2().close()
    var db: Db = open_file("game.db", [MgPlayerV1], [])
    assert_false(db.is_open())
    assert_string_contains(db.last_error(), "made by a newer version")


func test_invalid_migration_lists() -> void:
    var cases: Dictionary = {
        "m_no_version.gd": "has no VERSION constant",
        "m_zero_version.gd": "VERSION must be 1 or more",
        "m_text_version.gd": "VERSION must be an int",
        "m_not_migration.gd": "does not extend DbMigration",
    }
    for file_name: String in cases:
        var db: Db = open_memory([MgPlayerV1], [_m(file_name)])
        assert_false(db.is_open(), file_name)
        assert_eq(db.last_error_kind(), Db.ErrorKind.MIGRATION, file_name)
        assert_string_contains(db.last_error(), cases[file_name])


func test_duplicate_versions_are_refused() -> void:
    var db: Db = open_memory([MgPlayerV1], [_m("m1_add_xp.gd"), _m("m1_duplicate.gd")])
    assert_false(db.is_open())
    assert_string_contains(db.last_error(), "both have VERSION 1")


func test_non_script_in_migration_list() -> void:
    var db: Db = open_memory([MgPlayerV1], ["m1"])
    assert_false(db.is_open())
    assert_string_contains(db.last_error(), "not a GDScript")


func test_backup_is_written_before_migrations() -> void:
    _v1_with_players()
    var options: DbOptions = make_options()
    options.backup_path = scratch_path("before.db")
    var db: Db = open_file("game.db", [MgPlayerV2], [_m("m1_add_xp.gd")], options)
    assert_open(db)
    assert_true(FileAccess.file_exists(scratch_path("before.db")))
    var backup: Db = Db.open(scratch_path("before.db"), [MgPlayerV1], [], make_options())
    _opened.append(backup)
    assert_open(backup)
    assert_eq(backup.select(MgPlayerV1).count(), 2)
    assert_eq(_applied(backup), [], "the copy is from before the migration")


func test_no_backup_when_nothing_is_pending() -> void:
    _v1_with_players()
    _v2().close()
    var options: DbOptions = make_options()
    options.backup_path = scratch_path("before.db")
    var db: Db = open_file("game.db", [MgPlayerV2], [_m("m1_add_xp.gd")], options)
    assert_open(db)
    assert_false(FileAccess.file_exists(scratch_path("before.db")))


func _m(file_name: String) -> GDScript:
    return load(DIR + file_name)


func _v1_with_players(names: Array[String] = ["Ada", "Bob"]) -> void:
    var db: Db = open_file("game.db", [MgPlayerV1])
    assert_open(db)
    for player_name: String in names:
        var player: MgPlayerV1 = MgPlayerV1.new()
        player.name = player_name
        assert_ok(db.insert(player), db)
    db.close()


func _v2() -> Db:
    return open_file("game.db", [MgPlayerV2], [_m("m1_add_xp.gd")])


func _v3() -> Db:
    return open_file(
        "game.db",
        [MgPlayerV3, MgPetV3],
        [_m("m1_add_xp.gd"), _m("m2_rename_and_pets.gd")],
    )


func _applied(db: Db) -> Array:
    var versions: Array = []
    for row: Dictionary in db.raw("SELECT version FROM _migrations ORDER BY version"):
        versions.append(DbSql.to_int(row["version"]))
    return versions
