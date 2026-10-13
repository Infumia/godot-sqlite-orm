# GUT asserts take untyped arguments; Godot 4.7 flags every Variant passed to them.
@warning_ignore_start("unsafe_call_argument")
extends DbTestCase
## Edge cases that cut across features: locks, sizes, odd keys and lifecycle details.


func test_table_with_only_a_key_uses_default_values() -> void:
    var db: Db = open_memory()
    var first: FxTick = FxTick.new()
    var second: FxTick = FxTick.new()
    assert_ok(db.insert(first), db)
    assert_ok(db.insert(second), db)
    assert_eq(second.id, 2)
    assert_ok(db.update(second), db)
    assert_ok(db.save(second), db)
    assert_eq(db.select(FxTick).count(), 2)


func test_second_connection_waits_then_reports_busy() -> void:
    var writer: Db = open_file("shared.db")
    var options: DbOptions = make_options()
    options.busy_timeout_ms = 50
    var other: Db = open_file("shared.db", [], [], options)
    assert_open(other)
    var other_result: Array[bool] = [true]
    writer.transaction(
        func() -> bool:
            writer.insert(make_item("Writer"))
            other_result[0] = other.insert(make_item("Blocked"))
            return true,
    )
    expect_engine_errors("locked")
    assert_false(other_result[0])
    assert_eq(other.last_error_kind(), Db.ErrorKind.BUSY)
    assert_ok(other.insert(make_item("Later")), other)
    assert_eq(writer.select(FxItem).count(), 2)


func test_second_connection_sees_committed_rows() -> void:
    var first: Db = open_file("shared.db")
    var second: Db = open_file("shared.db")
    first.insert(make_item("Shared"))
    assert_eq(second.select(FxItem).pluck("name"), ["Shared"])


func test_very_long_text_and_blob() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("x".repeat(1_000_000))
    var bytes: PackedByteArray = PackedByteArray()
    bytes.resize(2_000_000)
    bytes.fill(7)
    item.icon = bytes
    assert_ok(db.insert(item), db)
    var found: FxItem = db.find(FxItem, item.id)
    assert_eq(found.name.length(), 1_000_000)
    assert_eq(found.icon.size(), 2_000_000)


func test_large_json_array() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Many rolls")
    for i: int in 10_000:
        item.rolls.append(i * 0.5)
    db.insert(item)
    var found: FxItem = db.find(FxItem, item.id)
    assert_eq(found.rolls.size(), 10_000)
    assert_eq(found.rolls[9_999], 4_999.5)


func test_find_with_string_name_key() -> void:
    var db: Db = open_memory()
    var hero: FxHero = make_hero("Named")
    hero.id = "abc"
    db.insert(hero)
    assert_not_null(db.find(FxHero, &"abc"))


func test_sync_keeps_more_children_than_one_chunk() -> void:
    var db: Db = open_memory()
    var hero: FxHero = make_hero("Hoarder")
    for i: int in 1_100:
        hero.gear.append(make_gear(StringName("g%d" % i)))
    assert_ok(db.save_tree(hero, ["gear"]), db)
    hero.gear.remove_at(5)
    assert_ok(db.sync_children(hero, "gear"), db)
    assert_eq(db.select(FxGear).count(), 1_099)
    assert_eq(db.select(FxGear).where("base_id", "=", &"g5").count(), 0)


func test_sync_children_with_composite_child_keys() -> void:
    var db: Db = open_memory()
    var hero: FxHero = make_hero("Slots")
    for slot: int in 3:
        var equipped: FxEquipped = FxEquipped.new()
        equipped.slot = slot
        hero.equipped.append(equipped)
    assert_ok(db.save_tree(hero, ["equipped"]), db)
    hero.equipped.remove_at(1)
    assert_ok(db.sync_children(hero, "equipped"), db)
    var slots: Array = db.select(FxEquipped).order_by("slot").pluck("slot")
    assert_eq(slots, [0, 2])


func test_relations_are_marked_loaded_after_save_tree() -> void:
    var db: Db = open_memory()
    var hero: FxHero = make_hero("Marked")
    db.save_tree(hero, ["gear", "quests"])
    assert_true(hero.is_loaded("gear"))
    assert_true(hero.is_loaded("quests"))
    assert_false(hero.is_loaded("equipped"))


