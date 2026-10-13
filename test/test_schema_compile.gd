# GUT asserts take untyped arguments; Godot 4.7 flags every Variant passed to them.
@warning_ignore_start("unsafe_call_argument")
extends DbTestCase
## Compiling model scripts into tables: what valid models produce and what invalid ones report.

const INVALID: String = "res://test/fixtures/invalid/"


func test_all_fixture_models_compile() -> void:
    var registry: DbRegistry = _compile(all_models())
    assert_eq(registry.ordered.size(), all_models().size())


func test_columns_follow_var_types() -> void:
    var table: DbTable = _compile(all_models()).table_for_script(FxItem)
    var expected: Dictionary = {
        "id": ["INTEGER", DbColumn.Kind.INT],
        "name": ["TEXT", DbColumn.Kind.STRING],
        "damage": ["INTEGER", DbColumn.Kind.INT],
        "weight": ["REAL", DbColumn.Kind.FLOAT],
        "rarity": ["INTEGER", DbColumn.Kind.INT],
        "tradable": ["INTEGER", DbColumn.Kind.BOOL],
        "kind": ["TEXT", DbColumn.Kind.STRING_NAME],
        "icon": ["BLOB", DbColumn.Kind.BYTES],
        "tags": ["TEXT", DbColumn.Kind.JSON],
        "stats": ["TEXT", DbColumn.Kind.JSON],
        "grid_cell": ["TEXT", DbColumn.Kind.JSON],
        "description": ["TEXT", DbColumn.Kind.STRING],
    }
    for column_name: String in expected:
        var column: DbColumn = table.column(column_name)
        assert_not_null(column, column_name)
        if column != null:
            var pair: Array = expected[column_name]
            var sql_type: String = pair[0]
            var kind: DbColumn.Kind = pair[1]
            assert_eq(column.sql_type, sql_type, column_name)
            assert_eq(column.kind, kind, column_name)


func test_typed_container_element_types() -> void:
    var table: DbTable = _compile(all_models()).table_for_script(FxItem)
    assert_eq(table.column("tags").element_type, TYPE_STRING_NAME)
    assert_eq(table.column("rolls").element_type, TYPE_FLOAT)
    assert_eq(table.column("stats").key_type, TYPE_STRING)
    assert_eq(table.column("stats").dictionary_value_type, TYPE_INT)
    assert_eq(table.column("notes").element_type, TYPE_NIL)


func test_private_ignored_and_relation_vars_are_not_columns() -> void:
    var registry: DbRegistry = _compile(all_models())
    var item: DbTable = registry.table_for_script(FxItem)
    assert_false(item.has_column("_cache"))
    assert_false(item.has_column("transient"))
    assert_false(item.has_column("_db_persisted"))
    var character: DbTable = registry.table_for_script(FxCharacter)
    assert_false(character.has_column("weapon"))
    assert_true(character.has_column("weapon_id"))
    assert_false(character.has_column("saves"))


func test_typed_fields_are_not_null_and_variants_are_nullable() -> void:
    var registry: DbRegistry = _compile(all_models())
    var item: DbTable = registry.table_for_script(FxItem)
    assert_false(item.column("name").nullable)
    assert_true(item.column("description").nullable)
    var character: DbTable = registry.table_for_script(FxCharacter)
    assert_true(character.column("weapon_id").nullable)


func test_typed_fields_default_to_their_initial_value() -> void:
    var item: DbTable = _compile(all_models()).table_for_script(FxItem)
    assert_true(item.column("weight").has_default)
    var weight: float = item.column("weight").default_value
    var kind: StringName = item.column("kind").default_value
    assert_eq(weight, 1.5)
    assert_eq(kind, &"weapon")
    assert_false(item.column("id").has_default, "keys have no default")
    assert_false(item.column("description").has_default, "nullable fields default to NULL")


func test_foreign_key_takes_type_from_target() -> void:
    var registry: DbRegistry = _compile(all_models())
    var gear: DbTable = registry.table_for_script(FxGear)
    var hero_id: DbColumn = gear.column("hero_id")
    assert_eq(hero_id.sql_type, "TEXT")
    assert_eq(hero_id.reference_table, "heroes")
    assert_eq(hero_id.reference_column, "id")
    var character: DbTable = registry.table_for_script(FxCharacter)
    assert_eq(character.column("weapon_id").sql_type, "INTEGER")


