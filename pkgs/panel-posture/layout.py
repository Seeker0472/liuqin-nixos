# SPDX-License-Identifier: MIT
"""Display policy, independent of D-Bus and the live desktop."""
import xml.etree.ElementTree as ET

ROTATIONS = {"normal": 0, "left": 1, "upside-down": 2, "right": 3}
ORIENTATIONS = {"normal": 0, "left-up": 1, "bottom-up": 2, "right-up": 3}


def value(item):
    return item.unpack() if hasattr(item, "unpack") else item


def laptop_rotation(path, default):
    """Use a stored panel-only configuration, never another monitor's rotation."""
    try:
        tree = ET.parse(path)
    except (OSError, ET.ParseError):
        return default
    for config in tree.findall("configuration"):
        logicals = config.findall("logicalmonitor")
        if len(logicals) != 1:
            continue
        monitors = logicals[0].findall("monitor")
        if len(monitors) != 1:
            continue
        connector = (monitors[0].findtext("monitorspec/connector")
                     or monitors[0].findtext("connector"))
        if connector == "DSI-1":
            return ROTATIONS.get(logicals[0].findtext("transform/rotation"), default)
    return default


def monitor_state(monitors, spec):
    monitor = next((item for item in monitors if tuple(item[0]) == tuple(spec)), None)
    if monitor is None:
        return None
    _, modes, properties = monitor
    current = [mode for mode in modes if value(mode[6].get("is-current", False))]
    if len(current) != 1:
        return None
    return current[0], properties


def logical_size(logical, states):
    """Return a logical monitor's current width and height."""
    _, _, scale, transform, _, specs, _ = logical
    if not specs:
        return None
    state = states.get(tuple(specs[0]))
    if state is None:
        return None
    mode, _ = state
    width, height = mode[1], mode[2]
    if transform in (1, 3):
        width, height = height, width
    return round(width / scale), round(height / scale)


def rotation_config(state, transform):
    """Rotate DSI-1 while preserving a valid extended-desktop topology.

    The complete current layout is returned because Mutter treats
    ApplyMonitorsConfig as a replacement. Monitors to the right or below the
    panel move by the panel's logical-size delta, preserving their placement
    without overlap. A mirrored DSI logical monitor is left desktop-managed.
    """
    serial, monitors, logicals, properties = state
    if transform not in range(4):
        return None

    targets = [index for index, logical in enumerate(logicals)
               if any(spec[0] == "DSI-1" for spec in logical[5])]
    if len(targets) != 1:
        return None
    target_index = targets[0]
    target = logicals[target_index]
    if len(target[5]) != 1 or target[5][0][0] != "DSI-1" or target[3] == transform:
        return None

    states = {}
    for logical in logicals:
        for spec in logical[5]:
            current = monitor_state(monitors, spec)
            if current is None:
                return None
            states[tuple(spec)] = current

    old_size = logical_size(target, states)
    if old_size is None:
        return None
    old_width, old_height = old_size
    mode, _ = states[tuple(target[5][0])]
    new_width, new_height = round(mode[1] / target[2]), round(mode[2] / target[2])
    if transform in (1, 3):
        new_width, new_height = new_height, new_width
    delta_width = new_width - old_width
    delta_height = new_height - old_height
    old_right = target[0] + old_width
    old_bottom = target[1] + old_height

    requested = []
    for index, logical in enumerate(logicals):
        x, y, scale, current_transform, primary, specs, _ = logical
        if index == target_index:
            current_transform = transform
        else:
            if x >= old_right:
                x += delta_width
            if y >= old_bottom:
                y += delta_height

        requested_monitors = []
        for spec in specs:
            current_mode, monitor_properties = states[tuple(spec)]
            request_properties = {}
            for source, destination in (("is-underscanning", "underscanning"),
                                        ("color-mode", "color-mode")):
                if source in monitor_properties:
                    request_properties[destination] = value(monitor_properties[source])
            requested_monitors.append((spec[0], current_mode[0], request_properties))
        requested.append((x, y, scale, current_transform, primary, requested_monitors))

    global_properties = {key: value(properties[key])
                         for key in ("layout-mode",) if key in properties}
    return serial, 1, requested, global_properties
