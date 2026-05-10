extends Node
## Autoload that wires `tr("KEY")` to a programmatic [Translation] table.
##
## We deliberately avoid `.po` / `.csv` import for now: it ties us to a
## Godot import step that the headless CI smoke job doesn't always run.
## Translations are registered in code, one [Translation] resource per
## locale. Adding a new language is a 5-minute job: copy [_TABLE_EN],
## change values, register with locale "ru" / "fr" / etc.
##
## All UI source code calls [tr] with a snake_case key (e.g.
## `tr("hud.civ.label")`). When no translation exists for the active
## locale, [TranslationServer] falls back to the literal key, so every
## key includes a *humane* English value here — never tag noise.

const _TABLE_EN := {
	# Top-bar / pause
	"top.borders_hint":          "[T] borders",
	"top.zoom":                  "zoom",
	"top.speed.normal":          "1×",
	"top.speed.fast":            "4×",
	"top.speed.very_fast":       "16×",
	"top.save":                  "Save",
	"top.load":                  "Load",
	"top.menu":                  "Menu",

	# Civ panel
	"civ_panel.years_in_power":  "%d y in power",
	"civ_panel.age":             "age %d",
	"civ_panel.no_leader":       "(vacant — no eligible elder)",
	"civ_panel.stats":           "%d pop · %d houses · %d%% land",

	# Hover tooltip
	"hover.unclaimed":           "Unclaimed (%d, %d)",
	"hover.claimed":             "%s — ★ %s, %dy",
	"hover.claimed_no_leader":   "%s — (no leader)",

	# Save / load toasts
	"toast.saved":               "Saved",
	"toast.save_failed":         "Save failed",
	"toast.loaded":              "Loaded",
	"toast.load_failed":         "Load failed",
	"toast.no_save":             "No quick-save found",
}

func _ready() -> void:
	var t := Translation.new()
	t.locale = "en"
	for k in _TABLE_EN:
		t.add_message(k, _TABLE_EN[k])
	TranslationServer.add_translation(t)
	TranslationServer.set_locale("en")
