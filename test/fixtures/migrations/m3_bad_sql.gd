extends DbMigration
## A broken statement.

const VERSION := 3


func up(m: DbMigrator) -> void:
    m.execute("UPDATE players SET xp = 0")
    m.execute("UPDATE nowhere SET x = 1")
