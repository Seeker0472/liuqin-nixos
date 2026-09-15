#!/bin/sh
# SPDX-License-Identifier: MIT
# Fixed desktop actions for liuqin-power-keyd. Never power off directly.
# Adapted from the downstream helper: all tool paths come from the Nix-built
# environment injected by the systemd unit (PATH and the variables below).
set -eu

action=${1:-}
: "${loginctl:?}" "${gdbus:?}" "${gsettings:?}" "${systemctl:?}" \
	"${systemd_run:?}" "${power_menu:?}" "${setpriv:?}" "${getent:?}" \
	"${test_bin:?}"
state_dir=${LIUQIN_STATE_DIR:-/run/liuqin-power-keyd}
runtime_base=/run/user
power_schema_dir=${GSETTINGS_SCHEMA_DIR:?}

case $action in short|long) ;; *) exit 64 ;; esac

session=$("$loginctl" show-seat seat0 --property=ActiveSession --value 2>/dev/null || :)
[ -n "$session" ] && [ "$session" != n/a ] || {
	echo "liuqin-power-key-action: no active seat0 session; $action ignored" >&2
	exit 3
}
active=$("$loginctl" show-session "$session" --property=Active --value 2>/dev/null || :)
class=$("$loginctl" show-session "$session" --property=Class --value 2>/dev/null || :)
uid=$("$loginctl" show-session "$session" --property=User --value 2>/dev/null || :)
name=$("$loginctl" show-session "$session" --property=Name --value 2>/dev/null || :)
[ "$active" = yes ] && [ "$class" = user ] || {
	echo "liuqin-power-key-action: seat0 session is not an active user; $action ignored" >&2
	exit 3
}
case $uid in ''|*[!0-9]*) exit 3 ;; esac
[ "$uid" -ge 1000 ] && [ -n "$name" ] || exit 3

passwd_entry=$("$getent" passwd "$uid" 2>/dev/null || :)
[ -n "$passwd_entry" ] || exit 3
gid=$(printf '%s\n' "$passwd_entry" | cut -d: -f4)
home=$(printf '%s\n' "$passwd_entry" | cut -d: -f6)
case $gid in ''|*[!0-9]*) exit 3 ;; esac
runtime=$runtime_base/$uid
"$setpriv" --reuid="$uid" --regid="$gid" --clear-groups -- \
	"$test_bin" -S "$runtime/bus" || {
	echo "liuqin-power-key-action: active session has no D-Bus; $action ignored" >&2
	exit 3
}

session_command() {
	"$setpriv" --reuid="$uid" --regid="$gid" --clear-groups -- \
		env -i \
		HOME="$home" USER="$name" LOGNAME="$name" \
		XDG_RUNTIME_DIR="$runtime" \
		DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/bus" \
		PATH=/run/current-system/sw/bin \
		GSETTINGS_SCHEMA_DIR="$power_schema_dir" \
		"$@"
}

session_call() {
	session_command "$gdbus" call --session --timeout 5 "$@"
}

if [ "$action" = short ]; then
	policy=$(session_command "$gsettings" get io.github.liuqin.power short-press-action)
	case $policy in
		"'blank'") policy=blank ;;
		"'suspend'") policy=suspend ;;
		"'nothing'") exit 0 ;;
		*) exit 3 ;;
	esac
	[ -d "$state_dir" ] && [ ! -L "$state_dir" ] || exit 3
	state_file=$state_dir/display-state
	state=$(cat "$state_file" 2>/dev/null || :)
	case $state in off|on-locked|suspend-requested|'') ;; *) state= ;; esac
	active_reply=$(session_call \
		--dest org.gnome.ScreenSaver \
		--object-path /org/gnome/ScreenSaver \
		--method org.gnome.ScreenSaver.GetActive 2>/dev/null || :)
	case $active_reply in *true*) screen_active=yes ;; *) screen_active=no ;; esac
	dpms_reply=$(session_call \
		--dest org.gnome.Mutter.DisplayConfig \
		--object-path /org/gnome/Mutter/DisplayConfig \
		--method org.freedesktop.DBus.Properties.Get \
		org.gnome.Mutter.DisplayConfig PowerSaveMode 2>/dev/null || :)
	case $dpms_reply in *\<3\>*) dpms_off=yes ;; *) dpms_off=no ;; esac

	if [ "$state" = suspend-requested ]; then
		direction=on
	elif [ "$state" = off ] && [ "$screen_active" = yes ]; then
		direction=on
	elif [ "$state" = on-locked ] && [ "$screen_active" = yes ]; then
		direction=off
	elif [ "$screen_active" = yes ] || [ "$dpms_off" = yes ]; then
		direction=on
	else
		direction=off
	fi

	if [ "$direction" = off ]; then
		"$loginctl" lock-sessions
		session_call \
			--dest org.gnome.ScreenSaver \
			--object-path /org/gnome/ScreenSaver \
			--method org.gnome.ScreenSaver.SetActive true >/dev/null
		session_call \
			--dest org.gnome.Mutter.DisplayConfig \
			--object-path /org/gnome/Mutter/DisplayConfig \
			--method org.freedesktop.DBus.Properties.Set \
			org.gnome.Mutter.DisplayConfig PowerSaveMode '<3>' >/dev/null
		new_state=off
		[ "$policy" != suspend ] || new_state=suspend-requested
	else
		session_call \
			--dest org.gnome.Mutter.DisplayConfig \
			--object-path /org/gnome/Mutter/DisplayConfig \
			--method org.freedesktop.DBus.Properties.Set \
			org.gnome.Mutter.DisplayConfig PowerSaveMode '<0>' >/dev/null
		new_state=on-locked
	fi
	state_tmp=$state_file.$$
	(umask 077; printf '%s\n' "$new_state" >"$state_tmp")
	mv -f -- "$state_tmp" "$state_file"
	printf 'liuqin-power-key-action: display=%s\n' "$direction"
	if [ "$new_state" = suspend-requested ]; then
		"$systemctl" suspend
		printf '%s\n' 'liuqin-power-key-action: suspend requested'
	fi
else
	session_command "$systemd_run" --user --quiet --collect \
		--unit=liuqin-power-menu "$power_menu"
	printf '%s\n' 'liuqin-power-key-action: power menu requested'
fi
