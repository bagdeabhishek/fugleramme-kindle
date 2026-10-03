"""Packaging guards for the Kindle thin client."""

import json
from pathlib import Path

CLIENT = Path(__file__).resolve().parents[1] / "examples" / "kindle-fugleramme"


def test_the_client_survives_case_insensitive_kindle_storage():
    """Two names differing only by case overwrite each other on Kindle FAT."""
    names = [path.name.casefold() for path in CLIENT.iterdir()]
    assert len(names) == len(set(names))


def test_kual_closes_after_launching_each_action():
    """Leaving KUAL open lets it repaint or retain the client's process group."""
    items = json.loads((CLIENT / "menu.json").read_text())["items"][0]["items"]
    assert all(item["exitmenu"] is True for item in items)


def test_the_kmc_launcher_starts_the_extension_client():
    launcher = (CLIENT / "kmc-launcher.sh").read_text()
    assert "/mnt/us/extensions/fugleramme/start.sh" in launcher
