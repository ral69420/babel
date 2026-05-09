extends CanvasLayer
## On-screen UI: clock, speed indicator, debug info.

@onready var clock_label: Label = $Root/Clock
@onready var status_label: Label = $Root/Status

var _state: Node = null

func bind(state: Node) -> void:
	_state = state
	refresh()

func refresh() -> void:
	if _state == null:
		clock_label.text = "(no sim)"
		status_label.text = ""
		return
	clock_label.text = "Year %d  ·  tick %d" % [_state.year(), _state.ticks()]
	var dims: Vector2i = _state.dims()
	status_label.text = "Map %dx%d" % [dims.x, dims.y]
