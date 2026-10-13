extends DbModel
## Invalid on purpose: bad converter.

var id: int
var data: String


static func _schema(s: DbSchema) -> void:
    s.table("t_bad_conv")
    s.field("id").primary_key()
    s.field("data").converter(BadConverter.new())


class BadConverter:
    extends DbConverter

    func sql_type() -> String:
        return "JSON"
