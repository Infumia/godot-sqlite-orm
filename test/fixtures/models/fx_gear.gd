class_name FxGear
extends DbModel
## An item instance in a hero's bag, with affix rolls as children.

enum Rarity {
    COMMON,
    MAGIC,
    RARE,
}

var uid: String
var hero_id: Variant
var hero: FxHero
var slot_index: int = 0
var base_id: StringName
var rarity: Rarity = Rarity.COMMON
var affixes: Array[FxAffix] = []


static func _schema(s: DbSchema) -> void:
    s.table("gear")
    s.field("uid").primary_key().default_uuid()
    s.field("hero_id").belongs_to("hero", FxHero).on_delete_cascade()
    s.has_many("affixes", FxAffix, "gear_uid").position("position")
