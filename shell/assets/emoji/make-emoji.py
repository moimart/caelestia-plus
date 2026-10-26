#!/usr/bin/env python3
"""Builds emoji.json for the emoji picker from Unicode's emoji list and CLDR's
English keywords.

    curl -LO https://unicode.org/Public/emoji/latest/emoji-test.txt
    curl -L -o en.xml https://raw.githubusercontent.com/unicode-org/cldr/main/common/annotations/en.xml
    curl -L -o en-derived.xml https://raw.githubusercontent.com/unicode-org/cldr/main/common/annotationsDerived/en.xml
    ./make-emoji.py emoji-test.txt en.xml en-derived.xml > emoji.json

Each emoji is { e, n, k, v? }: the emoji, its name, search keywords, and its
five skin tones (light to dark) if it has them. Groups keep Unicode's order.
"""

import json
import re
import sys
import xml.etree.ElementTree as ET

TONES = ["light", "medium-light", "medium", "medium-dark", "dark"]
LINE = re.compile(r"^([0-9A-F ]+?)\s*; fully-qualified\s*# (\S+) E[\d.]+ (.+)$")
TONED = re.compile(r"^(.+): (" + "|".join(TONES) + r") skin tone$")


def keywords(paths):
    words, names = {}, {}
    for path in paths:
        for a in ET.parse(path).getroot().iter("annotation"):
            cp = a.get("cp", "").replace("️", "")
            if a.get("type") == "tts":
                names.setdefault(cp, a.text)
            else:
                words.setdefault(cp, a.text.replace(" | ", " ").lower())
    return words, names


def main():
    test, *annotations = sys.argv[1:]
    words, names = keywords(annotations)
    groups, by_name = [], {}

    for line in open(test, encoding="utf-8"):
        if line.startswith("# group: "):
            name = line[9:].strip()
            groups.append({"name": name, "emojis": []})
            continue
        m = LINE.match(line)
        if not m or groups[-1]["name"] == "Component":
            continue
        emoji, name = m.group(2), m.group(3)

        toned = TONED.match(name)
        if toned:
            base = by_name.get(toned.group(1))
            if base is not None:
                base.setdefault("v", [None] * 5)[TONES.index(toned.group(2))] = emoji
            continue
        if ":" in name and "skin tone" in name:
            continue  # mixed tones (couples): not offered

        key = emoji.replace("️", "")
        entry = {"e": emoji, "n": names.get(key, name), "k": words.get(key, "")}
        by_name[name] = entry
        groups[-1]["emojis"].append(entry)

    for g in groups:
        for e in g["emojis"]:
            # Only offer complete sets of tones
            if "v" in e and None in e["v"]:
                del e["v"]

    groups = [g for g in groups if g["emojis"]]
    json.dump({"groups": groups}, sys.stdout, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    main()
