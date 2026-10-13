# GUT asserts take untyped arguments; Godot 4.7 flags every Variant passed to them.
@warning_ignore_start("unsafe_call_argument")
extends DbTestCase
## belongs_to, has_many and has_one: loading, saving and syncing children.


func test_assigning_a_belongs_to_target_sets_the_key() -> void:
    var db: Db = open_memory()
    var sword: FxItem = make_item("Sword")
    db.insert(sword)
    var character: FxCharacter = _armed_character(db, "Ada", sword)
    assert_eq(character.weapon_id, sword.id)
    var found: FxCharacter = db.find(FxCharacter, character.id)
    assert_eq(found.weapon_id, sword.id)
    assert_null(found.weapon, "relations are not loaded unless asked")
    assert_false(found.is_loaded("weapon"))


func test_unsaved_belongs_to_target_is_an_error() -> void:
    var db: Db = open_memory()
    var character: FxCharacter = make_character("Early")
    character.weapon = make_item("Unsaved")
    assert_failed(db.insert(character), db, Db.ErrorKind.USAGE, "save the FxItem")


func test_wrong_model_in_belongs_to_var_is_an_error() -> void:
    var db: Db = open_memory()
    var character: FxCharacter = make_character("Odd")
    var stranger: FxCharacter = make_character("Stranger")
    db.insert(stranger)
    character.set("weapon", stranger)
    if character.weapon == null:
        pass_test("the typed var refuses the wrong model by itself")
        return
    assert_failed(db.insert(character), db, Db.ErrorKind.USAGE, "not the related model")


func test_null_belongs_to_var_keeps_the_key() -> void:
    var db: Db = open_memory()
    var sword: FxItem = make_item("Sword")
    db.insert(sword)
    var character: FxCharacter = make_character("Keeper")
    character.weapon_id = sword.id
    assert_ok(db.insert(character), db)
    assert_eq(character.weapon_id, sword.id)


func test_load_belongs_to() -> void:
    var db: Db = open_memory()
    var sword: FxItem = make_item("Sword")
    db.insert(sword)
    var character: FxCharacter = _armed_character(db, "Ada", sword)
    var found: FxCharacter = db.find(FxCharacter, character.id)
    assert_ok(db.load(found, "weapon"), db)
    assert_eq(found.weapon.name, "Sword")
    assert_true(found.is_loaded("weapon"))


func test_load_belongs_to_with_null_key() -> void:
    var db: Db = open_memory()
    var character: FxCharacter = make_character("Unarmed")
    db.insert(character)
    assert_ok(db.load(character, "weapon"), db)
    assert_null(character.weapon)
    assert_true(character.is_loaded("weapon"))


func test_with_loads_belongs_to_in_one_query_and_shares_targets() -> void:
    var db: Db = open_memory()
    var sword: FxItem = make_item("Sword")
    var bow: FxItem = make_item("Bow")
    db.insert(sword)
    db.insert(bow)
    for i: int in 10:
        _armed_character(db, "c%d" % i, sword if i % 2 == 0 else bow)
    db.insert(make_character("Unarmed"))
    var characters: Array = []
    var queries: int = count_queries(
        db,
        func() -> void:
            characters.append_array(db.select(FxCharacter).with("weapon").all()),
    )
    assert_eq(queries, 2, "one for characters, one for all their weapons")
    var first: FxCharacter = characters[0]
    var third: FxCharacter = characters[2]
    assert_eq(first.weapon.name, "Sword")
    assert_same(first.weapon, third.weapon, "rows of one load share target objects")
    var last: FxCharacter = characters[-1]
    assert_null(last.weapon)


func test_has_many_loads_in_position_order() -> void:
    var db: Db = open_memory()
    var hero: FxHero = _saved_hero(db)
    var found: FxHero = db.find(FxHero, hero.id)
    assert_ok(db.load(found, "gear"), db)
    var bases: Array[StringName] = []
    for gear: FxGear in found.gear:
        bases.append(gear.base_id)
    assert_eq(bases, [&"sword", &"shield", &"ring"] as Array[StringName])
    assert_eq(found.gear[1].slot_index, 1)


func test_loaded_has_many_array_stays_typed() -> void:
    var db: Db = open_memory()
    var hero: FxHero = _saved_hero(db)
    var found: FxHero = db.select(FxHero).with("gear").first()
    assert_true(found.gear.is_typed())
    assert_eq(found.gear.get_typed_script(), FxGear)
    assert_eq(found.gear.size(), hero.gear.size())


