# SPDX-License-Identifier: MIT
#
# Keeps the panel transform right across folio posture changes, because mutter
# does not:
#
#   * On leaving tablet mode it keeps the last gravity-derived transform
#     (measured 2026-10-08: folded portrait, keyboard deployed, panel stays
#     portrait even though monitors.xml configures the landscape pose).
#   * Its accelerometer claim is one-shot.  gnome-shell's mutter claims when
#     net.hadess.SensorProxy appears after it started and never re-claims
#     after the claim is lost (measured: proxy CPU ticks frozen, orientation
#     stuck, PanelOrientationManaged still true).  A dead claim means no
#     rotation at all while folded or with the folio removed.
#
# This loop watches the bridge driver's derived switch (tablet_mode, 1 = no
# keyboard attached: folio folded or absent) and repairs both:
#
#   * entering the laptop posture: re-apply the rotation monitors.xml
#     configures, as a temporary config so neither mutter's store nor the file
#     is rewritten;
#   * entering tablet mode: if the proxy is not being polled, claim the
#     accelerometer here and follow AccelerometerOrientation directly.
#     Restarting the proxy cannot help - mutter does not resume consuming
#     orientations once its own claim has failed.
#
# The transform table is the pair measured on the unit: right-up is the
# landscape pose (270 deg), normal the native portrait.
{ writeShellApplication
, coreutils
, gawk
, glib
, gnused
, liuqinIioSensorProxy
, procps
, systemd
}:

