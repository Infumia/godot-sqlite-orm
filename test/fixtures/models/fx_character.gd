class_name FxCharacter
extends DbModel
## A character that may hold a weapon (belongs_to with ON DELETE SET NULL).

var id: int
var name: String
var level: int = 1
var weapon_id: Variant
var weapon: FxItem
var saves: int = 0
var loads: int = 0


static func _schema(s: DbSchema) -> void:
    s.table("characters")
    s.field("id").primary_key().auto_increment()
    s.field("level").check(">= 1")
    s.field("weapon_id").belongs_to("weapon", FxItem).on_delete_set_null()
    s.ignore("saves")
    s.ignore("loads")


func _before_save() -> void:
    saves += 1


func _after_load() -> void:
    loads += 1
