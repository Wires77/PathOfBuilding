"""Refresh pinned NeverSink templates and GGG's 3.30 item-filter announcement.

Network access is explicit. Generated data is shipped for offline use.
"""
import argparse
import hashlib
import json
import re
import urllib.parse
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "src/Data/LootFilters"
ANNOUNCEMENT = "https://www.pathofexile.com/forum/view-thread/4013923"
REVIEWED_COMMIT = "9f94f4bd120574b4aa5a3366ceac461f8b733264"


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "PathOfBuilding-AI-Edition"})
    with urllib.request.urlopen(request, timeout=45) as response:
        return response.read()


class Post(HTMLParser):
    def __init__(self):
        super().__init__()
        self.depth = 0
        self.done = False
        self.parts = []
        self.news_post = False

    def handle_starttag(self, tag, attrs):
        if self.done:
            return
        if tag == "tr" and "newsPost" in dict(attrs).get("class", "").split():
            self.news_post = True
        if tag == "div":
            if self.depth:
                self.depth += 1
            elif self.news_post and "content" in dict(attrs).get("class", "").split():
                self.depth = 1
        if self.depth and tag in ("br", "div", "p"):
            self.parts.append("\n")

    def handle_endtag(self, tag):
        if tag == "tr":
            self.news_post = False
        if self.depth and tag == "div":
            self.depth -= 1
            if not self.depth:
                self.done = True

    def handle_data(self, text):
        if self.depth:
            self.parts.append(text)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--commit", default=REVIEWED_COMMIT)
    parser.add_argument("--native-patch", choices=["3.30"], help="Mark a reviewed template as native to this game patch")
    args = parser.parse_args()
    assert re.fullmatch(r"[a-f0-9]{40}", args.commit), "Use an immutable commit SHA"
    ROOT.mkdir(parents=True, exist_ok=True)
    prefix = f"https://raw.githubusercontent.com/NeverSinkDev/NeverSink-Filter/{args.commit}/"
    files = {}
    names = ["SOFT", "REGULAR", "SEMI-STRICT", "STRICT", "VERY-STRICT", "UBER-STRICT", "UBER-PLUS-STRICT"]
    for index, name in enumerate(names):
        filename = f"NeverSink's filter - {index}-{name}.filter"
        raw = fetch(prefix + urllib.parse.quote(filename))
        assert b"Show" in raw and len(raw) > 10000
        target = f"{index}.filter"
        (ROOT / target).write_bytes(raw)
        files[target] = {"sha256": hashlib.sha256(raw).hexdigest(), "source": prefix + urllib.parse.quote(filename)}
    license_data = fetch(prefix + "LICENSE")
    (ROOT / "LICENSE-NeverSink.txt").write_bytes(license_data)
    html = fetch(ANNOUNCEMENT)
    post = Post()
    post.feed(html.decode("utf-8"))
    text = "".join(post.parts)
    assert "UnidentifiedItemTier" in text and "Removed Items" in text
    new = text.split("New Items", 1)[1].split("Renamed Items", 1)[0]
    additions = {}
    for match in re.finditer(r"Item class:\s*([^\n]+)\n(.*?)(?=Item class:|\Z)", new, re.S):
        additions[match[1].strip()] = [line.strip() for line in match[2].splitlines() if line.strip() and line.strip() != "Spoiler"]
    renamed = dict(re.findall(r'"([^"]+)" renamed to "([^"]+)"', text))
    removed = [line.strip() for line in text.split("Removed Items", 1)[1].splitlines() if line.strip() and line.strip() != "Spoiler"]
    assert "Enshrouded Items" in additions and "Viscera" in additions and len(removed) > 50
    patch = {"version": "3.30", "source": ANNOUNCEMENT, "sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(), "sha256Kind": "extracted-news-text",
             "keywords": {"UnidentifiedItemTier": [0, 5], "Fated": [True, False]},
             "added": additions, "renamed": renamed, "removed": removed}
    (ROOT / "patch-3.30.json").write_text(json.dumps(patch, indent=2) + "\n", encoding="utf-8")
    manifest = {"schemaVersion": 1, "commit": args.commit, "source": "NeverSinkDev/NeverSink-Filter", "license": "MIT", "files": files}
    native_patch = args.native_patch or ("3.30" if args.commit == REVIEWED_COMMIT else None)
    if native_patch:
        manifest["nativePatch"] = native_patch
    (ROOT / "source.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Pinned {len(files)} templates, {sum(map(len, additions.values()))} new items, {len(renamed)} renames, {len(removed)} removals")


if __name__ == "__main__":
    main()