writeShellApplication {
  name = "liuqin-panel-posture";
  runtimeInputs = [
    coreutils
    gawk
    glib
    gnused
    liuqinIioSensorProxy
    procps
    systemd
  ];
  text = ''
    switch_dir=
    for candidate in /sys/bus/i2c/devices/*-004c; do
        [ -d "$candidate" ] || continue
        switch_dir=$candidate
        break
    done
    switch_file=''${switch_dir:+$switch_dir/tablet_mode}
    fallback_pid_file=''${XDG_RUNTIME_DIR:-/tmp}/liuqin-panel-posture.fallback

    posture() {
        cat "$switch_file" 2>/dev/null || true
    }

    mutter_state() {
        gdbus call --session \
            --dest org.gnome.Mutter.DisplayConfig \
            --object-path /org/gnome/Mutter/DisplayConfig \
            --method org.gnome.Mutter.DisplayConfig.GetCurrentState 2>/dev/null
    }

    current_transform() {
        mutter_state \
            | sed -n 's/.*(\([0-9]*\), \([0-9]*\), \([0-9.]*\), uint32 \([0-9]*\), \(true\|false\),.*/\4/p' \
            | head -1
    }

    # Apply one transform to the built-in panel and check it took.  The
    # persistent method is the one that works: the temporary method is a
    # silent no-op in this mutter (measured 2026-10-09 - the call succeeds and
    # the state does not move), while the persistent one applies at once and
    # still writes no monitors.xml, so the configured file stays the source of
    # truth.  The check is there because the apply can also be deferred while
    # the session is not visible, and the caller's posture change is then
    # retried instead of trusted.
    apply_transform() {
        want=$1
        attempt=1
        while [ "$attempt" -le 3 ]; do
            if [ "$(current_transform)" = "$want" ]; then
                return 0
            fi

            state=$(mutter_state) || return 0
            [ -n "$state" ] || return 0

            serial=$(printf '%s\n' "$state" | head -1 \
                | sed -n 's/^(uint32 \([0-9]*\),.*/\1/p')
            mode=$(printf '%s\n' "$state" \
                | sed -n "s/.*(('DSI-1'.*\[('\([0-9]*x[0-9]*@[0-9.]*\)'.*/\1/p" \
                | head -1)
            fields=$(printf '%s\n' "$state" \
                | sed -n 's/.*(\([0-9]*\), \([0-9]*\), \([0-9.]*\), uint32 \([0-9]*\), \(true\|false\),.*/\1 \2 \3/p' \
                | head -1)
            [ -n "$serial" ] && [ -n "$mode" ] && [ -n "$fields" ] || return 0

            # shellcheck disable=SC2086
            set -- $fields

            gdbus call --session \
                --dest org.gnome.Mutter.DisplayConfig \
                --object-path /org/gnome/Mutter/DisplayConfig \
                --method org.gnome.Mutter.DisplayConfig.ApplyMonitorsConfig \
                "$serial" 1 \
                "[(0, 0, $3, uint32 $want, true, [('DSI-1', '$mode', {})])]" \
                "{}" >/dev/null 2>&1 || :

            sleep 1
            attempt=$((attempt + 1))
        done
    }

    apply_configured_rotation() {
        xml=''${XDG_CONFIG_HOME:-$HOME/.config}/monitors.xml
        [ -r "$xml" ] || return 0

        rotation=$(sed -n 's:.*<rotation>\([a-z-]*\)</rotation>.*:\1:p' "$xml" \
            | head -1)
        case $rotation in
        normal) want=0 ;;
        left) want=1 ;;
        upside-down) want=2 ;;
        right) want=3 ;;
        *) return 0 ;;
        esac

        apply_transform "$want"
    }

    # A claiming client is what makes the proxy's CPU time advance.
    proxy_ticks() {
        pid=$(pgrep -f libexec/iio-sensor-proxy | head -1) || return 1
        [ -n "$pid" ] || return 1
        awk '{print $14+$15}' "/proc/$pid/stat" 2>/dev/null
    }

    claim_is_alive() {
        before=$(proxy_ticks) || return 1
        [ -n "$before" ] || return 1
        sleep 2
        after=$(proxy_ticks) || return 1
        [ -n "$after" ] && [ "$after" -gt "$before" ]
    }

    stop_fallback() {
        [ -f "$fallback_pid_file" ] || return 0
        kill "$(cat "$fallback_pid_file")" 2>/dev/null || :
        rm -f "$fallback_pid_file"
    }

    # Claim the accelerometer and follow the orientation ourselves.  Runs
    # until the posture leaves tablet mode, then drops the claim again so a
    # future shell can have one.
    fallback() {
        stop_fallback
        monitor-sensor --accel >/dev/null 2>&1 &
        printf '%s\n' "$!" > "$fallback_pid_file"

        previous=
        while :; do
            [ "$(posture)" = 1 ] || break

            orientation=$(gdbus call --system \
                --dest net.hadess.SensorProxy \
                --object-path /net/hadess/SensorProxy \
                --method org.freedesktop.DBus.Properties.Get \
                net.hadess.SensorProxy AccelerometerOrientation 2>/dev/null \
                | sed -n "s/.*'\([a-z-]*\)'.*/\1/p")
            case $orientation in
            normal) candidate=0 ;;
            right-up) candidate=3 ;;
            left-up) candidate=1 ;;
            bottom-up) candidate=2 ;;
            *) candidate= ;;
            esac

            if [ -n "$candidate" ] && [ "$orientation" != "$previous" ]; then
                apply_transform "$candidate" || :
                previous=$orientation
            fi
            sleep 1
        done

        stop_fallback
    }

    # Let the session's own proxy refresh settle before judging its claim.
    sleep 10

    # Idempotent: every pass re-checks the state instead of only reacting to
    # a posture change, because mutter re-applies its stored config when the
    # screen blanks or locks - which drops the laptop transform back to the
    # native portrait (measured 2026-10-09, transform 3 -> 0 with no input
    # event) - and because the fallback can die with the posture unchanged.
    while :; do
        now=$(posture)
        if [ "$now" = 0 ]; then
            stop_fallback
            apply_configured_rotation || :
        elif [ "$now" = 1 ]; then
            claim_is_alive || fallback || :
        fi
        sleep 3
    done
  '';
}
