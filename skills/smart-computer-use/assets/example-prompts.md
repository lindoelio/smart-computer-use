# Example prompts

Tasks a user might give the agent. Each one follows target, observe, decide, act, verify. Confirm with the user before any step marked sensitive.

These examples use the 0.3.0 surface: `list-apps`, `tree`, `--element`, `--session`, `--state-diff`, `--tier`, and `policy check`. Every command of a flow carries the same `--session` id, and every mutating command ends with `--state-diff` so the delta comes back in the same round trip.

## Open a file in Finder

User: "Open Monthly-Report.pdf in Documents."

1. `computer-use list-apps` to confirm Finder is running and get its bundle id.
2. `computer-use list-windows --app Finder` to see the windows in z-order, index 0 in front.
3. `computer-use tree --session finder --app Finder --window 0 --full` and read the numbered rows.
4. `computer-use press --session finder --app Finder --element <N> --state-diff` on the file row. Read `state.diff`, not the screen.
5. If the tree is empty, `computer-use screenshot --app Finder --window 0 --marks` and press the index stamped on the image.

## Search in a browser

User: "Search the web for the weather in Lisbon."

Prefer CDP when the browser exposes it — it needs no Accessibility and does not move the cursor:

1. `computer-use --cdp browser tabs` and pick a `type == "page"` target.
2. `computer-use --cdp browser navigate --url "https://duckduckgo.com/?q=Lisbon+weather" --target <TARGET>`.
3. `computer-use --cdp browser text --selector "h1" --target <TARGET>` to confirm the page loaded.

Without CDP, drive the window: `tree --session web --app "Google Chrome" --window 0`, then `press --session web --element <address bar>`, `type --session web --text "https://duckduckgo.com/?q=Lisbon+weather"`, `press --session web --element <go>`.

Do not type an account password if a sign-in wall appears. Stop and tell the user.

## Read a window title

User: "What app is in front, and what is the window called?"

`computer-use get-state` is enough. Report `frontmost_app` and `frontmost_window`. If they are `null`, read `note` and say what permission is missing. Do not click.

To enumerate instead: `computer-use list-apps` and `computer-use list-windows`.

## Scroll a long page

User: "Scroll the release notes until you see version 0.2.0."

1. `computer-use tree --session notes --app <app> --window 0` and look for a scrollable row.
2. `computer-use press --session notes --app <app> --element <N> --count 3 --state-diff`, or `computer-use scroll --session notes --direction down --amount 3 --x <x> --y <y>` when there is no element.
3. Each `--state-diff` returns the delta, so compare against the previous turn instead of screenshotting. Stop when the version appears or after a few scrolls with no change.

Use `--tier ax` or `--tier event` when the user is at the keyboard and you must not move the cursor.

## Fill a non-secret form

User: "In the feedback form, set the subject to Printer jam and leave the rest."

1. `tree --session form --app <app> --window 0` and identify the subject field by role and title.
2. `computer-use set-value --session form --app <app> --element <N> --value "Printer jam" --state-diff`. That sets the value through the accessibility interface rather than typing keystrokes, and refuses a secure field outright.
3. Read `state.diff` and confirm the field changed.
4. Do not press the submit control. Submitting is sensitive. Ask the user first.

If `set-value` returns `stale_element`, the page moved: re-read with `tree --session form --full` and re-derive the index. Do not resend the same number.

## Read a canvas or a game surface

User: "Click the button at the top right of this canvas."

There is no element for a canvas. Fall back to pixels:

1. `computer-use screenshot --output /tmp/canvas.png` and read the target position in image pixels.
2. Convert with the result's `image_to_screen` map, not by dividing by `scale`.
3. `computer-use click --session canvas --x <logical x> --y <logical y> --state-diff`.

Say plainly that this is a coordinate guess and could miss.

## Browser via Chrome DevTools Protocol

User: "Log into the dashboard and report the last five orders."

1. Tell the user to start Chrome with `--remote-debugging-port=9222` first. `computer-use` attaches only and will not start or restart Chrome.
2. `computer-use --cdp browser tabs`.
3. `computer-use --cdp browser text --selector "table"` and report what is on the page.

If a URL returns `blocked_url`, it is on `[browser].blocked_urls`. Do not look for another route. Never type credentials — ask the user to sign in themselves.

## Sensitive: moving a file to the trash

User: "Delete the file Draft.txt on the Desktop."

This is destructive. Before any `press` or `key`:

1. `computer-use policy check --app Finder` — read `decision`, not `ok`.
2. Read the tree, quote the exact file name and location back to the user, and wait for an explicit yes.
3. Only then `computer-use press --session trash --app Finder --element <the Draft.txt row> --state-diff` to select it.
4. Confirm again, then move it to the trash with a fresh observation between the two steps.
5. Verify the file is gone from the folder listing.

If the user has not confirmed, do not press `cmd+delete`, Delete, or Empty Trash. Do not batch a destructive step with anything else.

## The user is at the keyboard

User: "Keep going, but do not steal my mouse."

Use `--require-background` so a cursor move fails instead of falling back to foreground input:

```bash
computer-use --require-background press --session notes --app Notes --element 12
```

Prefer `--tier ax` for presses and values, and `--tier event` for coordinates. With `pause_on_user_input = true` in the policy file, the agent pauses itself when they touch the machine. `computer-use resume` clears it.

## Laya chooses between two buttons

User: "Click Save, not Save As."

The main model writes a text state naming both buttons from the numbered tree, then asks a `choice` question with `save`, `save_as`, and `other`. Act on `save` only when `answer_confidence` is at least 0.8. Otherwise read the tree again.

Saving can overwrite a file. If the document already exists, ask the user before pressing.
## Use a menu instead of a tree row

User: "Save As to the Desktop."

Menu bars are the classic hole in the accessibility tree, and the CLI walks them by name:

1. `computer-use menu list --app <app> --depth 2` to see the menu titles.
2. `computer-use menu click --app <app> --path "File > Save As > Save"` — one call, no index, no coordinates.
3. `computer-use get-state --app <app>` to confirm the sheet that opened.

Reach for `menu click` before hunting for a menu row in the tree, and before a coordinate guess on the menu bar.

## Verify what was typed

User: "Type 'hello' in the search box and make sure it landed."

1. `computer-use type --session search --app <app> --text "hello" --state-diff` to type it.
2. `computer-use clipboard get` to read back what the field holds — cheaper than re-reading the tree, and it works on a field the tree does not expose.
3. If the field is a secure field, the type is refused with `policy_denied`. Ask the user to type it.