func test_reload_keeps_relation_vars() -> void:
    var db: Db = open_memory()
    var hero: FxHero = make_hero("Reloaded")
    hero.gear.append(make_gear(&"kept"))
    db.save_tree(hero, ["gear"])
    db.update_all(FxHero).set_field("level", 9).where("id", "=", hero.id).execute()
    assert_ok(db.reload(hero), db)
    assert_eq(hero.level, 9)
    assert_eq(hero.gear.size(), 1)


func test_where_on_json_column_equality() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Tagged")
    item.tags = [&"a", &"b"]
    db.insert(item)
    assert_eq(db.select(FxItem).where("tags", "=", [&"a", &"b"] as Array[StringName]).count(), 1)
    assert_eq(db.select(FxItem).where("tags", "=", [&"b"] as Array[StringName]).count(), 0)


func test_where_on_empty_blob() -> void:
    var db: Db = open_memory()
    db.insert(make_item("No icon"))
    var with_icon: FxItem = make_item("Icon")
    with_icon.icon = PackedByteArray([1])
    db.insert(with_icon)
    assert_eq(db.select(FxItem).where("icon", "=", PackedByteArray()).pluck("name"), ["No icon"])


func test_raw_sql_inside_a_transaction_counts_toward_rollback() -> void:
    var db: Db = open_memory()
    var ok: bool = db.transaction(
        func() -> bool:
            db.insert(make_item("A"))
            db.execute("INSERT INTO nowhere VALUES (1)")
            return true,
    )
    expect_engine_errors("no such table")
    assert_false(ok)
    assert_eq(db.select(FxItem).count(), 0)


func test_keys_survive_close_and_reopen() -> void:
    var db: Db = open_file("game.db")
    var hero: FxHero = make_hero("Persisted")
    hero.gear.append(make_gear(&"blade", [4.5]))
    db.save_tree(hero, ["gear.affixes"])
    db.close()
    var again: Db = open_file("game.db")
    var found: FxHero = again.select(FxHero).with("gear.affixes").first()
    assert_eq(found.id, hero.id)
    assert_eq(found.gear[0].uid, hero.gear[0].uid)
    assert_eq(found.gear[0].affixes[0].value, 4.5)


func test_auto_increment_continues_after_reopen() -> void:
    var db: Db = open_file("game.db")
    for i: int in 3:
        db.insert(make_item("i%d" % i))
    db.delete_all(FxItem).all_rows().execute()
    db.close()
    var again: Db = open_file("game.db")
    var item: FxItem = make_item("Next")
    again.insert(item)
    assert_eq(item.id, 4)


func test_identifiers_that_are_sql_keywords() -> void:
    var db: Db = open_memory()
    var rows: Array[Dictionary] = db.raw(
        "SELECT name FROM pragma_table_info('equipped') WHERE name = 'slot'"
    )
    assert_eq(rows.size(), 1)
    var hero: FxHero = make_hero("Kw")
    db.insert(hero)
    var slot: FxEquipped = FxEquipped.new()
    slot.hero_id = hero.id
    slot.slot = 1
    assert_ok(db.insert(slot), db)
    assert_eq(db.select(FxEquipped).where("slot", "=", 1).count(), 1)


func test_open_two_databases_with_the_same_models() -> void:
    var first: Db = open_memory()
    var second: Db = open_memory()
    first.insert(make_item("Only in first"))
    assert_eq(first.select(FxItem).count(), 1)
    assert_eq(second.select(FxItem).count(), 0)


func test_unsaved_children_with_auto_keys_are_inserted_by_sync() -> void:
    var db: Db = open_memory()
    var hero: FxHero = make_hero("Banner holder")
    db.insert(hero)
    var banner: FxBanner = FxBanner.new()
    banner.motto = "New"
    hero.banner = banner
    assert_ok(db.sync_children(hero, "banner"), db)
    assert_ne(banner.id, 0)
    assert_eq(banner.hero_id, hero.id)
