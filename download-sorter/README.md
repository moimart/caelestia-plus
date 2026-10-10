# download-sorter

Moves finished downloads out of `~/Downloads` by extension rules. Standard
library Python, inotify via ctypes. A file is moved once it has been closed
after writing or renamed into place (browsers rename `.part`/`.crdownload`
when done) and has then stayed unchanged for `settle` seconds.

- Config: `~/.config/download-sorter/config.toml` (see `config.example.toml`), reloaded on save
- Service: `systemctl --user {status,restart,stop} download-sorter`
- Log: `journalctl --user -u download-sorter -f`

## appimage-desktop

Keeps launcher entries in sync with `~/Applications`: every `*.AppImage` there
gets a `.desktop` file in `~/.local/share/applications` and an icon in
`~/.local/share/icons/hicolor`, removed again when the AppImage goes. Name,
categories and icon come from the AppImage's embedded `.desktop` file, read
with `7z` (nothing inside the AppImage is executed); unreadable ones get a
plain entry named after the file. Files it wrote are listed in
`~/.local/state/appimage-desktop/state.json` and only those are ever deleted.

- Service: `systemctl --user {status,restart,stop} appimage-desktop`
- Log: `journalctl --user -u appimage-desktop -f`
- One-off sync: `./appimage-desktop.py --once [folder]`
