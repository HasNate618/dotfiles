#!/usr/bin/env python3

import gi
import subprocess
import os
import sys
from urllib.parse import urlparse

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, GdkPixbuf, GLib, Gdk, Pango

COVER_DIR = "/tmp/waybar"
COVER_PATH = os.path.join(COVER_DIR, "cover.png")
PLAYERCTL = "playerctl"

os.makedirs(COVER_DIR, exist_ok=True)


def pick_player():
    try:
        out = subprocess.check_output([PLAYERCTL, "-l"], stderr=subprocess.DEVNULL).decode().splitlines()
    except Exception:
        return None
    for p in out:
        try:
            st = subprocess.check_output([PLAYERCTL, "-p", p, "status"], stderr=subprocess.DEVNULL).decode().strip()
            if st == "Playing":
                return p
        except Exception:
            continue
    return out[0] if out else None


def run_playerctl_cmd(args, player=None):
    cmd = [PLAYERCTL]
    if player:
        cmd += ["-p", player]
    cmd += args
    try:
        subprocess.run(cmd, check=False)
    except Exception:
        pass


class MediaPopup(Gtk.Window):
    def __init__(self):
        Gtk.Window.__init__(self, title="WaybarMediaPopup")
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_keep_above(True)
        self.set_type_hint(Gdk.WindowTypeHint.DIALOG)

        screen = Gdk.Screen.get_default()
        css = b"""
#media-popup { background-color: rgba(18,17,17,0.26); border-radius: 12px; padding: 10px; }
#title { font-weight: 600; font-size: 14px; }
#artist { color: rgba(255,255,255,0.8); font-size: 12px; }
.button { background: transparent; border: none; padding: 6px; }
"""
        style = Gtk.CssProvider()
        style.load_from_data(css)
        Gtk.StyleContext.add_provider_for_screen(screen, style, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        root = Gtk.EventBox()
        root.set_name("media-popup")
        self.add(root)

        hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        root.add(hbox)

        # cover image placeholder
        self.image = Gtk.Image()
        hbox.pack_start(self.image, False, False, 0)

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        hbox.pack_start(vbox, True, True, 0)

        self.title_label = Gtk.Label(xalign=0)
        self.title_label.set_name("title")
        self.title_label.set_ellipsize(Pango.EllipsizeMode.END)
        self.title_label.set_max_width_chars(40)
        self.title_label.set_selectable(False)
        vbox.pack_start(self.title_label, False, False, 0)

        self.artist_label = Gtk.Label(xalign=0)
        self.artist_label.set_name("artist")
        self.artist_label.set_ellipsize(Pango.EllipsizeMode.END)
        self.artist_label.set_max_width_chars(40)
        vbox.pack_start(self.artist_label, False, False, 0)

        # controls row
        ctrl_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        vbox.pack_start(ctrl_box, False, False, 0)

        self.btn_prev = Gtk.Button(label="󰒮")
        self.btn_prev.get_style_context().add_class("button")
        self.btn_prev.connect("clicked", lambda w: run_playerctl_cmd(["previous"], self.player))
        ctrl_box.pack_start(self.btn_prev, False, False, 0)

        self.btn_play = Gtk.Button(label="󰐊")
        self.btn_play.get_style_context().add_class("button")
        self.btn_play.connect("clicked", lambda w: run_playerctl_cmd(["play-pause"], self.player))
        ctrl_box.pack_start(self.btn_play, False, False, 0)

        self.btn_next = Gtk.Button(label="󰒭")
        self.btn_next.get_style_context().add_class("button")
        self.btn_next.connect("clicked", lambda w: run_playerctl_cmd(["next"], self.player))
        ctrl_box.pack_start(self.btn_next, False, False, 0)

        # progress bar
        self.progress = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 100, 1)
        self.progress.set_draw_value(False)
        self.progress.set_sensitive(False)
        vbox.pack_start(self.progress, False, True, 0)

        self.player = None
        self.update()
        # adjust image size after layout
        GLib.idle_add(self.adjust_image_size)
        GLib.timeout_add_seconds(1, self.update)

        self.connect("focus-out-event", lambda *args: Gtk.main_quit())
        self.connect("key-press-event", lambda w, e: Gtk.main_quit() if e.keyval == Gdk.KEY_Escape else None)

        self.show_all()

    def adjust_image_size(self):
        # try to match image pixel-size to vbox height
        try:
            alloc = self.get_allocation()
            height = alloc.height
            # reserve some space for padding
            target = max(48, int(height * 0.85))
            if os.path.exists(COVER_PATH):
                try:
                    pb = GdkPixbuf.Pixbuf.new_from_file(COVER_PATH)
                    scaled = pb.scale_simple(target, target, GdkPixbuf.InterpType.BILINEAR)
                    self.image.set_from_pixbuf(scaled)
                except Exception:
                    pass
        except Exception:
            pass
        return False

    def update(self):
        p = pick_player()
        self.player = p
        if not p:
            self.title_label.set_text("Nothing playing")
            self.artist_label.set_text("")
            self.progress.set_value(0)
            return True
        # metadata
        try:
            title = subprocess.check_output([PLAYERCTL, "-p", p, "metadata", "xesam:title"], stderr=subprocess.DEVNULL).decode().strip()
        except Exception:
            title = ""
        try:
            artist = subprocess.check_output([PLAYERCTL, "-p", p, "metadata", "xesam:artist"], stderr=subprocess.DEVNULL).decode().splitlines()[0].strip()
        except Exception:
            artist = ""
        try:
            length_us = int(subprocess.check_output([PLAYERCTL, "-p", p, "metadata", "mpris:length"], stderr=subprocess.DEVNULL).decode().strip())
        except Exception:
            length_us = 0
        try:
            position = float(subprocess.check_output([PLAYERCTL, "-p", p, "position"], stderr=subprocess.DEVNULL).decode().strip())
        except Exception:
            position = 0.0
        # update labels
        self.title_label.set_text(title if title else "")
        self.artist_label.set_text(artist if artist else "")
        # update progress
        if length_us > 0:
            length_s = length_us / 1e6
            pct = min(100, max(0, (position / length_s) * 100))
            self.progress.set_value(pct)
        else:
            self.progress.set_value(0)
        # cover
        try:
            art_url = subprocess.check_output([PLAYERCTL, "-p", p, "metadata", "mpris:artUrl"], stderr=subprocess.DEVNULL).decode().strip()
        except Exception:
            art_url = ""
        if art_url:
            prev = open(os.path.join(COVER_DIR, "cover_url"), "r").read().strip() if os.path.exists(os.path.join(COVER_DIR, "cover_url")) else ""
            if art_url != prev:
                # download or copy
                if art_url.startswith("file://"):
                    src = art_url[7:]
                    if os.path.exists(src):
                        try:
                            subprocess.run(["cp", src, COVER_PATH], check=False)
                        except Exception:
                            pass
                elif art_url.startswith("http://") or art_url.startswith("https://"):
                    if shutil_which("curl"):
                        try:
                            subprocess.run(["curl", "-sL", "-o", COVER_PATH, art_url], check=False)
                        except Exception:
                            pass
                    elif shutil_which("wget"):
                        try:
                            subprocess.run(["wget", "-qO", COVER_PATH, art_url], check=False)
                        except Exception:
                            pass
                try:
                    with open(os.path.join(COVER_DIR, "cover_url"), "w") as f:
                        f.write(art_url)
                except Exception:
                    pass
                # update image
                try:
                    pb = GdkPixbuf.Pixbuf.new_from_file_at_scale(COVER_PATH, 96, 96, True)
                    self.image.set_from_pixbuf(pb)
                except Exception:
                    pass
        return True


def shutil_which(cmd):
    from shutil import which
    return which(cmd) is not None


if __name__ == '__main__':
    try:
        app = MediaPopup()
        Gtk.main()
    except Exception as e:
        print(e, file=sys.stderr)
        sys.exit(1)
