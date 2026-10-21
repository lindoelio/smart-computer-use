# computer-use CLI reference

Binary name: `computer-use` (`computer-use.exe` on Windows).

Source of truth and releases: <https://github.com/lindoelio/computer-use>

Upstream reference: [`docs/CLI.md`](https://github.com/lindoelio/computer-use/blob/main/docs/CLI.md). That document is generated from the binary's `--help` and the `Action`, `ComputerError`, and `CallContext` types. When this file and the binary disagree, the binary is right.

Install from this skill with `scripts/setup.sh` (or `scripts/setup.ps1`). Manual install is `cargo install computer-use --locked` (Rust 1.91 or newer).

Every action writes one JSON object to stdout. `--help` and `--version` are human-readable and exit 0. `--version` prints `computer-use <version>`.

```json
{"ok":true,"waited_ms":10}
```

```json
{"ok":false,"error":{"code":"invalid_arguments","message":"invalid arguments: wait requires ms, seconds, or both"}}
```

## Version compatibility

This skill targets **0.3.0**. Anything not listed in the "Works on 0.1.0" column needs 0.2.0 or 0.3.0 and fails with `invalid_arguments` (unknown subcommand, exit 2) or `unsupported` on an older binary.

| Surface | Works on 0.1.0 | Needs 0.2.0 | Needs 0.3.0 |
| --- | --- | --- | --- |
| Subcommands | `screenshot` `click` `move` `type` `key` `scroll` `get-state` `wait` `displays` `serve` `exec` | `triple-click` `press` `set-value` `select-text` `perform-action` `scroll-to` `focus` `drag` `mouse-down` `mouse-up` `hold-key` `clipboard` `zoom` `list-apps` `list-windows` `launch` `activate` `quit` `tree` `ocr` `menu` `apple-event` `shortcuts` `dock` `spaces` `policy` `pause` `resume` `doctor` `isolation` `session` `overlay` `browser` | `batch` `cursor-position` |
| Global flags | `--pretty` `--json` | `--app` `--window` `--element` `--require-visible` `--diff` `--full` `--session` `--state` `--screenshot` `--coord` `--adapter` `--policy` `--confirm-cmd` `--tier` `--synthetic-focus` `--allow-foreground` `--require-background` `--no-overlay` `--cdp` `--cdp-url` `--display` `--exec` | `--state-diff` |
| Error codes | `invalid_arguments` `execution_failed` `io_error` `unsupported` | `app_not_found` `window_not_found` `element_not_found` `stale_element` `permission_required` `policy_denied` `confirm_required` `confirm_denied` `blocked_url` `paused` `cdp_unavailable` `display_unavailable` | none added; `policy check` and the `tree` response gained the `code` and `baseline` fields |

Without element targeting you can only click blind coordinates. The 0.3.0 main loop in [SKILL.md](../SKILL.md) depends on `tree`, `--element`, `--app`/`--window`, `--session`, and `--state-diff`. Run `bash scripts/setup.sh` and confirm with `computer-use --version` before relying on them.

## Exit codes

| Code | When |
| --- | --- |
| 0 | `"ok": true`. Also `--help` and `--version`. `serve` and `--json` exit 0 on a clean end of stdin. `doctor` exits 0 whenever the report was produced, even with a permission missing. |
| 1 | `"ok": false`. |
| 2 | The command line could not be parsed, `--json` was combined with a subcommand, or no subcommand was given. Parse errors still print JSON. |

## Conventions

- Logical coordinates everywhere on the CLI and in JSON. Image-pixel coordinates are accepted when `--coord image` or `coord: "image"`.
- One JSON object per action. `--pretty` pretty-prints a one-shot. `serve` and `--json` stay one object per line.
- A failed action exits non-zero and carries `{"ok":false,"error":{"code","message"}}`. `error.code` is the stable contract — branch on it, not on the message text.

## Global flags

Applies to every subcommand, except `--json` and `--exec`, which are top-level only. The JSON equivalents are sibling keys of `action` and are stripped before `Action` is decoded.

| Flag | JSON key | Default | Meaning |
| --- | --- | --- | --- |
| `--pretty` | n/a | off | Pretty-print one-shot JSON. Serve mode stays one object per line. |
| `--json` | n/a | off | Read newline-delimited JSON actions from stdin. |
| `--app <NAME\|BUNDLE\|PID>` | `app` | frontmost on macOS | Target application. |
| `--window <TITLE\|INDEX\|ID>` | `window` | key window of `--app` | `index` is z-order, `0` is front. `id:<number>` selects by window id. |
| `--element <N>` | `element` | none | Index from the latest `tree` for this app and window. |
| `--require-visible` | `require_visible` | false | Fail when the element is outside the window and scroll-into-view cannot run. |
| `--diff` | `diff` | true once a baseline exists | Print a diff against the cached tree. |
| `--full` | `full` | off | Print the full tree. The baseline is always the most recent observation. |
| `--session <ID>` | `session` | process id | Cache namespace. Use it to keep parallel runs apart — and to keep the baseline alive between commands. |
| `--state` | `return_state` | false | Attach the post-action accessibility tree. |
| `--state-diff` | `state_diff` | false | Attach only the post-action delta. Implies `--state` and omits `state.tree`. |
| `--screenshot` | `include_screenshot` | false | With `--state`, also attach a window image. |
| `--coord <screen\|image>` | `coord` | `screen` on the CLI, `image` inside adapters | Coordinate space for `x`/`y`. |
| `--adapter <native\|openai\|anthropic>` | `adapter` | `native` | Schema translator for `exec`, `serve`, and `--json`. |
| `--policy <PATH>` | n/a | `~/.config/computer-use/policy.toml` | User policy file. |
| `--confirm-cmd <COMMAND>` | `confirm_cmd` | env `COMPUTER_USE_CONFIRM_CMD` | Sensitive-action confirm hook. |
| `--tier <TIER>` | `tier` | auto | Input tier. |
| `--synthetic-focus` | sets `tier: "synthetic"` | off | Alias of `--tier synthetic`. Conflicts with `--tier`. |
| `--allow-foreground` | `allow_foreground` | false | Skip `foreground.lock` for tier `activate`. |
| `--require-background` | `require_background` | false | Do not fall back to `activate`. Cursor motion becomes `execution_failed`. |
| `--no-overlay` | `no_overlay` | false | Do not send the agent point to the overlay helper. |
| `--cdp` | `cdp` | off | Route `browser` commands through Chrome DevTools Protocol. Requires the `cdp` feature. |
| `--cdp-url <URL>` | `cdp_url` | argv discovery | Override the discovered CDP websocket URL. |
| `--display <ID\|VIRTUAL>` | `display` | all | Restrict capture and coordinate conversion to one monitor id from `displays`. `--display virtual` is the Linux Xvfb recipe. |
| `--exec <CMD>...` | n/a | none | With `--display virtual`, replace this process with a command inside the prepared environment (`DISPLAY=:99`). |

### Tiers

`ax` and `event` stay in the background and do not move the shared cursor. That is what you want by default for an agent.

- `ax` — accessibility action or value. Does not activate the app.
- `event` — post events to the target process. Does not move the system cursor.
- `synthetic` — private SkyLight front-process call, then post events. Requires the `skylight` feature. Experimental, fails closed.
- `activate` — activate the target, run foreground input, then restore the previous app. Takes `foreground.lock`.

Absent `--tier` is auto: accessibility for presses and values, `event` then `activate` for coordinates.

## Feature flags

Features are compiled in. `default = []`. A published release asset enables **`portal` on Linux only**, so the stock macOS and Windows binaries have no optional feature at all.

| Feature | Effect | On a release asset? |
| --- | --- | --- |
| `cdp` | `chromiumoxide` and a minimal `tokio`, enabling `browser *`. | **No.** Build it yourself: `cargo install computer-use --locked --features cdp`. |
| `skylight` | `SLPSSetFrontProcessWithOptions` / `CPSSetFrontProcess` behind `--tier synthetic`. Experimental, private API, fail closed. | No. |
| `virtual-display` | Probes two private CoreGraphics symbols and stops. No display is ever created. Experimental. | No. |
| `portal` | XDG Desktop Portal ScreenCast + RemoteDesktop on Wayland. | Linux only. |

A binary built without `cdp` answers every `browser` command with:

```json
{"ok":false,"error":{"code":"unsupported","message":"unsupported: browser commands require the `cdp` feature (build with --features cdp)"}}
```

`cdp_unavailable` means the opposite: the feature **is** built in, but Chrome is not attachable (no debugging port, no page target, websocket died). Upstream `docs/CLI.md` folds both into `cdp_unavailable`; the binary is the contract, and the binary uses `unsupported` for the missing feature. Check both codes when you branch on browser failures.

## Command coverage

Every command the binary accepts, and where the skill teaches it. `loop` means the main loop in `SKILL.md` uses it, `capability` means the "Capabilities you should reach for" table points at it, `safety` means it appears in the safety rules, and `reference` means it is documented here but is not part of the loop.

| Command | Where |
| --- | --- |
| `screenshot` | loop, capability |
| `click` | loop |
| `triple-click` | capability |
| `press` | loop |
| `set-value` | loop |
| `select-text` | loop |
| `perform-action` | capability |
| `scroll-to` | loop |
| `focus` | capability |
| `move` | reference |
| `drag` | capability |
| `mouse-down` | capability |
| `mouse-up` | capability |
| `type` | loop |
| `key` | loop |
| `hold-key` | capability |
| `clipboard` | capability |
| `zoom` | capability |
| `scroll` | reference |
| `get-state` | loop |
| `wait` | reference |
| `displays` | reference |
| `isolation` | reference |
| `list-apps` | loop |
| `list-windows` | loop |
| `launch` | capability |
| `activate` | capability |
| `quit` | safety |
| `policy` | safety |
| `pause` | safety |
| `resume` | safety |
| `doctor` | loop |
| `tree` | loop |
| `ocr` | loop |
| `menu` | capability |
| `apple-event` | capability |
| `shortcuts` | capability |
| `dock` | capability |
| `spaces` | capability |
| `session` | reference |
| `serve` | reference |
| `exec` | reference |
| `batch` | loop |
| `cursor-position` | reference |
| `overlay` | reference |
| `browser` | loop |

## Post-action state

A mutating action with `--state` returns a `state` block beside the action result:

```json
{
  "ok": true,
  "action": "press",
  "state": {
    "app": "com.apple.Notes",
    "pid": 812,
    "window_id": 44,
    "revision": 18114448678970534631,
    "tree": "[0] AXWindow ...",
    "diff": "~ [9] AXTextField value: \"old\" -> \"new\"",
    "truncated": false,
    "baseline": "existing"
  }
}
```

`state.tree` is the whole numbered tree and `state.diff` is the delta against the previous observation. On a busy window the tree runs to tens of kilobytes while the delta is a few lines, so ask for the delta only:

```bash
computer-use press --session notes --app Notes --element 12 --state-diff
```

`--state-diff` implies `--state` and omits `state.tree`. The block keeps `app`, `pid`, `window_id`, `revision`, `diff`, `truncated`, and `baseline`.

A read-only action never attaches a state block, and neither does a failed action. When the action succeeded but the tree snapshot failed, the block is present with null fields and a `warnings` entry names the failure.

## Commands

### `screenshot`

```
      --output <PATH>        File to write. Defaults to a path in the system temp directory. Alias: --path.
      --region <X,Y,W,H>     Logical region `x,y,width,height` in the same space as click coordinates.
      --format <FORMAT>      png (default) or jpeg (`jpg` is accepted).
      --max-width <N>        Scale the image down so its width is at most N pixels. Default: 1440. 0 keeps the source width.
      --canvas <WxH>         Letterbox into WxH pixels, for example 1440x900. The image is not scaled up.
      --base64               Add a standard base64 `data` field to the JSON result.
      --marks                Stamp numbered element rectangles on the image (tree indices or OCR `oN`).
```

`--app`/`--window` capture that window only. A capture made for a window returns `capture_source` (`sck` on macOS, `windows-capture` on Windows, `portal` on Linux, `xcap` for a desktop crop fallback) and `occluded` when the fallback was used. The result also carries `image_to_screen` and `screen_to_image`, so image pixels map back to logical points.

```bash
computer-use screenshot --output /tmp/screen.png --region 0,0,800,600
computer-use screenshot --app Notes --window 0 --marks --output /tmp/notes.png
computer-use screenshot --format jpeg --max-width 1280 --base64
```

### `click`

```
      --x <X>             Logical x coordinate. Required with --y when --element is omitted.
      --y <Y>             Logical y coordinate. Required with --x when --element is omitted.
      --button <BUTTON>   left (default), right, middle, back (button 4), forward (button 5).
      --double            Click twice. With --element, this presses twice.
      --count <COUNT>     Click count, 1, 2, or 3. --count 3 is a triple click. Default: 1.
```

`--element N` is an alias of `press`. Pass one of the element form or the coordinate form, not both.

### `press`

```
      --count <COUNT>     How many times to press. Default: 1.
      --button <BUTTON>   left (default), right, middle, back (button 4), forward (button 5).
```

`--button right` runs `AXShowMenu` when the element advertises it; otherwise the click is aimed at the element center.

### `set-value`

```
      --value <VALUE>     New value.
```

Sets the value through the accessibility value interface, not by typing keystrokes. Secure fields are refused with `policy_denied` and the value is never read.

### `select-text`

```
      --start <START>     First selected character.
      --end <END>         Character after the selection.
```

Secure fields are refused. `start` must be ≤ `end`, and `end` must sit inside the character count when the platform reports it.

### `perform-action`

```
      --name <NAME>       Allowlisted accessibility action name.
```

- macOS: `AXPress`, `AXShowMenu`, `AXIncrement`, `AXDecrement`, `AXConfirm`, `AXCancel`, `AXRaise`, `AXScrollToVisible`, `AXScrollToVisibleTopLeft`, `AXScrollToVisibleBottomRight`, `AXScrollToVisibleLeft`, `AXScrollToVisibleRight`, `AXScrollPageUp`, `AXScrollPageDown`, `AXScrollPageLeft`, `AXScrollPageRight`.
- Windows: `press` (UIA `Invoke`), `expand`, `collapse` (UIA `ExpandCollapse`).
- Linux: any action from `Action::get_actions()` on the matched element; the first action is the default.

### `scroll-to`, `focus`, `move`, `drag`, `mouse-down`, `mouse-up`

```
scroll-to  Scroll an element into view.  Alias: scroll-to-visible
focus      Focus an element
move       Move the pointer without clicking.  Requires --x and --y
drag       --path <X,Y,X,Y>  at least two points, or a JSON array of {x, y}
           --button <left|right|middle>
mouse-down --x --y  Press and hold until mouse-up. Default: --button left
mouse-up   --x --y  Release a button pressed by mouse-down
```

`mouse-down` stays down for the rest of a `serve` loop or a `batch`, and is released when that process drops the input session. A later process is not held down.

### `type`, `key`, `hold-key`

```
type      --text <TEXT>        Text to type. A null byte or empty text is refused.
key       --keys <COMBO>       Combination such as `super+c` or `ctrl+alt+Delete`.
hold-key  --keys <COMBO>       One combo. Space-separated sequences are refused.
          --ms <N>             Milliseconds to hold (at most 30000).
```

Modifier tokens: `cmd`/`command`, `meta`/`super`, `ctrl`/`control`, `alt`/`option`, `shift`.
Named keys: `enter`/`return`, `tab`, `esc`/`escape`, `space`, `left`/`right`/`up`/`down` (and `arrow` aliases), `f1`–`f24`, `backspace`, `delete`, `home`, `end`, `pageup`/`pagedown` (and `page_up`/`page_down`), `insert`, `caps_lock`, `num_lock`, `scroll_lock`, `print_screen`, `menu`, plus xdotool keysyms on Linux.

A key aimed at a secure field returns `policy_denied`. A key without `--element` cannot see a secure focused field, which is why the element form is the safe one.

### `clipboard`

```
clipboard get   Read text, or write a clipboard image to the session cache.
clipboard set   Replace the clipboard. Requires a confirm hook.
                --text <TEXT>   Text to write. Empty text is refused.
                --image <PNG>   PNG file to write. Used when --text is omitted.
```

`get` returns `{ok: true, kind: "text", text: "..."}`, `{ok: true, kind: "image", path: "...", width, height}`, or `{ok: true, kind: "empty"}`. Text wins over an image.

### `zoom`

```
      --region <X,Y,W,H>   Required. Logical region `x,y,width,height`.
      --output <PATH>      File to write. Alias: --path.
      --format <FORMAT>    png (default) or jpeg.
      --max-width <N>      Scale down to at most N pixels. Default: 1440.
      --canvas <WxH>       Letterbox into WxH pixels.
      --base64             Add a standard base64 `data` field.
```

Window-local coordinates when `--app`/`--window` is set; the far edge may equal the window size.

### `scroll`

```
      --x <X>             Move the pointer to this logical x before scrolling.
      --y <Y>             Move the pointer to this logical y before scrolling.
      --dx <DX>           Horizontal wheel steps. Positive is right.
      --dy <DY>           Vertical wheel steps. Positive is down.
      --direction <DIR>   up | down | left | right (paired with --amount).
      --amount <N>        Wheel steps. Default: 1.
```

Do not mix `--dx`/`--dy` with `--direction`/`--amount`.

### `get-state`, `wait`, `displays`, `isolation`

`get-state` reports `{platform, displays, screen, cursor, frontmost_app, frontmost_window, accessibility, note}`. Missing fields are `null` and `note` explains why. `wait` takes `--ms` and `--seconds`, adds them when both are set, and requires at least one. `displays` lists connected monitors with `display_id` for `--display`. `isolation` returns `{platform, display_filter, cdp, virtual_display, set_of_marks, notes}` plus the `infeasible` object.

```bash
computer-use get-state
computer-use wait --ms 250
computer-use displays
computer-use isolation
```

### `list-apps`

```
      --all    Include accessory and prohibited apps.
```

Returns running applications with `name`, `bundle_id`, `pid`, `path`, `active`, and `hidden`. Use it to learn the exact name or bundle id you then pass to `--app`.

### `list-windows`

Returns on-screen windows in z-order. Index `0` is front. `--app` filters to that application and renumbers so `0` is that app's front window. Each row carries `id`, `title`, `app`, `pid`, `bounds`, `layer`, `z`, `on_screen`, and `ax_matched`.

### `launch`, `activate`, `quit`

```
launch [APP]      Launch by name, bundle id, path, or pid. macOS uses NSWorkspace.
activate          Bring an application forward. Requires --app. --window is checked first.
quit              --force   Force-quit after the confirm hook allows it.
```

A built-in deny list covers Terminals and Password Managers and runs before the backend on every OS. Off macOS these return `unsupported`.

### `policy`

```
policy check   Report allow or deny for `--app`.
```

Returns `{ok: true, decision: "allow" | "deny", source: "builtin" | "admin" | "user" | "default", code: "ok" | "policy_denied", ...}` without performing an action. A `deny` decision keeps `ok: true` and reports `code: "policy_denied"`, so branch on `decision`.

A user policy file can exempt one entry of the built-in deny list:

```toml
version = 1

[builtin_deny]
exempt = ["app.crynta.terax"]
```

The exemption matches a bundle id, an executable name, or a `.app` bundle name, and covers the whole app. The admin file cannot set it.

### `pause`, `resume`

`pause` installs a cross-process kill switch on macOS (`CGEventTap`). Mutating actions return `paused` afterwards. `resume` clears it.

### `doctor`

```
      --prompt             Prompt for Accessibility, Screen Recording, Post Event, and Input Monitoring. Alias: --request.
      --open-settings      Open System Settings to the first missing permission pane (macOS only).
```

Returns `{ok, permissions_ok, missing, fix, fixes, identity, accessibility, screen_capture, post_events, input_monitoring, input_monitor, atspi_bus, session, portal, uiaccess, integrity, bundle_id, responsible_app, note, text}`. `permissions_ok` and `missing` are the grant aggregate. `fix` is an array **parallel** to `missing`: index `i` of `fix` describes `missing[i]`; `fixes` carries the same entries as one-line strings. Envelope `ok: true` means the report was produced, so the process exits 0 even when a permission is missing — branch on `permissions_ok`.

`identity` reports whether the binary runs inside the app bundle, its bundle id, its signature, and the program responsible for the grant. A binary outside the bundle inherits the permission of whatever started it.

### `tree`

Prints the numbered accessibility tree for the key window, one line per node:

```
[n] ROLE "title" @x,y wxh value=... actions=...
```

`--diff` (default once a baseline exists) prints only what changed. `--full` prints everything; the baseline is always the most recent observation. Truncation caps: 40 children (`… +N`), depth 12, 400 lines, then `truncated=true`. `http`/`https` values keep scheme, host, and at most 60 characters of path; the query is stripped.

The response carries `baseline: "created" | "existing"` — `created` when the observation had no previous tree and the printed text is the whole tree, `existing` when the printed text is a delta.

A diff line starts with `+` (added node), `-` (removed node) or `~` (changed value, `~ [9] AXTextField value: "old" -> "new"`).

```bash
computer-use tree --app Notes --window 0
computer-use tree --app Notes --window 0 --diff
computer-use tree --app Notes --window 0 --full
```

### `ocr`

```
      --force    Re-run OCR even when the latest screenshot map is recent.
```

Runs OCR on the most recent capture for `--app` or `--window`. macOS uses `VNRecognizeTextRequest`, Windows uses `Windows.Media.Ocr.OcrEngine`. **Linux returns `unsupported`** ("no OCR backend on Linux in 0.2.0"). The recognized text is never logged; it lives in the JSON response body only.

The `ocr --help` text on the binary still says "macOS only" and names Linux and Windows — that string is stale, since P12b replaced the Windows stub with a real Media OCR call. This file and the source agree with the code.

### `menu`, `apple-event`, `shortcuts`, `dock`, `spaces`

macOS only except `spaces`, which groups on-screen windows by the screen containing each window's center and does not attempt Mission Control moves.

```
menu list   --app <APP>   --depth <N>   Default 4, max 8.
menu click  --app <APP>   --path "File > Save As > Save"
apple-event --app <APP>   --script <SCRIPT>   --language applescript|javascript
shortcuts run <NAME>
dock list
dock click  --title <T>   Case-insensitive
spaces
```

`apple-event` runs `osascript -e`. The script body is never logged verbatim; the response body carries `script_bytes` and a stable FNV-1a 64-bit hash, while the audit line records only sizes. `shortcuts run` invokes `["shortcuts", "run", name]` with a 60 s timeout.

### `session`

```
session end     Restore Electron accessibility flags this process changed and stop observers.
session prune   --dry-run   --ttl <TTL>   Default 86400 seconds (24 hours).
```

### `serve`, `exec`, `batch`, `cursor-position`, `overlay`

`serve` reads newline-delimited JSON from stdin and writes one JSON response per line. Stdin protocol, not a TCP server. Exits 0 on a clean end of input. `exec` runs one JSON action from an argument and honors `--pretty`. `batch` runs a batch of actions from an argument: the JSON object has `action: "batch"` and an `actions` array; one resolved target, one revision sequence, each step re-validated; a nested batch is `invalid_arguments`; a step's own `return_state` is ignored because the batch attaches one post-state at the end. `cursor-position` prints the pointer position. `overlay serve` draws a click-through ring at the agent point; the main CLI sends `{x, y, session}` on `<cache>/overlay.sock` after a successful positional action, a missing helper adds the note `overlay helper not running` and the action still succeeds, and `--no-overlay` skips the socket.

### `browser` (requires the `cdp` feature)

```
browser activate    --target <TARGET>            Restrict to one tab by targetId.
browser navigate    --url <URL> --target <TARGET>
browser click       --selector <SELECTOR> --target <TARGET>
browser text        --selector <SELECTOR> --target <TARGET>
browser type        --text <TEXT> --selector <SELECTOR> --target <TARGET>
browser eval        --eval <SCRIPT> --target <TARGET>
browser tabs
```

Attach only. The CLI flag is `--cdp`, the JSON field is `cdp: true`. `computer-use` never spawns, restarts, or quits Chrome — you start Chrome with `--remote-debugging-port=N` yourself. The port is discovered by scanning the `--app` pid's argv (macOS `sysctl KERN_PROCARGS2`, Linux `/proc/<pid>/cmdline`); Windows cannot read another process's argv, so pass `--cdp-url ws://host:port` there. With no `--app` it defaults to `ws://127.0.0.1:9222`. No page target is `cdp_unavailable`, never a new page.

`browser click` uses CDP `Input.dispatchMouseEvent`, which is a page coordinate system with no screen-space transform.

## JSON actions

`action` is the tag, `snake_case`. Aliases are accepted where the field or command accepts them (`move_mouse`, `set-value`, `scroll-to`, `browser-tabs`).

| Action | Fields | 0.2.0? |
| --- | --- | --- |
| `screenshot` | `output`/`path`, `region`, `format`, `max_width`, `canvas`, `base64`, `marks` | fields beyond the 0.1.0 set are |
| `click` | `x`, `y`, `button`, `double`, `count` | `count` is |
| `double_click` | `x`, `y`, `button` | 0.1.0 |
| `triple_click` | `x`, `y`, `button` | yes |
| `move` | `x`, `y`. Alias: `move_mouse`. | 0.1.0 |
| `press` | `count`, `button` | yes |
| `type` | `text` | 0.1.0 |
| `key` | `keys` | 0.1.0 |
| `scroll` | `x`, `y`, `dx`/`scroll_x`, `dy`/`scroll_y`, `direction`, `amount` | 0.1.0 |
| `drag` | `path`, `button` | yes |
| `mouse_down` / `mouse_up` | `x`, `y`, `button` | yes |
| `hold_key` | `keys`, `ms` (≤ 30000) | yes |
| `zoom` | `region` (required), `output`/`path`, `format`, `max_width`, `canvas`, `base64` | yes |
| `clipboard_get` | none | yes |
| `clipboard_set` | `text`, `image` (PNG path) | yes |
| `focus` | none | yes |
| `set_value` | `value` | yes |
| `select_text` | `start`, `end` | yes |
| `perform_action` | `name` | yes |
| `scroll_to` | none. Aliases: `scroll-to`, `scroll_to_visible`, `scroll-to-visible`. | yes |
| `get_state` | none. Alias: `get-state`. | 0.1.0 |
| `cursor_position` | none | yes |
| `wait` | `ms`, `seconds` | 0.1.0 |
| `displays` | none | 0.1.0 |
| `isolation` | none | yes |
| `list_apps` | `all`. Alias: `list-apps`. | yes |
| `list_windows` | none. Alias: `list-windows`. | yes |
| `launch` | none (uses `--app`) | yes |
| `activate` | none (uses `--app`/`--window`) | yes |
| `quit` | `force` | yes |
| `policy_check` | none (uses `--app`) | yes |
| `pause` / `resume` | none | yes |
| `doctor` | `prompt` (alias `request`), `open_settings`, `x11` | yes |
| `tree` | none | yes |
| `ocr` | `force` | yes |
| `session_end` | none | yes |
| `session_prune` | `dry_run`, `ttl_secs` | yes |
| `menu_list` | `app` (override), `depth` | yes |
| `menu_click` | `app` (override), `path` | yes |
| `apple_event` | `app` (override), `script`, `language` | yes |
| `shortcuts_run` | `name` | yes |
| `dock_list` | none | yes |
| `dock_click` | `title` | yes |
| `spaces` | none | yes |
| `batch` | `actions` (array of native actions), `stop_on_error` | yes |
| `browser_tabs` | none | yes |
| `browser_activate` | `target_id` | yes |
| `browser_navigate` | `url`, `target_id` | yes |
| `browser_click` | `selector`, `target_id` | yes |
| `browser_text` | `selector`, `target_id` | yes |
| `browser_type` | `text`, `selector` (optional), `target_id` | yes |
| `browser_eval` | `script`, `target_id` | yes |

### Action aliases

The protocol also accepts a kebab-case spelling of these actions: `browser-activate`, `browser-click`, `browser-eval`, `browser-navigate`, `browser-text`, `browser-type`, `clipboard-set`, `dock-click`, `dock-list`, `menu-click`, `menu-list`, `session-prune`, `shortcuts-run`. The table above lists the canonical name of each.

### Batch

`action: "batch"` runs one resolved target through one cache revision sequence. `stop_on_error` defaults true and sets `stopped_at`. Each step re-validates. `return_state` runs once at the end, and a step's own `return_state` is ignored. A nested batch is `invalid_arguments`.

```json
{"action":"batch","app":"Notes","stop_on_error":true,"actions":[{"action":"click","element":12},{"action":"set_value","element":4,"value":"hello"}]}
```

### Adapters

`native` passes through. `openai` translates nine actions of the OpenAI `computer` tool shape (screenshot, click, double_click, scroll, type, keypress, move, drag, wait) and sets `coord=image`; `back` and `forward` are mouse-button values, not actions, and `hold_key`, `zoom` and `cursor_position` have no OpenAI mapping. `anthropic` translates Anthropic `computer_20251124` (left/right/middle click, double_click, triple_click, mouse_move, left_click_drag, mouse_down, mouse_up, hold_key, scroll, type, key, wait, zoom, cursor_position) and sets `coord=image`; the mouse buttons are named `left_mouse_down` and `left_mouse_up`.

Image coordinates need a stored screenshot map. There is no auto-detection.

### `--state`

`--state` (JSON `return_state`) attaches the post-action `state.tree` as numbered full text, `state.diff`, and the new revision. `--state-diff` (JSON `state_diff`) attaches the same block without the tree. That diff becomes the `tree --diff` baseline. Read-only actions ignore it. A tree or screenshot failure keeps the action result and adds `warnings`.

## Error codes

`ComputerError::code()` is the stable contract, and the same string is written into `error.code` of every failed response.

| Code | When | 0.2.0? |
| --- | --- | --- |
| `invalid_arguments` | Bad CLI flags, malformed JSON, or a missing required field. | 0.1.0 |
| `execution_failed` | Framework error that is not in this table. | 0.1.0 |
| `io_error` | stdin/stdout/filesystem failure. | 0.1.0 |
| `unsupported` | Off-platform or feature-off. | 0.1.0 |
| `app_not_found` | Name, bundle id, or pid matched nothing running, and launch was not requested. | yes |
| `window_not_found` | App resolved, window did not. | yes |
| `element_not_found` | Index missing in the cached or fresh tree, or no session cache. | yes |
| `stale_element` | The cached path's role, identifier, or frame (beyond 2 points) changed, or the cached pid, window, or revision header does not match. Action not performed. Body includes the new tree. | yes |
| `permission_required` | Accessibility or Screen Recording is off, or a portal dialog was cancelled. | yes |
| `policy_denied` | Built-in or configured deny, including secure fields. | yes |
| `confirm_required` | Sensitive action and no confirm hook is configured. | yes |
| `confirm_denied` | Hook exited non-zero or timed out. | yes |
| `blocked_url` | Browser URL matched the block list. | yes |
| `paused` | Local user input tripped the kill switch. | yes |
| `cdp_unavailable` | The `cdp` feature is built in but Chrome has no debugging port or no page target. A binary without the feature returns `unsupported` instead. | yes |
| `display_unavailable` | The screen is locked, the display is asleep, or no display or shareable window is available. Checked before `window_not_found`. | yes |

## Coordinates

Click, move, scroll, and screenshot regions use logical points. A display's `width`, `height`, `x`, and `y` are logical. `scale` is physical pixels divided by logical width. A screenshot's `width` and `height` are image pixels.

Prefer the `image_to_screen` and `screen_to_image` maps in a screenshot result over dividing by `scale` yourself. `scale` alone is wrong on a mixed-DPI desktop. Coordinates are a fallback; act by element index.

`--display <id>` narrows what may be addressed without rebasing: points stay virtual-desktop points, and a point outside the monitor is `invalid_arguments`. Right and bottom edges are exclusive.

Scroll signs follow the platform wheel: positive `dy` is down, positive `dx` is right.

## File locations

| Item | macOS / Linux | Windows |
| --- | --- | --- |
| Session cache | `${XDG_CACHE_HOME:-~/.cache}/computer-use/sessions/<session>/` | `%LOCALAPPDATA%\computer-use\cache\sessions\<session>\` |
| User policy | `~/.config/computer-use/policy.toml` | `~/.config/computer-use/policy.toml` |
| Admin policy | `/etc/computer-use/policy.toml` | `%ProgramData%\computer-use\policy.toml` |
| Audit log | `${XDG_STATE_HOME:-~/.local/state}/computer-use/audit.jsonl` | `%LOCALAPPDATA%\computer-use\audit.jsonl` |
| Foreground lock | `<cache>/foreground.lock` | `<cache>\foreground.lock` |
| Overlay socket | `<cache>/overlay.sock` | `<cache>\overlay.sock` |

Cache files are JSON, mode `0600` on Unix. They hold the last revision, the rendered tree, the structural nodes, and the last screenshot map. They do not hold secure-field values.

## CLI/library parity

Every CLI command has a matching `Action` variant or runs through `dispatch` (`serve`, `exec`, `batch`, `overlay`, the `browser` feature gate, `policy_check`, `pause`, `resume`). Two JSON actions are also reachable as commands: `batch` and `cursor_position` (as `cursor-position`). Upstream ships a test, `tests/cli_doc_matches_help.rs`, that parses its own `docs/CLI.md` and asserts each action name and subcommand is reachable on a fresh build.

This file is a copy for the agent. It is regenerated in this repository, not upstream.