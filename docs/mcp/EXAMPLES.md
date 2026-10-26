# Things to ask an agent

With the server set up ([README.md](README.md)), you can talk to the desktop.
A few examples, with the tools an agent would reach for ([TOOLS.md](TOOLS.md)
has their parameters).

## Look and feel

| Ask | Tools |
| --- | --- |
| "Put a video wallpaper on my left monitor, the one with the city at night." | `wallpaper_list` (with a query), `wallpaper_set` (with `monitor`) |
| "Make everything rounder and the bar a bit wider." | `config_get`, `config_set` (`border.rounding`, `bar.sizes...`) |
| "Switch to a light scheme for the afternoon." | `scheme_get`, `scheme_set` (`mode: light`) |
| "Take a screenshot and tell me why the clock looks cut off." | `screenshot`, then `config_get` / `config_set` |
| "Dim the screens to 40%." | `brightness` |

## Getting things done

| Ask | Tools |
| --- | --- |
| "What's my shortcut for the emoji picker?" | `keybinds` (with a query) |
| "Pause the music and turn on do-not-disturb, I'm in a call." | `media_control`, `notifications` |
| "Keep the screen awake while I read this." | `toggle` (`feature: idleInhibitor`, `action: enable`) |
| "Type a 🎉 where I'm writing." | `emoji` (`search`, then `type`) |
| "Open the settings on the camera page." | `panel` (`settings`) or `ipc_call` |

## The fork's features

| Ask | Tools |
| --- | --- |
| "Pair Chrome and Steam into a card, Chrome in front." | `list_windows` (for their addresses), `cards` (`pair`) |
| "Flip my card." | `cards` (`flip`) |
| "Add the eyes widget in the top right corner, almond style." | `widgets` (`add`, `place`, `configure` with `{"style":"almond"}`) |
| "Is any app using my camera right now?" | `camera` (`status`) |
| "Turn on hand gestures." | `camera` (`gestures`) |
| "Zoom the camera in a bit and save that as my 'desk' preset." | `camera` (`controls`, `set`), then the camera panel for saving presets |

## Anything the shell can do

Every panel and feature has IPC functions; `ipc_list` shows them all and
`ipc_call` runs one. That's how an agent reaches things the dedicated tools
don't cover, like `ipc_call picker openClip` for the screenshot picker.
