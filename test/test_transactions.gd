# GUT asserts take untyped arguments; Godot 4.7 flags every Variant passed to them.
@warning_ignore_start("unsafe_call_argument")
extends DbTestCase
## Transactions, nesting and rollback.


func test_commit_keeps_everything() -> void:
    var db: Db = open_memory()
    var ok: bool = db.transaction(
        func() -> bool:
            db.insert(make_item("A"))
            db.insert(make_item("B"))
            return true,
    )
    assert_ok(ok, db)
    assert_eq(db.select(FxItem).count(), 2)
    assert_false(db.in_transaction())


func test_body_without_return_value_commits() -> void:
    var db: Db = open_memory()
    var ok: bool = db.transaction(
        func() -> void:
            db.insert(make_item("Void")),
    )
    assert_ok(ok, db)
    assert_eq(db.select(FxItem).count(), 1)


func test_returning_false_rolls_back() -> void:
    var db: Db = open_memory()
    var ok: bool = db.transaction(
        func() -> bool:
            db.insert(make_item("A"))
            return false,
    )
    assert_failed(ok, db, Db.ErrorKind.USAGE, "returned false")
    assert_eq(db.select(FxItem).count(), 0)


func test_failed_statement_rolls_back_even_if_body_returns_true() -> void:
    var db: Db = open_memory()
    var ok: bool = db.transaction(
        func() -> bool:
            db.insert(make_item("A"))
            db.insert(make_item("A"))
            db.insert(make_item("B"))
            return true,
    )
    assert_failed(ok, db, Db.ErrorKind.UNIQUE)
    expect_engine_errors("UNIQUE")
    assert_eq(db.select(FxItem).count(), 0)


func test_conversion_error_rolls_back() -> void:
    var db: Db = open_memory()
    var ok: bool = db.transaction(
        func() -> bool:
            db.insert(make_item("A"))
            var bad: FxItem = make_item("B")
            bad.description = 5
            db.insert(bad)
            return true,
    )
    assert_failed(ok, db, Db.ErrorKind.CONVERSION)
    assert_eq(db.select(FxItem).count(), 0)


func test_in_transaction_flag() -> void:
    var db: Db = open_memory()
    var inside: Array[bool] = [false]
    db.transaction(
        func() -> void:
            inside[0] = db.in_transaction(),
    )
    assert_true(inside[0])
    assert_false(db.in_transaction())


func test_failed_inner_transaction_rolls_back_only_itself() -> void:
    var db: Db = open_memory()
    var inner_result: Array[bool] = [true]
    var ok: bool = db.transaction(
        func() -> bool:
            db.insert(make_item("Outer"))
            inner_result[0] = db.transaction(
                func() -> bool:
                    db.insert(make_item("Inner"))
                    return false,
            )
            db.insert(make_item("After"))
            return true,
    )
    assert_ok(ok, db)
    assert_false(inner_result[0])
    assert_eq(db.select(FxItem).pluck("name"), ["Outer", "After"])


func test_inner_statement_failure_does_not_fail_the_outer() -> void:
    var db: Db = open_memory()
    db.insert(make_item("Taken"))
    var ok: bool = db.transaction(
        func() -> bool:
            var inner: bool = db.transaction(
                func() -> bool:
                    return db.insert(make_item("Taken")),
            )
            assert_false(inner)
            return db.insert(make_item("Free")),
    )
    expect_engine_errors("UNIQUE")
    assert_ok(ok, db)
    assert_eq(db.select(FxItem).count(), 2)


func test_outer_rollback_undoes_committed_inner_work() -> void:
    var db: Db = open_memory()
    var ok: bool = db.transaction(
        func() -> bool:
            db.transaction(
                func() -> bool:
                    return db.insert(make_item("Inner")),
            )
            return false,
    )
    assert_false(ok)
    assert_eq(db.select(FxItem).count(), 0)


func test_deep_nesting() -> void:
    var db: Db = open_memory()
    var ok: bool = db.transaction(
        func() -> bool:
            return db.transaction(
                func() -> bool:
                    return db.transaction(
                        func() -> bool:
                            return db.insert(make_item("Deep")),
                    ),
            ),
    )
    assert_ok(ok, db)
    assert_eq(db.select(FxItem).count(), 1)


func test_transaction_after_a_rollback_works() -> void:
    var db: Db = open_memory()
    db.transaction(
        func() -> bool:
            return false,
    )
    assert_ok(
        db.transaction(
            func() -> bool:
                return db.insert(make_item("Fresh")),
        ),
        db,
    )
    assert_eq(db.select(FxItem).count(), 1)


func test_error_message_survives_the_rollback() -> void:
    var db: Db = open_memory()
    db.insert(make_item("Dup"))
    db.transaction(
        func() -> bool:
            return db.insert(make_item("Dup")),
    )
    expect_engine_errors("UNIQUE")
    assert_string_contains(db.last_error(), "UNIQUE constraint failed")
    assert_eq(db.last_error_kind(), Db.ErrorKind.UNIQUE)


func test_rollback_is_visible_on_disk() -> void:
    var db: Db = open_file("tx.db")
    db.insert(make_item("Kept"))
    db.transaction(
        func() -> bool:
            db.insert(make_item("Dropped"))
            return false,
    )
    db.close()
    var again: Db = open_file("tx.db")
    assert_eq(again.select(FxItem).pluck("name"), ["Kept"])


func test_backup_inside_a_transaction_is_refused() -> void:
    var db: Db = open_file("tx.db")
    var result: Array[bool] = [true]
    db.transaction(
        func() -> void:
            result[0] = db.backup(scratch_path("b.db")),
    )
    assert_false(result[0])
    assert_string_contains(db.last_error(), "inside a transaction")
