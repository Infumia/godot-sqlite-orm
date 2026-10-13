class_name DbRelationIO
extends RefCounted
## Loads and saves relations for [Db]. Not part of the public API.


## Loads every relation path in [param paths] ("inventory.affixes") onto [param models].
static func load_paths(db: Db, models: Array, paths: Array) -> bool:
    var tree: Dictionary = { }
    if not _build_tree(db, paths, tree):
        return false
    return _load_tree(db, models, tree)


## Saves [param model] with the relations in [param paths]; runs inside a transaction.
static func save_tree(db: Db, model: DbModel, paths: Array) -> bool:
    var tree: Dictionary = { }
    if not _build_tree(db, paths, tree):
        return false
    return _save_node(db, model, tree)


## Saves the children of [param parent]'s relation [param relation_name] and deletes the
## parent's other children; runs inside a transaction. [param subtree] holds the relation
## paths to save below each child.
static func sync_children(
    db: Db,
    parent: DbModel,
    relation_name: String,
    subtree: Dictionary,
) -> bool:
    var table: DbTable = db._table_of(parent)
    if table == null:
        return false
    var relation: DbRelation = table.relations.get(relation_name)
    if relation == null or relation.kind == DbRelation.Kind.BELONGS_TO:
        return db._fail(
            Db.ErrorKind.USAGE,
            "%s has no has_many or has_one relation '%s'" % [table.model_name, relation_name],
        )
    if not parent.is_persisted():
        return db._fail(Db.ErrorKind.USAGE, "save the %s before its children" % table.model_name)
    if parent._db_read and not parent.is_loaded(relation_name):
        return db._fail(
            Db.ErrorKind.USAGE,
            (
                "%s.%s was never loaded, so saving it would delete its rows; load it first"
                % [table.model_name, relation_name]
            ),
        )
    var child_table: DbTable = db._registry.table_for_script(relation.target)
    var parent_key: Variant = parent.get(relation.target_key)
    if parent_key == null:
        return db._fail(
            Db.ErrorKind.USAGE,
            "%s.%s is null" % [table.model_name, relation.target_key],
        )

    var children: Array = []
    var held: Variant = parent.get(relation_name)
    if relation.kind == DbRelation.Kind.HAS_MANY:
        var list: Array = held
        children = list
    elif held != null:
        children = [held]

    var back_relation: DbRelation = null
    for candidate: DbRelation in child_table.relations.values():
        if (
            candidate.kind == DbRelation.Kind.BELONGS_TO
            and candidate.foreign_key == relation.foreign_key
        ):
            back_relation = candidate

    # Validate first, then delete the rows that go away, then save: a child that replaces
    # another under a unique key (has_one) must not meet the old row.
    var kept: Array = []
    for item: Variant in children:
        var child: DbModel = item if item is DbModel else null
        if child == null or db._registry.table_for(child) != child_table:
            return db._fail(
                Db.ErrorKind.USAGE,
                "%s.%s holds %s, not a %s"
                % [table.model_name, relation_name, item, child_table.model_name],
            )
        if not child_table.is_unsaved(child):
            kept.append(child)
    if not _delete_others(db, child_table, relation, parent_key, kept):
        return false
    for index: int in children.size():
        var child: DbModel = children[index]
        child.set(relation.foreign_key, parent_key)
        if not relation.position_field.is_empty():
            child.set(relation.position_field, index)
        if back_relation != null:
            var pointed: Variant = child.get(back_relation.name)
            if pointed != null and pointed != parent:
                child.set(back_relation.name, null)
        if not _save_node(db, child, subtree):
            return false
    parent.mark_loaded(relation_name)
    return true


