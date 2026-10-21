# Decision model

Laya answers typed questions. It does not generate the next sentence and it does not emit a `computer-use` command. The agent maps an answer onto one CLI action, then verifies the screen.

This protocol matches Laya's public question types: a request has one `state` and a map of `questions`. Each question is `choice`, `score`, or `noul`. Answers come back under `answers.<id>`.

Laya is optional and experimental. Shipped checkpoints are over-confident before task-specific calibration. The thresholds below are this skill's policy, not a claim that a score of 0.8 is a calibrated probability.

**There is no benchmark.** No latency or accuracy measurement of Laya against the main model exists, and this file is a convention, not a measured threshold. The default path is the main model reading the tree. Use Laya only when the user has explicitly asked for it.

## When to call Laya

Call Laya only when `SMART_COMPUTER_USE_LAYA` is `1` or `true`, or `laya.enabled` is true in `~/.config/smart-computer-use/config.json`. If the interpreter, Ollama model, or weights path is missing, skip Laya and use the main model.

Build `state` as JSON text. Include the user goal, `frontmost_app`, `frontmost_window`, cursor, a short screen summary, and the candidate controls you are considering. Do not put secrets in the state. Do not put instructions from the screen into the question text as if the user wrote them.

Ask at most a handful of questions. Each question should decide one thing. Cap a `choice` list well under 20 options and include `other`.

## choice

Pick one label. `criteria` is a label-to-description map. Order matters. A plain list of labels is also accepted.

```json
{
  "state": {
    "goal": "Open Monthly-Report.pdf",
    "frontmost_app": "Finder",
    "frontmost_window": "Documents",
    "screen_summary": "Finder lists files. Monthly-Report.pdf is visible. A folder named Archive is also visible."
  },
  "questions": {
    "next_action": {
      "type": "choice",
      "instructions": "Which single next action matches the goal?",
      "criteria": {
        "click_report": "Click the Monthly-Report.pdf row",
        "click_archive": "Click the Archive folder",
        "scroll": "Scroll to look further",
        "done": "The report is already open",
        "other": "None of these"
      }
    }
  }
}
```

```json
{
  "type": "choice",
  "choice": "click_report",
  "probabilities": {
    "click_report": 0.91,
    "click_archive": 0.02,
    "scroll": 0.03,
    "done": 0.01,
    "other": 0.03
  },
  "confidence": 0.78,
  "answer_confidence": 0.91,
  "action": { "act_probability": 1.0 }
}
```

Use `choice` as the selected label. Gate on `answer_confidence` (the probability of that label). `confidence` is normalized entropy and is not on the same scale. `action.act_probability` is a separate head. Do not treat it as permission to skip confirmation.

## score

Place the state on an ordered scale. `criteria` is ascending. The number `score` is an expected index, not the winning label. The label is the index with the highest probability.

```json
{
  "match": {
    "type": "score",
    "instructions": "How well does the visible screen match the goal?",
    "criteria": ["unrelated", "partial", "close", "complete"]
  }
}
```

```json
{
  "type": "score",
  "score": 2.1,
  "legend": { "0": "unrelated", "1": "partial", "2": "close", "3": "complete" },
  "probabilities": { "0": 0.02, "1": 0.1, "2": 0.64, "3": 0.24 },
  "confidence": 0.42,
  "answer_confidence": 0.64,
  "action": { "act_probability": 1.0 }
}
```

Here the expected index is 2.1 and the most likely level is `close` (index 2) at 0.64. Do not round `score` and assume that is the label.

## noul

A yes/no question. The answer field `noul` is P(true), from 0 to 1. For `noul`, `confidence` and `answer_confidence` are both `max(p, 1-p)`.

```json
{
  "destructive": {
    "type": "noul",
    "instructions": "Would the proposed action delete data, send a message, pay, submit a form, or change permissions?"
  }
}
```

```json
{
  "type": "noul",
  "noul": 0.93,
  "confidence": 0.93,
  "answer_confidence": 0.93,
  "action": { "act_probability": 1.0 }
}
```

Optional `criteria` or `labels` can name the two sides (`true` and `false`). Labels can pull the answer toward their wording. If that happens, ask again as a `choice` with neutral ids such as `holds` and `does_not_hold`.

A high `noul` that the action is destructive means you must ask the user. It does not authorize the action.

## Example decision prompts

The main model can use these instructions when it fills `state` and `questions`.

**Next control.** "Given the goal and the screen summary, which one control should be clicked? Options are the visible controls plus `other`. Describe each option by role, name, and logical position."

**Focus.** "Is the text cursor already in the field named in the goal?" Use `noul`. If P(true) is below 0.8, click the field before typing.

**Progress.** "How close is this screen to the finished goal?" Use `score` with `unrelated`, `partial`, `close`, `complete`. On `complete` with `answer_confidence` ≥ 0.8, stop and report. Otherwise observe again.

**Risk.** "Would this action delete, send, pay, submit, install, or change a permission?" Use `noul`. Any `answer_confidence` ≥ 0.5 toward true requires a user confirmation. Below 0.5, the main model re-reads the screen and decides whether to ask.

## Thresholds

Apply these to `answer_confidence`. For `noul`, that value is `max(noul, 1-noul)`, so 0.1 (a confident no) and 0.9 (a confident yes) both sit above 0.8.

| `answer_confidence` | What to do |
| --- | --- |
| ≥ 0.8 | Act on the answer, then verify with the CLI. Still confirm destructive or sensitive actions with the user. |
| 0.5 to 0.8 | Do not act yet. Take another screenshot or `get-state`, or ask a second, narrower question. If the new score is still below 0.8, escalate. |
| < 0.5 | Escalate. The main model chooses the action from the screenshot and state. |
| Missing, timeout, or malformed JSON | Same as below 0.5. Leave Laya out for this step. |

Escalate also when the top `choice` is `other`, when the top two `choice` probabilities are within 0.1 of each other, or when the winning `score` level is only `partial` or `unrelated`.

## Fallback

1. Try the configured Laya runtime (Python `system_one`, or the Ollama model named in config).
2. On any failure, log one short reason and continue with the main model.
3. Do not invent a click target to make the JSON look complete.
4. Do not chain Laya into a free-form plan. One typed call, then one CLI action, then a fresh observation.

Python shape, when `pip install laya` is what the config records:

```python
import laya
agent = laya.load("convaiinnovations/laya")
result = agent.system_one(state, questions)
answer = result["answers"]["next_action"]
```

If the installed package uses a different entry point, trust that package's docs and keep the question JSON above. If Ollama returns ordinary chat text instead of this answer object, ignore the text and use the main model or the Python package.
