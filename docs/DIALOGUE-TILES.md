# Dialogue Tiles

## Overview

Dialogue tiles are inline widgets in the Lucifer conversation stream. They display status information (progress bars) or solicit operator input (Allow/Deny buttons). They are created and managed programmatically by lucibridge -- the LLM never sees them.

## Tile Types

### dialogue

Status/info tile with optional progress bar. Used for compaction feedback and agent notifications.

### form

Interactive tile with option buttons. Used for pre-tool approval (Allow/Deny). Blocks the agent until the operator responds.

## Protocol

Write to `/n/ui/activity/{id}/conversation/ctl`:

```
role=veltro dtype=dialogue title=Compacting progress=50 text=Summarizing...
role=veltro dtype=form title=Permission options=Allow,Deny text=exec rm -r /tmp
```

Update in-place:

```
update idx=N progress=100 title=Done
update idx=N options= title=Allowed
```

### Fields

| Field | Description |
|-------|-------------|
| `dtype` | `"dialogue"` or `"form"` |
| `title` | Tile heading (rendered via widget Label) |
| `progress` | 0-100 percentage (renders progress bar with theme progbg/progfg) |
| `options` | Comma-separated button labels (rendered via widget Button) |
| `text` | Body text |

## Architecture

- **luciuisrv.b**: Stores ConvMsg with dtype/title/progress/options. `hasattr()` handles Limbo's nil=="" string semantics for field clearing.
- **luciconv.b**: Renders tiles inline. Pass 1 estimates height (dialogue tiles are NOT markdown-rendered in Pass 2). Pass 3 draws title (Label), body text, progress bar, buttons (Button). DlgButton array for click hit-testing.
- **lucibridge.b**: `writedialogue()`, `updatedialogue()`, `pretoolapproval()`, `checkandcompact_ui()`, `updatefailstreak_ui()`, `syncconvcount()`.

## Programmatic Triggers

| Trigger | Type | When | Alert |
|---------|------|------|-------|
| Pre-tool approval | Form (Allow/Deny) | Destructive exec/write/edit | Urgency 2 (red flash) |
| Failure streak | Dialogue (info) | Same tool fails 3x | Urgency 1 (yellow flash) |
| Compaction | Dialogue (progress) | Context > 75% of 200K | None |

## Button Click Flow

1. User clicks button. `dlgbuttonclick()` writes the response to `conversation/input`.
2. `pretoolapproval()` reads it (was blocking on input).
3. Tile updates: buttons disappear, title shows result ("Allowed"/"Denied").
4. No human message tile is created -- button clicks are programmatic, not user messages.
5. The LLM never sees the button response.

## Key Design Decisions

- Dialogue tiles are regular ConvMsg messages with extra fields -- no separate data structure.
- Buttons use the widget toolkit (`widget.m` Button ADT), not custom drawing.
- Title uses the widget toolkit Label ADT.
- Progress bar uses theme colors (progbg/progfg) -- no widget ADT exists for this.
- `syncconvcount()` prevents streaming placeholder index drift when dialogue tiles are injected.
- `sendinput()` does not `appendmsg` locally -- the server is authoritative for message store.
- `hasattr()` is needed because Limbo treats nil and `""` as identical for strings.

## File Locations

| File | Role |
|------|------|
| `appl/cmd/luciuisrv.b` | Protocol server -- ConvMsg storage, parsing, serialization |
| `appl/cmd/luciconv.b` | Rendering -- height estimation, drawing, button hit-testing |
| `appl/cmd/lucibridge.b` | Emitters -- writedialogue, pretoolapproval, compaction, failure streak |
| `module/widget.m` | Widget toolkit interface (Button, Label) -- unchanged |
| `appl/lib/widget.b` | Widget toolkit implementation -- unchanged |
