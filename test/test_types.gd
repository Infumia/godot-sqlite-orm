# GUT asserts take untyped arguments; Godot 4.7 flags every Variant passed to them.
@warning_ignore_start("unsafe_call_argument")
extends DbTestCase
## Every built-in field type survives a round trip, and bad stored data is reported.


func test_scalars_round_trip() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Scalars", 7)
    item.weight = 0.125
    item.rarity = FxItem.Rarity.LEGENDARY
    item.tradable = false
    item.kind = &"shield"
    var found: FxItem = _round_trip(db, item)
    assert_eq(found.damage, 7)
    assert_eq(found.weight, 0.125)
    assert_eq(found.rarity, FxItem.Rarity.LEGENDARY)
    assert_false(found.tradable)
    assert_eq(found.kind, &"shield")
    assert_eq(typeof(found.kind), TYPE_STRING_NAME)


func test_extreme_numbers_round_trip() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Big", 9_223_372_036_854_775_807)
    item.weight = 1.0e300
    var found: FxItem = _round_trip(db, item)
    assert_eq(found.damage, 9_223_372_036_854_775_807)
    assert_eq(found.weight, 1.0e300)
    var tiny: FxItem = make_item("Tiny")
    tiny.weight = -0.000_001
    assert_eq(_round_trip(db, tiny).weight, -0.000_001)


func test_strings_round_trip_unicode_quotes_and_empty() -> void:
    var db: Db = open_memory()
    for text: String in [
        "",
        "it's \"quoted\"",
        "Türkçe ğüşiöç",
        "日本語",
        "emoji 🗡️",
        "line\nbreak\ttab",
        "'; DROP TABLE items; --",
    ]:
        var item: FxItem = make_item(text)
        var found: FxItem = _round_trip(db, item)
        assert_eq(found.name, text)
    assert_eq(db.select(FxItem).count(), 7, "the injection string was stored, not run")


func test_bytes_round_trip_including_empty() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Bytes")
    item.icon = PackedByteArray([0, 1, 2, 255, 0])
    assert_eq(_round_trip(db, item).icon, PackedByteArray([0, 1, 2, 255, 0]))
    var empty: FxItem = make_item("Empty")
    var found: FxItem = _round_trip(db, empty)
    assert_eq(found.icon, PackedByteArray())
    empty.icon = PackedByteArray([9])
    assert_ok(db.update(empty), db)
    empty.icon = PackedByteArray()
    assert_ok(db.update(empty), db)
    assert_eq((db.find(FxItem, empty.id) as FxItem).icon, PackedByteArray())


func test_typed_arrays_round_trip_with_element_types() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Arrays")
    item.tags = [&"fire", &"ice"]
    item.rolls = [1.0, 2.5, -3.0]
    var found: FxItem = _round_trip(db, item)
    assert_eq(found.tags, [&"fire", &"ice"] as Array[StringName])
    assert_eq(found.tags.get_typed_builtin(), TYPE_STRING_NAME)
    assert_eq(typeof(found.tags[0]), TYPE_STRING_NAME)
    assert_eq(found.rolls, [1.0, 2.5, -3.0] as Array[float])
    assert_eq(typeof(found.rolls[0]), TYPE_FLOAT)


func test_typed_dictionary_round_trip() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Dict")
    item.stats = { "str": 5, "dex": -1 }
    var found: FxItem = _round_trip(db, item)
    assert_eq(found.stats, { "str": 5, "dex": -1 })
    assert_true(found.stats.is_typed())
    assert_eq(typeof(found.stats["str"]), TYPE_INT)


func test_untyped_containers_keep_mixed_values() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Mixed")
    item.notes = [1, 2.5, "three", &"four", Vector2i(5, 6), [7], { "eight": 8 }, null, true]
    item.extra = { "a": 1, 2: "b", &"c": Color.RED }
    var found: FxItem = _round_trip(db, item)
    assert_eq(found.notes, item.notes)
    assert_eq(typeof(found.notes[0]), TYPE_INT, "ints stay ints through JSON")
    assert_eq(typeof(found.notes[3]), TYPE_STRING_NAME)
    assert_eq(typeof(found.notes[4]), TYPE_VECTOR2I)
    assert_eq(found.extra, item.extra)


func test_vector_round_trip() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Vector")
    item.grid_cell = Vector2i(-3, 40)
    assert_eq(_round_trip(db, item).grid_cell, Vector2i(-3, 40))


func test_nullable_field_round_trip() -> void:
    var db: Db = open_memory()
    var empty: FxItem = make_item("NoDescription")
    var missing: Variant = _round_trip(db, empty).description
    assert_null(missing)
    var full: FxItem = make_item("Described")
    full.description = "sharp"
    var present: Variant = _round_trip(db, full).description
    assert_eq(present, "sharp")


func test_nullable_typed_field_rejects_other_types() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("WrongType")
    item.description = 42
    assert_failed(
        db.insert(item),
        db,
        Db.ErrorKind.CONVERSION,
        "'description' expects String, got int",
    )


