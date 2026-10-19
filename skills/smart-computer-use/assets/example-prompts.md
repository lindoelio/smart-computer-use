# Example prompts

These are tasks a user might give the agent. Each one follows observe, decide, act, verify. Confirm with the user before any step marked sensitive.

## Open a file in Finder

User: "Open Monthly-Report.pdf in Documents."

1. `computer-use get-state` to see the frontmost app.
2. If Finder is not in front, `computer-use key` with the platform shortcut or click the Finder icon, then observe again.
3. Click the file only after the screenshot shows that name. Logical coordinates come from the accessibility tree or from image pixels divided by `scale`.
4. Verify the frontmost window title changed.

## Search in a browser

User: "Search the web for the weather in Lisbon."

1. Observe. Focus the address bar only if the summary shows a browser window.
2. `computer-use key --keys "cmd+l"` on macOS, or `ctrl+l` on Linux and Windows.
3. `computer-use type --text "Lisbon weather"` and `computer-use key --keys "enter"`.
4. `computer-use wait --ms 500`, then screenshot. Scroll only if the result is not visible.

Do not type an account password if a sign-in wall appears. Stop and tell the user.

## Read a window title

User: "What app is in front, and what is the window called?"

`computer-use get-state` is enough. Report `frontmost_app` and `frontmost_window`. If they are null, read `note` and say what permission is missing. Do not click.

## Scroll a long page

User: "Scroll the release notes until you see version 0.1.0."

1. Screenshot.
2. `computer-use scroll --direction down --amount 3` over the page (`--x` and `--y` together when the pointer must move first).
3. Screenshot again. Stop when the version is visible or after a few scrolls with no change.

## Fill a non-secret form

User: "In the feedback form, set the subject to Printer jam and leave the rest."

1. Observe and confirm the field name.
2. Click the subject field. `computer-use type --text "Printer jam"`.
3. Screenshot and check the field.
4. Do not press the submit control. Submitting is sensitive. Ask the user first.

## Sensitive: moving a file to the trash

User: "Delete the file Draft.txt on the Desktop."

This is destructive. Before any `key` or `click`:

1. Observe and quote the exact file name and location back to the user.
2. Wait for an explicit yes.
3. Only then select that file and move it to trash.
4. Verify the file is no longer in the folder.

If the user has not confirmed, do not press `cmd+delete`, Delete, or Empty Trash.

## Laya chooses between two buttons

User: "Click Save, not Save As."

The main model writes a text state that names both buttons and their logical positions, then asks a `choice` question with `save`, `save_as`, and `other`. Act on `save` only when `answer_confidence` is at least 0.8. Otherwise look at the screenshot again. Saving can overwrite a file. If the document already exists, ask the user before the click.
