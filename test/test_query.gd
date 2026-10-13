# GUT asserts take untyped arguments; Godot 4.7 flags every Variant passed to them.
@warning_ignore_start("unsafe_call_argument")
extends DbTestCase
## The query builder: conditions, grouping, sorting, paging and the terminal calls.


func test_all_returns_rows_in_key_order_by_default() -> void:
    var db: Db = open_memory()
    _seed(db)
    assert_eq(
        _names(db.select(FxCharacter).all()),
        ["Ada", "Bob", "Cid", "Dee", "Eve", "Fay"] as Array[String],
    )


func test_comparison_operators() -> void:
    var db: Db = open_memory()
    _seed(db)
    assert_eq(db.select(FxCharacter).where("level", "=", 30).count(), 1)
    assert_eq(db.select(FxCharacter).where("level", "!=", 30).count(), 5)
    assert_eq(db.select(FxCharacter).where("level", "<>", 30).count(), 5)
    assert_eq(db.select(FxCharacter).where("level", "<", 30).count(), 2)
    assert_eq(db.select(FxCharacter).where("level", "<=", 30).count(), 3)
    assert_eq(db.select(FxCharacter).where("level", ">", 30).count(), 3)
    assert_eq(db.select(FxCharacter).where("level", ">=", 30).count(), 4)


func test_operators_ignore_case_and_spacing() -> void:
    var db: Db = open_memory()
    _seed(db)
    assert_eq(db.select(FxCharacter).where("name", "like", "a%").count(), 1)
    assert_eq(db.select(FxCharacter).where("name", "  not   like ", "a%").count(), 5)


func test_like_and_glob() -> void:
    var db: Db = open_memory()
    _seed(db)
    assert_eq(
        _names(db.select(FxCharacter).where("name", "LIKE", "%e%").all()),
        ["Dee", "Eve"] as Array[String],
    )
    assert_eq(db.select(FxCharacter).where("name", "GLOB", "[AB]*").count(), 2)
    assert_eq(db.select(FxCharacter).where("name", "NOT GLOB", "[AB]*").count(), 4)


func test_like_needs_a_string_pattern() -> void:
    var db: Db = open_memory()
    assert_eq(db.select(FxCharacter).where("name", "LIKE", 5).all(), [])
    assert_eq(db.last_error_kind(), Db.ErrorKind.USAGE)


func test_where_joins_with_and() -> void:
    var db: Db = open_memory()
    _seed(db)
    var found: Array = db.select(FxCharacter).where("level", ">", 10).where("level", "<", 40).all()
    assert_eq(_names(found), ["Bob", "Cid"] as Array[String])


func test_or_where_binds_looser_than_and() -> void:
    var db: Db = open_memory()
    _seed(db)
    var found: Array = (
        db
        .select(FxCharacter)
        .where("level", ">", 10)
        .where("level", "<", 30)
        .or_where("name", "=", "Fay")
        .all()
    )
    assert_eq(_names(found), ["Bob", "Fay"] as Array[String])


func test_where_group_adds_parentheses() -> void:
    var db: Db = open_memory()
    _seed(db)
    var found: Array = (
        db
        .select(FxCharacter)
        .where("level", ">", 10)
        .where_group(
            func(w: DbWhere) -> void:
                w.where("name", "=", "Ada").or_where("name", "=", "Eve"),
        )
        .all()
    )
    assert_eq(_names(found), ["Eve"] as Array[String])


func test_or_where_group_and_nested_groups() -> void:
    var db: Db = open_memory()
    _seed(db)
    var found: Array = (
        db.select(FxCharacter).where("name", "=", "Ada").or_where_group(_high_level_fay).all()
    )
    assert_eq(_names(found), ["Ada", "Fay"] as Array[String])


func test_empty_group_adds_nothing() -> void:
    var db: Db = open_memory()
    _seed(db)
    assert_eq(
        db.select(FxCharacter).where_group(
            func(_w: DbWhere) -> void:
                pass,
        ).count(),
        6,
    )


func test_error_inside_a_group_is_reported() -> void:
    var db: Db = open_memory()
    var query: DbQuery = db.select(FxCharacter).where_group(
        func(w: DbWhere) -> void:
            w.where("nope", "=", 1),
    )
    assert_eq(query.all(), [])
    assert_string_contains(db.last_error(), "has no field 'nope'")


func test_where_in_and_not_in() -> void:
    var db: Db = open_memory()
    _seed(db)
    assert_eq(
        _names(db.select(FxCharacter).where_in("level", [10, 30, 99]).all()),
        ["Ada", "Cid"] as Array[String],
    )
    assert_eq(db.select(FxCharacter).where_not_in("level", [10, 30]).count(), 4)
    var either: DbQuery = db.select(FxCharacter).where("level", "=", 60).or_where_in(
        "name",
        ["Ada"],
    )
    assert_eq(either.count(), 2)


