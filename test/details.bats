#!/usr/bin/env bats
# details.sh: the details popup body, printed once, colours stripped.
# shellcheck disable=SC2030,SC2031,SC2016
load test_helper

setup() { setup_env; }

NOW=1795074751   # Thu 07:52 UTC

# Write a usage snapshot. windows: label:used_pct:seconds-to-reset ...
snap() { # provider status ok_age window...
  local p=$1 st=$2 age=$3 w ws='[]' l u r
  shift 3
  for w in "$@"; do
    IFS=: read -r l u r <<<"$w"
    ws=$(jq -c --arg l "$l" --argjson u "$u" --argjson r $((NOW + r)) \
      '. + [{label:$l,used_pct:$u,resets_at:$r,window_seconds:18000}]' <<<"$ws")
  done
  jq -n --arg p "$p" --arg st "$st" --argjson now "$NOW" --argjson ok $((NOW - age)) --argjson ws "$ws" \
    '{provider:$p,status:$st,fetched_at:$now,ok_at:(if $ws == [] then null else $ok end),
      retry_at:$now,error:null,windows:$ws}' >"$CACHE/$p.json"
}

# Compare with the expected text on stdin; print a diff when they differ.
matches() { # actual
  local want
  want=$(cat)
  [ "$1" = "$want" ] || { diff <(printf '%s\n' "$want") <(printf '%s\n' "$1"); return 1; }
}

details() { # columns
  COLUMNS=$1 TZ=UTC AI_USAGE_NOW=$NOW "$ROOT/scripts/details.sh" --once |
    LC_ALL=C sed $'s/\033\\[[0-9;]*m//g'
}

@test "the table lists every window of every enabled provider, most-used first" {
  snap claude ok 0 5h:19:13080 wk:67:274000
  snap codex ok 0 5h:81:2820
  snap cursor ok 0 wk:58:86400
  matches "$(details 80)" <<'OUT'
Provider Window     Usage            Resets in Resets at
Claude   wk         ▰▰▰▰▰▰▰▱▱▱   67% 3d4h      Sun 11:59
         5h         ▰▰▱▱▱▱▱▱▱▱   19% 3h38m     Thu 11:30
Codex    5h         ▰▰▰▰▰▰▰▰▱▱   81% 47m       Thu 08:39
Cursor   wk         ▰▰▰▰▰▰▱▱▱▱   58% 1d        Fri 07:52
OUT
}

@test "below 60 columns each provider is one line" {
  snap claude ok 0 5h:19:13080 wk:0:601200
  snap codex ok 0 5h:81:2820
  snap cursor ok 0 wk:58:86400
  matches "$(details 59)" <<'OUT'
Claude  5h 19% 3h38m  wk 0% 6d23h
Codex   5h 81% 47m
Cursor  wk 58% 1d
OUT
}

@test "sign-in problems name the marker and each provider's fix" {
  snap claude signed_out 0
  snap codex signed_out 0
  snap cursor signed_out 0
  matches "$(details 80)" <<'OUT'
Provider Window     Usage            Resets in Resets at
Claude   !login Run `claude` in a terminal and log in.
Codex    !login Run `codex login`.
Cursor   !login Open the Cursor app and sign in.
OUT
}

@test "missing deps, bad format and errors with no good reading are explained" {
  snap claude missing_dep 0
  snap codex bad_shape 0
  snap cursor error 0
  matches "$(details 80)" <<'OUT'
Provider Window     Usage            Resets in Resets at
Claude   !deps Something it needs is missing. Run
         doctor.sh to see what.
Codex    !format The provider answered in a format the
         plugin doesn't know. The plugin may need an
         update.
Cursor   !error Temporary error; retrying automatically.
OUT
}

@test "an error keeps the last good windows, with the problem under them" {
  snap codex error 0 5h:81:2820
  matches "$(details 80 | grep -A1 '^Codex')" <<'OUT'
Codex    5h         ▰▰▰▰▰▰▰▰▱▱   81% 47m       Thu 08:39
         !error Temporary error; retrying automatically.
OUT
}

@test "a stale reading shows the age of the last good reading" {
  snap codex ok 7200 5h:81:2820
  matches "$(details 80 | grep -A2 '^Codex')" <<'OUT'
Codex    5h         ▰▰▰▰▰▰▰▰▱▱   81% 47m       Thu 08:39
         ~ last good reading 2h ago; numbers may be out
         of date
OUT
  matches "$(details 59 | grep -A2 '^Codex')" <<'OUT'
Codex   5h 81% 47m
        ~ last good reading 2h ago; numbers may be out
        of date
OUT
}

