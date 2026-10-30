import os

application = os.path.abspath(defines["app"])
background_path = os.path.abspath(defines["background"])
app_name = os.path.basename(application)

format = "UDZO"
compression_level = 9
files = [application]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(application, "Contents", "Resources", "AppIcon.icns")

window_rect = ((120, 120), (660, 400))
background = background_path
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
show_icon_preview = False
include_icon_view_settings = True
arrange_by = None
label_pos = "bottom"
text_size = 13
icon_size = 96
icon_locations = {
    app_name: (165, 190),
    "Applications": (495, 190),
}
