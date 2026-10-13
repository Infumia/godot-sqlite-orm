# GUT asserts take untyped arguments; Godot 4.7 flags every Variant passed to them.
@warning_ignore_start("unsafe_call_argument")
extends DbTestCase
## Inserting, updating, saving, finding and deleting rows.


func test_insert_fills_auto_increment_key() -> void:
    var db: Db = open_memory()
    var sword: FxItem = make_item("Sword")
    var bow: FxItem = make_item("Bow")
    assert_ok(db.insert(sword), db)
    assert_ok(db.insert(bow), db)
    assert_eq(sword.id, 1)
    assert_eq(bow.id, 2)
    assert_true(sword.is_persisted())


func test_insert_keeps_an_explicit_key() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Relic")
    item.id = 77
    assert_ok(db.insert(item), db)
    assert_eq(item.id, 77)
    assert_not_null(db.find(FxItem, 77))


func test_auto_increment_never_reuses_deleted_ids() -> void:
    var db: Db = open_memory()
    var first: FxItem = make_item("A")
    db.insert(first)
    db.delete(first)
    var second: FxItem = make_item("B")
    db.insert(second)
    assert_eq(second.id, 2)


func test_insert_fills_empty_uuid_key() -> void:
    var db: Db = open_memory()
    var hero: FxHero = make_hero("Ada")
    assert_ok(db.insert(hero), db)
    assert_eq(hero.id.length(), 36)
    var found: FxHero = db.find(FxHero, hero.id)
    assert_eq(found.display_name, "Ada")


func test_insert_keeps_a_given_uuid() -> void:
    var db: Db = open_memory()
    var hero: FxHero = make_hero("Lin")
    hero.id = "fixed-id"
    assert_ok(db.insert(hero), db)
    assert_eq(hero.id, "fixed-id")


func test_insert_duplicate_key_fails_with_unique() -> void:
    var db: Db = open_memory()
    var hero: FxHero = make_hero("One")
    hero.id = "same"
    db.insert(hero)
    var twin: FxHero = make_hero("Two")
    twin.id = "same"
    assert_failed(db.insert(twin), db, Db.ErrorKind.UNIQUE)
    expect_engine_errors("UNIQUE")


func test_failed_insert_leaves_the_model_untouched() -> void:
    var db: Db = open_memory()
    db.insert(make_item("Taken"))
    var copy: FxItem = make_item("Taken")
    assert_false(db.insert(copy))
    expect_engine_errors("UNIQUE")
    assert_eq(copy.id, 0)
    assert_eq(copy.created, 0, "timestamps are written back only on success")
    assert_false(copy.is_persisted())


func test_timestamps_on_insert_and_update() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Clock")
    db.insert(item)
    assert_eq(item.created, clock_time())
    assert_eq(item.updated, clock_time())
    advance_clock(60)
    item.damage = 5
    assert_ok(db.update(item), db)
    assert_eq(item.created, 1_000)
    assert_eq(item.updated, 1_060)
    var found: FxItem = db.find(FxItem, item.id)
    assert_eq(found.created, 1_000)
    assert_eq(found.updated, 1_060)


func test_auto_created_keeps_a_set_value() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Old")
    item.created = 5
    db.insert(item)
    assert_eq(item.created, 5)


func test_update_writes_every_field() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Plain")
    db.insert(item)
    item.name = "Shiny"
    item.damage = 99
    item.tags = [&"fire"]
    assert_ok(db.update(item), db)
    var found: FxItem = db.find(FxItem, item.id)
    assert_eq(found.name, "Shiny")
    assert_eq(found.damage, 99)
    assert_eq(found.tags, [&"fire"] as Array[StringName])


func test_update_of_missing_row_is_not_found() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Gone")
    item.id = 404
    assert_failed(db.update(item), db, Db.ErrorKind.NOT_FOUND, "has no row")


