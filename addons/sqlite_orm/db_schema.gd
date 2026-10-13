class_name DbSchema
extends RefCounted
## Describes a model's table. A model's static [code]_schema(s: DbSchema)[/code] receives one.
##
## Every typed var of the model is a column. Vars whose name starts with "_" are not, and
## neither are relation vars or vars passed to [method ignore].

var table_name: String = ""
var fields: Dictionary[String, DbField] = { }
var field_order: Array[String] = []
var primary_key_fields: Array[String] = []
var unique_sets: Array[Array] = []
var index_sets: Array[Array] = []
var ignored: Array[String] = []
var relations: Array[DbRelation] = []
var errors: PackedStringArray = []


## The table's name in the database.
func table(name: String) -> void:
    table_name = name


## Settings for the column of the var named [param name]. Calling it twice returns the
## same field.
func field(name: String) -> DbField:
    if not fields.has(name):
        fields[name] = DbField.new(name)
        field_order.append(name)
    return fields[name]


## A primary key made of several fields together.
func primary_key(field_names: Array[String]) -> void:
    if not primary_key_fields.is_empty():
        errors.append("primary_key() is called twice")
    primary_key_fields = field_names.duplicate()


## No two rows may hold the same values in all of [param field_names] together.
func unique(field_names: Array[String]) -> void:
    unique_sets.append(field_names.duplicate())


## An index over [param field_names], in that order.
func index(field_names: Array[String]) -> void:
    index_sets.append(field_names.duplicate())


## Keeps the var named [param name] out of the table.
func ignore(name: String) -> void:
    ignored.append(name)


## The var [param name], typed [code]Array[Model][/code], holds every [param model] row whose
## [param foreign_key] field points at this row.
func has_many(name: String, model: GDScript, foreign_key: String) -> DbRelation:
    var relation: DbRelation = DbRelation.new(DbRelation.Kind.HAS_MANY, name, model, foreign_key)
    relations.append(relation)
    return relation


## Like [method has_many] for at most one row: the var [param name] is typed as [param model].
func has_one(name: String, model: GDScript, foreign_key: String) -> DbRelation:
    var relation: DbRelation = DbRelation.new(DbRelation.Kind.HAS_ONE, name, model, foreign_key)
    relations.append(relation)
    return relation
