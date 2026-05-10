extends Node
## Singleton holding the parameters of the current run.
##
## Populated by the main-menu / new-game flow before Main.tscn loads.
## Main.tscn reads from here instead of hard-coding seed / dims, so you can
## also boot Main.tscn directly during development — the defaults below
## are exactly what Main.gd used to hard-code.

const DEFAULT_SEED := 0x000B_ABE1
const DEFAULT_WIDTH := 256
const DEFAULT_HEIGHT := 256
const DEFAULT_CIV_COUNT := 4
const DEFAULT_PLAYER_CIV_ID := 0

## Sentinel value meaning "not set yet — fall back to defaults at start_game".
const _UNSET := -1

var seed: int = _UNSET
var map_width: int = _UNSET
var map_height: int = _UNSET
var civ_count: int = _UNSET
var player_civ_id: int = _UNSET

## True once the menu / new-game flow has explicitly populated us.
## Used to distinguish a real run from "Main.tscn opened directly".
var is_initialized: bool = false


func reset() -> void:
	seed = _UNSET
	map_width = _UNSET
	map_height = _UNSET
	civ_count = _UNSET
	player_civ_id = _UNSET
	is_initialized = false


## Fill any unset field with its default. Idempotent. Always safe to call.
func ensure_defaults() -> void:
	if seed == _UNSET:
		seed = DEFAULT_SEED
	if map_width == _UNSET:
		map_width = DEFAULT_WIDTH
	if map_height == _UNSET:
		map_height = DEFAULT_HEIGHT
	if civ_count == _UNSET:
		civ_count = DEFAULT_CIV_COUNT
	if player_civ_id == _UNSET:
		player_civ_id = DEFAULT_PLAYER_CIV_ID


func configure(p_seed: int, p_w: int, p_h: int, p_civs: int, p_player_civ: int) -> void:
	seed = p_seed
	map_width = p_w
	map_height = p_h
	civ_count = p_civs
	player_civ_id = p_player_civ
	is_initialized = true
