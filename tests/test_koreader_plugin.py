"""Packaging guards for the portable KOReader plugin."""

from pathlib import Path

PLUGIN = (
    Path(__file__).resolve().parents[1] / "examples" / "koreader-fugleramme" / "fugleramme.koplugin"
)
INSTALLER = PLUGIN.parent / "install-kobo.sh"


def test_koreader_plugin_has_the_required_package_files():
    assert (PLUGIN / "_meta.lua").is_file()
    assert (PLUGIN / "main.lua").is_file()


def test_koreader_plugin_uses_runtime_geometry_and_colour_detection():
    plugin = (PLUGIN / "main.lua").read_text()

    assert "Screen:getWidth()" in plugin
    assert "Screen:getHeight()" in plugin
    assert "Device:hasColorScreen()" in plugin
    assert '"/display/version"' in plugin
    assert '"/display/frame.png"' in plugin


def test_koreader_plugin_does_not_ship_a_private_lan_address():
    plugin = (PLUGIN / "main.lua").read_text()
    assert "192.168." not in plugin


def test_kobo_installer_avoids_nickel_scanner_configuration():
    installer = INSTALLER.read_text()

    assert 'TARGET="$KOBO_MOUNT/.kobo/koreader"' in installer
    assert "ExcludeSyncFolders" not in installer
    assert "Kobo eReader.conf" in installer
    assert "CONF_HASH" in installer