func test_where_in_with_empty_lists() -> void:
    var db: Db = open_memory()
    _seed(db)
    assert_eq(db.select(FxCharacter).where_in("level", []).count(), 0)
    assert_eq(db.select(FxCharacter).where_not_in("level", []).count(), 6)


func test_where_in_with_more_values_than_one_chunk() -> void:
    var db: Db = open_memory()
    _seed(db)
    var values: Array = range(-1_500, 0)
    values.append(30)
    values.append(60)
    assert_eq(db.select(FxCharacter).where_in("level", values).count(), 2)
    assert_eq(db.select(FxCharacter).where_not_in("level", values).count(), 4)


func test_where_in_rejects_null() -> void:
    var db: Db = open_memory()
    assert_eq(db.select(FxCharacter).where_in("weapon_id", [1, null]).count(), -1)
    assert_string_contains(db.last_error(), "use where_null()")


func test_null_conditions() -> void:
    var db: Db = open_memory()
    _seed(db)
    var sword: FxItem = make_item("Sword")
    db.insert(sword)
    var armed: FxCharacter = db.select(FxCharacter).where("name", "=", "Ada").first()
    armed.weapon = sword
    db.update(armed)
    assert_eq(db.select(FxCharacter).where_null("weapon_id").count(), 5)
    assert_eq(db.select(FxCharacter).where_not_null("weapon_id").count(), 1)
    assert_eq(db.select(FxCharacter).where("weapon_id", "=", null).count(), 5)
    assert_eq(db.select(FxCharacter).where("weapon_id", "!=", null).count(), 1)
    assert_eq(db.select(FxCharacter).where("weapon_id", "IS NOT", null).count(), 1)
    assert_eq(
        db.select(FxCharacter).where("name", "=", "Bob").or_where_null("weapon_id").count(),
        5,
    )


func test_ordering_against_null_is_an_error() -> void:
    var db: Db = open_memory()
    assert_eq(db.select(FxCharacter).where("weapon_id", ">", null).count(), -1)
    assert_string_contains(db.last_error(), "cannot compare 'weapon_id' with null")


func test_where_between() -> void:
    var db: Db = open_memory()
    _seed(db)
    assert_eq(
        _names(db.select(FxCharacter).where_between("level", 20, 40).all()),
        ["Bob", "Cid", "Dee"] as Array[String],
    )


func test_where_raw() -> void:
    var db: Db = open_memory()
    _seed(db)
    assert_eq(db.select(FxCharacter).where_raw("level % ? = 0", [20]).count(), 3)


func test_order_by_limit_offset() -> void:
    var db: Db = open_memory()
    _seed(db)
    var page: Array = db.select(FxCharacter).order_by("level", Db.DESC).limit(2).offset(1).all()
    assert_eq(_names(page), ["Eve", "Dee"] as Array[String])
    assert_eq(db.select(FxCharacter).limit(0).all(), [])
    assert_eq(db.select(FxCharacter).offset(4).count(), 6, "count ignores paging")
    assert_eq(db.select(FxCharacter).offset(4).all().size(), 2)


func test_order_by_several_fields() -> void:
    var db: Db = open_memory()
    for spec: Array in [["B", 2], ["A", 2], ["C", 1]]:
        var level: int = spec[1]
        db.insert(make_character(str(spec[0]), level))
    var sorted: Array = db.select(FxCharacter).order_by("level").order_by("name", Db.DESC).all()
    assert_eq(_names(sorted), ["C", "B", "A"] as Array[String])


func test_negative_limit_or_offset_is_an_error() -> void:
    var db: Db = open_memory()
    assert_eq(db.select(FxCharacter).limit(-1).all(), [])
    assert_string_contains(db.last_error(), "limit()")
    assert_eq(db.select(FxCharacter).offset(-1).all(), [])
    assert_string_contains(db.last_error(), "offset()")


func test_first_and_exists() -> void:
    var db: Db = open_memory()
    assert_null(db.select(FxCharacter).first())
    assert_eq(db.last_error(), "")
    assert_false(db.select(FxCharacter).exists())
    _seed(db)
    var top: FxCharacter = db.select(FxCharacter).order_by("level", Db.DESC).first()
    assert_eq(top.name, "Fay")
    assert_true(db.select(FxCharacter).where("name", "=", "Cid").exists())
    assert_false(db.select(FxCharacter).where("name", "=", "Zed").exists())


func test_first_does_not_change_the_query_limit() -> void:
    var db: Db = open_memory()
    _seed(db)
    var query: DbQuery = db.select(FxCharacter).limit(3)
    query.first()
    assert_eq(query.all().size(), 3)


