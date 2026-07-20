# screenshot-rename

Automatically renames macOS screenshots based on what's actually in them, using Claude — instead of the opaque `SCR-20260710-abcd.png` style names most screenshot tools default to.

A background `launchd` agent watches a folder. Whenever a new screenshot lands there, it asks Claude (via the [Claude Code](https://claude.com/product/claude-code) CLI, headless mode) for a short caption, sanitizes that into a filename, and renames the file — handling naming collisions and giving up gracefully (never deleting or corrupting anything) if a file can't be captioned after a few tries.

Example: `SCR-20260710-abcd.png` → `operate-incident-view-process-instance-timeline.png`

## How it works

1. A screenshot tool (built and tested against [Shottr](https://shottr.cc), but anything that lets you set a custom save folder works) saves a new screenshot into a watched folder.
2. `launchd`'s `WatchPaths` fires `rename-screenshot.sh` whenever that folder changes.
3. The script finds any files still matching the raw `SCR-YYYYMMDD-xxxx.{png,jpg,jpeg}` naming pattern, and for each:
   - Calls `claude -p` (Haiku model) with the image path embedded in the prompt, asking for a short descriptive slug.
   - Sanitizes the response into a filename-safe slug (lowercase, hyphenated, `a-z0-9-` only).
   - Renames the file, appending a `-YYYYMMDD-HHMMSS` timestamp suffix only if there's a naming collision.
4. On any failure (Claude call fails, or the caption sanitizes to nothing), the original file is left completely untouched, an attempt is logged and counted, and after 3 failed attempts the script stops retrying that specific file and logs it as needing a manual look.
5. If `launchd`'s trigger fires before a screenshot has fully settled on disk, the script internally retries the scan a few times (2 seconds apart) within that same invocation before giving up — no separate polling process, no cost when idle.

## ⚠️ Important: where NOT to put the watched folder

**Do not point this at a folder inside `~/Downloads`, `~/Desktop`, or `~/Documents`.** These are macOS privacy-protected (TCC) folders. A background process without Full Disk Access doesn't get a permission *error* there — it silently sees the folder as **completely empty**, even though the files are really there. This will make the automation appear to do absolutely nothing, with no error anywhere, and it's genuinely confusing to debug.

Use a plain folder directly under your home directory instead (e.g. `~/Screenshots`) — those aren't subject to this restriction, confirmed by direct testing. If you'd rather keep the folder inside Downloads/Desktop/Documents anyway, you'll need to grant Full Disk Access to `/bin/bash` in System Settings → Privacy & Security → Full Disk Access.

## Prerequisites

- macOS (uses `launchd`, BSD `stat -f`, and other macOS-specific tooling — this will not run on Linux)
- [`jq`](https://jqlang.github.io/jq/) — `brew install jq`
- The [Claude Code CLI](https://claude.com/product/claude-code) installed and logged in (`claude` on your `PATH`, `claude /login` completed). This project reuses that login — no separate API key needed.
- A screenshot tool that can be configured to save to a specific folder (e.g. [Shottr](https://shottr.cc), or any similar tool)

## Installation

1. **Clone the repo** somewhere permanent, e.g.:
   ```bash
   git clone https://github.com/aleksander-dytko/screenshot-rename.git ~/.local/bin/screenshot-rename
   ```

2. **Create the watched folder** — a plain folder directly under your home directory (see the warning above):
   ```bash
   mkdir -p ~/Screenshots
   ```

3. **Point your screenshot tool's save location** at that folder (in Shottr: Preferences → Save → set the folder to `~/Screenshots`).

4. **Edit the plist** (`com.aleksander.screenshot-rename.plist`) to match your machine — it needs real absolute paths since `launchd` plists can't expand `~` or `$HOME`. Replace every occurrence of `/Users/aleksander.dytko` with your own home directory path:

   | Key | Should point to |
   |---|---|
   | `ProgramArguments` | Wherever you cloned this repo's `rename-screenshot.sh` |
   | `WatchPaths` | Your watched folder (e.g. `/Users/yourname/Screenshots`) |
   | `EnvironmentVariables` → `PATH` | Must include the directory containing your `claude` binary (check with `which claude`) and `jq` (`which jq`) — on Apple Silicon Homebrew that's `/opt/homebrew/bin`, on Intel Macs it's `/usr/local/bin` |
   | `StandardOutPath` / `StandardErrorPath` | Wherever you want the agent's own stdout/stderr logged |

   Also consider changing the `Label` (`com.aleksander.screenshot-rename`) to something with your own name/identifier, so it doesn't collide if you ever install another copy of this.

5. **Load the agent:**
   ```bash
   launchctl bootstrap gui/$(id -u) ~/.local/bin/screenshot-rename/com.aleksander.screenshot-rename.plist
   ```

6. **Verify it's loaded:**
   ```bash
   launchctl list | grep screenshot-rename
   ```

7. Take a screenshot and check the watched folder a few seconds later — it should show up renamed instead of `SCR-*`.

## Configuration

All of these are environment variables read by `rename-screenshot.sh`, with sensible defaults — set them via the plist's `EnvironmentVariables` if you want to override them:

| Variable | Default | Purpose |
|---|---|---|
| `SCREENSHOTS_DIR` | `$HOME/Screenshots` | The watched folder |
| `ATTEMPTS_FILE` | `$HOME/Library/Application Support/screenshot-rename/attempts.json` | Per-file failed-attempt counter, so a permanently-broken file doesn't get retried forever |
| `LOG_FILE` | `$HOME/Library/Logs/screenshot-rename.log` | Human-readable log of every rename, failure, and give-up |
| `MAIN_RETRY_COUNT` | `3` | How many times to rescan the folder within one triggered run before giving up |
| `MAIN_RETRY_DELAY` | `2` (seconds) | Delay between rescans |
| `CLAUDE_BIN` | `claude` | Override the Claude CLI binary — mainly useful for testing with a stub |

## Testing

The test suite is plain bash, no framework, fully offline (it stubs the `claude` CLI, never calls the real API):

```bash
~/.local/bin/screenshot-rename/rename-screenshot.test.sh
```

## Uninstalling

```bash
launchctl bootout gui/$(id -u)/com.aleksander.screenshot-rename
rm -rf ~/.local/bin/screenshot-rename
rm -rf ~/Library/Application\ Support/screenshot-rename
rm -f ~/Library/Logs/screenshot-rename.log ~/Library/Logs/screenshot-rename.stdout.log ~/Library/Logs/screenshot-rename.stderr.log
```

(Your watched folder and its contents are left alone — delete `~/Screenshots` yourself if you don't want it anymore.)
