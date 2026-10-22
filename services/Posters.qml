pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

// Poster frames for video wallpapers, extracted with ffmpeg and cached. A
// poster is the frame at `time` seconds; playback starts at the same time so
// the poster hands over to the video seamlessly. Posters double as picker
// thumbnails and as the image the colour scheme is generated from.
Singleton {
    id: root

    readonly property string dir: `${Paths.cache}/videoposters`
    property var posters: ({}) // video path -> { path, time }
    property var failed: ({}) // video path -> true; not retried until restart
    // Mutated in place, never reassigned: get() runs inside bindings, and a
    // notifying property here would make those bindings loop.
    readonly property var queue: []

    signal ready(video: string, poster: var)

    // The poster for a video, or null while it's being extracted (bindings
    // re-evaluate when `posters` updates).
    function get(video: string): var {
        const poster = posters[video];
        if (poster)
            return poster;
        if (!failed[video] && !queue.includes(video)) {
            queue.push(video);
            Qt.callLater(next);
        }
        return null;
    }

    // Calls back with the poster as soon as it exists.
    function request(video: string, callback: var): void {
        const poster = get(video);
        if (poster || failed[video]) {
            if (poster)
                callback(poster);
            return;
        }
        const conn = (v, p) => {
            if (v !== video)
                return;
            ready.disconnect(conn);
            if (p)
                callback(p);
        };
        ready.connect(conn);
    }

    function next(): void {
        if (proc.running || queue.length === 0)
            return;
        proc.video = queue[0];
        proc.running = true;
    }

    Process {
        id: proc

        property string video

        // Reuse a cached poster, else try 1s in, then the first frame for very short clips.
        command: ["sh", "-c", `out="$2"; mkdir -p "$(dirname "$out")"
for t in 1 0; do [ -s "$out-$t.jpg" ] && { echo "$t $out-$t.jpg"; exit 0; }; done
for t in 1 0; do
    ffmpeg -v error -nostdin -y -ss "$t" -i "$1" -frames:v 1 -q:v 2 "$out-$t.jpg" && [ -s "$out-$t.jpg" ] && { echo "$t $out-$t.jpg"; exit 0; }
    rm -f "$out-$t.jpg"
done
exit 1`, "sh", video, `${root.dir}/${Qt.md5(video)}`]

        stdout: StdioCollector {
            onStreamFinished: {
                const video = proc.video;
                const [time, ...path] = text.trim().split(" ");
                let poster = null;
                if (path.length) {
                    poster = {
                        path: path.join(" "),
                        time: Number(time)
                    };
                    root.posters = Object.assign({}, root.posters, {
                        [video]: poster
                    });
                } else {
                    console.warn(`Posters: could not extract a frame from ${video}`);
                    root.failed = Object.assign({}, root.failed, {
                        [video]: true
                    });
                }
                const i = root.queue.indexOf(video);
                if (i >= 0)
                    root.queue.splice(i, 1);
                root.ready(video, poster);
            }
        }

        onExited: Qt.callLater(root.next)
    }
}
