"""Print an apply_patch patch for the app's pinned, offline vector icon subset.

No files are changed by this script. The SVGs are converted to path data so the
app can cache and draw them with one consistent stroke, without runtime I/O.
"""

import concurrent.futures
import json
from pathlib import Path
import re
import urllib.request
import xml.etree.ElementTree as ET

REVISION = "23f9abc4ed0146cffededd3d7f94c1018bfdf693"
ROOT = Path(__file__).resolve().parent.parent
SOURCE = f"https://raw.githubusercontent.com/lucide-icons/lucide/{REVISION}"

# Material identifiers remain semantic tokens, not the rendered font glyphs.
MAPPING = """
create_new_folder_outlined folder-plus
grid_view_rounded layout-grid
view_list_rounded list
star_outline_rounded star
restore_rounded rotate-ccw
sort_rounded arrow-down-wide-narrow
add_circle_outline_rounded circle-plus
add_comment_outlined message-square-plus
add_location_alt_outlined map-pin-plus
add_rounded plus
add_to_drive_outlined archive-restore
alarm_outlined alarm-clock
alt_route_rounded route
arrow_back_rounded arrow-left
arrow_back arrow-left
arrow_drop_down_rounded chevron-down
arrow_drop_down chevron-down
arrow_forward_rounded arrow-right
arrow_upward_rounded arrow-up
aspect_ratio_rounded ratio
attach_file_rounded paperclip
auto_awesome_outlined sparkles
auto_awesome_rounded sparkles
auto_fix_high_rounded wand-sparkles
auto_mode_rounded route
broken_image_outlined image-off
bug_report_outlined bug
calendar_month_outlined calendar-days
calendar_today_outlined calendar
chat_bubble_outline_rounded message-square
check check
check_circle_outline circle-check
check_circle_outline_rounded circle-check
check_circle_rounded fk-selected
check_rounded check
checklist_rounded list-checks
check_box list-checks
chevron_left_rounded chevron-left
chevron_right_rounded chevron-right
close_rounded x
close x
cloud_download_outlined cloud-download
cloud_outlined cloud
cloud_sync_outlined cloud-sync
content_copy_rounded copy
content_cut_rounded scissors
content_paste_rounded clipboard-paste
copy_all_rounded copy
delete_outline_rounded trash-2
delete_sweep_outlined trash-2
description_outlined file-text
document_scanner_rounded scan-text
download_done_rounded check-check
download_outlined download
download_rounded download
downloading_rounded circle-arrow-down
edit_location_alt_outlined map-pin-pen
edit_note_rounded file-pen-line
edit_outlined pencil
error_outline_rounded circle-alert
expand_more_rounded chevron-down
expand_more chevron-down
fact_check_outlined clipboard-check
find_replace_rounded replace
fingerprint_rounded fingerprint-pattern
folder_open_rounded folder-open
format_align_center_rounded text-align-center
format_align_left_rounded text-align-start
format_align_right_rounded text-align-end
format_bold bold
format_indent_decrease list-indent-decrease
format_indent_increase list-indent-increase
format_italic italic
format_underline underline
format_list_bulleted list
format_list_numbered list-ordered
format_quote quote
format_clear remove-formatting
forum_outlined messages-square
graphic_eq_rounded audio-lines
groups_2_outlined users
high_quality_outlined badge-check
history_rounded clock-arrow-left
home_outlined house
horizontal_rule minus
horizontal_rule_rounded minus
image_not_supported_outlined image-off
image_outlined image
image_search_rounded scan-eye
info_outline_rounded info
insert_drive_file_outlined file
inventory_2_outlined archive
ios_share_rounded upload
keyboard_arrow_down_rounded chevron-down
keyboard_arrow_up_rounded chevron-up
label_outline_rounded fk-tag
language_rounded globe
library_add_check_outlined copy-check
library_add_outlined copy-plus
lightbulb_outline_rounded lightbulb
local_fire_department_outlined flame
location_on_outlined map-pin
lock_outline_rounded lock-keyhole
lock_open_rounded lock-keyhole-open
manage_search_rounded file-search
memory_outlined cpu
memory_rounded cpu
mic_none_rounded mic
mic_rounded mic
more_horiz_rounded ellipsis
more_vert_rounded ellipsis-vertical
movie_outlined clapperboard
multiline_chart_rounded activity
my_location_rounded locate-fixed
network_check_rounded wifi
noise_control_off_rounded audio-waveform
north_east_rounded arrow-up-right
note_add_outlined file-plus
offline_pin_outlined shield-check
open_in_full_rounded expand
pause_rounded pause
photo_camera_outlined camera
photo_library_outlined images
photo_outlined image
place_outlined map-pin
play_arrow_rounded play
play_circle_outline_rounded circle-play
playlist_add_rounded list-plus
psychology_alt_outlined brain
public_rounded globe
push_pin_outlined pin
radio_button_unchecked_rounded circle
record_voice_over_rounded speech
remove_circle_outline_rounded circle-minus
remove_done_rounded list-x
save_alt_rounded download
save_outlined save
schedule_rounded clock
search_off_rounded search-x
search_rounded search
security_outlined shield-check
select_all_rounded scan
settings_backup_restore_rounded archive-restore
settings_outlined fk-settings
settings_suggest_outlined fk-settings
share_outlined share-2
shield_outlined shield
speed_rounded gauge
stay_current_landscape_rounded tablet
stay_current_portrait_rounded smartphone
stop_circle_outlined circle-stop
stop_rounded square
storage_rounded database
summarize_outlined file-text
sync_rounded refresh-cw
refresh_rounded refresh-cw
system_update_alt_rounded download
table_rows_outlined rows-3
tag_rounded fk-tag
title_rounded type
toc_rounded list-tree
translate_rounded languages
travel_explore_rounded globe
tune_rounded sliders-horizontal
verified_outlined badge-check
verified_user_outlined shield-check
vertical_align_bottom arrow-down-to-line
video_library_outlined video
videocam_outlined video
view_column_outlined columns-3
visibility_off_outlined eye-off
visibility_outlined eye
volume_up_outlined volume-2
warning_amber_rounded triangle-alert
undo_outlined undo-2
redo_outlined redo-2
link link
link_off_rounded unlink
menu menu
menu_open panel-left-close
"""

