#!/bin/sh
# Records the camera for the camera panel, with a live preview for its mirror.
#   camera-record.sh <device> <output.mp4> <preview.jpg> <on|off: microphone>
# Stops and finishes the file on "q" from stdin.
#
# H.264 in 4:2:0 so it plays anywhere, on NVENC when it works, else x264. Sound
# comes from the camera's own microphone if it has one, else the default one.

dev=$1
out=$2
preview=$3
mic=$4

set -- -f v4l2 -input_format mjpeg -video_size 1920x1080 -framerate 30 -thread_queue_size 512 -i "$dev"
audio=
if [ "$mic" = on ]; then
    camera=$(awk '{ print tolower($1); exit }' "/sys/class/video4linux/${dev##*/}/name" 2> /dev/null)
    source=$(pactl list sources short 2> /dev/null | awk '{ print $2 }' | grep '^alsa_input' | grep -i -m1 -- "${camera:-none}")
    set -- "$@" -f pulse -thread_queue_size 1024 -i "${source:-default}"
    audio=1
fi

set -- "$@" -filter_complex "[0:v]split=2[r][p];[r]scale=in_range=pc:out_range=tv,format=yuv420p[rec];[p]fps=15,scale=960:-2,hflip[prev]" -map "[rec]"
[ -n "$audio" ] && set -- "$@" -map 1:a -c:a aac -b:a 160k
if ffmpeg -hide_banner -v error -f lavfi -i nullsrc=s=256x256 -frames:v 1 -c:v h264_nvenc -f null - 2> /dev/null; then
    set -- "$@" -c:v h264_nvenc -preset p5 -rc vbr -cq 23 -b:v 0
else
    set -- "$@" -c:v libx264 -preset veryfast -crf 21
fi
set -- "$@" -color_range tv -movflags +faststart "$out"
set -- "$@" -map "[prev]" -f image2 -update 1 -atomic_writing 1 -q:v 6 "$preview"

exec ffmpeg -hide_banner -loglevel error -nostats -y "$@"
