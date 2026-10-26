/*
 * SPDX-License-Identifier: MIT
 *
 * Keyboard Backlight — a Quick Settings tile backed by UPower's standard
 * KbdBacklight interface.  The tile toggles the light, its arrow opens a
 * brightness slider, and UPower signals keep both views synchronized with
 * changes made outside GNOME Shell.
 */

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GObject from 'gi://GObject';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import * as QuickSettings from 'resource:///org/gnome/shell/ui/quickSettings.js';
import {Slider} from 'resource:///org/gnome/shell/ui/slider.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const ICON = 'keyboard-brightness-symbolic';
const UPOWER_NAME = 'org.freedesktop.UPower';
const UPOWER_PATH = '/org/freedesktop/UPower/KbdBacklight';

const KBD_BACKLIGHT_XML = `
<node>
  <interface name="org.freedesktop.UPower.KbdBacklight">
    <method name="GetBrightness">
      <arg type="i" direction="out"/>
    </method>
    <method name="GetMaxBrightness">
      <arg type="i" direction="out"/>
    </method>
    <method name="SetBrightness">
      <arg type="i" direction="in"/>
    </method>
    <property name="NativePath" type="s" access="read"/>
    <signal name="BrightnessChanged">
      <arg type="i"/>
    </signal>
  </interface>
</node>`;

const KbdBacklightProxy = Gio.DBusProxy.makeProxyWrapper(KBD_BACKLIGHT_XML);

/* Retain the level selected in this Shell process when the tile is toggled
 * off.  UPower/systemd-backlight retain the actual LED level across the
 * remaining lifecycle boundaries. */
let lastLevel = 50;

const BrightnessItem = GObject.registerClass(
class BrightnessItem extends PopupMenu.PopupBaseMenuItem {
    _init() {
        super._init({activate: false});

        this.add_child(new St.Label({
            text: 'Brightness',
            y_align: Clutter.ActorAlign.CENTER,
        }));

        this.slider = new Slider({
            x_expand: true,
            y_align: Clutter.ActorAlign.CENTER,
        });
        this.add_child(this.slider);
    }
});