func test_nested_with_loads_every_level_with_one_query_each() -> void:
    var db: Db = open_memory()
    _saved_hero(db)
    _saved_hero(db)
    var heroes: Array = []
    var queries: int = count_queries(
        db,
        func() -> void:
            heroes.append_array(db.select(FxHero).with("gear.affixes").all()),
    )
    assert_eq(queries, 3)
    var hero: FxHero = heroes[0]
    assert_eq(hero.gear.size(), 3)
    assert_eq(hero.gear[0].affixes.size(), 2)
    assert_eq(hero.gear[0].affixes[1].value, 2.0)
    assert_eq(hero.gear[1].affixes.size(), 0)
    assert_true(hero.gear[1].is_loaded("affixes"), "an empty list is still loaded")


func test_several_with_paths_share_prefixes() -> void:
    var db: Db = open_memory()
    _saved_hero(db)
    var queries: int = count_queries(
        db,
        func() -> void:
            db.select(FxHero).with("gear").with("gear.affixes").with("quests").all(),
    )
    assert_eq(queries, 4)


func test_has_many_order_by() -> void:
    var db: Db = open_memory()
    var hero: FxHero = make_hero("Questor")
    for quest_name: StringName in [&"b", &"c", &"a"]:
        var quest: FxQuest = FxQuest.new()
        quest.quest_id = quest_name
        hero.quests.append(quest)
    assert_ok(db.save_tree(hero, ["quests"]), db)
    var found: FxHero = db.select(FxHero).with("quests").first()
    var ids: Array[StringName] = []
    for quest: FxQuest in found.quests:
        ids.append(quest.quest_id)
    assert_eq(ids, [&"c", &"b", &"a"] as Array[StringName], "order_by quest_id descending")


func test_has_one() -> void:
    var db: Db = open_memory()
    var hero: FxHero = make_hero("Bannered")
    var banner: FxBanner = FxBanner.new()
    banner.motto = "Onward"
    hero.banner = banner
    assert_ok(db.save_tree(hero, ["banner"]), db)
    var found: FxHero = db.select(FxHero).with("banner").first()
    assert_eq(found.banner.motto, "Onward")
    var plain: FxHero = make_hero("Plain")
    db.insert(plain)
    var plain_found: FxHero = db.find(FxHero, plain.id)
    db.load(plain_found, "banner")
    assert_null(plain_found.banner)


func test_has_one_sync_replaces_and_clears() -> void:
    var db: Db = open_memory()
    var hero: FxHero = make_hero("Flag")
    var first: FxBanner = FxBanner.new()
    first.motto = "One"
    hero.banner = first
    db.save_tree(hero, ["banner"])
    var second: FxBanner = FxBanner.new()
    second.motto = "Two"
    hero.banner = second
    assert_ok(db.sync_children(hero, "banner"), db)
    assert_eq(db.select(FxBanner).pluck("motto"), ["Two"])
    hero.banner = null
    assert_ok(db.sync_children(hero, "banner"), db)
    assert_eq(db.select(FxBanner).count(), 0)


func test_load_many() -> void:
    var db: Db = open_memory()
    _saved_hero(db)
    _saved_hero(db)
    var heroes: Array = db.select(FxHero).all()
    assert_ok(db.load_many(heroes, "gear"), db)
    for item: Variant in heroes:
        var hero: FxHero = item
        assert_eq(hero.gear.size(), 3)


func test_load_through_belongs_to_then_has_many() -> void:
    var db: Db = open_memory()
    var hero: FxHero = _saved_hero(db)
    var gear: FxGear = db.select(FxGear).where("base_id", "=", &"ring").with("hero.gear").first()
    assert_eq(gear.hero.id, hero.id)
    assert_eq(gear.hero.gear.size(), 3)


func test_unknown_relation_is_an_error() -> void:
    var db: Db = open_memory()
    var hero: FxHero = _saved_hero(db)
    assert_failed(db.load(hero, "pets"), db, Db.ErrorKind.USAGE, "has no relation 'pets'")
    assert_eq(db.select(FxHero).with("gear.nope").all(), [])
    assert_string_contains(db.last_error(), "FxGear has no relation 'nope'")


func test_empty_path_parts_are_ignored() -> void:
    var db: Db = open_memory()
    _saved_hero(db)
    var hero: FxHero = db.select(FxHero).with("gear..affixes.").first()
    assert_eq(hero.gear[0].affixes.size(), 2)