# Composer-specific artwork must not replace the same tokens elsewhere.
CHAT_COMPOSER_MAPPING = """
photo_camera_outlined fk-chat-camera
record_voice_over_rounded fk-chat-voice
add_circle_outline_rounded fk-chat-plus
"""

CUSTOM_PATHS = {
    # Traced from the composer reference on the shared 24-unit viewBox.
    # These three silhouettes use a 2-unit round stroke in AppIcon.
    "fk-chat-camera": "M12 3.25C9.2 3.25 9.05 3.5 8.35 4.9C7.75 6.05 7.35 6.05 5.9 6.4C3.55 6.95 2.65 7.8 2.65 12.65C2.65 18.7 3.9 20.5 12 20.5C20.1 20.5 21.35 18.7 21.35 12.65C21.35 7.8 20.45 6.95 18.1 6.4C16.65 6.05 16.25 6.05 15.65 4.9C14.95 3.5 14.8 3.25 12 3.25Z M8.5 12.7a3.5 3.5 0 1 0 7 0a3.5 3.5 0 1 0-7 0Z",
    "fk-chat-voice": "M2 12a10 10 0 1 0 20 0a10 10 0 1 0-20 0Z M8.45 12.1h.01 M11.3 9.55C12.6 10.85 12.6 13.15 11.3 14.45 M13.45 6.75C16.4 9.35 16.4 14.65 13.45 17.25",
    "fk-chat-plus": "M2 12a10 10 0 1 0 20 0a10 10 0 1 0-20 0Z M8.25 12h7.5 M12 8.4v7.2",
    "fk-settings": "M11.4 2.05Q12 1.7 12.6 2.05L20.3 6.5Q20.9 6.85 20.9 7.55V16.45Q20.9 17.15 20.3 17.5L12.6 21.95Q12 22.3 11.4 21.95L3.7 17.5Q3.1 17.15 3.1 16.45V7.55Q3.1 6.85 3.7 6.5Z M8.75 12a3.25 3.25 0 1 0 6.5 0a3.25 3.25 0 1 0-6.5 0",
    "fk-tag": "M5 3H10.5Q11.35 3 11.95 3.6L20.4 12.05Q21.8 13.45 20.4 14.85L14.85 20.4Q13.45 21.8 12.05 20.4L3.6 11.95Q3 11.35 3 10.5V5Q3 3 5 3Z M5.9 7.25a1.35 1.35 0 1 0 2.7 0a1.35 1.35 0 1 0-2.7 0",
    # An even-odd cutout preserves a clearly selected state on any background.
    "fk-selected": "M2 12a10 10 0 1 0 20 0a10 10 0 1 0-20 0Z M6.1 11.8L7.5 10.4L10.4 13.3L16.3 7.4L17.7 8.8L10.4 16.1Z",
}