const KeyboardBacklightToggle = GObject.registerClass(
class KeyboardBacklightToggle extends QuickSettings.QuickMenuToggle {
    _init() {
        super._init({
            title: 'Keyboard Backlight',
            iconName: ICON,
            toggleMode: true,
        });

        this.menu.setHeader(ICON, 'Keyboard Backlight');
        this._max = 0;
        this._brightness = 0;
        this._pendingBrightness = null;
        this._setting = false;
        this._syncGeneration = 0;
        this._lastError = null;
        this._destroyed = false;
        this._proxySignalIds = [];

        this._item = new BrightnessItem();
        this.menu.addMenuItem(this._item);
        this._item.slider.connect('notify::value', () => this._onSliderChanged());

        this.connect('clicked', () => {
            if (this._max <= 0)
                return;

            const target = this._brightness > 0
                ? 0
                : Math.min(this._max, Math.max(1, lastLevel));
            this._queueBrightness(target);
        });
        this.connect('destroy', () => this._onDestroy());

        this._setUnavailable();
        this._proxy = new KbdBacklightProxy(
            Gio.DBus.system,
            UPOWER_NAME,
            UPOWER_PATH,
            (proxy, error) => this._proxyReady(proxy, error));
    }

    _proxyReady(proxy, error) {
        if (this._destroyed)
            return;
        if (error) {
            this._report(error);
            this._setUnavailable();
            return;
        }

        this._proxy = proxy;
        this._proxySignalIds.push(proxy.connectSignal(
            'BrightnessChanged', (_proxy, _sender, [brightness]) => {
                if (this._max > 0)
                    this._applyBrightness(brightness);
                else
                    this._sync();
            }));
        this._ownerSignalId = proxy.connect('notify::g-name-owner', () => this._sync());
        this._propertiesSignalId = proxy.connect('g-properties-changed', () => this._sync());
        this._sync();
    }

    _sync() {
        const proxy = this._proxy;
        const generation = ++this._syncGeneration;

        if (!proxy || !proxy.get_name_owner()) {
            this._setUnavailable();
            return;
        }

        proxy.GetMaxBrightnessRemote((maxResult, maxError) => {
            if (this._destroyed || generation !== this._syncGeneration)
                return;
            if (maxError || !maxResult || maxResult[0] <= 0) {
                if (maxError)
                    this._report(maxError);
                this._setUnavailable();
                return;
            }

            const max = maxResult[0];
            proxy.GetBrightnessRemote((brightnessResult, brightnessError) => {
                if (this._destroyed || generation !== this._syncGeneration)
                    return;
                if (brightnessError || !brightnessResult) {
                    if (brightnessError)
                        this._report(brightnessError);
                    this._setUnavailable();
                    return;
                }

                this._max = max;
                this._lastError = null;
                this._applyBrightness(brightnessResult[0]);
            });
        });
    }

    _onSliderChanged() {
        if (this._updating || this._max <= 0)
            return;

        this._queueBrightness(Math.round(this._item.slider.value * this._max));
    }

    _queueBrightness(brightness) {
        this._pendingBrightness = Math.max(0, Math.min(this._max, brightness));
        if (!this._setting)
            this._writeNext();
    }

    _writeNext() {
        if (this._pendingBrightness === null || !this._proxy || this._max <= 0)
            return;

        const brightness = this._pendingBrightness;
        this._pendingBrightness = null;
        this._setting = true;
        this._proxy.SetBrightnessRemote(brightness, (_result, error) => {
            if (this._destroyed)
                return;

            this._setting = false;
            if (error) {
                this._report(error);
                this._sync();
            } else {
                if (brightness > 0)
                    lastLevel = brightness;
                this._applyBrightness(brightness);
                this._lastError = null;
            }

            if (this._pendingBrightness !== null)
                this._writeNext();
        });
    }

    _applyBrightness(brightness) {
        brightness = Math.max(0, Math.min(this._max, brightness));
        this._brightness = brightness;
        if (brightness > 0)
            lastLevel = brightness;

        const on = brightness > 0;
        this.checked = on;
        this.subtitle = on
            ? `${Math.round(brightness * 100 / this._max)}%`
            : 'Off';
        this.reactive = true;
        this.menuEnabled = true;
        this._item.reactive = true;

        this._updating = true;
        this._item.slider.value = brightness / this._max;
        this._updating = false;
    }

    _setUnavailable() {
        this._max = 0;
        this._brightness = 0;
        this.checked = false;
        this.subtitle = 'Unavailable';
        this.reactive = false;
        this.menuEnabled = false;
        this._item.reactive = false;

        this._updating = true;
        this._item.slider.value = 0;
        this._updating = false;
    }

    _report(error) {
        const message = `${error}`;
        if (message === this._lastError)
            return;
        this._lastError = message;
        logError(error, 'keyboard-backlight');
    }

    _onDestroy() {
        this._destroyed = true;
        ++this._syncGeneration;
        if (!this._proxy)
            return;

        for (const id of this._proxySignalIds)
            this._proxy.disconnectSignal(id);
        this._proxySignalIds = [];
        if (this._ownerSignalId)
            this._proxy.disconnect(this._ownerSignalId);
        if (this._propertiesSignalId)
            this._proxy.disconnect(this._propertiesSignalId);
        this._proxy = null;
    }
});

const KeyboardBacklightIndicator = GObject.registerClass(
class KeyboardBacklightIndicator extends QuickSettings.SystemIndicator {
    _init() {
        super._init();

        this._toggle = new KeyboardBacklightToggle();
        this.quickSettingsItems.push(this._toggle);
    }

    destroy() {
        this.quickSettingsItems.forEach(item => item.destroy());
        this.quickSettingsItems = [];
        super.destroy();
    }
});

export default class KeyboardBacklightExtension extends Extension {
    enable() {
        this._indicator = new KeyboardBacklightIndicator();
        Main.panel.statusArea.quickSettings.addExternalIndicator(this._indicator);
    }

    disable() {
        this._indicator?.destroy();
        this._indicator = null;
    }
}