## Copies the key of every belongs_to target held in a relation var into its foreign key.
static func copy_belongs_to_keys(db: Db, table: DbTable, model: DbModel) -> bool:
    for relation: DbRelation in table.relations.values():
        if relation.kind != DbRelation.Kind.BELONGS_TO:
            continue
        var held: Variant = model.get(relation.name)
        if held == null:
            continue
        var target: DbModel = held if held is DbModel else null
        var target_table: DbTable = db._registry.table_for(target)
        if target_table == null or target_table.model_script != relation.target:
            return db._fail(
                Db.ErrorKind.USAGE,
                "%s.%s holds %s, not the related model" % [table.model_name, relation.name, held],
            )
        if target_table.is_unsaved(target):
            return db._fail(
                Db.ErrorKind.USAGE,
                "save the %s in %s.%s first"
                % [target_table.model_name, table.model_name, relation.name],
            )
        model.set(relation.foreign_key, target.get(relation.target_key))
    return true


static func _build_tree(db: Db, paths: Array, tree: Dictionary) -> bool:
    for path: Variant in paths:
        if typeof(path) != TYPE_STRING and typeof(path) != TYPE_STRING_NAME:
            return db._fail(Db.ErrorKind.USAGE, "a relation path must be a String, not %s" % [path])
        var node: Dictionary = tree
        for part: String in str(path).split(".", false):
            if not node.has(part):
                node[part] = { }
            node = node[part]
    return true


static func _load_tree(db: Db, models: Array, tree: Dictionary) -> bool:
    if models.is_empty() or tree.is_empty():
        return true
    var groups: Dictionary[DbTable, Array] = { }
    for item: Variant in models:
        if not item is DbModel:
            return db._fail(Db.ErrorKind.USAGE, "%s is not a DbModel" % [item])
        var model: DbModel = item
        var table: DbTable = db._table_of(model)
        if table == null:
            return false
        if not groups.has(table):
            groups[table] = []
        groups[table].append(item)
    for table: DbTable in groups:
        for relation_name: String in tree:
            var relation: DbRelation = table.relations.get(relation_name)
            if relation == null:
                return db._fail(
                    Db.ErrorKind.USAGE,
                    "%s has no relation '%s'" % [table.model_name, relation_name],
                )
            var loaded: Array = []
            if not _load_relation(db, groups[table], relation, loaded):
                return false
            var subtree: Dictionary = tree[relation_name]
            if not _load_tree(db, loaded, subtree):
                return false
    return true


## Fills [param relation] on every model of [param models]; [param loaded] receives each
## related row once.
static func _load_relation(db: Db, models: Array, relation: DbRelation, loaded: Array) -> bool:
    var target_table: DbTable = db._registry.table_for_script(relation.target)
    if relation.kind == DbRelation.Kind.BELONGS_TO:
        var keys: Array = _unique_values(models, relation.foreign_key)
        var by_key: Dictionary = { }
        for chunk: Array in DbSql.chunks(keys):
            var rows: Array = db.select(relation.target).where_in(relation.target_key, chunk).all()
            if not db.last_error().is_empty():
                return false
            for row: Variant in rows:
                var target: DbModel = row
                by_key[_key(target.get(relation.target_key))] = target
                loaded.append(target)
        for item: Variant in models:
            var model: DbModel = item
            var key: Variant = model.get(relation.foreign_key)
            model.set(relation.name, by_key.get(_key(key)) if key != null else null)
            model.mark_loaded(relation.name)
        return true

    var parent_keys: Array = _unique_values(models, relation.target_key)
    var groups: Dictionary = { }
    for chunk: Array in DbSql.chunks(parent_keys):
        var query: DbQuery = db.select(relation.target).where_in(relation.foreign_key, chunk)
        if not relation.position_field.is_empty():
            query.order_by(relation.position_field)
        if not relation.order_field.is_empty():
            query.order_by(relation.order_field, relation.order_descending)
        for key_name: String in target_table.primary_key:
            query.order_by(key_name)
        var rows: Array = query.all()
        if not db.last_error().is_empty():
            return false
        for row: Variant in rows:
            var child: DbModel = row
            var group_key: Variant = _key(child.get(relation.foreign_key))
            if not groups.has(group_key):
                groups[group_key] = []
            var group: Array = groups[group_key]
            group.append(child)
            loaded.append(child)
    for item: Variant in models:
        var model: DbModel = item
        var children: Array = groups.get(_key(model.get(relation.target_key)), [])
        if relation.kind == DbRelation.Kind.HAS_MANY:
            var typed: Array = Array(
                children,
                TYPE_OBJECT,
                relation.target.get_instance_base_type(),
                relation.target,
            )
            model.set(relation.name, typed)
        else:
            model.set(relation.name, children[0] if not children.is_empty() else null)
        model.mark_loaded(relation.name)
    return true