def fetch(relative):
    request = urllib.request.Request(f"{SOURCE}/{relative}", headers={"User-Agent": "FKNotes icon generator"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.read().decode("utf-8")
    except Exception as error:
        raise RuntimeError(f"Failed to load {relative}: {error}") from error


def circle_path(cx, cy, rx, ry):
    return f"M{cx-rx:g} {cy:g}a{rx:g} {ry:g} 0 1 0 {2*rx:g} 0a{rx:g} {ry:g} 0 1 0 {-2*rx:g} 0Z"


def independent_path(data):
    # Each SVG element's initial relative move is relative to (0, 0), not
    # the previous element's endpoint in our combined Flutter Path.
    data = data.strip()
    number = r"[+-]?(?:\d*\.\d+|\d+\.?)(?:[eE][+-]?\d+)?"
    match = re.match(rf"^m\s*({number})[\s,]*({number})(.*)$", data, re.S)
    if match is None:
        return data
    rest = match[3].lstrip(" ,\n\t")
    # Additional coordinate pairs after a relative move are relative lines.
    if rest and re.match(r"[+\-.\d]", rest):
        rest = "l" + rest
    return f"M{match[1]} {match[2]}{rest}"


def convert(name):
    root = ET.fromstring(fetch(f"icons/{name}.svg"))
    assert root.attrib["viewBox"] == "0 0 24 24"
    paths = []
    for element in root:
        tag = element.tag.rsplit("}", 1)[-1]
        values = element.attrib
        number = lambda key, default=0: float(values.get(key, default))
        if tag == "path":
            paths.append(independent_path(values["d"]))
        elif tag in ("circle", "ellipse"):
            paths.append(circle_path(number("cx"), number("cy"), number("r") if tag == "circle" else number("rx"), number("r") if tag == "circle" else number("ry")))
        elif tag == "line":
            paths.append(f'M{number("x1"):g} {number("y1"):g}L{number("x2"):g} {number("y2"):g}')
        elif tag in ("polyline", "polygon"):
            points = re.split(r"[\s,]+", values["points"].strip())
            paths.append("M" + " ".join(points[:2]) + "L" + " ".join(points[2:]) + ("Z" if tag == "polygon" else ""))
        elif tag == "rect":
            x, y, w, h = (number(key) for key in ("x", "y", "width", "height"))
            rx = min(number("rx", values.get("ry", 0)), w / 2)
            ry = min(number("ry", values.get("rx", 0)), h / 2)
            paths.append(f"M{x+rx:g} {y:g}H{x+w-rx:g}Q{x+w:g} {y:g} {x+w:g} {y+ry:g}V{y+h-ry:g}Q{x+w:g} {y+h:g} {x+w-rx:g} {y+h:g}H{x+rx:g}Q{x:g} {y+h:g} {x:g} {y+h-ry:g}V{y+ry:g}Q{x:g} {y:g} {x+rx:g} {y:g}Z")
        else:
            raise ValueError(f"Unsupported SVG element {tag} in {name}")
    return name, " ".join(paths)


def patch_file(relative, content):
    target = ROOT / relative
    if target.exists():
        return f"*** Update File: {target}\n@@\n" + "\n".join("-" + line for line in target.read_text().splitlines()) + "\n" + "\n".join("+" + line for line in content.splitlines()) + "\n"
    return f"*** Add File: {target}\n" + "\n".join("+" + line for line in content.splitlines()) + "\n"


def main():
    mapping = dict(line.split() for line in MAPPING.strip().splitlines())
    composer_mapping = dict(line.split() for line in CHAT_COMPOSER_MAPPING.strip().splitlines())
    names = sorted((set(mapping.values()) | set(composer_mapping.values())) - CUSTOM_PATHS.keys())
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        paths = dict(pool.map(convert, names))
    paths.update(CUSTOM_PATHS)
    license_text = fetch("LICENSE")
    source = [
        "// Generated by tool/generate_app_icons.py. Do not edit vector data by hand.",
        f"// Lucide revision: {REVISION}. See third_party/lucide/LICENSE.",
        "import 'package:flutter/material.dart' show IconData, Icons;",
        "",
        "final appIconNames = Map<IconData, String>.unmodifiable({",
        *[f"  Icons.{key}: '{value}'," for key, value in sorted(mapping.items())],
        "});", "",
        "final appChatComposerIconNames = Map<IconData, String>.unmodifiable({",
        *[f"  Icons.{key}: '{value}'," for key, value in sorted(composer_mapping.items())],
        "});", "",
        "const appIconPaths = <String, String>{",
        *[f"  '{key}': {json.dumps(value)}," for key, value in sorted(paths.items())],
        "};", "",
        "const appIconLicense = r'''" + license_text + "''';", "",
    ]
    print("*** Begin Patch\n" + patch_file("lib/widgets/app_icon_catalog.dart", "\n".join(source)) + patch_file("third_party/lucide/LICENSE", license_text) + "*** End Patch")


if __name__ == "__main__":
    main()