func test_update_of_unsaved_model_is_a_usage_error() -> void:
    var db: Db = open_memory()
    assert_failed(db.update(make_item("New")), db, Db.ErrorKind.USAGE, "insert it first")


func test_update_of_table_with_only_key_columns() -> void:
    var db: Db = open_memory()
    var hero: FxHero = make_hero("Key")
    db.insert(hero)
    var quest: FxQuest = FxQuest.new()
    quest.hero_id = hero.id
    quest.quest_id = &"intro"
    assert_ok(db.insert(quest), db)
    assert_ok(db.update(quest), db)


func test_save_inserts_then_updates() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Saved")
    assert_ok(db.save(item), db)
    assert_eq(item.id, 1)
    item.damage = 3
    advance_clock(10)
    assert_ok(db.save(item), db)
    assert_eq(db.select(FxItem).count(), 1)
    var found: FxItem = db.find(FxItem, 1)
    assert_eq(found.damage, 3)
    assert_eq(found.updated, 1_010)
    assert_eq(found.created, 1_000)


func test_save_with_given_key_upserts() -> void:
    var db: Db = open_memory()
    var hero: FxHero = make_hero("First")
    hero.id = "h1"
    assert_ok(db.save(hero), db)
    var other: FxHero = make_hero("Second")
    other.id = "h1"
    advance_clock(100)
    assert_ok(db.save(other), db)
    assert_eq(db.select(FxHero).count(), 1)
    var found: FxHero = db.find(FxHero, "h1")
    assert_eq(found.display_name, "Second")
    assert_eq(found.created_unix, 1_000, "an upsert keeps the first created time")
    assert_eq(other.created_unix, 1_000, "and reports it back to the model")
    assert_eq(found.saved_unix, 1_100)


func test_save_composite_key_upserts() -> void:
    var db: Db = open_memory()
    var hero: FxHero = make_hero("Q")
    db.insert(hero)
    var quest: FxQuest = FxQuest.new()
    quest.hero_id = hero.id
    quest.quest_id = &"rats"
    quest.counts = { "rats": 1 }
    assert_ok(db.save(quest), db)
    quest.counts = { "rats": 5 }
    quest.status = FxQuest.Status.DONE
    assert_ok(db.save(quest), db)
    var found: FxQuest = db.find(FxQuest, [hero.id, &"rats"])
    assert_eq(found.status, FxQuest.Status.DONE)
    assert_eq(found.counts["rats"], 5)


func test_delete_removes_the_row() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Doomed")
    db.insert(item)
    assert_ok(db.delete(item), db)
    assert_null(db.find(FxItem, item.id))
    assert_false(item.is_persisted())


func test_delete_twice_is_not_found() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Twice")
    db.insert(item)
    db.delete(item)
    assert_failed(db.delete(item), db, Db.ErrorKind.NOT_FOUND)


func test_delete_unsaved_is_a_usage_error() -> void:
    var db: Db = open_memory()
    assert_failed(db.delete(make_item("Never")), db, Db.ErrorKind.USAGE)


func test_find_missing_row_returns_null_without_error() -> void:
    var db: Db = open_memory()
    assert_null(db.find(FxItem, 12345))
    assert_eq(db.last_error(), "")


func test_find_with_composite_key_needs_every_value() -> void:
    var db: Db = open_memory()
    assert_null(db.find(FxQuest, "only-one"))
    assert_eq(db.last_error_kind(), Db.ErrorKind.USAGE)


func test_find_marks_the_model_loaded_and_runs_hook() -> void:
    var db: Db = open_memory()
    var character: FxCharacter = make_character("Hook")
    db.insert(character)
    assert_eq(character.saves, 1, "_before_save ran")
    var found: FxCharacter = db.find(FxCharacter, character.id)
    assert_eq(found.loads, 1, "_after_load ran")
    assert_true(found.is_persisted())


