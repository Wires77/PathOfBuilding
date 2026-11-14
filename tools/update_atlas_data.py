"""Rebuild bundled Atlas graphs from pinned, official GGG exports."""
import hashlib
import argparse
import json
import math
import re
from pathlib import Path
from urllib.request import urlopen

VERSIONS = {
    "3.27.0": "dd12728df527cf96a93f91cbee7d5951285b8883",
    "3.27.0-ruthless": "dd12728df527cf96a93f91cbee7d5951285b8883",
    "3.29.1": "0ae2e0f94f266fc21c86ee8dd561d7b559bf2db4",
    "3.29.1-ruthless": "0ae2e0f94f266fc21c86ee8dd561d7b559bf2db4",
    "3.29.3": "dcb2a006b68740f3ecbd317775c262fc6ed7b8af",
    "3.29.3-ruthless": "dcb2a006b68740f3ecbd317775c262fc6ed7b8af",
    "3.30.0-preview": "d225501d7a3e52c991309116473908c284075e89",
    "3.30.0-preview-ruthless": "d225501d7a3e52c991309116473908c284075e89",
}
DESTINATION = Path(__file__).resolve().parents[1] / "src" / "Data" / "Atlas"
ANGLES = [0, 30, 45, 60, 90, 120, 135, 150, 180, 210, 225, 240, 270, 300, 315, 330]

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--version", action="append", choices=VERSIONS, help="Rebuild only this pinned version")
selected = parser.parse_args().version or VERSIONS
for version in selected:
    commit = VERSIONS[version]
    ruthless = version.endswith("-ruthless")
    source = f"https://raw.githubusercontent.com/grindinggear/atlastree-export/{commit}/{'ruthless.json' if ruthless else 'data.json'}"
    with urlopen(source, timeout=30) as response:
        raw = response.read()
    data = json.loads(raw)
    assert data["tree"] == "Atlas"
    nodes = {}
    decorations = []
    start = int(data["nodes"]["root"]["out"][0])
    for key, node in data["nodes"].items():
        if key == "root":
            continue
        group = data["groups"][str(node["group"])]
        count = data["constants"]["skillsPerOrbit"][node["orbit"]]
        index = node["orbitIndex"]
        angle = math.radians(ANGLES[index] if count == 16 else 360 * index / count)
        radius = data["constants"]["orbitRadii"][node["orbit"]]
        entry = {
            "id": int(key), "name": node["name"] or "Atlas start", "stats": node["stats"],
            "x": round(group["x"] + math.sin(angle) * radius, 2),
            "y": round(group["y"] - math.cos(angle) * radius, 2),
            "links": sorted({int(other) for other in node["out"] + node["in"]
                             if other != "root" and not data["nodes"][other].get("isMastery")}),
            "kind": "keystone" if node.get("isKeystone") else "notable" if node.get("isNotable")
                    else "gateway" if node.get("isWormhole") else "small",
            "grantedPoints": node.get("grantedPassivePoints", 0),
            "icon": node.get("icon"),
        }
        if node.get("isMastery"):
            decorations.append(entry)
        else:
            nodes[key] = entry
    result = {
        "version": version, "mode": "ruthless" if ruthless else "standard", "source": source, "commit": commit,
        "sha256": hashlib.sha256(raw).hexdigest(), "start": start,
        "maxPoints": data["points"]["totalPoints"], "nodes": nodes,
        "decorations": decorations, "bounds": [data[k] for k in ("min_x", "min_y", "max_x", "max_y")],
        "groups": [{"x": group["x"], "y": group["y"], "background": group["background"]["image"]}
                   for group in data["groups"].values() if group.get("background")],
    }
    if "-preview" in version:
        result["preview"] = True
        league_source = source.replace("/ruthless.json", "/ruthless-league.json") if ruthless else source.replace("/data.json", "/league.json")
        with urlopen(league_source, timeout=30) as response:
            league_raw = response.read()
        league = json.loads(league_raw)
        assert {k: v for k, v in data.items() if k != "tree"} == {k: v for k, v in league.items() if k != "tree"}
        result["compatibleModes"] = ["Ruthless Standard", "Ruthless Covens of Umbra"] if ruthless else ["Standard", "Covens of Umbra"]
        result["leagueSource"] = league_source
        result["leagueSha256"] = hashlib.sha256(league_raw).hexdigest()
    elif ruthless:
        result["compatibleModes"] = ["Ruthless Standard"]
    if ruthless:
        # Reuse the existing artwork only after checking the pinned exports agree.
        with urlopen(source.replace("/ruthless.json", "/data.json"), timeout=30) as response:
            standard = json.load(response)
        assert data["sprites"] == standard["sprites"], "Ruthless artwork differs from Standard"
    DESTINATION.mkdir(parents=True, exist_ok=True)
    # Preserve the game's spelling in generated data, as with other GGG exports.
    encoded = '{"_comment":"Generated official GGG data. cspell:disable",\n' + json.dumps(
        result, ensure_ascii=False, separators=(",", ":"))[1:]
    (DESTINATION / f"{version}.json").write_text(encoded, encoding="utf-8")
    if ruthless:
        print(f"{version}: {len(nodes)} allocatable nodes; source {result['sha256']}")
        continue
    artwork = {"_comment": "Generated official GGG artwork. cspell:disable", "source": source, "sprites": {}}
    asset_root = DESTINATION.parents[1] / "Assets" / "Atlas" / version
    asset_root.mkdir(parents=True, exist_ok=True)
    for category, levels in data["sprites"].items():
        if category in ("background", "masteryOverlay", "line"):
            continue
        sheet = levels.get("0.5") or list(levels.values())[-1]
        filename = sheet["filename"].split("/")[-1].split("?")[0]
        assert re.fullmatch(r"[a-zA-Z0-9_.-]+", filename)
        asset_source = f"https://raw.githubusercontent.com/grindinggear/atlastree-export/{commit}/assets/{filename}"
        path = asset_root / filename
        if not path.exists():
            with urlopen(asset_source, timeout=60) as response:
                path.write_bytes(response.read())
        artwork["sprites"][category] = {**sheet, "filename": f"Assets/Atlas/{version}/{filename}",
                                         "source": asset_source, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    (asset_root / "manifest.json").write_text(json.dumps(artwork, indent=2) + "\n", encoding="utf-8")
    print(f"{version}: {len(nodes)} allocatable nodes; source {result['sha256']}")