func test_sync_children_adds_updates_reorders_and_removes() -> void:
    var db: Db = open_memory()
    var hero: FxHero = _saved_hero(db)
    var loaded: FxHero = db.select(FxHero).with("gear").first()
    var sword: FxGear = loaded.gear[0]
    var ring: FxGear = loaded.gear[2]
    ring.rarity = FxGear.Rarity.RARE
    var axe: FxGear = make_gear(&"axe")
    loaded.gear = [ring, axe, sword] as Array[FxGear]
    assert_ok(db.sync_children(loaded, "gear"), db)
    var again: FxHero = db.select(FxHero).with("gear").first()
    var bases: Array[StringName] = []
    for gear: FxGear in again.gear:
        bases.append(gear.base_id)
    assert_eq(bases, [&"ring", &"axe", &"sword"] as Array[StringName])
    assert_eq(again.gear[0].rarity, FxGear.Rarity.RARE)
    assert_eq(db.select(FxGear).where("base_id", "=", &"shield").count(), 0, "shield removed")
    assert_eq(db.select(FxAffix).count(), 3, "affixes of the kept items stay; the shield had none")
    assert_eq(hero.id, again.id)


func test_sync_children_with_empty_list_deletes_all() -> void:
    var db: Db = open_memory()
    _saved_hero(db)
    var loaded: FxHero = db.select(FxHero).with("gear").first()
    loaded.gear.clear()
    assert_ok(db.sync_children(loaded, "gear"), db)
    assert_eq(db.select(FxGear).count(), 0)
    assert_eq(db.select(FxAffix).count(), 0)


func test_sync_children_refuses_a_relation_that_was_never_loaded() -> void:
    var db: Db = open_memory()
    _saved_hero(db)
    var found: FxHero = db.select(FxHero).first()
    assert_eq(found.gear.size(), 0)
    assert_failed(db.sync_children(found, "gear"), db, Db.ErrorKind.USAGE, "never loaded")
    assert_eq(db.select(FxGear).count(), 3, "nothing was wiped")
    found.mark_loaded("gear")
    assert_ok(db.sync_children(found, "gear"), db)
    assert_eq(db.select(FxGear).count(), 0)


func test_sync_children_on_unsaved_parent_is_an_error() -> void:
    var db: Db = open_memory()
    var hero: FxHero = make_hero("Unsaved")
    assert_failed(db.sync_children(hero, "gear"), db, Db.ErrorKind.USAGE, "save the FxHero before")


func test_sync_children_needs_a_to_many_or_to_one_relation() -> void:
    var db: Db = open_memory()
    var gear: FxGear = make_gear(&"x")
    assert_failed(
        db.sync_children(gear, "hero"),
        db,
        Db.ErrorKind.USAGE,
        "no has_many or has_one relation 'hero'",
    )


func test_sync_children_moves_a_child_from_another_parent() -> void:
    var db: Db = open_memory()
    var first: FxHero = _saved_hero(db)
    var second: FxHero = make_hero("Thief")
    db.insert(second)
    var stolen: FxGear = first.gear[0]
    stolen.hero = first
    second.gear.append(stolen)
    assert_ok(db.sync_children(second, "gear"), db)
    var moved: FxGear = db.find(FxGear, stolen.uid)
    assert_eq(moved.hero_id, second.id)
    assert_null(stolen.hero, "a stale back-reference is dropped instead of overwriting the key")


func test_save_tree_failure_late_in_the_tree_rolls_back_everything() -> void:
    var db: Db = open_memory()
    _saved_hero(db)
    var loaded: FxHero = db.select(FxHero).with("gear").with("equipped").first()
    loaded.gear[0].base_id = &"changed"
    loaded.display_name = "Renamed"
    var slot: FxEquipped = FxEquipped.new()
    slot.slot = 2
    slot.gear_uid = 5
    loaded.equipped.append(slot)
    assert_failed(
        db.save_tree(loaded, ["gear", "equipped"]),
        db,
        Db.ErrorKind.CONVERSION,
        "'gear_uid' expects String",
    )
    assert_eq(db.select(FxGear).where("base_id", "=", &"changed").count(), 0)
    assert_eq(db.select(FxHero).pluck("display_name"), ["Ada"])


func test_save_tree_saves_a_whole_new_graph() -> void:
    var db: Db = open_memory()
    var hero: FxHero = make_hero("Graph")
    hero.gear.append(make_gear(&"sword", [5.0, 6.0]))
    var quest: FxQuest = FxQuest.new()
    quest.quest_id = &"first"
    quest.counts = { "wolves": 3 }
    hero.quests.append(quest)
    var slot: FxEquipped = FxEquipped.new()
    slot.slot = 1
    slot.gear = hero.gear[0]
    hero.equipped.append(slot)
    var queries: int = count_queries(
        db,
        func() -> void:
            assert_ok(db.save_tree(hero, ["gear.affixes", "quests", "equipped.gear"]), db),
    )
    assert_gt(queries, 0)
    var found: FxHero = db \
        .select(FxHero) \
        .with("gear.affixes") \
        .with("quests") \
        .with("equipped.gear") \
        .first()
    assert_eq(found.gear[0].affixes.size(), 2)
    assert_eq(found.quests[0].counts["wolves"], 3)
    assert_eq(found.equipped[0].gear.base_id, &"sword")
    assert_eq(found.equipped[0].gear_uid, found.gear[0].uid)


