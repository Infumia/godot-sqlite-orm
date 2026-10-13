# GUT asserts take untyped arguments; Godot 4.7 flags every Variant passed to them.
@warning_ignore_start("unsafe_call_argument")
extends DbTestCase
## The model helper generator and the helpers it generated for the fixture models.

var _saved_output_dir: Variant = null


func after_each() -> void:
    if _saved_output_dir != null:
        ProjectSettings.set_setting(DbCodegen.OUTPUT_DIR_SETTING, _saved_output_dir)
        _saved_output_dir = null
    super()


func test_committed_helpers_are_up_to_date() -> void:
    var report: DbCodegen.Report = DbCodegen.run(true)
    assert_eq(report.errors, PackedStringArray())
    assert_eq(report.changed, PackedStringArray(), "run the generator and commit the result")
    assert_eq(report.removed, PackedStringArray())
    assert_true(report.is_current())


func test_command_line_check_passes() -> void:
    var output: Array = []
    var code: int = OS.execute(
        OS.get_executable_path(),
        [
            "--headless",
            "--path",
            ProjectSettings.globalize_path("res://"),
            "--script",
            "res://addons/sqlite_orm/generator/generate.gd",
            "--",
            "--check",
        ],
        output,
        true,
    )
    assert_eq(code, 0, "\n".join(output))
    assert_string_contains("\n".join(output), "helpers are up to date")


func test_models_are_found_by_class_and_folder() -> void:
    var models: Array[GDScript] = DbCodegen.find_models(DbCodegen.exclude_setting())
    assert_has(models, FxCharacter)
    assert_has(models, FxQuest)
    assert_does_not_have(models, MgPlayerV1, "excluded folder")
    assert_does_not_have(models, CgClash, "excluded folder")
    var everything: Array[GDScript] = DbCodegen.find_models(PackedStringArray())
    assert_has(everything, MgPlayerV1)


func test_check_mode_reports_missing_stale_and_orphaned_files() -> void:
    var output: String = _use_scratch_output()
    var model_count: int = DbCodegen.find_models(DbCodegen.exclude_setting()).size()
    var missing: DbCodegen.Report = DbCodegen.run(true)
    assert_eq(missing.changed.size(), model_count)
    assert_false(DirAccess.dir_exists_absolute(output), "check mode writes nothing")
    var written: DbCodegen.Report = DbCodegen.run(false)
    assert_eq(written.changed.size(), model_count)
    assert_true(DbCodegen.run(true).is_current())

    var stale_path: String = output.path_join("fx_item_db.gd")
    var stale: FileAccess = FileAccess.open(stale_path, FileAccess.READ_WRITE)
    stale.seek_end()
    stale.store_string("# edited by hand\n")
    stale.close()
    var orphan_path: String = output.path_join("fx_gone_db.gd")
    var orphan: FileAccess = FileAccess.open(orphan_path, FileAccess.WRITE)
    orphan.store_string(DbCodegen.MARKER + " from res://gone.gd.\n")
    orphan.close()
    var mine_path: String = output.path_join("hand_written.gd")
    var mine: FileAccess = FileAccess.open(mine_path, FileAccess.WRITE)
    mine.store_string("extends RefCounted\n")
    mine.close()

    var check: DbCodegen.Report = DbCodegen.run(true)
    assert_eq(check.changed, PackedStringArray([stale_path]))
    assert_eq(check.removed, PackedStringArray([orphan_path]))
    assert_false(check.is_current())
    DbCodegen.run(false)
    assert_true(DbCodegen.run(true).is_current())
    assert_false(FileAccess.file_exists(orphan_path))
    assert_true(FileAccess.file_exists(mine_path), "files without the marker are left alone")


func test_generation_is_deterministic() -> void:
    var models: Array[GDScript] = DbCodegen.find_models(DbCodegen.exclude_setting())
    var first: Dictionary = DbCodegen.build(models, "res://out")
    var second: Dictionary = DbCodegen.build(models, "res://out")
    assert_eq(first, second)


func test_name_clash_is_an_error() -> void:
    var built: Dictionary = DbCodegen.build([CgClash], "res://out")
    var errors: PackedStringArray = built["errors"]
    assert_eq(errors.size(), 1)
    assert_string_contains(errors[0], "'where_group' (from field 'group' and the query itself)")


func test_key_field_named_db_is_an_error() -> void:
    var built: Dictionary = DbCodegen.build([CgDbKey], "res://out")
    assert_string_contains("\n".join(built["errors"]), "key field 'db'")


func test_model_without_class_name_is_an_error() -> void:
    var built: Dictionary = DbCodegen.build(
        [load("res://test/fixtures/codegen/cg_unnamed.gd")],
        "res://out",
    )
    assert_string_contains("\n".join(built["errors"]), "has no class_name")


