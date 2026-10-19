# computer-use CLI

Binary name: `computer-use` (`computer-use.exe` on Windows).

Source and releases: <https://github.com/lindoelio/computer-use>

Install from this skill with `scripts/setup.sh` or `scripts/setup.ps1`. A manual install is `cargo install computer-use --locked` (Rust 1.81 or newer).

Every action writes one JSON object to stdout and a trailing newline. `--help` and `--version` stay human-readable and exit 0. `--version` looks like `computer-use 0.1.0`.

```json
{"ok":true,"waited_ms":10}
```

```json
{"ok":false,"error":{"code":"invalid_arguments","message":"invalid arguments: wait requires ms, seconds, or both"}}
```

## Exit codes

| Code | When |
| --- | --- |
| 0 | The action returned `"ok": true`. Also `--help` and `--version`. `serve` and `--json` exit 0 on a clean end of stdin. |
| 1 | The action returned `"ok": false` (invalid action arguments or the desktop call failed). |
| 2 | The command line could not be parsed, `--json` was combined with a subcommand, or no subcommand was given. Parse errors still print JSON. No-subcommand prints human help. |

`--pretty` pretty-prints one-shot JSON, including `exec`. `serve` and `--json` always print compact JSON, one object per line, so `--pretty` does not change them.

With no subcommand and without `--json`, the process prints help and exits 2.

## Global flags

| Flag | Meaning |
| --- | --- |
| `--pretty` | Pretty-print one-shot JSON. |
| `--json` | Read newline-delimited JSON actions from stdin. Do not combine with a subcommand. |
| `--help`, `-h` | Human-readable help. Exit 0. |
| `--version`, `-V` | Human-readable version. Exit 0. |

## Commands

### screenshot

Capture the screen, or a logical region, and write a PNG or JPEG. The default path is in the system temp directory (`computer-use-<pid>-<nanos>-<n>.png` or `.jpg`). Coordinates are logical points, the same space as `click` and `move`. On a Retina display the image pixel size can be `scale` times the logical size.

```bash
computer-use screenshot
computer-use screenshot --output /tmp/screen.png --region 0,0,800,600
computer-use screenshot --format jpeg --max-width 1280 --base64
```

| Flag | Meaning |
| --- | --- |
| `--output PATH` | File to write. Parent directories are created. |
| `--region X,Y,W,H` | Logical region. Whitespace around commas is ignored. Width and height must be ≥ 1 and ≤ 100000. |
| `--format png\|jpeg\|jpg` | Default `png`. `jpg` is an alias of `jpeg`. The JPEG file extension is `.jpg`. |
| `--max-width N` | Scale the image down so its width is at most N pixels. |
| `--base64` | Add a standard, unwrapped base64 `data` field. |

```json
{"ok":true,"path":"/tmp/computer-use-123-456.png","width":800,"height":600,"scale":2.0,"format":"png"}
```

`width` and `height` are image pixels. `scale` is the frame scale (physical pixels divided by logical width).

### click

Move the pointer to a logical point and click.

```bash
computer-use click --x 120 --y 240
computer-use click --x 120 --y 240 --button right --double
```

| Flag | Meaning |
| --- | --- |
| `--x` | Logical x. Required. |
| `--y` | Logical y. Required. |
| `--button left\|right\|middle` | Default `left`. |
| `--double` | Click twice. |

```json
{"ok":true,"action":"click","x":120,"y":240,"button":"left","double":false}
```

A double click reports `"action": "double_click"` and `"double": true`.

### move

Move the pointer without clicking.

```bash
computer-use move --x 400 --y 300
```

```json
{"ok":true,"action":"move","x":400,"y":300}
```

### type

Type Unicode text into the focused control. Empty text is rejected. A null byte is rejected.

```bash
computer-use type --text "hello"
```

```json
{"ok":true,"action":"type","text":"hello","chars":5}
```

`chars` is the Unicode scalar count, not the byte length.

### key

Press a key combination. The last `+` segment is the key. Earlier segments are modifiers. Segments are trimmed. An empty segment is an error.

```bash
computer-use key --keys "cmd+shift+4"
computer-use key --keys "ctrl+c"
computer-use key --keys "alt+tab"
computer-use key --keys "enter"
```

