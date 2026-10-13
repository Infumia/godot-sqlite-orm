extends DbMigration
## Renames name to nickname and creates the pets table, spelled out.

const VERSION := 2


func up(m: DbMigrator) -> void:
    m.rename_column("players", "name", "nickname")
    m.execute(
        "CREATE TABLE pets (" + "id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, "
        + "owner_id INTEGER NOT NULL DEFAULT 0 REFERENCES players (id) ON DELETE CASCADE, "
        + "species TEXT NOT NULL DEFAULT 'cat') STRICT"
    )
    m.execute("CREATE INDEX pets_owner_id_index ON pets (owner_id)")
