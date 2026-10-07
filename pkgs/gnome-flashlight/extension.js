/*
 * SPDX-License-Identifier: MIT
 *
 * Flashlight — the Xiaomi Pad 6 Pro's rear flash LED in the Quick Settings
 * menu, laid out like the Wi-Fi/Bluetooth tiles: one tile that toggles the
 * light and shows its level as the subtitle, and an arrow that opens a
 * second-level menu with the brightness slider.
 *
 * The LED is the kernel's white:flash LED class device; the NixOS side hands
 * its brightness attribute to the video group so the session user can write
 * it.  State is read back from sysfs, so the tile and the slider follow
 * changes made by anything else (the camera's flash, a shell).
 */

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import * as QuickSettings from 'resource:///org/gnome/shell/ui/quickSettings.js';
import {Slider} from 'resource:///org/gnome/shell/ui/slider.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const ICON_ON = 'flashlight-symbolic';
const ICON_OFF = 'flashlight-off-symbolic';
const BRIGHTNESS = '/sys/class/leds/white:flash/brightness';
const MAX_BRIGHTNESS = '/sys/class/leds/white:flash/max_brightness';

function readNumber(path, fallback) {
    try {
        const [, contents] = GLib.file_get_contents(path);
        const value = parseInt(new TextDecoder().decode(contents).trim(), 10);
        return Number.isFinite(value) ? value : fallback;
    } catch (e) {
        return fallback;
    }
}

/*
 * Sysfs attributes reject GLib.file_set_contents(): that writes atomically,
 * by creating a temporary file next to the target and renaming it, and sysfs
 * has no way to create files (measured: "Failed to create file
 * .../brightness.VI7NW3: Permission denied").  Append to it instead - the
 * O_APPEND the shell's >> uses - and write the whole value each time.
 */
function writeNumber(path, value) {
    const bytes = new TextEncoder().encode(`${value}\n`);

    try {
        const file = Gio.File.new_for_path(path);
        const stream = file.append_to(Gio.FileCreateFlags.NONE, null);
        stream.write_all(bytes, null);
        stream.close(null);
        return true;
    } catch (e) {
        logError(e, `flashlight: writing ${value} to ${path}`);
        return false;
    }
}

/* The LED is shared: remember the level the user last chose so toggling off
 * and back on returns to it rather than to the maximum. */
let lastLevel = 128;

const BrightnessItem = GObject.registerClass(
class BrightnessItem extends PopupMenu.PopupBaseMenuItem {
    _init() {
        /* activate: false keeps the menu open while the slider is used. */
        super._init({ activate: false });

        this.add_child(new St.Label({
            text: 'Brightness',
            y_align: Clutter.ActorAlign.CENTER,
        }));

        /* GNOME 50 has no St.Slider; its own sliders come from ui/slider.js. */
        this.slider = new Slider({
            x_expand: true,
            y_align: Clutter.ActorAlign.CENTER,
        });
        this.add_child(this.slider);
    }
});

const FlashlightToggle = GObject.registerClass(
class FlashlightToggle extends QuickSettings.QuickMenuToggle {
    _init() {
        super._init({
            title: 'Flashlight',
            iconName: ICON_OFF,
            toggleMode: true,
        });

        this.menu.setHeader(ICON_OFF, 'Flashlight');
        this.menuEnabled = true;

        this._max = Math.max(1, readNumber(MAX_BRIGHTNESS, 255));

        this._item = new BrightnessItem();
        this.menu.addMenuItem(this._item);
        this._item.slider.connect('notify::value', () => this._onSliderChanged());

        this._sync();
        this._timer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 2, () => {
            this._sync();
            return GLib.SOURCE_CONTINUE;
        });

        /* The tile itself toggles the light; the arrow opens the menu. */
        this.connect('clicked', () => {
            this._write(readNumber(BRIGHTNESS, 0) > 0 ? 0 : lastLevel);
            this._sync();
        });
        this.connect('destroy', () => this._clearTimer());
    }

    _onSliderChanged() {
        if (this._updating)
            return;

        this._write(Math.round(this._item.slider.value * this._max));
        this._sync();
    }

    _write(brightness) {
        if (brightness > 0)
            lastLevel = brightness;

        writeNumber(BRIGHTNESS, brightness);
    }

    _sync() {
        const brightness = readNumber(BRIGHTNESS, 0);
        if (brightness > 0)
            lastLevel = brightness;

        const on = brightness > 0;
        const percent = Math.round(brightness * 100 / this._max);

        this.checked = on;
        this.iconName = on ? ICON_ON : ICON_OFF;
        this.subtitle = on ? `${percent}%` : 'Off';

        this._updating = true;
        this._item.slider.value = brightness / this._max;
        this._updating = false;
    }

    _clearTimer() {
        if (this._timer) {
            GLib.source_remove(this._timer);
            this._timer = 0;
        }
    }
});

const FlashlightIndicator = GObject.registerClass(
class FlashlightIndicator extends QuickSettings.SystemIndicator {
    _init() {
        super._init();

        this._toggle = new FlashlightToggle();
        this.quickSettingsItems.push(this._toggle);
    }

    destroy() {
        this.quickSettingsItems.forEach(item => item.destroy());
        this.quickSettingsItems = [];
        super.destroy();
    }
});

export default class FlashlightExtension extends Extension {
    enable() {
        this._indicator = new FlashlightIndicator();
        Main.panel.statusArea.quickSettings.addExternalIndicator(this._indicator);
    }

    disable() {
        this._indicator?.destroy();
        this._indicator = null;
    }
}
