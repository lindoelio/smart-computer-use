# Laya setup

Laya is optional and experimental, and **not measured**: no latency or accuracy benchmark exists. The skill runs without it, and a failed install must not block `computer-use`. The default path is the main model reading the tree.

The installer is `scripts/install-laya.sh`. `scripts/setup.sh --with-laya` calls it with `--yes` and keeps going if it cannot install Laya.

## What the script looks for

In order:

1. An Ollama model whose name is `laya` or starts with `laya:` (`ollama list`).
2. A `laya` executable on `PATH`.
3. A directory in `LAYA_MODEL_PATH`.

If one of those is present, the script writes config and does not reinstall.

## Install

Interactive (a terminal, no `--yes`):

```bash
bash scripts/install-laya.sh
```

The script offers:

- `ollama pull laya`
- `pip install laya` (`pip3`, `pip`, or `python3 -m pip`, with `--user`)
- skip

Non-interactive:

```bash
bash scripts/install-laya.sh --method ollama --yes
bash scripts/install-laya.sh --method pip --yes
bash scripts/install-laya.sh --yes
```

`--yes` alone picks Ollama when `ollama` is on `PATH`, otherwise pip when a pip command exists, otherwise it prints instructions and exits 0. `--method` is `ollama` or `pip`.

Ollama must already be installed. This script does not download the Ollama app. The Python package is the path that implements typed `choice`, `score`, and `noul` questions. An Ollama tag named `laya` is recorded so the agent can try `http://127.0.0.1:11434`. If that server returns chat prose instead of the answer JSON in [decision-model.md](decision-model.md), ignore it.

## Config

The script writes `~/.config/smart-computer-use/config.json`:

```json
{
  "laya": {
    "enabled": true,
    "experimental": true,
    "endpoint": "http://127.0.0.1:11434",
    "model": "laya",
    "path": "",
    "method": "ollama"
  }
}
```

`method` is `ollama`, `pip`, `cli`, or `weights`. `path` is set when `LAYA_MODEL_PATH` points at a directory. `enabled` is false when the user skips install.

The CLI never reads this file.

## Environment

```bash
export SMART_COMPUTER_USE_LAYA=1
export SMART_COMPUTER_USE_LAYA_MODEL=laya
export SMART_COMPUTER_USE_LAYA_ENDPOINT=http://127.0.0.1:11434
export SMART_COMPUTER_USE_LAYA_PATH=
```

| Variable | Meaning |
| --- | --- |
| `SMART_COMPUTER_USE_LAYA` | `1` or `true` turns Laya on. `0` or `false` turns it off. `ollama` or `pip` selects that method. |
| `SMART_COMPUTER_USE_LAYA_MODEL` | Model name. Default `laya`. |
| `SMART_COMPUTER_USE_LAYA_ENDPOINT` | HTTP endpoint, usually the Ollama daemon. |
| `SMART_COMPUTER_USE_LAYA_PATH` | Weights directory, overriding `LAYA_MODEL_PATH`. |

Environment variables override the config file for that process. Unset `SMART_COMPUTER_USE_LAYA` means "read `laya.enabled` from the config file".

## Turn it off

Set `SMART_COMPUTER_USE_LAYA=0` or `"enabled": false`. The CLI setup is unchanged.