func test_hooks_run_on_update_and_save() -> void:
    var db: Db = open_memory()
    var character: FxCharacter = make_character("Hooks")
    db.insert(character)
    db.update(character)
    db.save(character)
    assert_eq(character.saves, 3)


func test_reload_reads_the_row_again() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Stale")
    db.insert(item)
    db.update_all(FxItem).set_field("damage", 50).where("id", "=", item.id).execute()
    assert_eq(item.damage, 1)
    assert_ok(db.reload(item), db)
    assert_eq(item.damage, 50)


func test_reload_of_deleted_row_is_not_found() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Vanish")
    db.insert(item)
    db.delete_all(FxItem).all_rows().execute()
    assert_failed(db.reload(item), db, Db.ErrorKind.NOT_FOUND)


func test_insert_many_is_all_or_nothing() -> void:
    var db: Db = open_memory()
    var batch: Array = [make_item("A"), make_item("B"), make_item("A")]
    assert_false(db.insert_many(batch))
    expect_engine_errors("UNIQUE")
    assert_eq(db.last_error_kind(), Db.ErrorKind.UNIQUE)
    assert_eq(db.select(FxItem).count(), 0)
    assert_ok(db.insert_many([make_item("A"), make_item("B")]), db)
    assert_eq(db.select(FxItem).count(), 2)


func test_insert_many_rejects_non_models() -> void:
    var db: Db = open_memory()
    assert_failed(db.insert_many([make_item("A"), "nope"]), db, Db.ErrorKind.USAGE, "not a DbModel")
    assert_eq(db.select(FxItem).count(), 0)


func test_save_many() -> void:
    var db: Db = open_memory()
    var a: FxItem = make_item("A")
    db.insert(a)
    a.damage = 9
    assert_ok(db.save_many([a, make_item("B")]), db)
    assert_eq(db.select(FxItem).count(), 2)
    assert_eq((db.find(FxItem, a.id) as FxItem).damage, 9)


func test_model_outside_the_list_is_a_usage_error() -> void:
    var db: Db = open_memory([FxItem])
    assert_failed(
        db.insert(make_character("Stranger")),
        db,
        Db.ErrorKind.USAGE,
        "not in this database",
    )
    assert_null(db.find(FxCharacter, 1))
    assert_eq(db.select(FxCharacter).all(), [])
    assert_eq(db.last_error_kind(), Db.ErrorKind.USAGE)


func test_null_model_is_a_usage_error() -> void:
    var db: Db = open_memory()
    assert_failed(db.insert(null), db, Db.ErrorKind.USAGE, "null")
    assert_failed(db.save(null), db, Db.ErrorKind.USAGE)
    assert_failed(db.delete(null), db, Db.ErrorKind.USAGE)


func test_check_constraint_failure() -> void:
    var db: Db = open_memory()
    var character: FxCharacter = make_character("Zero", 0)
    assert_failed(db.insert(character), db, Db.ErrorKind.CHECK)
    expect_engine_errors("CHECK")


func test_last_error_clears_on_success() -> void:
    var db: Db = open_memory()
    db.update(make_item("x"))
    assert_ne(db.last_error(), "")
    db.insert(make_item("y"))
    assert_eq(db.last_error(), "")
    assert_eq(db.last_error_kind(), Db.ErrorKind.NONE)


func test_ignored_and_private_vars_are_not_stored() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Quiet")
    item.transient = "temp"
    item._cache = 9
    db.insert(item)
    var found: FxItem = db.find(FxItem, item.id)
    assert_eq(found.transient, "")
    assert_eq(found._cache, 0)


func test_many_rows_round_trip() -> void:
    var db: Db = open_memory()
    var batch: Array = []
    for i: int in 2_000:
        batch.append(make_item("item %d" % i, i))
    assert_ok(db.insert_many(batch), db)
    assert_eq(db.select(FxItem).count(), 2_000)
    var last: FxItem = db.select(FxItem).order_by("damage", Db.DESC).first()
    assert_eq(last.damage, 1_999)
