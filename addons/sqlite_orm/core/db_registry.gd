class_name DbRegistry
extends RefCounted
## Compiles model scripts into [DbTable]s and checks that they fit together.
## Not part of the public API.

const _MAX_TYPE_NAME_LOOKUP: int = TYPE_MAX

var tables: Dictionary[GDScript, DbTable] = { }
var by_table_name: Dictionary[String, DbTable] = { }
## Models in the order they were given.
var ordered: Array[DbTable] = []
var _schemas: Dictionary[GDScript, DbSchema] = { }
var _properties: Dictionary[GDScript, Dictionary] = { }
var _errors: PackedStringArray = []


static func _script_name(script: GDScript) -> String:
    if script == null:
        return "null"
    var global_name: String = script.get_global_name()
    if not global_name.is_empty():
        return global_name
    return script.resource_path.get_file()


## Compiles [param models]. Returns every problem found; empty when all is well.
func compile(models: Array) -> PackedStringArray:
    _errors.clear()
    for item: Variant in models:
        if not item is GDScript:
            _errors.append("model list holds %s, not a GDScript" % [item])
            continue
        var script: GDScript = item
        if tables.has(script):
            _errors.append("%s is in the model list twice" % _script_name(script))
            continue
        _compile_table(script)
    if not _errors.is_empty():
        return _errors
    for table: DbTable in ordered:
        _resolve_references(table)
    if not _errors.is_empty():
        return _errors
    for table: DbTable in ordered:
        _resolve_relations(table)
    for table: DbTable in ordered:
        _finish_indexes(table)
    return _errors


func table_for(model: Object) -> DbTable:
    if model == null:
        return null
    var script: Variant = model.get_script()
    if not script is GDScript:
        return null
    var gdscript: GDScript = script
    return tables.get(gdscript)


func table_for_script(script: GDScript) -> DbTable:
    return tables.get(script)


func _compile_table(script: GDScript) -> void:
    var label: String = _script_name(script)
    if not script.can_instantiate():
        _errors.append("%s cannot be instantiated" % label)
        return
    var instance: Object = script.new()
    if not instance is DbModel:
        _errors.append("%s does not extend DbModel" % label)
        return
    var schema: DbSchema = DbSchema.new()
    script.call("_schema", schema)
    _schemas[script] = schema
    for error: String in schema.errors:
        _errors.append("%s: %s" % [label, error])
    if schema.table_name.is_empty():
        _errors.append("%s: _schema() does not call s.table()" % label)
        return
    if by_table_name.has(schema.table_name):
        _errors.append(
            "%s and %s both use table '%s'"
            % [label, by_table_name[schema.table_name].model_name, schema.table_name]
        )
        return

    var table: DbTable = DbTable.new()
    table.model_script = script
    table.name = schema.table_name
    table.model_name = label

    var properties: Dictionary = { }
    for property: Dictionary in instance.get_property_list():
        var usage: int = property["usage"]
        if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
            var property_name: String = property["name"]
            properties[property_name] = property
    _properties[script] = properties

    var relation_vars: Array[String] = []
    for field: DbField in schema.fields.values():
        if not field.relation_name.is_empty():
            relation_vars.append(field.relation_name)
    for relation: DbRelation in schema.relations:
        relation_vars.append(relation.name)

    for field_name: String in schema.field_order:
        var field: DbField = schema.fields[field_name]
        for error: String in field.errors:
            _errors.append("%s: %s" % [label, error])
        if not properties.has(field_name):
            _errors.append("%s: s.field(\"%s\") has no matching var" % [label, field_name])
        elif field_name.begins_with("_") or field_name in schema.ignored:
            _errors.append("%s: '%s' is not a column but has s.field()" % [label, field_name])
        elif field_name in relation_vars:
            _errors.append("%s: '%s' is a relation but has s.field()" % [label, field_name])
    for ignored: String in schema.ignored:
        if not properties.has(ignored):
            _errors.append("%s: s.ignore(\"%s\") has no matching var" % [label, ignored])

    for property_name: String in properties:
        if property_name.begins_with("_") or property_name in schema.ignored:
            continue
        if property_name in relation_vars:
            continue
        var property: Dictionary = properties[property_name]
        var field: DbField = schema.fields.get(property_name, DbField.new(property_name))
        var column: DbColumn = _compile_column(label, field, property, instance)
        if column != null:
            table.columns.append(column)
            table.by_name[column.name] = column

    _compile_keys(label, table, schema)
    tables[script] = table
    by_table_name[table.name] = table
    ordered.append(table)


