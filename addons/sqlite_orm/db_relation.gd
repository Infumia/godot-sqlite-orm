class_name DbRelation
extends RefCounted
## A relation between two models. [method DbField.belongs_to] makes one on the side that holds
## the foreign key; [method DbSchema.has_many] and [method DbSchema.has_one] make the other side.

enum Kind {
    BELONGS_TO,
    HAS_MANY,
    HAS_ONE,
}

var kind: Kind
## The var on the model that holds the related row or rows.
var name: String
var target: GDScript
## BELONGS_TO: the column on this model. HAS_MANY / HAS_ONE: the column on [member target].
var foreign_key: String
## The key the foreign key points at. Filled in when the schema is compiled.
var target_key: String = ""
var order_field: String = ""
var order_descending: bool = false
var position_field: String = ""


func _init(relation_kind: Kind, relation_name: String, target_model: GDScript, key: String) -> void:
    kind = relation_kind
    name = relation_name
    target = target_model
    foreign_key = key


## Loads the related rows sorted by [param field]. Without it they come in primary key order.
func order_by(field: String, descending: bool = false) -> DbRelation:
    order_field = field
    order_descending = descending
    return self


## Keeps the list order: [method Db.sync_children] writes each child's index into
## [param field], and loading sorts by it.
func position(field: String) -> DbRelation:
    position_field = field
    return self


func is_to_many() -> bool:
    return kind == Kind.HAS_MANY
