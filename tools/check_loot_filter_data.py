"""Verify bundled third-party templates without network access."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1] / "src/Data/LootFilters"
source = json.loads((root / "source.json").read_text())
assert source["license"] == "MIT"
assert source.get("nativePatch") == "3.30"
assert set(source["files"]) == {f"{index}.filter" for index in range(7)}
for filename, record in source["files"].items():
    raw = (root / filename).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == record["sha256"], filename
    assert source["commit"] in record["source"], filename
license_text = (root / "LICENSE-NeverSink.txt").read_text()
assert "Copyright (c) 2026 NeverSink" in license_text and "Permission is hereby granted" in license_text
patch = json.loads((root / "patch-3.30.json").read_text())
assert patch["version"] == "3.30" and patch["keywords"]["UnidentifiedItemTier"] == [0, 5]
assert patch["sha256Kind"] == "extracted-news-text"
assert "Fated" in patch["keywords"]
assert "Frayed Thread" in patch["added"]["Stackable Currency"]
assert "Enshrouded Quiver" in patch["added"]["Enshrouded Items"]
assert patch["renamed"]["Maven's Chisel of Scarabs"] == "Maven's Chisel of Threads"
assert "Orb of Binding" in patch["removed"]
assert len(patch["removed"]) == 171 and len(set(patch["removed"])) == 171
assert "Report Forum Post" not in patch["removed"]
print("Loot filter data: 7 pinned hashes, MIT notice and 3.30 snapshot verified")
