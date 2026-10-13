extends Node
## A game's event bus, registered as the FxGameEvents autoload. Autoloads do not exist when the
## generator runs from the command line, so scripts that name one fail to compile there.

signal ticked(count: int)