| Token | Meaning |
| --- | --- |
| `cmd`, `command` | Command. Sent as the platform meta key. Reported modifier `command`. |
| `meta`, `super` | Meta / Super. Reported modifier `meta`. |
| `ctrl`, `control` | Control. Reported modifier `control`. |
| `alt`, `option` | Alt / Option. Reported modifier `alt`. |
| `shift` | Shift. |

Named keys: `enter` / `return`, `tab`, `esc` / `escape`, `space`, `left` / `right` / `up` / `down` (and `arrow` aliases such as `arrow_left`), `f1`–`f12`, `backspace` / `bksp`, `delete` / `del`, `home`, `end`, `pageup` / `pagedown` (and `page_up` / `page_down`). A single character is that character, case preserved (`shift+A` keeps `A`).

```json
{"ok":true,"action":"key","keys":"cmd+c","modifiers":["command"],"key":"c"}
```

### scroll

Scroll the mouse wheel. Positive `dy` is down. Positive `dx` is right.

Use `--dx` and `--dy`, or `--direction` with `--amount`. Do not mix the two forms. `--amount` without `--direction` is an error. The default amount is 1. Pass `--x` and `--y` together to move the pointer first. One of them alone is an error.

```bash
computer-use scroll --dy 3
computer-use scroll --dx -2 --dy 1
computer-use scroll --direction down --amount 3
computer-use scroll --x 400 --y 300 --direction up --amount 2
```

| Flag | Meaning |
| --- | --- |
| `--x`, `--y` | Logical point to move to first. Both or neither. |
| `--dx` | Horizontal steps. Positive is right. |
| `--dy` | Vertical steps. Positive is down. |
| `--direction up\|down\|left\|right` | Direction used with `--amount`. |
| `--amount` | Steps for `--direction`. Default 1. |

`up` becomes negative `dy`. `left` becomes negative `dx`. The result reports the resolved steps:

```json
{"ok":true,"action":"scroll","x":400,"y":300,"dx":0,"dy":3}
```

Omitted `--x` and `--y` are JSON `null`.

### get-state

Report screen size and displays, cursor position, the frontmost app and window, and a best-effort accessibility tree. The command does not panic when a subsystem is unavailable. Missing data is `null`, and `note` explains why. `get_state` is a CLI alias.

```bash
computer-use get-state
computer-use get_state
```

```json
{
  "ok": true,
  "platform": "macos",
  "displays": [
    {"id": 1, "name": "Built-in", "x": 0, "y": 0, "width": 1512, "height": 982, "scale": 2.0, "is_primary": true}
  ],
  "screen": {"id": 1, "name": "Built-in", "x": 0, "y": 0, "width": 1512, "height": 982, "scale": 2.0},
  "cursor": {"x": 400, "y": 300},
  "frontmost_app": "Finder",
  "frontmost_window": "Desktop",
  "accessibility": null,
  "note": "execution failed: accessibility needs Accessibility permission. Enable this terminal or computer-use in System Settings > Privacy & Security > Accessibility, then retry"
}
```

`platform` is `macos`, `linux`, or `windows`. `screen` is the primary display, or the first display. Display `width`, `height`, `x`, and `y` are logical. `scale` is device pixels per logical pixel, or `1.0` when the platform does not report one.

On macOS the tree comes from System Events. A window element can include `role`, `description`, `title`, `value`, `position`, `size`, and `children` (depth capped, children capped). On Linux and Windows in this build, `accessibility` is `null` and `note` says the tree is not available. Linux frontmost-window lookup uses `xdotool` when it is on `PATH`.

`note` is `null` when nothing was missing. Several failures are joined with `"; "`. A permission failure mentions Accessibility and **System Settings > Privacy & Security > Accessibility**. `"ok"` stays true for those gaps. A totally failed action is a different path and returns `"ok": false`.

### wait

Sleep, then return `waited_ms`. `--ms` and `--seconds` are added when both are set. At least one is required. Fractions are allowed for `--seconds`. Values must be finite and ≥ 0. The total must be at most 24 hours.

```bash
computer-use wait --ms 250
computer-use wait --seconds 0.5
computer-use wait --ms 100 --seconds 1
```

```json
{"ok":true,"waited_ms":250}
```