func test_invalid_models_report_compile_errors() -> void:
    var built: Dictionary = DbCodegen.build(
        [load("res://test/fixtures/invalid/inv_no_key.gd")],
        "res://out",
    )
    assert_string_contains("\n".join(built["errors"]), "has no primary key")


func test_output_file_names() -> void:
    var built: Dictionary = DbCodegen.build([FxItem], "res://out/")
    var files: Dictionary = built["files"]
    assert_has(files.keys(), "res://out/fx_item_db.gd")


func test_type_texts_of_columns() -> void:
    var registry: DbRegistry = DbRegistry.new()
    registry.compile(all_models())
    var item: DbTable = registry.table_for_script(FxItem)
    assert_eq(item.column("rarity").type_text, "FxItem.Rarity")
    assert_eq(item.column("tags").type_text, "Array[StringName]")
    assert_eq(item.column("stats").type_text, "Dictionary[String, int]")
    assert_eq(item.column("notes").type_text, "Array")
    assert_eq(item.column("grid_cell").type_text, "Vector2i")
    assert_eq(item.column("description").type_text, "Variant")
    assert_eq(item.column("kind").type_text, "StringName")


func test_long_signatures_are_wrapped() -> void:
    var out: PackedStringArray = []
    var params: PackedStringArray = ["op: String", "value: " + "VeryLongTypeName".repeat(6)]
    DbCodegen._emit_signature(out, "    func where_x", params, "Query", "    ")
    assert_eq(out[0], "    func where_x(")
    assert_eq(out[1], "        op: String,")
    assert_eq(out[3], "    ) -> Query:")
    var short: PackedStringArray = []
    DbCodegen._emit_signature(short, "func f", ["a: int"], "int", "")
    assert_eq(short, PackedStringArray(["func f(a: int) -> int:"]))


func test_operator_constants() -> void:
    assert_eq(Db.EQ, "=")
    assert_eq(Db.NE, "!=")
    assert_eq(Db.GTE, ">=")
    assert_eq(Db.NOT_LIKE, "NOT LIKE")
    assert_eq(Db.IS_NOT, "IS NOT")
    for op: String in [
        Db.EQ,
        Db.NE,
        Db.LT,
        Db.LTE,
        Db.GT,
        Db.GTE,
        Db.LIKE,
        Db.NOT_LIKE,
        Db.GLOB,
        Db.NOT_GLOB,
        Db.IS,
        Db.IS_NOT,
    ]:
        assert_has(DbWhere.OPERATORS, op)


func test_field_and_relation_constants() -> void:
    assert_eq(FxCharacterDb.Field.LEVEL, &"level")
    assert_eq(FxCharacterDb.Field.WEAPON_ID, &"weapon_id")
    assert_eq(FxCharacterDb.Rel.WEAPON, "weapon")
    assert_eq(FxHeroDb.Rel.GEAR, "gear")


func test_find_is_typed_for_every_key_kind() -> void:
    var db: Db = open_memory()
    var item: FxItem = make_item("Found")
    db.insert(item)
    var found_item: FxItem = FxItemDb.find(db, item.id)
    assert_eq(found_item.name, "Found")
    var hero: FxHero = make_hero("Uuid")
    db.insert(hero)
    assert_eq(FxHeroDb.find(db, hero.id).display_name, "Uuid")
    var quest: FxQuest = FxQuest.new()
    quest.hero_id = hero.id
    quest.quest_id = &"q1"
    db.insert(quest)
    assert_not_null(FxQuestDb.find(db, hero.id, &"q1"))
    assert_null(FxQuestDb.find(db, hero.id, &"nope"))


func test_typed_query_results() -> void:
    var db: Db = open_memory()
    _seed(db)
    var rows: Array[FxCharacter] = FxCharacterDb.query(db).where_level(Db.GTE, 20).all()
    assert_eq(rows.size(), 2)
    assert_true(rows.is_typed())
    assert_eq(rows.get_typed_script(), FxCharacter)
    var first: FxCharacter = FxCharacterDb.query(db).order_by_level(Db.DESC).first()
    assert_eq(first.name, "Cid")
    assert_null(FxCharacterDb.query(db).where_name(Db.EQ, "Zed").first())


