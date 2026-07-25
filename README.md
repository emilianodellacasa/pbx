# pbx

A terminal UI dashboard for monitoring an Asterisk PBX via AMI (Asterisk Manager Interface).

## Features

- **Peers tab** (`p`) — live SIP/PJSIP peer status with IP address, port, type, RTT, and last-change time
- **Calls tab** (`c`) — active channel tracking with state, dialplan app, connected party, and duration
- **Queues tab** (`q`) — queue summary with strategy, callers waiting, available/total agents, completed, abandoned, and average hold time
- All three tabs update in real time from the AMI event stream
- Press `e` or `Esc` or `Ctrl-C` to quit; press `i` for the info modal

## Requirements

- Ruby >= 3.2
- An Asterisk PBX with AMI enabled

## Installation

```bash
git clone https://github.com/emilianodellacasa/pbx
cd pbx
bundle install
```

## Usage

```bash
bundle exec exe/pbx monitor --host HOST --port PORT --user USER --secret SECRET
```

All flags are optional and fall back to the values in the config file, then to built-in defaults (`127.0.0.1:5038`).

### Options

| Flag | Default | Description |
|------|---------|-------------|
| `--host` | `127.0.0.1` | AMI host |
| `--port` | `5038` | AMI port |
| `--user` | — | AMI username |
| `--secret` | — | AMI password |
| `--config`, `-c` | — | Path to a YAML config file |
| `--debug` | — | Write raw AMI traffic to `/tmp/pbx_debug.log` |

### YAML configuration

Create a file (e.g. `~/.pbx.yml`) and pass it with `-c`:

```yaml
host: pbx.example.com
port: 5038
user: monitor
secret: s3cret
```

CLI flags override YAML values; YAML values override built-in defaults.

## Keyboard shortcuts

| Key | Action |
|-----|--------|
| `p` | Peers tab |
| `c` | Calls tab |
| `q` | Queues tab |
| `↑` / `↓` | Scroll the active table |
| `i` | Info modal |
| `e` / `Esc` / `Ctrl-C` | Quit |

## AMI user setup

The monitor only needs read access — it issues just `Login`, `SIPpeers`,
`PJSIPShowEndpoints`, `QueueStatus`, `Events` and `Logoff`, none of which
require a write class. A minimal `/etc/asterisk/manager.conf` entry:

```ini
[monitor]
secret = s3cret
read = system,call,agent,reporting,dialplan
```

`system` covers peer and endpoint discovery, `agent` and `reporting` the queue
events, `call` the channel events and `dialplan` the `Newexten` app updates.

## Development

```bash
bundle exec rspec        # run the test suite
bundle exec standardrb   # check code style
bundle exec standardrb --fix  # auto-fix style violations
```
