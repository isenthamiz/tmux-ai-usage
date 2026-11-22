# PROTOTYPE — README outline, variant B: "short tour, then one reference"

> Throwaway skeleton for [Rough README outline and section skeleton](https://github.com/isenthamiz/tmux-ai-usage/issues/62).
> The top half is a short illustrated tour with snippets only — no option tables.
> Every option lives in one Reference section at the bottom, grouped as today.

---

# tmux-ai-usage

One line pitch. `[IMAGE hero.png]`

## Quick start

Same as variant A: one copy-paste block, `prefix + I`, `brew install jq`, "you should now see" `[IMAGE quickstart-result.png]`.

## Tour

Each item: one picture, two or three sentences, one snippet. No tables.

### Reading a usage bar
`[IMAGE anatomy.png]` — parts, colours, which window (`auto`).

### Narrow terminals shrink the bar
`[GIF steps.gif]` — "always full": `@ai_usage_step full`.

### One provider at a time
`[GIF rotation.gif]` — `@ai_usage_rotate on`.

### Only the agent in this pane
`[GIF focus.gif]` — `@ai_usage_focus on` (+ reload).

### Everything at once: the popup
`[IMAGE popup.png]` — `prefix + u`.

### When something's wrong
`[IMAGE markers.png]` — marker → fix table (this one table stays in the tour).

## Placement

`#{ai_usage}` vs per-provider tokens, load order, reload rule.

## Requirements

Dependency matrix; Cursor Keychain.

## Troubleshooting

Common failures, doctor.sh, when changes apply.

## Reference

All option tables in one place, grouped: What to show · Steps · Rotation · Focus · Details popup · Bar · Colours and thresholds · Refresh and cache · Window labels.

## Privacy: what it reads

## Development