func test_where_helpers() -> void:
    var db: Db = open_memory()
    _seed(db)
    var query: FxCharacterDb.Query = FxCharacterDb.query(db)
    assert_eq(query.where_level_in([10, 30]).count(), 2)
    assert_eq(FxCharacterDb.query(db).where_level_not_in([10]).count(), 2)
    assert_eq(FxCharacterDb.query(db).where_level_between(15, 35).count(), 2)
    assert_eq(
        FxCharacterDb.query(db).where_name(Db.LIKE, "A%").or_where_name(Db.EQ, "Cid").count(),
        2,
    )
    assert_eq(FxCharacterDb.query(db).where_weapon_id_null().count(), 3)
    assert_eq(FxCharacterDb.query(db).where_weapon_id_not_null().count(), 0)
    assert_eq(FxCharacterDb.query(db).where_level(Db.GT, 25).or_where_weapon_id_null().count(), 3)
    assert_eq(FxCharacterDb.query(db).where_name_in(["Ada", "Bob"]).count(), 2)


func test_enum_string_name_and_bool_helpers() -> void:
    var db: Db = open_memory()
    var rare: FxItem = make_item("Rare")
    rare.rarity = FxItem.Rarity.RARE
    rare.kind = &"ring"
    rare.tradable = false
    db.insert(rare)
    db.insert(make_item("Common"))
    assert_eq(FxItemDb.query(db).where_rarity(Db.EQ, FxItem.Rarity.RARE).count(), 1)
    var rarities: Array[FxItem.Rarity] = [FxItem.Rarity.RARE, FxItem.Rarity.LEGENDARY]
    assert_eq(FxItemDb.query(db).where_rarity_in(rarities).count(), 1)
    assert_eq(FxItemDb.query(db).where_kind(Db.EQ, &"ring").count(), 1)
    assert_eq(FxItemDb.query(db).where_tradable(Db.EQ, false).count(), 1)


func test_typed_pluck() -> void:
    var db: Db = open_memory()
    _seed(db)
    var levels: Array[int] = FxCharacterDb.query(db).order_by_level().pluck_level()
    assert_eq(levels, [10, 20, 30] as Array[int])
    var item: FxItem = make_item("Plucked")
    item.kind = &"gem"
    item.tags = [&"x"]
    db.insert(item)
    var kinds: Array[StringName] = FxItemDb.query(db).pluck_kind()
    assert_eq(kinds, [&"gem"] as Array[StringName])
    assert_eq(FxItemDb.query(db).pluck_tags(), [[&"x"]])


func test_relation_helpers_and_nested_paths() -> void:
    var db: Db = open_memory()
    var hero: FxHero = make_hero("Nested")
    hero.gear.append(make_gear(&"sword", [1.0, 2.0]))
    db.save_tree(hero, [FxHeroDb.Rel.GEAR + "." + FxGearDb.Rel.AFFIXES])
    var found: FxHero = FxHeroDb.query(db).with_gear(FxGearDb.Rel.AFFIXES).first()
    assert_eq(found.gear[0].affixes.size(), 2)
    var sword: FxItem = make_item("Sword")
    db.insert(sword)
    var character: FxCharacter = make_character("Armed")
    character.weapon = sword
    db.insert(character)
    var loaded: FxCharacter = FxCharacterDb.query(db).with_weapon().first()
    assert_eq(loaded.weapon.name, "Sword")


func test_generic_passthrough_methods() -> void:
    var db: Db = open_memory()
    _seed(db)
    var grouped: FxCharacterDb.Query = FxCharacterDb.query(db).where_group(
        func(w: DbWhere) -> void:
            w.where("name", Db.EQ, "Ada").or_where("name", Db.EQ, "Bob"),
    )
    assert_eq(grouped.count(), 2)
    assert_eq(FxCharacterDb.query(db).where_raw("level > ?", [15]).count(), 2)
    assert_eq(FxCharacterDb.query(db).order_by_level().limit(1).offset(1).first().name, "Bob")
    assert_true(FxCharacterDb.query(db).where_name(Db.EQ, "Ada").exists())
    assert_string_contains(FxCharacterDb.query(db).where_level(Db.GT, 1).to_sql(), "\"level\" > ?")
    assert_eq(FxCharacterDb.query(db).db_query().count(), 3)


func test_helper_errors_surface_on_the_database() -> void:
    var db: Db = open_memory()
    assert_eq(FxCharacterDb.query(db).where_level("===", 1).all(), [] as Array[FxCharacter])
    assert_string_contains(db.last_error(), "unknown operator")


func _seed(db: Db) -> void:
    for spec: Array in [["Ada", 10], ["Bob", 20], ["Cid", 30]]:
        var level: int = spec[1]
        assert_ok(db.insert(make_character(str(spec[0]), level)), db)


func _use_scratch_output() -> String:
    _saved_output_dir = ProjectSettings.get_setting(DbCodegen.OUTPUT_DIR_SETTING)
    var output: String = scratch_path("generated")
    ProjectSettings.set_setting(DbCodegen.OUTPUT_DIR_SETTING, output)
    return output
