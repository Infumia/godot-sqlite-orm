class_name DbMigration
extends RefCounted
## One change to an existing database. Extend it, set a [code]VERSION[/code] constant and
## write [method up]:
## [codeblock]
## extends DbMigration
##
## const VERSION := 3
##
## func up(m: DbMigrator) -> void:
##     m.add_column(Character, "xp")
## [/codeblock]
## Migrations run in VERSION order, each in its own transaction. A new database never runs
## them: its tables come from the models, which already describe the latest schema.


## Makes the change. Any failed step rolls the whole migration back.
func up(_m: DbMigrator) -> void:
    pass
