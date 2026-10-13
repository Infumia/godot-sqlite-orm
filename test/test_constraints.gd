# GUT asserts take untyped arguments; Godot 4.7 flags every Variant passed to them.
@warning_ignore_start("unsafe_call_argument")
extends DbTestCase
## Unique fields alone and together, checks, NOT NULL and foreign keys.


func test_single_field_unique() -> void:
    var db: Db = open_memory()
    assert_ok(db.insert(_person("Ada", "Lovelace", "1")), db)
    assert_failed(
        db.insert(_person("Bob", "Builder", "1")),
        db,
        Db.ErrorKind.UNIQUE,
        "people.government_id",
    )
    expect_engine_errors("UNIQUE")


func test_fields_unique_together() -> void:
    var db: Db = open_memory()
    assert_ok(db.insert(_person("Ada", "Lovelace", "1")), db)
    assert_ok(db.insert(_person("Ada", "Byron", "2")), db, "same name, other surname")
    assert_ok(db.insert(_person("Bob", "Lovelace", "3")), db, "other name, same surname")
    assert_failed(
        db.insert(_person("Ada", "Lovelace", "4")),
        db,
        Db.ErrorKind.UNIQUE,
        "people.name, people.surname",
    )
    expect_engine_errors("UNIQUE")


func test_null_slips_through_a_unique_pair() -> void:
    var db: Db = open_memory()
    assert_ok(db.insert(_person("Ada", null, "1")), db)
    assert_ok(db.insert(_person("Ada", null, "2")), db, "SQLite treats NULLs as distinct")


func test_unique_violation_on_update() -> void:
    var db: Db = open_memory()
    db.insert(_person("Ada", "Lovelace", "1"))
    var other: FxPerson = _person("Bob", "Builder", "2")
    db.insert(other)
    other.name = "Ada"
    other.surname = "Lovelace"
    assert_failed(db.update(other), db, Db.ErrorKind.UNIQUE)
    expect_engine_errors("UNIQUE")
    var stored: FxPerson = db.find(FxPerson, other.id)
    assert_eq(stored.name, "Bob")


func test_indexes_exist_in_the_database() -> void:
    var db: Db = open_memory()
    var rows: Array[Dictionary] = db.raw("PRAGMA index_list('people')")
    var found: Dictionary = { }
    for row: Dictionary in rows:
        found[str(row["name"])] = DbSql.to_int(row["unique"])
    assert_eq(found.get("people_name_surname_unique"), 1)
    assert_eq(found.get("people_government_id_unique"), 1)
    assert_eq(found.get("people_surname_name_index"), 0)


func test_check_constraint_on_update() -> void:
    var db: Db = open_memory()
    var character: FxCharacter = make_character("Lvl")
    db.insert(character)
    character.level = -5
    assert_failed(db.update(character), db, Db.ErrorKind.CHECK, "CHECK constraint failed")
    expect_engine_errors("CHECK")


func test_string_check_constraint() -> void:
    var db: Db = open_memory()
    assert_failed(db.insert(make_hero("")), db, Db.ErrorKind.CHECK)
    expect_engine_errors("CHECK")


func test_not_null_through_raw_sql() -> void:
    var db: Db = open_memory()
    var ok: bool = db.execute("INSERT INTO items (name, damage) VALUES (NULL, 1)")
    assert_failed(ok, db, Db.ErrorKind.NOT_NULL)
    expect_engine_errors("NOT NULL")


func test_foreign_key_to_missing_row_fails() -> void:
    var db: Db = open_memory()
    var character: FxCharacter = make_character("Ghost holder")
    character.weapon_id = 999
    assert_failed(db.insert(character), db, Db.ErrorKind.FOREIGN_KEY)
    expect_engine_errors("FOREIGN KEY")


func test_foreign_key_on_composite_key_child() -> void:
    var db: Db = open_memory()
    var quest: FxQuest = FxQuest.new()
    quest.hero_id = "nobody"
    quest.quest_id = &"q"
    assert_failed(db.insert(quest), db, Db.ErrorKind.FOREIGN_KEY)
    expect_engine_errors("FOREIGN KEY")


func test_delete_cascades() -> void:
    var db: Db = open_memory()
    var hero: FxHero = make_hero("Cascade")
    hero.gear.append(make_gear(&"sword", [1, 2]))
    hero.gear.append(make_gear(&"shield", [3]))
    assert_ok(db.save_tree(hero, ["gear.affixes"]), db)
    assert_eq(db.select(FxAffix).count(), 3)
    assert_ok(db.delete(hero), db)
    assert_eq(db.select(FxGear).count(), 0)
    assert_eq(db.select(FxAffix).count(), 0, "cascades two levels down")


func test_delete_sets_null() -> void:
    var db: Db = open_memory()
    var sword: FxItem = make_item("Sword")
    db.insert(sword)
    var character: FxCharacter = make_character("Holder")
    character.weapon = sword
    db.insert(character)
    db.delete(sword)
    var found: FxCharacter = db.find(FxCharacter, character.id)
    assert_null(found.weapon_id)


func test_delete_restricted() -> void:
    var db: Db = open_memory()
    var guild: FxGuild = FxGuild.new()
    db.insert(guild)
    var member: FxMember = FxMember.new()
    member.guild_id = guild.id
    db.insert(member)
    assert_failed(db.delete(guild), db, Db.ErrorKind.FOREIGN_KEY)
    expect_engine_errors("FOREIGN KEY")
    db.delete(member)
    assert_ok(db.delete(guild), db)


func test_error_kinds_from_messages() -> void:
    assert_eq(Db._kind_of("UNIQUE constraint failed: t.a"), Db.ErrorKind.UNIQUE)
    assert_eq(Db._kind_of("FOREIGN KEY constraint failed"), Db.ErrorKind.FOREIGN_KEY)
    assert_eq(Db._kind_of("NOT NULL constraint failed: t.a"), Db.ErrorKind.NOT_NULL)
    assert_eq(Db._kind_of("CHECK constraint failed: a"), Db.ErrorKind.CHECK)
    assert_eq(Db._kind_of("PRIMARY KEY constraint failed"), Db.ErrorKind.CONSTRAINT)
    assert_eq(Db._kind_of("cannot store TEXT value in INTEGER column t.a"), Db.ErrorKind.CONVERSION)
    assert_eq(Db._kind_of("file is not a database"), Db.ErrorKind.CORRUPT)
    assert_eq(Db._kind_of("database disk image is malformed"), Db.ErrorKind.CORRUPT)
    assert_eq(Db._kind_of("database is locked"), Db.ErrorKind.BUSY)
    assert_eq(Db._kind_of("no such table: x"), Db.ErrorKind.SQL)


func _person(person_name: String, surname: Variant, government_id: String) -> FxPerson:
    var person: FxPerson = FxPerson.new()
    person.name = person_name
    person.surname = surname
    person.government_id = government_id
    return person
