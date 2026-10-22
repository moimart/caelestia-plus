pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.Models
import qs.services
import qs.utils

Searcher {
    id: root

    readonly property string currentNamePath: `${Paths.state}/wallpaper/path.txt`
    // A video wallpaper is set through the CLI as its poster frame (so colours
    // and hooks work as for images); this records which video the poster is for.
    readonly property string videoStatePath: `${Paths.state}/wallpaper/video.json`
    // Per-monitor wallpapers (images or videos), overriding the global one.
    readonly property string monitorsStatePath: `${Paths.state}/wallpaper/monitors.json`
    readonly property list<string> videoExtensions: ["mp4", "mkv", "webm", "mov", "m4v", "avi"]
    readonly property list<string> smartArg: GlobalConfig.services.smartScheme ? [] : ["--no-smart"]
    readonly property string fallback: Quickshell.shellPath("assets/wallpaper.webp")

    property bool showPreview: false
    readonly property string current: showPreview ? previewPath : actualCurrent
    property string previewPath
    property string actualCurrent
    property bool previewColourLock
    property string pendingPreview
    property bool pendingPreviewClear

    property var videoState: ({}) // { poster, video }
    property var overrides: ({}) // screen name -> wallpaper path
    // The global wallpaper as chosen: a video path, or the same as actualCurrent.
    readonly property string actualVideo: videoState.poster && videoState.poster === actualCurrent ? videoState.video : ""
    readonly property string actualSource: actualVideo || actualCurrent

    function isVideo(path: string): bool {
        return videoExtensions.includes(path.slice(path.lastIndexOf(".") + 1).toLowerCase());
    }

    // What to draw for a path: the poster for videos ("" until extracted).
    function thumbFor(path: string): string {
        return isVideo(path) ? Posters.get(path)?.path ?? "" : path;
    }

    // The wallpaper chosen for a screen: { image, video, time }. During a
    // preview every screen shows the previewed wallpaper as a still.
    function forScreen(name: string): var {
        if (showPreview)
            return {
                image: previewPath,
                video: "",
                time: 0
            };
        const source = overrides[name] ?? actualSource;
        if (!isVideo(source))
            return {
                image: source,
                video: "",
                time: 0
            };
        const poster = Posters.get(source);
        return {
            image: poster?.path ?? "",
            video: poster ? source : "",
            time: poster?.time ?? 0
        };
    }

    function getCategoryFor(w: FileSystemEntry): string {
        if (isVideo(w.path))
            return qsTr("Videos");
        let category = w.parentDir.slice(Paths.wallsdir.length + 1);
        if (category.includes("/"))
            category = category.slice(0, category.indexOf("/"));
        return category;
    }

    function setRandom(): void {
        Quickshell.execDetached(["caelestia", "wallpaper", "-r", ...smartArg]);
    }

    // Sets the wallpaper on every screen, clearing per-screen choices.
    function setWallpaper(path: string): void {
        if (Object.keys(overrides).length)
            saveOverrides({});
        if (!isVideo(path)) {
            actualCurrent = path;
            Quickshell.execDetached(["caelestia", "wallpaper", "-f", path, ...smartArg]);
            return;
        }
        Posters.request(path, poster => {
            videoState = {
                poster: poster.path,
                video: path
            };
            videoStateFile.setText(JSON.stringify(videoState));
            actualCurrent = poster.path;
            Quickshell.execDetached(["caelestia", "wallpaper", "-f", poster.path, ...smartArg]);
        });
    }

    // Sets the wallpaper on one screen only. The colour scheme follows the global wallpaper.
    function setWallpaperFor(screen: string, path: string): void {
        saveOverrides(Object.assign({}, overrides, {
            [screen]: path
        }));
    }

    function clearWallpaperFor(screen: string): void {
        const next = Object.assign({}, overrides);
        delete next[screen];
        saveOverrides(next);
    }

    function saveOverrides(next: var): void {
        overrides = next;
        monitorsFile.setText(JSON.stringify(next, null, 4));
    }

    function preview(path: string): void {
        if (isVideo(path)) {
            const poster = Posters.get(path);
            if (!poster) {
                // Preview once the poster exists, unless the selection moved on.
                pendingPreview = path;
                Posters.request(path, () => {
                    if (pendingPreview === path)
                        preview(path);
                });
                return;
            }
            path = poster.path;
        }
        pendingPreview = "";
        previewPath = path;
        showPreview = true;

        if (Colours.scheme === "dynamic")
            getPreviewColoursProc.running = true;
    }

    function stopPreview(): void {
        pendingPreview = "";
        showPreview = false;
        if (previewColourLock)
            pendingPreviewClear = true;
        else
            Colours.showPreview = false;
    }

    onPreviewColourLockChanged: {
        if (!previewColourLock && pendingPreviewClear)
            Colours.showPreview = false;
    }

    list: [...wallpapers.entries, ...videos.entries]
    key: "relativePath"
    useFuzzy: GlobalConfig.launcher.useFuzzy.wallpapers
    extraOpts: useFuzzy ? ({}) : ({
            forward: false
        })

    IpcHandler {
        function get(): string {
            return root.actualSource;
        }

        function set(path: string): void {
            root.setWallpaper(path);
        }

        function getFor(screen: string): string {
            return root.overrides[screen] ?? root.actualSource;
        }

        function setFor(screen: string, path: string): void {
            root.setWallpaperFor(screen, path);
        }

        function clearFor(screen: string): void {
            root.clearWallpaperFor(screen);
        }

        function list(): string {
            return root.list.map(w => w.path).join("\n");
        }

        target: "wallpaper"
    }

    FileView {
        path: root.currentNamePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let wall = text().trim();
            if (!wall) {
                wall = root.fallback;
                Quickshell.execDetached(["caelestia", "wallpaper", "-f", root.fallback, ...root.smartArg]);
            }
            root.actualCurrent = wall;
            root.previewColourLock = false;
        }
        onLoadFailed: {
            root.actualCurrent = root.fallback;
            root.previewColourLock = false;
            Quickshell.execDetached(["caelestia", "wallpaper", "-f", root.fallback, ...root.smartArg]);
        }
    }

    FileView {
        id: videoStateFile

        path: root.videoStatePath
        printErrors: false
        onLoaded: {
            try {
                root.videoState = JSON.parse(text());
            } catch (e) {
                root.videoState = {};
            }
        }
    }

    FileView {
        id: monitorsFile

        path: root.monitorsStatePath
        printErrors: false
        onLoaded: {
            try {
                root.overrides = JSON.parse(text());
            } catch (e) {
                root.overrides = {};
            }
        }
    }

    FileSystemModel {
        id: videos

        recursive: true
        path: Paths.absolutePath(GlobalConfig.paths.videoWallpaperDir)
        filter: FileSystemModel.Files
        nameFilters: [...root.videoExtensions.map(e => `*.${e}`), ...root.videoExtensions.map(e => `*.${e.toUpperCase()}`)]
    }

    FileSystemModel {
        id: wallpapers

        recursive: true
        path: Paths.wallsdir
        filter: FileSystemModel.Images
    }

    Process {
        id: getPreviewColoursProc

        command: ["caelestia", "wallpaper", "-p", root.previewPath, ...root.smartArg]
        stdout: StdioCollector {
            onStreamFinished: {
                Colours.load(text, true);
                Colours.showPreview = true;
            }
        }
    }
}
