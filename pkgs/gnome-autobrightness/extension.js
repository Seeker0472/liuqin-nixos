/*
 * SPDX-License-Identifier: MIT
 *
 * Automatic Brightness — a Quick Settings tile for the desktop's
 * ambient-light automatic screen brightness, in the Wi-Fi/Bluetooth row.
 *
 * A plain toggle: the switch is the whole interface and the lux reading rides
 * in the subtitle, so there is no second-level menu (and no menu arrow).
 *
 * The tile binds gnome-settings-daemon's own switch,
 * org.gnome.settings-daemon.plugins.power ambient-enabled — the key
 * gnome-control-center's Power panel writes for "Automatic Screen
 * Brightness" — so both surfaces always agree and no second state exists.
 * Flipping it here takes effect at once: a change of that key is one of the
 * few events on which gsd-power re-evaluates the light-sensor claim it
 * drives off (the others are a screen blank/unblank cycle, a session-active
 * change and the SensorProxy name appearing), which is also what makes the
 * tile the reliable way to establish the claim after a proxy restart —
 * measured 2026-10-09: with the key toggled off and back on, LightLevel
 * advanced from a stale 10.9 to fresh readings within seconds.
 *
 * The sensor is the SSC ambient-light instance the liuqin stack bridges
 * (uncalibrated; see docs/PORTING-NOTES.md, Sensors).  The tile appears only
 * while net.hadess.SensorProxy reports an ambient light sensor, and its
 * subtitle carries the lux reading gsd-power is working from — LightLevel
 * only advances while a client holds the claim, so a frozen reading while
 * the tile is on is itself the symptom of a claim that never landed.
 */

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as QuickSettings from 'resource:///org/gnome/shell/ui/quickSettings.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const ICON = 'auto-brightness-symbolic';

/* gnome-settings-daemon's power plugin schema; the key the Power panel's
 * "Automatic Screen Brightness" row writes (default: true). */
const POWER_SCHEMA = 'org.gnome.settings-daemon.plugins.power';
const AMBIENT_KEY = 'ambient-enabled';

const SENSOR_BUS_NAME = 'net.hadess.SensorProxy';
const SENSOR_OBJECT_PATH = '/net/hadess/SensorProxy';
const SENSOR_INTERFACE = 'net.hadess.SensorProxy';

/* The two properties this tile reads, named as iio-sensor-proxy exports them;
 * GDBusProxy caches exactly the properties its interface info carries. */
const SENSOR_INTERFACE_INFO = Gio.DBusNodeInfo.new_for_xml(`
<node>
  <interface name="${SENSOR_INTERFACE}">
    <property name="HasAmbientLight" type="b" access="read"/>
    <property name="LightLevel" type="d" access="read"/>
  </interface>
</node>
`).interfaces[0];

const AutoBrightnessToggle = GObject.registerClass(
class AutoBrightnessToggle extends QuickSettings.QuickToggle {
    _init() {
        super._init({
            title: 'Automatic Brightness',
            iconName: ICON,
            toggleMode: true,
        });

        this._settings = new Gio.Settings({ schema_id: POWER_SCHEMA });
        /* DEFAULT is two-way: clicking the tile writes the key, and a change
         * made from the Power panel moves the tile. */
        this._settings.bind(AMBIENT_KEY, this, 'checked',
            Gio.SettingsBindFlags.DEFAULT);

        this._hasAmbientLight = false;

        this._proxy = new Gio.DBusProxy({
            g_connection: Gio.DBus.system,
            g_name: SENSOR_BUS_NAME,
            g_object_path: SENSOR_OBJECT_PATH,
            g_interface_name: SENSOR_INTERFACE,
            g_interface_info: SENSOR_INTERFACE_INFO,
        });
        /* The proxy is a system service that liuqin-sensor-proxy-refresh
         * restarts: re-read on every owner change as well as on properties. */
        this._proxy.connectObject(
            'g-properties-changed', () => this._sync(),
            'notify::g-name-owner', () => this._sync(),
            this);
        this._proxy.init_async(GLib.PRIORITY_DEFAULT, null)
            .catch(e => console.error(e.message));

        this.connectObject('notify::checked', () => this._sync(), this);

        this._sync();
    }

    _sync() {
        const hasLight = this._proxy.get_cached_property('HasAmbientLight');
        /* The name is unowned while the proxy restarts: keep the last
         * reported presence so a restart does not blink the tile away. */
        if (this._proxy.g_name_owner && hasLight)
            this._hasAmbientLight = hasLight.unpack();

        this.visible = this._hasAmbientLight;

        const level = this._proxy.get_cached_property('LightLevel');
        const lux = level?.unpack() ?? 0;

        if (!this.checked)
            this.subtitle = 'Off';
        else
            this.subtitle = lux > 0 ? `${Math.round(lux)} lx` : 'On';
    }
});

const AutoBrightnessIndicator = GObject.registerClass(
class AutoBrightnessIndicator extends QuickSettings.SystemIndicator {
    _init() {
        super._init();

        this._toggle = new AutoBrightnessToggle();
        this.quickSettingsItems.push(this._toggle);
    }

    destroy() {
        this.quickSettingsItems.forEach(item => item.destroy());
        this.quickSettingsItems = [];
        super.destroy();
    }
});

export default class AutoBrightnessExtension extends Extension {
    enable() {
        this._indicator = new AutoBrightnessIndicator();
        Main.panel.statusArea.quickSettings.addExternalIndicator(this._indicator);
    }

    disable() {
        this._indicator?.destroy();
        this._indicator = null;
    }
}
