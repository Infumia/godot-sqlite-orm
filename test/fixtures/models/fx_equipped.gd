class_name FxEquipped
extends DbModel
## A paperdoll slot pointing at a gear item; deleting the item empties the slot.

var hero_id: String
var slot: int
var gear_uid: Variant
var gear: FxGear


static func _schema(s: DbSchema) -> void:
    s.table("equipped")
    s.primary_key(["hero_id", "slot"])
    s.field("hero_id").references(FxHero).on_delete_cascade()
    s.field("gear_uid").belongs_to("gear", FxGear).on_delete_set_null()