@test "a provider with no snapshot yet is shown as pending" {
  snap codex ok 0 5h:81:2820
  [ "$(details 80 | grep '^Claude')" = 'Claude   … no reading yet' ]
}

@test "a passed reset shows 0% with no countdown and sorts by that" {
  snap codex ok 0 5h:81:-60 wk:35:440000
  matches "$(details 80 | grep -A1 '^Codex')" <<'OUT'
Codex    wk         ▰▰▰▰▱▱▱▱▱▱   35% 5d2h      Tue 10:05
         5h         ▱▱▱▱▱▱▱▱▱▱    0%
OUT
}

@test "only enabled providers are shown, in @ai_usage_providers order" {
  snap claude ok 0 5h:19:13080
  snap codex ok 0 5h:81:2820
  snap cursor ok 0 wk:58:86400
  opt @ai_usage_providers '"cursor codex"'
  matches "$(details 59)" <<'OUT'
Cursor  wk 58% 1d
Codex   5h 81% 47m
OUT
}

@test "colours follow the usage colours and the dim colour" {
  snap codex ok 0 5h:81:2820
  opt @ai_usage_providers codex
  out=$(COLUMNS=59 TZ=UTC AI_USAGE_NOW=$NOW "$ROOT/scripts/details.sh" --once)
  [ "$out" = $'\033[38;2;186;194;222mCodex  \033[0m \033[38;2;108;112;134m5h \033[38;2;249;226;175m81%\033[0m \033[38;2;108;112;134m47m\033[0m\033[0m' ]
}

@test "the table reads the shared provider fixtures" {
  seed_snapshot_claude five-hour-weekly "$NOW"
  seed_snapshot primary-secondary "$NOW"
  seed_snapshot_cursor unified-weekly "$NOW"
  matches "$(details 59)" <<'OUT'
Claude  wk 67% 7d2h  5h 28% 7h7m
Codex   5h 81% 47m  wk 35% 5d2h
Cursor  wk 58% 2d1h
OUT
}

# --open as the key binding runs it: client name, width and height.
open_popup() { # client_width client_height
  export TMUX_SHIM_POPUP_LOG="$BATS_TEST_TMPDIR/popup.log"
  : >"$TMUX_SHIM_POPUP_LOG"
  TZ=UTC AI_USAGE_NOW=$NOW "$ROOT/scripts/details.sh" --open client0 "$1" "$2"
  cat "$TMUX_SHIM_POPUP_LOG"
}

popup_cmd() { # width height layout wrap-width
  printf "display-popup -c client0 -E -w %s -h %s -T  AI usage · q close  '%s' --layout %s --width %s" \
    "$1" "$2" "$ROOT/scripts/details.sh" "$3" "$4"
}

@test "the popup opens at the table's size plus padding and border" {
  snap claude ok 0 5h:19:13080 wk:67:274000
  snap codex ok 0 5h:81:2820
  snap cursor ok 0 wk:58:86400
  # Body: header + 4 rows, 56 columns wide. +2 padding, +2 border.
  [ "$(open_popup 200 50)" = "$(popup_cmd 60 9 table 56)" ]
}

seed_three() {
  snap claude ok 0 5h:19:13080 wk:0:601200
  snap codex ok 0 5h:81:2820
  snap cursor ok 0 wk:58:86400
}

@test "a client too narrow for the table gets a one-line popup sized to it" {
  seed_three
  # Widest line "Claude  5h 19% 3h38m  wk 0% 6d23h" is 33; 3 lines.
  # Notes would wrap to 59 - 4 = 55.
  [ "$(open_popup 59 30)" = "$(popup_cmd 37 7 line 55)" ]
}

@test "the popup never exceeds the client" {
  seed_three
  [ "$(open_popup 50 6)" = "$(popup_cmd 37 6 line 46)" ]
  [ "$(open_popup 30 40)" = "$(popup_cmd 30 7 line 26)" ]
}

@test "the popup is at least as wide as its title" {
  snap codex ok 0 5h:1:120
  opt @ai_usage_providers codex
  # "Codex   5h 1% 2m" is 16 + 4 = 20, under the 25 the 20-column title
  # needs: tmux 3.5a cuts its trailing space below title + 5.
  [ "$(open_popup 59 30)" = "$(popup_cmd 25 5 line 55)" ]
}

@test "wrapped notes keep the table popup at the table's width" {
  snap claude ok 0 5h:19:13080
  snap codex bad_shape 0
  snap cursor ok 0 wk:58:86400
  # header, claude row, 3 wrapped !format lines, cursor row = 6 lines.
  [ "$(open_popup 200 50)" = "$(popup_cmd 60 10 table 56)" ]
}