func _compile_column(
    label: String,
    field: DbField,
    property: Dictionary,
    instance: Object,
) -> DbColumn:
    var column: DbColumn = DbColumn.new()
    column.name = field.name
    var usage: int = property["usage"]
    var declared: int = property["type"]
    column.var_type = TYPE_NIL if usage & PROPERTY_USAGE_NIL_IS_VARIANT else declared
    if field.value_type != TYPE_NIL:
        if column.var_type != TYPE_NIL and column.var_type != field.value_type:
            _errors.append(
                "%s: '%s' is %s but .type() says %s"
                % [label, field.name, type_string(column.var_type), type_string(field.value_type)]
            )
            return null
        column.value_type = field.value_type
    else:
        column.value_type = column.var_type
    column.converter = field.custom_converter
    column.nullable = column.var_type == TYPE_NIL and not field.is_not_null
    column.primary_key = field.is_primary_key
    column.auto_increment = field.is_auto_increment
    column.uuid = field.is_uuid
    column.auto_created = field.is_auto_created
    column.auto_updated = field.is_auto_updated
    column.unique = field.is_unique
    column.indexed = field.is_indexed
    column.check_sql = field.check_sql
    column.reference_target = field.reference_target
    column.reference_column = field.reference_field
    column.on_delete = field.on_delete
    column.on_update_cascade = field.cascades_on_update

    var errors_before: int = _errors.size()
    var hint: int = property["hint"]
    var hint_string: String = property["hint_string"]
    if column.value_type == TYPE_ARRAY and hint == PROPERTY_HINT_ARRAY_TYPE:
        column.element_type = _element_type(label, field.name, hint_string)
    elif column.value_type == TYPE_DICTIONARY and hint == PROPERTY_HINT_DICTIONARY_TYPE:
        var pair: PackedStringArray = hint_string.split(";")
        column.key_type = _element_type(label, field.name, pair[0])
        column.dictionary_value_type = _element_type(
            label,
            field.name,
            pair[1] if pair.size() > 1 else "",
        )

    if _errors.size() > errors_before:
        return null

    # A foreign key on a Variant var takes its type from the target, once targets are compiled.
    var waits_for_target: bool = column.value_type == TYPE_NIL and column.reference_target != null
    if not waits_for_target:
        var error: String = column.resolve_kind()
        if not error.is_empty():
            _errors.append("%s: %s" % [label, error])
            return null

    if field.has_default:
        column.has_default = true
        column.default_value = field.default_value
    elif not column.nullable and not column.primary_key and column.converter == null:
        column.has_default = true
        column.default_value = instance.get(field.name)
    if not waits_for_target and not column.default_is_valid():
        _errors.append("%s: the default of '%s' cannot be stored" % [label, field.name])

    if column.auto_increment and column.value_type != TYPE_INT:
        _errors.append("%s: auto_increment() needs an int field, '%s' is not" % [label, field.name])
    if column.uuid and column.value_type not in [TYPE_STRING, TYPE_STRING_NAME]:
        _errors.append("%s: default_uuid() needs a String field, '%s' is not" % [label, field.name])
    if (column.auto_created or column.auto_updated) and column.value_type != TYPE_INT:
        _errors.append("%s: auto timestamps need an int field, '%s' is not" % [label, field.name])
    if column.on_delete == DbField.OnDelete.SET_NULL and not column.nullable:
        _errors.append(
            "%s: '%s' uses on_delete_set_null() but cannot hold null; declare it as Variant"
            % [label, field.name]
        )
    if field.on_delete != DbField.OnDelete.NO_ACTION and field.reference_target == null:
        _errors.append("%s: '%s' sets on_delete but references nothing" % [label, field.name])
    return column