func test_create_sql_holds_constraints() -> void:
    var registry: DbRegistry = _compile(all_models())
    var sql: String = registry.table_for_script(FxCharacter).create_sql()
    assert_string_contains(sql, "\"id\" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL")
    assert_string_contains(sql, "\"level\" INTEGER NOT NULL DEFAULT 1 CHECK (\"level\" >= 1)")
    assert_string_contains(
        sql,
        "\"weapon_id\" INTEGER REFERENCES \"items\" (\"id\") ON DELETE SET NULL",
    )
    assert_true(sql.ends_with("STRICT"))
    var quests: String = registry.table_for_script(FxQuest).create_sql()
    assert_string_contains(quests, "PRIMARY KEY (\"hero_id\", \"quest_id\")")
    assert_string_contains(quests, "ON DELETE CASCADE")
    var item: String = registry.table_for_script(FxItem).create_sql()
    assert_string_contains(
        item,
        "\"tradable\" INTEGER NOT NULL DEFAULT 1 CHECK (\"tradable\" IN (0, 1))",
    )


func test_indexes_are_named_after_table_and_fields() -> void:
    var registry: DbRegistry = _compile(all_models())
    var person: DbTable = registry.table_for_script(FxPerson)
    var names: Array[String] = []
    for index: DbTable.IndexDef in person.indexes:
        names.append(index.name)
    assert_has(names, "people_government_id_unique")
    assert_has(names, "people_name_surname_unique")
    assert_has(names, "people_surname_name_index")


func test_foreign_keys_get_an_index_unless_one_covers_them() -> void:
    var registry: DbRegistry = _compile(all_models())
    var gear: DbTable = registry.table_for_script(FxGear)
    assert_not_null(gear.find_index(["hero_id"], false))
    var equipped: DbTable = registry.table_for_script(FxEquipped)
    assert_null(equipped.find_index(["hero_id"], false), "the primary key starts with hero_id")
    assert_not_null(equipped.find_index(["gear_uid"], false))
    var banner: DbTable = registry.table_for_script(FxBanner)
    assert_null(banner.find_index(["hero_id"], false), "the unique index covers it")
    assert_not_null(banner.find_index(["hero_id"], true))


func test_relations_are_compiled() -> void:
    var registry: DbRegistry = _compile(all_models())
    var hero: DbTable = registry.table_for_script(FxHero)
    var gear: DbRelation = hero.relations["gear"]
    assert_eq(gear.kind, DbRelation.Kind.HAS_MANY)
    assert_eq(gear.foreign_key, "hero_id")
    assert_eq(gear.target_key, "id")
    assert_eq(gear.position_field, "slot_index")
    assert_eq(hero.relations["banner"].kind, DbRelation.Kind.HAS_ONE)
    var weapon: DbRelation = registry.table_for_script(FxCharacter).relations["weapon"]
    assert_eq(weapon.kind, DbRelation.Kind.BELONGS_TO)
    assert_eq(weapon.foreign_key, "weapon_id")


func test_auto_key_and_composite_key() -> void:
    var registry: DbRegistry = _compile(all_models())
    assert_eq(registry.table_for_script(FxItem).auto_key.name, "id")
    assert_null(registry.table_for_script(FxHero).auto_key)
    assert_eq(
        registry.table_for_script(FxQuest).primary_key,
        ["hero_id", "quest_id"] as Array[String],
    )


func test_error_no_table() -> void:
    assert_string_contains(_errors_of([_invalid("inv_no_table.gd")]), "does not call s.table()")


func test_error_no_key() -> void:
    assert_string_contains(_errors_of([_invalid("inv_no_key.gd")]), "has no primary key")


func test_error_unknown_field() -> void:
    assert_string_contains(
        _errors_of([_invalid("inv_unknown_field.gd")]),
        "s.field(\"missing\") has no matching var",
    )


func test_error_untyped_variant() -> void:
    assert_string_contains(_errors_of([_invalid("inv_untyped_variant.gd")]), "'data' is a Variant")


func test_error_object_field() -> void:
    assert_string_contains(_errors_of([_invalid("inv_object_field.gd")]), "cannot be stored")


func test_error_relation_without_var() -> void:
    assert_string_contains(
        _errors_of([FxItem, _invalid("inv_relation_missing_var.gd")]),
        "relation 'owner' has no matching var",
    )


func test_error_relation_var_of_wrong_type() -> void:
    assert_string_contains(
        _errors_of([FxItem, FxCharacter, _invalid("inv_relation_wrong_type.gd")]),
        "must be typed FxItem",
    )


func test_error_reference_to_model_outside_the_list() -> void:
    assert_string_contains(
        _errors_of([_invalid("inv_reference_outside.gd")]),
        "not in the model list",
    )


func test_error_reference_to_field_that_is_not_unique() -> void:
    assert_string_contains(
        _errors_of([FxItem, _invalid("inv_reference_not_unique.gd")]),
        "neither the primary key nor unique",
    )


func test_error_set_null_on_typed_field() -> void:
    assert_string_contains(
        _errors_of([FxItem, _invalid("inv_set_null_typed.gd")]),
        "on_delete_set_null()",
    )


func test_error_auto_increment_on_string() -> void:
    assert_string_contains(
        _errors_of([_invalid("inv_auto_increment_string.gd")]),
        "auto_increment() needs an int",
    )