func test_save_tree_twice_is_stable() -> void:
    var db: Db = open_memory()
    var hero: FxHero = _saved_hero(db)
    advance_clock(30)
    assert_ok(db.save_tree(hero, ["gear.affixes"]), db)
    assert_eq(db.select(FxGear).count(), 3)
    assert_eq(db.select(FxAffix).count(), 3)
    var found: FxHero = db.find(FxHero, hero.id)
    assert_eq(found.saved_unix, 1_030)
    assert_eq(found.created_unix, 1_000)


func test_save_tree_saves_belongs_to_targets_first() -> void:
    var db: Db = open_memory()
    var character: FxCharacter = make_character("Forger")
    character.weapon = make_item("New sword")
    assert_ok(db.save_tree(character, ["weapon"]), db)
    assert_ne(character.weapon.id, 0)
    var found: FxCharacter = db.select(FxCharacter).with("weapon").first()
    assert_eq(found.weapon.name, "New sword")


func test_save_tree_is_atomic() -> void:
    var db: Db = open_memory()
    db.insert(make_item("Taken"))
    var character: FxCharacter = make_character("Unlucky")
    character.weapon = make_item("Taken")
    assert_false(db.save_tree(character, ["weapon"]))
    expect_engine_errors("UNIQUE")
    assert_eq(db.select(FxCharacter).count(), 0)
    assert_eq(db.select(FxItem).count(), 1)


func test_save_tree_with_unknown_path_is_an_error() -> void:
    var db: Db = open_memory()
    var hero: FxHero = make_hero("Typo")
    assert_failed(db.save_tree(hero, ["gera"]), db, Db.ErrorKind.USAGE, "no relation 'gera'")
    assert_eq(db.select(FxHero).count(), 0)


func test_save_tree_with_bad_path_value() -> void:
    var db: Db = open_memory()
    assert_failed(db.save_tree(make_hero("X"), [3]), db, Db.ErrorKind.USAGE, "must be a String")


func test_save_tree_with_no_paths_is_a_save() -> void:
    var db: Db = open_memory()
    var hero: FxHero = make_hero("Solo")
    hero.gear.append(make_gear(&"ignored"))
    assert_ok(db.save_tree(hero), db)
    assert_eq(db.select(FxHero).count(), 1)
    assert_eq(db.select(FxGear).count(), 0)


func test_relation_loading_with_many_parents_uses_chunks() -> void:
    var db: Db = open_memory()
    var heroes: Array = []
    for i: int in 1_200:
        var hero: FxHero = make_hero("h%d" % i)
        hero.id = "hero-%04d" % i
        heroes.append(hero)
    assert_ok(db.insert_many(heroes), db)
    var gear: FxGear = make_gear(&"last")
    gear.hero_id = "hero-1199"
    db.insert(gear)
    var loaded: Array = db.select(FxHero).with("gear").all()
    assert_eq(loaded.size(), 1_200)
    var last: FxHero = loaded[-1]
    assert_eq(last.gear.size(), 1)
    var first: FxHero = loaded[0]
    assert_eq(first.gear.size(), 0)


func test_relation_children_point_back_through_string_name_keys() -> void:
    var db: Db = open_memory()
    var hero: FxHero = make_hero("Keys")
    hero.id = "abc"
    var quest: FxQuest = FxQuest.new()
    quest.quest_id = &"k"
    hero.quests.append(quest)
    assert_ok(db.save_tree(hero, ["quests"]), db)
    var found: FxHero = db.select(FxHero).with("quests").first()
    assert_eq(found.quests.size(), 1)


func _armed_character(db: Db, character_name: String, weapon: FxItem) -> FxCharacter:
    var character: FxCharacter = make_character(character_name)
    character.weapon = weapon
    assert_ok(db.insert(character), db)
    return character


func _saved_hero(db: Db) -> FxHero:
    var hero: FxHero = make_hero("Ada")
    hero.gear.append(make_gear(&"sword", [1.0, 2.0]))
    hero.gear.append(make_gear(&"shield", []))
    hero.gear.append(make_gear(&"ring", [3.0]))
    assert_ok(db.save_tree(hero, ["gear.affixes"]), db)
    return hero
