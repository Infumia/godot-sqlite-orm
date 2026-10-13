class_name FxAffix
extends DbModel
## One rolled affix of a gear item.

var id: int
var gear_uid: String
var affix_id: StringName
var value: float = 0.0
var position: int = 0


static func _schema(s: DbSchema) -> void:
    s.table("affixes")
    s.field("id").primary_key().auto_increment()
    s.field("gear_uid").references(FxGear).on_delete_cascade()
