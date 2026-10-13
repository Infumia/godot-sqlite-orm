class_name DbSchemaCheck
extends RefCounted
## Compares the compiled models with the tables in the database. Not part of the public API.

const ON_DELETE_NAMES: Dictionary[DbField.OnDelete, String] = {
    DbField.OnDelete.NO_ACTION: "NO ACTION",
    DbField.OnDelete.CASCADE: "CASCADE",
    DbField.OnDelete.SET_NULL: "SET NULL",
    DbField.OnDelete.RESTRICT: "RESTRICT",
}

var _db: Db


func _init(db: Db) -> void:
    _db = db


## Every difference found, one line each; empty when the models match.
func run() -> PackedStringArray:
    var problems: PackedStringArray = []
    for table: DbTable in _db._registry.ordered:
        _check_table(table, problems)
    _db._clear_error()
    return problems


func _check_table(table: DbTable, problems: PackedStringArray) -> void:
    var label: String = "%s (table '%s')" % [table.model_name, table.name]
    var info: Array[Dictionary] = _db._rows("PRAGMA table_xinfo(%s)" % DbSql.ident(table.name))
    if info.is_empty():
        problems.append("%s: the table does not exist; a migration must create it" % label)
        return
    var found: Dictionary = { }
    for row: Dictionary in info:
        found[str(row["name"])] = row
    for column: DbColumn in table.columns:
        if not found.has(column.name):
            problems.append("%s: column '%s' is missing" % [label, column.name])
            continue
        var row: Dictionary = found[column.name]
        var stored_type: String = str(row["type"]).to_upper()
        if stored_type != column.sql_type:
            problems.append(
                "%s: column '%s' is %s, the model says %s"
                % [label, column.name, stored_type, column.sql_type]
            )
        var not_null: bool = DbSql.to_int(row["notnull"]) == 1
        var expect_not_null: bool = not column.nullable
        if not_null != expect_not_null:
            problems.append(
                "%s: column '%s' is %s, the model says %s"
                % [
                    label,
                    column.name,
                    "NOT NULL" if not_null else "nullable",
                    "NOT NULL" if expect_not_null else "nullable",
                ]
            )
        var key_position: int = DbSql.to_int(row["pk"])
        var expected_position: int = table.primary_key.find(column.name) + 1
        if key_position != expected_position:
            problems.append(
                "%s: column '%s' has a different primary key role" % [label, column.name]
            )
    for column_name: String in found:
        if not table.has_column(column_name):
            problems.append("%s: column '%s' is not in the model" % [label, column_name])
    _check_foreign_keys(table, label, problems)
    _check_indexes(table, label, problems)


func _check_foreign_keys(table: DbTable, label: String, problems: PackedStringArray) -> void:
    var keys: Dictionary = { }
    for row: Dictionary in _db._rows("PRAGMA foreign_key_list(%s)" % DbSql.ident(table.name)):
        keys[str(row["from"])] = row
    for column: DbColumn in table.columns:
        var has_key: bool = keys.has(column.name)
        if column.reference_target == null:
            if has_key:
                problems.append(
                    "%s: column '%s' is a foreign key, the model says not" % [label, column.name]
                )
            continue
        if not has_key:
            problems.append("%s: column '%s' is not a foreign key" % [label, column.name])
            continue
        var row: Dictionary = keys[column.name]
        var target: String = "%s.%s" % [row["table"], row["to"]]
        var expected: String = "%s.%s" % [column.reference_table, column.reference_column]
        if target != expected:
            problems.append(
                "%s: column '%s' references %s, the model says %s"
                % [label, column.name, target, expected]
            )
        var on_delete: String = str(row["on_delete"]).to_upper()
        if on_delete != ON_DELETE_NAMES[column.on_delete]:
            problems.append(
                "%s: column '%s' is ON DELETE %s, the model says %s"
                % [label, column.name, on_delete, ON_DELETE_NAMES[column.on_delete]]
            )


func _check_indexes(table: DbTable, label: String, problems: PackedStringArray) -> void:
    var indexes: Dictionary = { }
    for row: Dictionary in _db._rows("PRAGMA index_list(%s)" % DbSql.ident(table.name)):
        if str(row["origin"]) == "c":
            indexes[str(row["name"])] = DbSql.to_int(row["unique"]) == 1
    for index: DbTable.IndexDef in table.indexes:
        if not indexes.has(index.name):
            problems.append("%s: index '%s' is missing" % [label, index.name])
            continue
        if indexes[index.name] != index.unique:
            problems.append("%s: index '%s' has a different unique flag" % [label, index.name])
            continue
        var columns: Array[String] = []
        for row: Dictionary in _db._rows("PRAGMA index_info(%s)" % DbSql.ident(index.name)):
            columns.append(str(row["name"]))
        if columns != index.columns:
            problems.append(
                "%s: index '%s' covers %s, the model says %s"
                % [label, index.name, columns, index.columns]
            )
    for index_name: String in indexes:
        if table.indexes.all(
            func(index: DbTable.IndexDef) -> bool:
                return index.name != index_name,
        ):
            problems.append("%s: index '%s' is not in the model" % [label, index_name])
