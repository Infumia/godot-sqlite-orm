# GUT asserts take untyped arguments; Godot 4.7 flags every Variant passed to them.
@warning_ignore_start("unsafe_call_argument")
extends DbTestCase
## SQL text helpers.


func test_ident_quotes_and_escapes() -> void:
    assert_eq(DbSql.ident("items"), "\"items\"")
    assert_eq(DbSql.ident("we\"ird"), "\"we\"\"ird\"")
    assert_eq(DbSql.ident("select"), "\"select\"")


func test_idents_joins_names() -> void:
    assert_eq(DbSql.idents(["a", "b"]), "\"a\", \"b\"")
    assert_eq(DbSql.idents([]), "")


func test_placeholders() -> void:
    assert_eq(DbSql.placeholders(0), "")
    assert_eq(DbSql.placeholders(3), "?, ?, ?")


func test_literals() -> void:
    var ok: Array[bool] = [true]
    assert_eq(DbSql.literal(null, ok), "NULL")
    assert_eq(DbSql.literal(true, ok), "1")
    assert_eq(DbSql.literal(false, ok), "0")
    assert_eq(DbSql.literal(-42, ok), "-42")
    assert_eq(DbSql.literal(1.5, ok), "1.5")
    assert_eq(DbSql.literal(2.0, ok), "2.0")
    assert_eq(DbSql.literal("it's", ok), "'it''s'")
    assert_eq(DbSql.literal(&"name", ok), "'name'")
    assert_eq(DbSql.literal(PackedByteArray([0, 255]), ok), "X'00ff'")
    assert_true(ok[0])


func test_literal_rejects_unstorable_values() -> void:
    for value: Variant in [NAN, INF, -INF, Vector2.ONE, [1], { }]:
        var ok: Array[bool] = [true]
        DbSql.literal(value, ok)
        assert_false(ok[0], "should reject %s" % [value])


func test_uuid_v4_format_and_uniqueness() -> void:
    var pattern: RegEx = RegEx.create_from_string(
        "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
    )
    var seen: Dictionary = { }
    for i: int in 500:
        var id: String = DbSql.uuid_v4()
        assert_not_null(pattern.search(id), "bad uuid " + id)
        seen[id] = true
    assert_eq(seen.size(), 500)


func test_chunks() -> void:
    assert_eq(DbSql.chunks([]).size(), 0)
    assert_eq(DbSql.chunks([1, 2, 3], 2), [[1, 2], [3]] as Array[Array])
    var big: Array = range(1001)
    var parts: Array[Array] = DbSql.chunks(big)
    assert_eq(parts.size(), 3)
    assert_eq(parts[2], [1000])


func test_to_int_and_to_float() -> void:
    assert_eq(DbSql.to_int(5), 5)
    assert_eq(DbSql.to_int(5.9), 5)
    assert_eq(DbSql.to_int(true), 1)
    assert_eq(DbSql.to_int("5"), 0)
    assert_eq(DbSql.to_int(null), 0)
    assert_eq(DbSql.to_float(2), 2.0)
    assert_eq(DbSql.to_float(2.5), 2.5)
    assert_eq(DbSql.to_float("x"), 0.0)