## The Variant type for an element type name from a typed Array or Dictionary hint.
func _element_type(label: String, field_name: String, type_name: String) -> int:
    if type_name.is_empty() or type_name == "Variant":
        return TYPE_NIL
    # Typed containers of enums name the enum ("Class.Enum" or "res://path.gd.Enum").
    if type_name.contains("."):
        return TYPE_INT
    if type_name.contains(":"):
        return type_name.get_slice(":", 0).get_slice("/", 0).to_int()
    for variant_type: int in _MAX_TYPE_NAME_LOOKUP:
        if type_string(variant_type) == type_name:
            if variant_type == TYPE_OBJECT:
                break
            return variant_type
    _errors.append(
        "%s: '%s' holds %s elements, which cannot be stored; use a relation or a converter"
        % [label, field_name, type_name]
    )
    return TYPE_NIL


func _compile_keys(label: String, table: DbTable, schema: DbSchema) -> void:
    for column: DbColumn in table.columns:
        if column.primary_key:
            table.primary_key.append(column.name)
    if not schema.primary_key_fields.is_empty():
        if not table.primary_key.is_empty():
            _errors.append("%s: uses both s.primary_key() and .primary_key()" % label)
            return
        for key: String in schema.primary_key_fields:
            var column: DbColumn = table.column(key)
            if column == null:
                _errors.append("%s: primary key field '%s' is not a column" % [label, key])
                return
            column.primary_key = true
            table.primary_key.append(key)
    if table.primary_key.is_empty():
        _errors.append("%s: has no primary key" % label)
        return
    if table.primary_key.size() > 1:
        for key: String in table.primary_key:
            var column: DbColumn = table.column(key)
            if column.auto_increment:
                _errors.append("%s: auto_increment() needs a single-field primary key" % label)
            if column.nullable:
                _errors.append("%s: primary key field '%s' cannot be nullable" % [label, key])
    else:
        var key_column: DbColumn = table.column(table.primary_key[0])
        if key_column.nullable:
            _errors.append("%s: primary key '%s' cannot be nullable" % [label, key_column.name])
        if key_column.auto_increment:
            table.auto_key = key_column
    for column: DbColumn in table.columns:
        if column.auto_increment and not column.primary_key:
            _errors.append("%s: auto_increment() is only for the primary key" % label)

    for column: DbColumn in table.columns:
        if column.unique and not (column.primary_key and table.primary_key.size() == 1):
            _add_index(table, [column.name], true, label)
        if column.indexed:
            _add_index(table, [column.name], false, label)
    for fields: Array in schema.unique_sets:
        _add_index(table, _strings(fields), true, label)
    for fields: Array in schema.index_sets:
        _add_index(table, _strings(fields), false, label)


func _add_index(table: DbTable, index_columns: Array[String], unique: bool, label: String) -> void:
    if index_columns.is_empty():
        _errors.append("%s: an index needs at least one field" % label)
        return
    for column_name: String in index_columns:
        if not table.has_column(column_name):
            _errors.append("%s: index field '%s' is not a column" % [label, column_name])
            return
    if table.find_index(index_columns, unique) != null:
        return
    table.indexes.append(
        DbTable.IndexDef.new(table.name, index_columns, unique, "unique" if unique else "index")
    )


func _resolve_references(table: DbTable) -> void:
    for column: DbColumn in table.columns:
        if column.reference_target == null:
            continue
        var label: String = table.model_name
        var target: DbTable = tables.get(column.reference_target)
        if target == null:
            _errors.append(
                "%s: '%s' references %s, which is not in the model list"
                % [label, column.name, _script_name(column.reference_target)]
            )
            continue
        if column.reference_column.is_empty():
            if target.primary_key.size() != 1:
                _errors.append(
                    "%s: '%s' references %s, whose primary key has several fields"
                    % [label, column.name, target.model_name]
                )
                continue
            column.reference_column = target.primary_key[0]
        var target_column: DbColumn = target.column(column.reference_column)
        if target_column == null:
            _errors.append(
                "%s: '%s' references %s.%s, which is not a column"
                % [label, column.name, target.model_name, column.reference_column]
            )
            continue
        var target_is_key: bool = (
            target.primary_key == [target_column.name]
            or target.find_index([target_column.name], true) != null
        )
        if not target_is_key:
            _errors.append(
                "%s: '%s' references %s.%s, which is neither the primary key nor unique"
                % [label, column.name, target.model_name, target_column.name]
            )
        column.reference_table = target.name
        if column.value_type == TYPE_NIL:
            column.value_type = target_column.value_type
            if column.converter == null:
                column.converter = target_column.converter
            var error: String = column.resolve_kind()
            if not error.is_empty():
                _errors.append("%s: %s" % [label, error])
                continue
            if not column.default_is_valid():
                _errors.append("%s: the default of '%s' cannot be stored" % [label, column.name])
        elif column.sql_type != target_column.sql_type:
            _errors.append(
                "%s: '%s' is %s but %s.%s is %s"
                % [
                    label,
                    column.name,
                    column.sql_type,
                    target.model_name,
                    target_column.name,
                    target_column.sql_type,
                ]
            )