func test_error_uuid_on_int() -> void:
    assert_string_contains(
        _errors_of([_invalid("inv_uuid_int.gd")]),
        "default_uuid() needs a String",
    )


func test_error_two_kinds_of_primary_key() -> void:
    assert_string_contains(
        _errors_of([_invalid("inv_both_keys.gd")]),
        "uses both s.primary_key() and .primary_key()",
    )


func test_error_type_mismatch() -> void:
    assert_string_contains(
        _errors_of([_invalid("inv_type_mismatch.gd")]),
        "'n' is int but .type() says String",
    )


func test_error_array_of_objects() -> void:
    assert_string_contains(_errors_of([_invalid("inv_node_array.gd")]), "holds Node elements")


func test_error_ignore_unknown_var() -> void:
    assert_string_contains(
        _errors_of([_invalid("inv_ignore_unknown.gd")]),
        "s.ignore(\"nope\") has no matching var",
    )


func test_error_has_many_key_that_does_not_point_back() -> void:
    assert_string_contains(
        _errors_of([FxItem, _invalid("inv_has_many_bad_key.gd")]),
        "needs FxItem.damage to reference",
    )


func test_error_duplicate_table_name() -> void:
    assert_string_contains(
        _errors_of([FxItem, _invalid("inv_duplicate_table.gd")]),
        "both use table 'items'",
    )


func test_error_not_a_model() -> void:
    assert_string_contains(_errors_of([_invalid("inv_not_model.gd")]), "does not extend DbModel")


func test_error_field_on_private_var() -> void:
    assert_string_contains(
        _errors_of([_invalid("inv_private_field.gd")]),
        "'_secret' is not a column",
    )


func test_error_unstorable_default() -> void:
    assert_string_contains(
        _errors_of([_invalid("inv_bad_default.gd")]),
        "default of 'ratio' cannot be stored",
    )


func test_error_converter_with_bad_sql_type() -> void:
    assert_string_contains(_errors_of([_invalid("inv_bad_converter.gd")]), "sql_type 'JSON'")


func test_error_position_field_not_int() -> void:
    assert_string_contains(
        _errors_of([_invalid("inv_position_parent.gd"), _invalid("inv_position_child.gd")]),
        "position field must be an int",
    )


func test_error_reference_to_composite_key() -> void:
    assert_string_contains(
        _errors_of(_with_game(_invalid("inv_composite_reference.gd"))),
        "primary key has several fields",
    )


func test_error_on_delete_without_reference() -> void:
    assert_string_contains(
        _errors_of([_invalid("inv_on_delete_alone.gd")]),
        "sets on_delete but references nothing",
    )


func test_error_nullable_primary_key() -> void:
    assert_string_contains(_errors_of([_invalid("inv_nullable_key.gd")]), "cannot be nullable")


func test_error_index_on_unknown_field() -> void:
    assert_string_contains(
        _errors_of([_invalid("inv_unknown_index.gd")]),
        "index field 'nope' is not a column",
    )


func test_error_relation_named_like_a_column() -> void:
    assert_string_contains(
        _errors_of([FxItem, _invalid("inv_relation_on_column.gd")]),
        "var 'damage' must be typed FxItem",
    )


func test_error_auto_created_on_string() -> void:
    assert_string_contains(
        _errors_of([_invalid("inv_auto_created_string.gd")]),
        "auto timestamps need an int",
    )


func test_error_model_listed_twice() -> void:
    assert_string_contains(_errors_of([FxItem, FxItem]), "in the model list twice")


func test_error_list_holds_non_script() -> void:
    assert_string_contains(_errors_of([FxItem, "items"]), "not a GDScript")


func test_open_with_invalid_models_fails_without_creating_a_file() -> void:
    var path: String = scratch_path("never.db")
    var db: Db = Db.open(path, [_invalid("inv_no_key.gd")], [], make_options())
    assert_false(db.is_open())
    assert_eq(db.last_error_kind(), Db.ErrorKind.SCHEMA)
    assert_string_contains(db.last_error(), "has no primary key")
    assert_false(FileAccess.file_exists(path))


func _compile(models: Array) -> DbRegistry:
    var registry: DbRegistry = DbRegistry.new()
    var errors: PackedStringArray = registry.compile(models)
    assert_eq(errors, PackedStringArray(), "compile errors")
    return registry


func _errors_of(models: Array) -> String:
    var registry: DbRegistry = DbRegistry.new()
    return "\n".join(registry.compile(models))


func _invalid(file_name: String) -> GDScript:
    return load(INVALID + file_name)


func _with_game(extra: GDScript) -> Array:
    var models: Array = [FxHero, FxGear, FxAffix, FxQuest, FxEquipped, FxBanner]
    models.append(extra)
    return models
