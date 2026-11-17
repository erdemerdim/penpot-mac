# dmgbuild ayarları: DMG açılınca görünen "Uygulamalar'a sürükle" penceresi.
# dmg-olustur.sh şöyle çağırır:
#   dmgbuild -s dmgbuild-ayarlari.py -D app=<Penpot.app> -D background=<background.tiff> \
#            -D icon=<Penpot.icns> "Penpot <sürüm>" <çıktı.dmg>
# Simge konumları arkaplan.swift'teki ok ve yazıyla eşleşir (pencere 660x420 nokta).
import os

app = defines["app"]  # noqa: F821  (dmgbuild bu değişkeni sağlar)
app_name = os.path.basename(app)

format = "ULMO"              # lzma sıkıştırma (macOS 10.15+)
filesystem = "HFS+"
files = [app]
symlinks = {"Uygulamalar": "/Applications"}
icon = defines["icon"]       # noqa: F821  bağlanan diskin simgesi (.VolumeIcon.icns)
hide_extensions = [app_name]

background = defines["background"]  # noqa: F821  1x+2x birleşik TIFF
window_rect = ((360, 240), (660, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 0
show_icon_preview = False

icon_size = 128
text_size = 13
label_pos = "bottom"
arrange_by = None
grid_spacing = 100
icon_locations = {
    app_name: (165, 190),
    "Uygulamalar": (495, 190),
}