static func _save_node(db: Db, model: DbModel, tree: Dictionary) -> bool:
    var table: DbTable = db._table_of(model)
    if table == null:
        return false
    for relation_name: String in tree:
        if not table.relations.has(relation_name):
            return db._fail(
                Db.ErrorKind.USAGE,
                "%s has no relation '%s'" % [table.model_name, relation_name],
            )
    for relation_name: String in tree:
        var relation: DbRelation = table.relations[relation_name]
        if relation.kind != DbRelation.Kind.BELONGS_TO:
            continue
        var held: Variant = model.get(relation_name)
        if held == null:
            continue
        if not held is DbModel:
            return db._fail(
                Db.ErrorKind.USAGE,
                "%s.%s is not a model" % [table.model_name, relation_name],
            )
        var target: DbModel = held
        var subtree: Dictionary = tree[relation_name]
        if not _save_node(db, target, subtree):
            return false
    if not db._save(table, model):
        return false
    for relation_name: String in tree:
        var relation: DbRelation = table.relations[relation_name]
        if relation.kind == DbRelation.Kind.BELONGS_TO:
            continue
        var subtree: Dictionary = tree[relation_name]
        if not sync_children(db, model, relation_name, subtree):
            return false
    return true


static func _delete_others(
    db: Db,
    child_table: DbTable,
    relation: DbRelation,
    parent_key: Variant,
    kept: Array,
) -> bool:
    var foreign_column: DbColumn = child_table.column(relation.foreign_key)
    var stored_parent: Variant = db._stored(child_table, foreign_column, parent_key)
    if not db.last_error().is_empty():
        return false
    var sql: String = "DELETE FROM %s WHERE %s = ?" % [
        DbSql.ident(child_table.name),
        DbSql.ident(relation.foreign_key),
    ]
    var args: Array = [stored_parent]
    var key_list: String = (
        DbSql.ident(child_table.primary_key[0])
        if child_table.primary_key.size() == 1
        else "(%s)" % DbSql.idents(child_table.primary_key)
    )
    var row_marks: String = (
        "?"
        if child_table.primary_key.size() == 1
        else "(%s)" % DbSql.placeholders(child_table.primary_key.size())
    )
    var rows_per_chunk: int = maxi(1, DbSql.MAX_BINDINGS / child_table.primary_key.size())
    for chunk: Array in DbSql.chunks(kept, rows_per_chunk):
        var marks: PackedStringArray = []
        for item: Variant in chunk:
            var child: DbModel = item
            var key_values: Array = db._key_values(child_table, child)
            if key_values.is_empty():
                return false
            args.append_array(key_values)
            marks.append(row_marks)
        if child_table.primary_key.size() == 1:
            sql += " AND %s NOT IN (%s)" % [key_list, ", ".join(marks)]
        else:
            sql += " AND %s NOT IN (VALUES %s)" % [key_list, ", ".join(marks)]
    return db._run(sql, args)


static func _unique_values(models: Array, field: String) -> Array:
    var seen: Dictionary = { }
    var values: Array = []
    for item: Variant in models:
        var model: Object = item
        var value: Variant = model.get(field)
        if value == null:
            continue
        var key: Variant = _key(value)
        if not seen.has(key):
            seen[key] = true
            values.append(value)
    return values


## A Dictionary key that treats a String and a StringName with the same text as equal.
static func _key(value: Variant) -> Variant:
    if typeof(value) == TYPE_STRING_NAME:
        return str(value)
    return value
