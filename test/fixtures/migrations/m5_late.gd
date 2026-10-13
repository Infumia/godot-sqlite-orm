extends DbMigration
## A version far ahead.

const VERSION := 5


func up(m: DbMigrator) -> void:
    m.execute("SELECT 1")
