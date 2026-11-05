# dmgbuild settings for the Orbit installer window. Used by scripts/release.sh:
#   dmgbuild -s scripts/dmg/settings.py -D app=<path to Orbit.app> -D icon=<AppIcon.icns> Orbit Orbit.dmg
# The window size and the icon positions must match scripts/dmg/make_background.py.
import os

app = defines["app"]                       # noqa: F821  (dmgbuild injects `defines`)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines.get("icon")                 # noqa: F821  volume icon
background = os.path.join(defines["dmgdir"], "background.tiff")  # noqa: F821

window_rect = ((200, 140), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 0

icon_size = 128
text_size = 13
arrange_by = None
icon_locations = {
    os.path.basename(app): (180, 190),
    "Applications": (480, 190),
}
