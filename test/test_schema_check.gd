# GUT asserts take untyped arguments; Godot 4.7 flags every Variant passed to them.
@warning_ignore_start("unsafe_call_argument")
extends DbTestCase
## Comparing models with the real tables after opening.


func test_matching_schema_has_no_problems() -> void:
    open_file("game.db").close()
    var db: Db = open_file("game.db")
    assert_open(db)
    assert_eq(db.schema_problems(), PackedStringArray())


func test_missing_columns_are_reported() -> void:
    open_file("game.db", [MgPlayerV1]).close()
    var db: Db = open_file("game.db", [MgPlayerV2], [], _lenient())
    assert_open(db)
    var text: String = _problems_text(db)
    assert_string_contains(text, "column 'xp' is missing")
    assert_string_contains(text, "column 'title' is missing")


func test_extra_columns_are_reported() -> void:
    open_file("game.db", [MgPlayerV2]).close()
    var db: Db = open_file("game.db", [MgPlayerV1], [], _lenient())
    assert_string_contains(_problems_text(db), "column 'xp' is not in the model")


func test_strict_schema_refuses_to_open() -> void:
    open_file("game.db", [MgPlayerV1]).close()
    var db: Db = open_file("game.db", [MgPlayerV2])
    assert_false(db.is_open())
    assert_eq(db.last_error_kind(), Db.ErrorKind.SCHEMA)
    assert_string_contains(db.last_error(), "do not match the database")


func test_check_can_be_turned_off() -> void:
    open_file("game.db", [MgPlayerV1]).close()
    var db: Db = open_file("game.db", [MgPlayerV2], [], _unchecked())
    assert_open(db)
    assert_eq(db.schema_problems(), PackedStringArray())


func test_missing_table_is_reported() -> void:
    open_file("game.db", [FxGuild]).close()
    var db: Db = open_file("game.db", [FxGuild, FxMember], [], _lenient())
    assert_string_contains(
        _problems_text(db),
        "FxMember (table 'members'): the table does not exist",
    )


func test_type_and_null_differences_are_reported() -> void:
    open_file("game.db", [MgPlayerV2]).close()
    var raw: Db = open_file("game.db", [MgPlayerV2], [], _unchecked())
    raw.execute("DROP TABLE players")
    raw.execute(
        (
            "CREATE TABLE players (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, "
            + "name TEXT, xp REAL NOT NULL DEFAULT 0, " + "title TEXT NOT NULL DEFAULT '') STRICT"
        )
    )
    raw.close()
    var db: Db = open_file("game.db", [MgPlayerV2], [], _lenient())
    var text: String = _problems_text(db)
    assert_string_contains(text, "column 'xp' is REAL, the model says INTEGER")
    assert_string_contains(text, "column 'name' is nullable, the model says NOT NULL")
    assert_string_contains(text, "column 'title' is NOT NULL, the model says nullable")


func test_primary_key_differences_are_reported() -> void:
    open_file("game.db", [MgPlayerV1]).close()
    var raw: Db = open_file("game.db", [MgPlayerV1], [], _unchecked())
    raw.execute("DROP TABLE players")
    raw.execute(
        "CREATE TABLE players (id INTEGER NOT NULL, name TEXT NOT NULL, PRIMARY KEY (name)) STRICT"
    )
    raw.close()
    var db: Db = open_file("game.db", [MgPlayerV1], [], _lenient())
    var text: String = _problems_text(db)
    assert_string_contains(text, "column 'id' has a different primary key role")
    assert_string_contains(text, "column 'name' has a different primary key role")


func test_foreign_key_differences_are_reported() -> void:
    open_file("game.db", [FxGuild, FxMember]).close()
    var raw: Db = open_file("game.db", [FxGuild, FxMember], [], _unchecked())
    raw.execute("DROP TABLE members")
    raw.execute(
        (
            "CREATE TABLE members (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, "
            + "guild_id INTEGER NOT NULL DEFAULT 0 REFERENCES guilds (id) ON DELETE CASCADE) STRICT"
        )
    )
    raw.execute("CREATE INDEX members_guild_id_index ON members (guild_id)")
    raw.close()
    var db: Db = open_file("game.db", [FxGuild, FxMember], [], _lenient())
    assert_string_contains(
        _problems_text(db),
        "column 'guild_id' is ON DELETE CASCADE, the model says RESTRICT",
    )


func test_missing_and_extra_foreign_keys_are_reported() -> void:
    open_file("game.db", [FxGuild, FxMember]).close()
    var raw: Db = open_file("game.db", [FxGuild, FxMember], [], _unchecked())
    raw.execute("DROP TABLE members")
    raw.execute(
        (
            "CREATE TABLE members (id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL "
            + "REFERENCES guilds (id), " + "guild_id INTEGER NOT NULL DEFAULT 0) STRICT"
        )
    )
    raw.execute("CREATE INDEX members_guild_id_index ON members (guild_id)")
    raw.close()
    var db: Db = open_file("game.db", [FxGuild, FxMember], [], _lenient())
    var text: String = _problems_text(db)
    assert_string_contains(text, "column 'guild_id' is not a foreign key")
    assert_string_contains(text, "column 'id' is a foreign key, the model says not")


func test_missing_and_extra_indexes_are_reported() -> void:
    open_file("game.db").close()
    var raw: Db = open_file("game.db", [], [], _unchecked())
    raw.execute("DROP INDEX people_name_surname_unique")
    raw.execute("CREATE INDEX people_extra ON people (government_id)")
    raw.close()
    var db: Db = open_file("game.db", [], [], _lenient())
    var text: String = _problems_text(db)
    assert_string_contains(text, "index 'people_name_surname_unique' is missing")
    assert_string_contains(text, "index 'people_extra' is not in the model")


func test_index_with_other_columns_or_flag_is_reported() -> void:
    open_file("game.db").close()
    var raw: Db = open_file("game.db", [], [], _unchecked())
    raw.execute("DROP INDEX people_surname_name_index")
    raw.execute("CREATE INDEX people_surname_name_index ON people (name, surname)")
    raw.execute("DROP INDEX people_government_id_unique")
    raw.execute("CREATE INDEX people_government_id_unique ON people (government_id)")
    raw.close()
    var db: Db = open_file("game.db", [], [], _lenient())
    var text: String = _problems_text(db)
    assert_string_contains(text, "index 'people_surname_name_index' covers")
    assert_string_contains(text, "index 'people_government_id_unique' has a different unique flag")


func test_schema_problems_are_empty_after_a_problem_free_reopen() -> void:
    open_file("game.db", [MgPlayerV1]).close()
    var lenient: Db = open_file("game.db", [MgPlayerV2], [], _lenient())
    assert_gt(lenient.schema_problems().size(), 0)
    lenient.close()
    var db: Db = open_file("game.db", [MgPlayerV1])
    assert_eq(db.schema_problems(), PackedStringArray())


func _lenient() -> DbOptions:
    var options: DbOptions = make_options()
    options.strict_schema = false
    return options


func _unchecked() -> DbOptions:
    var options: DbOptions = make_options()
    options.check_schema = false
    return options


func _problems_text(db: Db) -> String:
    return "\n".join(db.schema_problems())
