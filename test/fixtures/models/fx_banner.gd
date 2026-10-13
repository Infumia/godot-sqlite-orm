class_name FxBanner
extends DbModel
## At most one per hero (has_one).

var id: int
var hero_id: String
var motto: String


static func _schema(s: DbSchema) -> void:
    s.table("banners")
    s.field("id").primary_key().auto_increment()
    s.field("hero_id").references(FxHero).on_delete_cascade().unique()