func test_pluck_converts_values() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Tagged")
    item.tags = [&"a"]
    db.insert(item)
    var tags: Array = db.select(FxItem).pluck("tags")
    assert_eq(tags, [[&"a"]])
    var names: Array = db.select(FxItem).pluck("name")
    assert_eq(names, ["Tagged"])
    assert_eq(db.select(FxItem).pluck("nope"), [])
    assert_eq(db.last_error_kind(), Db.ErrorKind.USAGE)


func test_unknown_field_and_operator_are_errors() -> void:
    var db: Db = open_memory()
    _seed(db)
    assert_eq(db.select(FxCharacter).where("nope", "=", 1).all(), [])
    assert_string_contains(db.last_error(), "FxCharacter has no field 'nope'")
    assert_eq(db.select(FxCharacter).where("level", "===", 1).count(), -1)
    assert_string_contains(db.last_error(), "unknown operator")
    assert_eq(db.select(FxCharacter).where("level", "; DROP TABLE characters", 1).count(), -1)
    assert_eq(db.select(FxCharacter).order_by("nope").all(), [])
    assert_string_contains(db.last_error(), "has no field 'nope'")
    assert_eq(db.select(FxCharacter).count(), 6, "nothing was dropped")


func test_field_names_cannot_inject_sql() -> void:
    var db: Db = open_memory()
    _seed(db)
    assert_eq(db.select(FxCharacter).where("level\" OR 1=1 --", "=", 1).count(), -1)
    assert_eq(db.last_error_kind(), Db.ErrorKind.USAGE)


func test_values_are_bound_not_pasted() -> void:
    var db: Db = open_memory()
    _seed(db)
    assert_eq(db.select(FxCharacter).where("name", "=", "x' OR '1'='1").count(), 0)


func test_select_of_model_outside_the_list() -> void:
    var db: Db = open_memory([FxItem])
    var query: DbQuery = db.select(FxCharacter)
    assert_eq(query.all(), [])
    assert_eq(query.count(), -1)
    assert_false(query.exists())
    assert_null(query.first())
    assert_eq(query.to_sql(), "")
    assert_eq(db.last_error_kind(), Db.ErrorKind.USAGE)


func test_to_sql_shows_the_statement() -> void:
    var db: Db = open_memory()
    var sql: String = db \
        .select(FxCharacter) \
        .where("level", ">", 3) \
        .order_by("name") \
        .limit(2) \
        .to_sql()
    assert_eq(
        sql,
        (
            "SELECT \"id\", \"name\", \"level\", \"weapon_id\" FROM \"characters\" "
            + "WHERE \"level\" > ? ORDER BY \"name\" ASC LIMIT ? OFFSET ?"
        ),
    )


func test_raw_returns_string_keyed_rows() -> void:
    var db: Db = open_memory()
    _seed(db)
    var rows: Array[Dictionary] = db.raw(
        "SELECT name, level FROM characters WHERE level > ? ORDER BY level",
        [40],
    )
    assert_eq(rows.size(), 2)
    var first_name: Variant = rows[0]["name"]
    assert_eq(first_name, "Eve")
    assert_true(rows[0].has("level"))


func test_raw_with_bad_sql_reports_error() -> void:
    var db: Db = open_memory()
    assert_eq(db.raw("SELEC nonsense"), [] as Array[Dictionary])
    assert_eq(db.last_error_kind(), Db.ErrorKind.SQL)
    assert_string_contains(db.last_error(), "syntax error")
    expect_engine_errors("syntax error")


func test_queries_return_new_objects_each_time() -> void:
    var db: Db = open_memory()
    _seed(db)
    var first: FxCharacter = db.find(FxCharacter, 1)
    var second: FxCharacter = db.find(FxCharacter, 1)
    assert_ne(first, second)
    first.level = 99
    assert_eq(second.level, 10)


func _seed(db: Db) -> void:
    var specs: Array = [
        ["Ada", 10],
        ["Bob", 20],
        ["Cid", 30],
        ["Dee", 40],
        ["Eve", 50],
        ["Fay", 60],
    ]
    for spec: Array in specs:
        var level: int = spec[1]
        assert_ok(db.insert(make_character(str(spec[0]), level)), db)


func _names(models: Array) -> Array[String]:
    var names: Array[String] = []
    for item: Variant in models:
        var character: FxCharacter = item
        names.append(character.name)
    return names


func _high_level_fay(w: DbWhere) -> void:
    w.where("level", ">=", 50).where_group(_fay_or_zed)


func _fay_or_zed(w: DbWhere) -> void:
    w.where("name", "=", "Fay").or_where("name", "=", "Zed")