The library message when both are omitted is `invalid arguments: wait requires ms, seconds, or both`. The process exits 1.

### displays

List connected displays without capturing pixels.

```bash
computer-use displays
```

```json
{"ok":true,"displays":[{"id":1,"name":"Built-in","x":0,"y":0,"width":1512,"height":982,"scale":2.0,"is_primary":true}]}
```

## JSON mode

`serve` and `--json` read newline-delimited JSON from stdin and write one JSON response per line. This is a stdin protocol, not a TCP server. Empty lines are skipped. The process exits 0 on a clean end of input. It exits non-zero only when stdin or stdout fails. An individual action can still be `{"ok": false, ...}`.

`exec` runs one JSON action from an argument and honors `--pretty`. Its exit code follows that action (`0` or `1`).

```bash
printf '%s\n' '{"id":1,"action":"wait","ms":10}' | computer-use serve
printf '%s\n' '{"id":1,"action":"click","x":10,"y":20}' | computer-use --json
computer-use exec '{"action":"wait","ms":10}'
computer-use --pretty exec '{"id":"a","action":"displays"}'
```

Combining `--json` with a subcommand exits 2:

```json
{"ok":false,"error":{"code":"invalid_arguments","message":"--json reads actions from stdin. Drop the subcommand, or use serve or exec"}}
```

Requests are objects with an `action` tag and an optional `id`. The `id` is echoed on the response and may be any JSON value. Unknown fields that belong to the action are rejected. `id` is removed before the action is decoded.

| `action` | Fields |
| --- | --- |
| `screenshot` | `output`, `region` (`"x,y,w,h"` or `{x,y,width,height}`), `format` (`png` or `jpeg`), `max_width`, `base64` |
| `click` | `x`, `y`, `button` (`left`, `right`, `middle`), `double` |
| `double_click` | `x`, `y`, `button`. Same as `click` with `double: true`. Not a CLI subcommand. |
| `move` | `x`, `y`. Alias: `move_mouse`. |
| `type` | `text` |
| `key` | `keys` |
| `scroll` | `x`, `y`, `dx` (alias `scroll_x`), `dy` (alias `scroll_y`), `direction`, `amount` |
| `get_state` | none. Alias: `get-state`. |
| `wait` | `ms`, `seconds` |
| `displays` | none |

```json
{"id":1,"action":"click","x":10,"y":20,"button":"left"}
{"id":2,"action":"key","keys":"cmd+shift+4"}
{"id":3,"action":"scroll","direction":"down","amount":3}
{"id":4,"action":"screenshot","region":"0,0,800,600","format":"png"}
{"action":"get_state"}
```

A response with an id:

```json
{"ok":true,"id":1,"action":"click","x":10,"y":20,"button":"left","double":false}
```

Invalid JSON:

```json
{"ok":false,"error":{"code":"invalid_arguments","message":"invalid JSON: ..."}}
```

## Error codes

`error` is `{"code", "message"}`.

| `code` | When |
| --- | --- |
| `invalid_arguments` | Bad flags, bad JSON, empty text, mixed scroll forms, wait out of range, bad region. Library messages are prefixed with `invalid arguments: `. Clap's own message is passed through without that prefix. |
| `execution_failed` | The OS or a backend call failed, including a denied input or capture. A backend panic is caught and reported with this code. |
| `io_error` | Filesystem or process I/O failed. |
| `unsupported` | The platform does not implement the operation. Linux and Windows accessibility lookups use this, and `get-state` turns it into `accessibility: null` plus `note` rather than `"ok": false`. |

## Coordinates

Click, move, scroll, and screenshot regions use logical points. A display's `width`, `height`, `x`, and `y` are logical. `scale` is physical pixels divided by logical width. A screenshot's `width` and `height` are image pixels.

Scroll signs follow the platform wheel: positive `dy` is down, positive `dx` is right.

## Permissions

Input and capture need OS permission. Details and the threat model are in [security.md](security.md).

- **macOS.** Screen Recording for `screenshot`. Accessibility for mouse, keyboard, and the tree. **System Settings > Privacy & Security**.
- **Windows.** An interactive desktop session. The accessibility tree is null in this build.
- **Linux.** X11 only. Wayland is not a supported target. `xdotool` helps the frontmost-window lookup. The accessibility tree is null in this build.
