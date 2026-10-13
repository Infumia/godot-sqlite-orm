class_name FxEventListener
extends RefCounted
## A game script that is not a model and names an autoload. The generator must not load it.


func listen(on_tick: Callable) -> void:
    FxGameEvents.ticked.connect(on_tick)
