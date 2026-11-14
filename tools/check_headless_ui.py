"""Exercise native controls and audit rendered frames without opening a window."""
import argparse
from concurrent.futures import ProcessPoolExecutor
import hashlib
import json
import os
import subprocess
import tempfile
import zipfile
from pathlib import Path

from render_headless_ui import render
from update_crafting_currency_art import check as check_currency_art
from update_colour_picker_art import check as check_colour_art

ROOT = Path(__file__).resolve().parents[1]


def source_hashes():
    sources = list((ROOT / "src/Classes").glob("*.lua")) + list((ROOT / "src/Modules").glob("*.lua"))
    sources += list((ROOT / "src/Data").rglob("*.lua"))
    sources += list((ROOT / "src/AI").rglob("*.cjs"))
    sources += list((ROOT / "runtime/SimpleGraphic/Fonts").glob("*"))
    sources += list((ROOT / "runtime/lua").rglob("*.lua"))
    sources += list((ROOT / "src/Assets/Crafting").rglob("*"))
    sources += list((ROOT / "src/Assets/Atlas").rglob("*"))
    sources += list((ROOT / "src/Data/Atlas").glob("*.json"))
    sources += list((ROOT / "src/Data/Crafting").glob("*.json"))
    sources += [ROOT / "tools/update_harvest_enchants.py", ROOT / "tools/update_crafting_data.py", ROOT / "tools/crafting_data_status.py", ROOT / "tools/test_crafting_data_status.py", ROOT / "tools/update_allflame_data.py"]
    sources += list((ROOT / "src/Data/LootFilters").glob("*"))
    sources += list((ROOT / "src/Assets/LootFilters").glob("*"))
    sources += list((ROOT / "src/TreeData/3_30").glob("*"))
    sources += list((ROOT / "src/TreeData/3_30_ruthless").glob("*"))
    sources += list((ROOT / "src/TreeData/3_30_preview").glob("*"))
    sources += [ROOT / "src/_SimpleGraphic.def.lua", ROOT / "src/GameVersions.lua", ROOT / "src/Data/HeadlessImageSizes.json"]
    sources += [ROOT / "src/HeadlessWrapper.lua", ROOT / "src/Data/Global.lua", Path(__file__), ROOT / "tools/render_headless_ui.py", ROOT / "tools/test_headless_ui.lua", ROOT / "tools/update_crafting_currency_art.py", ROOT / "tools/update_colour_picker_art.py"]
    return {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(sources) if path.is_file()}


def render_frame(path):
    image, audit = render(json.loads(path.read_text()))
    image.save(path.parent.parent / (path.stem + ".png"))
    (path.parent.parent / (path.stem + ".audit.json")).write_text(json.dumps(audit, indent=2))
    if any(audit[key] for key in ("lowContrast", "horizontalClipping", "controlClipping", "controlOverlaps")):
        return {"frame": path.name, "audit": audit}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua", default="luajit", help="LuaJIT executable; defaults to PATH")
    parser.add_argument("--output", type=Path, default=ROOT / "artifacts/headless-ui")
    parser.add_argument("--workers", type=int, default=min(4, os.cpu_count() or 1), help="Parallel render processes (1 to 4)")
    args = parser.parse_args()
    assert 1 <= args.workers <= 4, "Use 1 to 4 render workers"
    check_currency_art()
    check_colour_art()
    hashes = source_hashes()
    args.output.mkdir(parents=True, exist_ok=True)
    directory = Path(tempfile.mkdtemp(prefix="run-", dir=args.output.resolve()))
    frames = directory / "frames"
    frames.mkdir()
    environment = dict(os.environ, LUA_PATH="../runtime/lua/?.lua;../runtime/lua/?/init.lua;;")
    if os.name == "nt":
        environment["LUA_CPATH"] = str(ROOT / "runtime/?.dll") + ";;"
        environment["PATH"] = str(ROOT / "runtime") + os.pathsep + environment["PATH"]
    result = subprocess.run([args.lua, "../tools/test_headless_ui.lua", str(frames)], cwd=ROOT / "src",
                            env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (directory / "controls.log").write_text(result.stdout)
    assert result.returncode == 0, result.stdout
    assert source_hashes() == hashes, "Source files changed during UI capture; repeat against stable sources"
    for width in (1280, 1024, 960):
        archive = frames / f"ui-{width}-strictnesses.zip"
        with zipfile.ZipFile(archive) as z:
            assert z.namelist() == [f"ui-{width}-{n}.filter" for n in range(7)], "ZIP has incorrect strictness files"
            assert z.testzip() is None, "ZIP failed CRC validation"
            assert all(b"Covens pickup plan" in z.read(name) for name in z.namelist()), "ZIP lost the personal filter"
        archive.unlink()
    paths = sorted(frames.glob("*.json"))
    assert len(paths) == 1131, f"Expected 1131 UI frames, found {len(paths)}"
    for width in (960, 1024, 1280):
        frame = json.loads((frames / f"{width}-filter-background-default-alpha.json").read_text())
        expected = (10 / 255, 20 / 255, 30 / 255, 240 / 255)
        assert any(command.get("kind") == "rect" and all(abs(a-b) < 1e-6 for a, b in zip(command.get("color", ()), expected)) and len(command.get("color", ())) == 4 for command in frame["commands"]), "Background preview lost the game-default opacity"
    with ProcessPoolExecutor(max_workers=args.workers) as pool:
        failures = [failure for failure in pool.map(render_frame, paths) if failure]
    tooltip = json.loads((directory / "expected-audit-tooltip.json").read_text())
    assert any(c["kind"] == "text" and c["sublayer"] == 100 and "Alt+3" in c["text"] for c in tooltip["commands"]), "Native tooltip fixture did not draw its overlay"
    image, audit = render(tooltip)
    image.save(directory / "expected-audit-tooltip.png")
    assert not any(audit[key] for key in ("lowContrast", "horizontalClipping", "controlClipping", "controlOverlaps")), "Native tooltip was incorrectly treated as control content"
    negative = json.loads((directory / "expected-audit-failures.json").read_text())
    image, audit = render(negative)
    image.save(directory / "expected-audit-failures.png")
    assert audit["lowContrast"] and audit["horizontalClipping"] and audit["controlClipping"] and audit["controlOverlaps"], "UI audits failed to detect the deliberate bad fixture"
    assert "Overlay outside the viewport" in audit["horizontalClipping"], "Overlay text escaped the viewport audit"
    try:
        revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True, stderr=subprocess.DEVNULL).strip()
        dirty = subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True, stderr=subprocess.DEVNULL).splitlines()
    except (FileNotFoundError, subprocess.CalledProcessError):
        revision = environment.get("GITHUB_SHA")
        dirty = None
    assert source_hashes() == hashes, "Source files changed during UI rendering; repeat against stable sources"
    (directory / "report.json").write_text(json.dumps({"revision": revision, "workingTreeChanges": dirty,
        "sourceHashes": hashes, "sourceStable": True, "frames": len(paths), "failures": failures, "auditSelfTest": "passed",
        "limitations": negative["limitations"]}, indent=2))
    print(f"Headless UI: {len(paths)} frames, {len(failures)} failures. Artifacts: {directory}")
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