func _resolve_relations(table: DbTable) -> void:
    var label: String = table.model_name
    var schema: DbSchema = _schemas[table.model_script]
    var properties: Dictionary = _properties[table.model_script]
    var relations: Array[DbRelation] = []
    for field: DbField in schema.fields.values():
        if field.relation_name.is_empty() or not table.has_column(field.name):
            continue
        var column: DbColumn = table.column(field.name)
        var relation: DbRelation = DbRelation.new(
            DbRelation.Kind.BELONGS_TO,
            field.relation_name,
            field.reference_target,
            field.name,
        )
        relation.target_key = column.reference_column
        relations.append(relation)
    relations.append_array(schema.relations)

    for relation: DbRelation in relations:
        if table.relations.has(relation.name):
            _errors.append("%s: relation '%s' is declared twice" % [label, relation.name])
            continue
        var target: DbTable = tables.get(relation.target)
        if target == null:
            _errors.append(
                "%s: relation '%s' points at %s, which is not in the model list"
                % [label, relation.name, _script_name(relation.target)]
            )
            continue
        if not properties.has(relation.name):
            _errors.append("%s: relation '%s' has no matching var" % [label, relation.name])
            continue
        var property: Dictionary = properties[relation.name]
        if not _relation_var_fits(property, relation, target):
            _errors.append(
                "%s: var '%s' must be typed %s"
                % [
                    label,
                    relation.name,
                    ("Array[%s]" % target.model_name
                        if relation.is_to_many()
                        else target.model_name),
                ]
            )
            continue
        if relation.kind != DbRelation.Kind.BELONGS_TO:
            var key: DbColumn = target.column(relation.foreign_key)
            if key == null:
                _errors.append(
                    "%s: relation '%s' uses %s.%s, which is not a column"
                    % [label, relation.name, target.model_name, relation.foreign_key]
                )
                continue
            if key.reference_target != table.model_script:
                _errors.append(
                    "%s: relation '%s' needs %s.%s to reference %s"
                    % [label, relation.name, target.model_name, relation.foreign_key, label]
                )
                continue
            relation.target_key = key.reference_column
        for field_name: String in [relation.order_field, relation.position_field]:
            if not field_name.is_empty() and not target.has_column(field_name):
                _errors.append(
                    "%s: relation '%s' sorts by %s.%s, which is not a column"
                    % [label, relation.name, target.model_name, field_name]
                )
        if not relation.position_field.is_empty():
            var position: DbColumn = target.column(relation.position_field)
            if position != null and position.value_type != TYPE_INT:
                _errors.append(
                    "%s: relation '%s' position field must be an int" % [label, relation.name]
                )
        table.relations[relation.name] = relation


func _relation_var_fits(property: Dictionary, relation: DbRelation, target: DbTable) -> bool:
    var target_name: String = target.model_script.get_global_name()
    var declared: int = property["type"]
    if relation.is_to_many():
        var hint: int = property["hint"]
        var hint_string: String = property["hint_string"]
        return (
            declared == TYPE_ARRAY and hint == PROPERTY_HINT_ARRAY_TYPE
            and (target_name.is_empty() or hint_string == target_name)
        )
    var class_label: String = property["class_name"]
    return declared == TYPE_OBJECT and (target_name.is_empty() or class_label == target_name)


## Indexes every foreign key column unless an existing index already starts with it.
func _finish_indexes(table: DbTable) -> void:
    for column: DbColumn in table.columns:
        if column.reference_target == null:
            continue
        if table.primary_key[0] == column.name:
            continue
        var covered: bool = false
        for index: DbTable.IndexDef in table.indexes:
            if index.columns[0] == column.name:
                covered = true
                break
        if not covered:
            table.indexes.append(DbTable.IndexDef.new(table.name, [column.name], false, "index"))


func _strings(values: Array) -> Array[String]:
    var result: Array[String] = []
    for value: Variant in values:
        result.append(str(value))
    return result
