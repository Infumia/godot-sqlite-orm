extends DbMigration
## Drops the title column and reads data back with query().

const VERSION := 3


func up(m: DbMigrator) -> void:
    var rows: Array[Dictionary] = m.query("SELECT count(*) AS n FROM players")
    if rows.is_empty():
        m.fail("no rows")
        return
    m.drop_column("players", "title")
