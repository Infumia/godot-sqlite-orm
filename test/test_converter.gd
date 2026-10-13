# GUT asserts take untyped arguments; Godot 4.7 flags every Variant passed to them.
@warning_ignore_start("unsafe_call_argument")
extends DbTestCase
## Custom converters and the default JSON storage of other types.


func test_custom_converter_round_trip() -> void:
    var db: Db = open_memory()
    var paint: FxPaint = FxPaint.new()
    paint.color = Color8(255, 128, 0)
    paint.shade = Color(0.25, 0.25, 0.25, 0.5)
    assert_ok(db.insert(paint), db)
    var rows: Array[Dictionary] = db.raw("SELECT color, accent FROM paints")
    assert_eq(str(rows[0]["color"]), "ff8000ff")
    var stored_accent: Variant = rows[0]["accent"]
    assert_null(stored_accent, "a nullable converter field stores null without the converter")
    var found: FxPaint = db.find(FxPaint, paint.id)
    assert_eq(found.color, Color8(255, 128, 0))
    assert_eq(
        found.shade,
        Color(0.25, 0.25, 0.25, 0.5),
        "a Color without converter goes through JSON",
    )
    var accent: Variant = found.accent
    assert_null(accent)


func test_nullable_converter_field_with_value() -> void:
    var db: Db = open_memory()
    var paint: FxPaint = FxPaint.new()
    paint.accent = Color.BLUE
    db.insert(paint)
    var found: FxPaint = db.find(FxPaint, paint.id)
    var accent: Color = found.accent
    assert_true(accent.is_equal_approx(Color.BLUE))


func test_converter_failure_on_load_is_a_conversion_error() -> void:
    var db: Db = open_memory()
    var paint: FxPaint = FxPaint.new()
    db.insert(paint)
    db.execute("UPDATE paints SET color = 'not-a-color'")
    assert_null(db.find(FxPaint, paint.id))
    assert_eq(db.last_error_kind(), Db.ErrorKind.CONVERSION)
    assert_string_contains(db.last_error(), "'not-a-color' is not a color")


func test_converter_column_uses_its_sql_type() -> void:
    var db: Db = open_memory()
    var rows: Array[Dictionary] = db.raw(
        "SELECT type FROM pragma_table_info('paints') WHERE name = 'color'"
    )
    assert_eq(str(rows[0]["type"]), "TEXT")


func test_where_uses_the_converter() -> void:
    var db: Db = open_memory()
    var paint: FxPaint = FxPaint.new()
    paint.color = Color.RED
    db.insert(paint)
    assert_eq(db.select(FxPaint).where("color", "=", Color.RED).count(), 1)
    assert_eq(db.select(FxPaint).where("color", "=", Color.GREEN).count(), 0)


func test_converter_error_message_is_cleared_after_reading() -> void:
    var converter: FxHexColorConverter = FxHexColorConverter.new()
    converter.from_sql("zz")
    assert_ne(converter.take_error(), "")
    assert_eq(converter.take_error(), "")


func test_base_converter_is_identity() -> void:
    var converter: DbConverter = DbConverter.new()
    assert_eq(converter.sql_type(), "TEXT")
    var stored: Variant = converter.to_sql("x")
    var loaded: Variant = converter.from_sql("y")
    var failed: Variant = converter.fail("bad")
    assert_eq(stored, "x")
    assert_eq(loaded, "y")
    assert_null(failed)
    assert_eq(converter.take_error(), "bad")
