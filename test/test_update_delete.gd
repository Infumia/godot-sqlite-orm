# GUT asserts take untyped arguments; Godot 4.7 flags every Variant passed to them.
@warning_ignore_start("unsafe_call_argument")
extends DbTestCase
## Bulk updates and deletes.


func test_update_all_changes_matching_rows_and_counts_them() -> void:
    var db: Db = open_memory()
    _seed(db)
    var changed: int = db \
        .update_all(FxItem) \
        .set_field("tradable", false) \
        .where("damage", ">=", 20) \
        .execute()
    assert_eq(changed, 3)
    assert_eq(db.select(FxItem).where("tradable", "=", false).count(), 3)


func test_update_all_sets_several_fields() -> void:
    var db: Db = open_memory()
    _seed(db)
    db \
        .update_all(FxItem) \
        .set_field("damage", 1) \
        .set_field("tags", [&"bulk"] as Array[StringName]) \
        .where("id", "=", 1) \
        .execute()
    var item: FxItem = db.find(FxItem, 1)
    assert_eq(item.damage, 1)
    assert_eq(item.tags, [&"bulk"] as Array[StringName])


func test_update_all_without_conditions_is_refused() -> void:
    var db: Db = open_memory()
    _seed(db)
    assert_eq(db.update_all(FxItem).set_field("damage", 0).execute(), -1)
    assert_eq(db.last_error_kind(), Db.ErrorKind.USAGE)
    assert_string_contains(db.last_error(), "all_rows()")
    assert_eq(db.select(FxItem).where("damage", "=", 0).count(), 1)


func test_update_all_rows_when_asked() -> void:
    var db: Db = open_memory()
    _seed(db)
    assert_eq(db.update_all(FxItem).set_field("damage", 0).all_rows().execute(), 5)


func test_update_all_needs_something_to_set() -> void:
    var db: Db = open_memory()
    assert_eq(db.update_all(FxItem).where("id", "=", 1).execute(), -1)
    assert_string_contains(db.last_error(), "nothing to set")


func test_update_all_rejects_unknown_fields_and_bad_values() -> void:
    var db: Db = open_memory()
    _seed(db)
    assert_eq(db.update_all(FxItem).set_field("nope", 1).all_rows().execute(), -1)
    assert_string_contains(db.last_error(), "has no field 'nope'")
    assert_eq(db.update_all(FxItem).set_field("damage", "lots").all_rows().execute(), -1)
    assert_string_contains(db.last_error(), "expects int")
    assert_eq(db.update_all(FxItem).set_field("name", null).all_rows().execute(), -1)
    assert_string_contains(db.last_error(), "cannot be null")


func test_update_all_touches_auto_updated_fields() -> void:
    var db: Db = open_memory()
    _seed(db)
    advance_clock(500)
    db.update_all(FxItem).set_field("damage", 3).where("id", "=", 2).execute()
    var changed: FxItem = db.find(FxItem, 2)
    var untouched: FxItem = db.find(FxItem, 3)
    assert_eq(changed.updated, 1_500)
    assert_eq(untouched.updated, 1_000)


func test_update_all_can_set_auto_updated_itself() -> void:
    var db: Db = open_memory()
    _seed(db)
    db.update_all(FxItem).set_field("updated", 7).where("id", "=", 1).execute()
    assert_eq((db.find(FxItem, 1) as FxItem).updated, 7)


func test_update_all_constraint_failure() -> void:
    var db: Db = open_memory()
    _seed(db)
    assert_eq(db.update_all(FxItem).set_field("name", "same").all_rows().execute(), -1)
    assert_eq(db.last_error_kind(), Db.ErrorKind.UNIQUE)
    expect_engine_errors("UNIQUE")
    assert_eq(db.select(FxItem).where("name", "=", "same").count(), 0, "the statement is atomic")


func test_update_all_with_no_match_changes_nothing() -> void:
    var db: Db = open_memory()
    _seed(db)
    assert_eq(db.update_all(FxItem).set_field("damage", 1).where("damage", ">", 1000).execute(), 0)


func test_delete_all_with_conditions() -> void:
    var db: Db = open_memory()
    _seed(db)
    assert_eq(db.delete_all(FxItem).where("damage", "<", 20).execute(), 2)
    assert_eq(db.select(FxItem).count(), 3)


func test_delete_all_without_conditions_is_refused() -> void:
    var db: Db = open_memory()
    _seed(db)
    assert_eq(db.delete_all(FxItem).execute(), -1)
    assert_string_contains(db.last_error(), "all_rows()")
    assert_eq(db.select(FxItem).count(), 5)
    assert_eq(db.delete_all(FxItem).all_rows().execute(), 5)
    assert_eq(db.select(FxItem).count(), 0)


func test_delete_all_with_groups_and_in() -> void:
    var db: Db = open_memory()
    _seed(db)
    var deleted: int = (
        db
        .delete_all(FxItem)
        .where_in("damage", [0, 10, 40])
        .where_group(
            func(w: DbWhere) -> void:
                w.where("name", "LIKE", "%0").or_where("name", "LIKE", "%4"),
        )
        .execute()
    )
    assert_eq(deleted, 2)


func test_delete_all_follows_foreign_key_rules() -> void:
    var db: Db = open_memory()
    var sword: FxItem = make_item("Sword")
    db.insert(sword)
    var hero: FxCharacter = make_character("Holder")
    hero.weapon = sword
    db.insert(hero)
    assert_eq(db.delete_all(FxItem).where("id", "=", sword.id).execute(), 1)
    var found: FxCharacter = db.find(FxCharacter, hero.id)
    var weapon_id: Variant = found.weapon_id
    assert_null(weapon_id, "ON DELETE SET NULL")


func test_delete_all_blocked_by_restrict() -> void:
    var db: Db = open_memory()
    var guild: FxGuild = FxGuild.new()
    guild.name = "Order"
    db.insert(guild)
    var member: FxMember = FxMember.new()
    member.guild = guild
    db.insert(member)
    assert_eq(db.delete_all(FxGuild).all_rows().execute(), -1)
    assert_eq(db.last_error_kind(), Db.ErrorKind.FOREIGN_KEY)
    expect_engine_errors("FOREIGN KEY")


func test_model_outside_the_list() -> void:
    var db: Db = open_memory([FxItem])
    assert_eq(db.update_all(FxCharacter).set_field("level", 1).all_rows().execute(), -1)
    assert_eq(db.delete_all(FxCharacter).all_rows().execute(), -1)
    assert_eq(db.last_error_kind(), Db.ErrorKind.USAGE)


func _seed(db: Db) -> void:
    for i: int in 5:
        assert_ok(db.insert(make_item("item %d" % i, i * 10)), db)
