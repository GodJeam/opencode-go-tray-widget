# OpenCode Go Tray Widget

A lightweight **Windows 11 system tray widget** that shows your **OpenCode Go** usage limits (5-hour rolling, weekly, and monthly) at a glance â€” no need to open the console in a browser.

> **Note**: this project was entirely generated using large language models (LLMs) via opencode. The code received **little personal review**: use it with due caution, test it, and report or fix any issues you find.

## Features

- **Tray icon with live percentage**: a colored dot showing the current 5-hour window usage (green < 50%, orange >= 50%, red >= 80%, gray on connection error).
- **Flyout panel on click**: left-click opens a small dark panel with rounded corners showing all three windows.
- **Progress bars**: one per window (5 hours / weekly / monthly) with color-coded fill, percentage, and reset time.
- **Auto refresh** every 5 minutes, plus manual refresh from the context menu.
- **Zero dependencies**: pure PowerShell + WinForms, no extra modules to install.
- **No secrets stored in code**: reads your existing API key from `~/.local/share/opencode/auth.json`.

## Requirements

- Windows 10/11
- PowerShell 5.1 (built into Windows)
- An active **OpenCode Go** subscription with a configured API key

The widget uses your existing opencode authentication: it reads the `opencode-go` key from `%USERPROFILE%\.local\share\opencode\auth.json`, so there is nothing to configure if you already use OpenCode Go from the CLI.

## Installation

1. Clone the repo:

```bash
git clone https://github.com/GodJeam/opencode-go-tray-widget.git
cd opencode-go-tray-widget
```

2. Double-click `launch-widget.vbs` (or run it from a terminal):

```powershell
wscript.exe launch-widget.vbs
```

A colored dot appears in the system tray (it may be inside the hidden icons overflow, next to the clock).

### Start at login (optional)

Create a shortcut to `launch-widget.vbs` in the Startup folder:

```powershell
$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\OpenCode Widget.lnk")
$lnk.TargetPath = "<path-to>\launch-widget.vbs"
$lnk.Save()
```

## Usage

- **Left-click** the tray icon: opens/closes the flyout panel with the three usage bars.
- **Right-click**: context menu with **Refresh**, **Details** (flyout), **Open Console** (opens the OpenCode console), and **Exit**.
- Press `Esc` or click elsewhere to close the flyout.
- Logs are written to `%TEMP%\opencode-widget.log` for troubleshooting.

## How it works

The widget calls the official endpoint:

```
GET https://opencode.ai/zen/go/v1/usage
Authorization: Bearer <your-opencode-go-key>
```

which returns the status, percentage, and reset time for each window. The API key is read at runtime from your local opencode auth file and is never sent anywhere else.

## Structure

- `opencode-tray.ps1` â€” tray icon, flyout UI, polling timer, and API calls
- `launch-widget.vbs` â€” launcher that starts the widget without a visible console window
- `LICENSE` â€” GPL-3.0 license text

## License

GPL-3.0 â€” see [LICENSE](LICENSE).

