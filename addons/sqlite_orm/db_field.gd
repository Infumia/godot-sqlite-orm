class_name DbField
extends RefCounted
## Settings for one column, made by [method DbSchema.field] inside a model's [code]_schema[/code].
## Every method returns the field, so calls chain.

enum OnDelete {
    NO_ACTION,
    CASCADE,
    SET_NULL,
    RESTRICT,
}

var name: String
var is_primary_key: bool = false
var is_auto_increment: bool = false
var is_not_null: bool = false
var is_unique: bool = false
var is_indexed: bool = false
var has_default: bool = false
var default_value: Variant = null
var value_type: int = TYPE_NIL
var check_sql: String = ""
var custom_converter: DbConverter = null
var is_uuid: bool = false
var is_auto_created: bool = false
var is_auto_updated: bool = false
var reference_target: GDScript = null
var reference_field: String = ""
var relation_name: String = ""
var on_delete: OnDelete = OnDelete.NO_ACTION
var cascades_on_update: bool = false
var errors: PackedStringArray = []


func _init(field_name: String) -> void:
    name = field_name


## Makes this the table's primary key. For a key over several fields use
## [method DbSchema.primary_key].
func primary_key() -> DbField:
    is_primary_key = true
    return self


## Lets SQLite pick the key: an [code]int[/code] primary key left at 0 gets the next id on
## insert, and ids of deleted rows are never reused.
func auto_increment() -> DbField:
    is_auto_increment = true
    return self


## Forbids NULL. Only needed on a [code]Variant[/code] field; a typed field cannot hold null
## and is always NOT NULL.
func not_null() -> DbField:
    is_not_null = true
    return self


## No two rows may hold the same value.
func unique() -> DbField:
    is_unique = true
    return self


## Adds an index on this field alone. Foreign keys get one without asking.
func index() -> DbField:
    is_indexed = true
    return self


## The value stored when a row is inserted without this column, such as a column a migration
## adds to existing rows. Typed fields default to their initial value without this call.
func default(value: Variant) -> DbField:
    has_default = true
    default_value = value
    return self


## The stored type of a [code]Variant[/code] field, as a [enum Variant.Type] constant.
func type(variant_type: int) -> DbField:
    value_type = variant_type
    return self


## A CHECK constraint on this column. [param condition] is SQL that follows the column name,
## such as [code]">= 1"[/code] or [code]"BETWEEN 0 AND 100"[/code].
func check(condition: String) -> DbField:
    check_sql = condition
    return self


## Stores the field through [param value_converter] instead of the built-in conversion.
func converter(value_converter: DbConverter) -> DbField:
    custom_converter = value_converter
    return self


## Fills an empty String key with a random UUID on insert.
func default_uuid() -> DbField:
    is_uuid = true
    return self


## Sets the field to the current Unix time when the row is inserted, if it is still 0.
func auto_created() -> DbField:
    is_auto_created = true
    return self


## Sets the field to the current Unix time on every insert and update.
func auto_updated() -> DbField:
    is_auto_updated = true
    return self


## Makes this column a foreign key to [param model]'s primary key, or to [param field] when
## given. The target field must be the primary key or unique.
func references(model: GDScript, field: String = "") -> DbField:
    if reference_target != null:
        errors.append("'%s' already references a model" % name)
    reference_target = model
    reference_field = field
    return self


## Like [method references], and also binds the model's [param relation] var, typed as
## [param model], to the row this key points at. See [method Db.load] and [method DbQuery.with].
func belongs_to(relation: String, model: GDScript) -> DbField:
    references(model)
    relation_name = relation
    return self


## The target field of [method belongs_to], when it is not the primary key.
func to(field: String) -> DbField:
    reference_field = field
    return self


## Deleting the target row deletes this row too.
func on_delete_cascade() -> DbField:
    on_delete = OnDelete.CASCADE
    return self


## Deleting the target row sets this column to NULL. The field must be nullable.
func on_delete_set_null() -> DbField:
    on_delete = OnDelete.SET_NULL
    return self


## The target row cannot be deleted while this row points at it, even inside a transaction.
func on_delete_restrict() -> DbField:
    on_delete = OnDelete.RESTRICT
    return self


## Changing the target key updates this column to match.
func on_update_cascade() -> DbField:
    cascades_on_update = true
    return self
