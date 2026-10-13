class_name DbModel
extends RefCounted
## Base class of every model: one row of a table.
##
## Every typed var is a column. Describe the table in a static [code]_schema[/code]:
## [codeblock]
## class_name Item
## extends DbModel
##
## var id: int
## var name: String
##
## static func _schema(s: DbSchema) -> void:
##     s.table("items")
##     s.field("id").primary_key().auto_increment()
## [/codeblock]
## Vars whose name starts with "_" are not columns.

## True once the row is known to exist in the database: after it is loaded or saved.
var _db_persisted: bool = false
## True when the row came from a database read, so its relation vars start out unloaded.
var _db_read: bool = false
## Relation names whose vars were filled from the database or saved through it.
var _db_loaded: Dictionary[String, bool] = { }


## Describes the table. Every model overrides it.
static func _schema(_s: DbSchema) -> void:
    pass


## Whether the row is in the database: it was loaded or saved.
func is_persisted() -> bool:
    return _db_persisted


## Whether the relation var [param relation] holds what the database holds.
func is_loaded(relation: String) -> bool:
    return _db_loaded.has(relation)


## Declares the relation var [param relation] complete, so [method Db.sync_children] may
## delete rows it does not hold. Use it after filling a relation by hand on a loaded row.
func mark_loaded(relation: String) -> void:
    _db_loaded[relation] = true


## Called after the row's columns are read, before relations are loaded.
func _after_load() -> void:
    pass


## Called before the row is inserted, updated or saved.
func _before_save() -> void:
    pass