func test_untyped_array_holding_an_object_is_rejected() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Obj")
    item.notes = [RefCounted.new()]
    assert_failed(db.insert(item), db, Db.ErrorKind.CONVERSION, "holds an Object")
    item.notes = []
    item.extra = { "deep": [{ "x": RefCounted.new() }] }
    assert_failed(db.insert(item), db, Db.ErrorKind.CONVERSION, "holds an Object")


func test_strict_table_rejects_wrong_raw_types() -> void:
    var db: Db = open_memory()
    var ok: bool = db.execute(
        "INSERT INTO items (name, damage) VALUES (?, ?)",
        ["raw", "not a number"],
    )
    assert_failed(ok, db, Db.ErrorKind.CONVERSION, "cannot store TEXT value in INTEGER column")
    expect_engine_errors("cannot store")


func test_bool_column_rejects_other_numbers() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Flag")
    db.insert(item)
    var ok: bool = db.execute("UPDATE items SET tradable = 2 WHERE id = ?", [item.id])
    assert_failed(ok, db, Db.ErrorKind.CHECK)
    expect_engine_errors("CHECK")


func test_invalid_json_in_the_database_is_a_conversion_error() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Broken")
    db.insert(item)
    db.execute("UPDATE items SET tags = '[not json' WHERE id = ?", [item.id])
    assert_null(db.find(FxItem, item.id))
    assert_eq(db.last_error_kind(), Db.ErrorKind.CONVERSION)
    assert_string_contains(db.last_error(), "invalid JSON")


func test_json_of_wrong_shape_is_a_conversion_error() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Shape")
    db.insert(item)
    db.execute("UPDATE items SET tags = '{\"a\": 1}' WHERE id = ?", [item.id])
    assert_null(db.find(FxItem, item.id))
    assert_string_contains(db.last_error(), "not Array")
    expect_engine_errors()
    db.execute("UPDATE items SET tags = '[\"i:1\"]' WHERE id = ?", [item.id])
    assert_null(db.find(FxItem, item.id))
    assert_string_contains(db.last_error(), "holds a int where StringName is expected")


func test_json_is_stored_in_godot_native_form() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Native form")
    item.tags = [&"a"]
    db.insert(item)
    var rows: Array[Dictionary] = db.raw("SELECT tags FROM items")
    assert_string_contains(str(rows[0]["tags"]), "\"sn:a\"")


func test_plain_json_strings_are_rejected() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Plain")
    db.insert(item)
    db.execute("UPDATE items SET tags = '[\"a\"]' WHERE id = ?", [item.id])
    assert_null(db.find(FxItem, item.id))
    assert_eq(db.last_error_kind(), Db.ErrorKind.CONVERSION)
    expect_engine_errors()


func test_json_with_unknown_native_type_is_rejected() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Native")
    db.insert(item)
    db.execute(
        "UPDATE items SET grid_cell = '{\"type\":\"Object\",\"props\":[]}' WHERE id = ?",
        [item.id],
    )
    assert_null(db.find(FxItem, item.id))
    assert_eq(db.last_error_kind(), Db.ErrorKind.CONVERSION)
    expect_engine_errors()


func test_query_reports_the_first_bad_row() -> void:
    var db: Db = open_memory()
    db.insert(make_item("Good"))
    var bad: FxItem = make_item("Bad")
    db.insert(bad)
    db.execute("UPDATE items SET stats = 'x' WHERE id = ?", [bad.id])
    assert_eq(db.select(FxItem).all(), [])
    assert_eq(db.last_error_kind(), Db.ErrorKind.CONVERSION)


func test_wrong_value_type_in_where_is_reported() -> void:
    var db: Db = open_memory()
    assert_eq(db.select(FxItem).where("damage", "=", "ten").all(), [])
    assert_eq(db.last_error_kind(), Db.ErrorKind.USAGE)
    assert_string_contains(db.last_error(), "'damage' expects int")


func test_where_converts_bool_string_name_and_enum() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Convert")
    item.tradable = false
    item.kind = &"ring"
    item.rarity = FxItem.Rarity.RARE
    db.insert(item)
    assert_eq(db.select(FxItem).where("tradable", "=", false).count(), 1)
    assert_eq(db.select(FxItem).where("kind", "=", &"ring").count(), 1)
    assert_eq(db.select(FxItem).where("kind", "=", "ring").count(), 1)
    assert_eq(db.select(FxItem).where("rarity", "=", FxItem.Rarity.RARE).count(), 1)


func test_float_field_accepts_int_values() -> void:
    var db: Db = open_memory()
    var hero: FxHero = make_hero("Gold")
    hero.gold = 10
    db.insert(hero)
    var found: FxHero = db.find(FxHero, hero.id)
    assert_eq(found.gold, 10.0)
    assert_eq(typeof(found.gold), TYPE_FLOAT)


func _round_trip(db: Db, item: FxItem) -> FxItem:
    assert_ok(db.insert(item), db)
    var found: FxItem = db.find(FxItem, item.id)
    assert_not_null(found, db.last_error())
    return found
