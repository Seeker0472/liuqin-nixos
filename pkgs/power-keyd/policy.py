# SPDX-License-Identifier: MIT
"""Power policy, independent of input devices, credentials and D-Bus.

Facts have distinct owners: Mutter reports display power, logind reports the
session's LockedHint and PrepareForSleep, and UPower reports the lid. Effects
are directional commands. A completion belongs to one transaction and one
step; a late reply can never commit a cancelled suspend.
"""
from dataclasses import dataclass
from enum import Enum, auto


class Phase(Enum):
    READY = auto()
    LOCKING = auto()
    BLANKING = auto()
    SUSPENDING = auto()
    SLEEPING = auto()
    ACTIVATING = auto()
    WAKING = auto()
    CHECKING_IDLE = auto()


@dataclass(frozen=True)
class Effect:
    kind: str
    token: int
    value: object = None


@dataclass
class Gesture:
    pressed_at: int
    wake_only: bool
    policy: str
    long_fired: bool = False


class PowerPolicy:
    MIN_PRESS_MS = 40
    LONG_PRESS_MS = 1500
    OPERATION_TIMEOUT_MS = 5000
    # Covers evdev events queued around logind's post-resume notification.
    # Holding the wake key remains consumed until release, without a timer.
    RESUME_GUARD_MS = 300
    BACKGROUND_GRACE_MS = 20000
    # Mutter resets its idle counter on resume too. Give that synthetic reset
    # time to settle before requiring a complete twenty seconds of idleness.
    RESUME_SETTLE_MS = 2000

    def __init__(self, emit, *, greeter=False):
        self.emit = emit
        self.greeter = greeter
        self.phase = Phase.READY
        self.power = None
        self.locked = None
        self.ready = False
        self.preparing = False
        self.lid_closed = False
        self.lid_blanked = False
        self.short_action = 'suspend'
        self.gesture = None
        self.ignore_release = False
        self.wake_requested = False
        self.resume_until = -1
        self.resume_wake_sent = False
        self.token = 0
        self.deadline = None
        self.suspend_after_blank = False
        self.background_enabled = True
        self.background_allowed = False
        self.quiet_resume = False
        self.background_deadline = None
        self.saw_sleep = False
        self.background_observed = False

    def _cancel_background(self):
        self.quiet_resume = False
        self.background_deadline = None
        self.background_observed = False
        if self.phase == Phase.CHECKING_IDLE:
            self.token += 1
            self.phase = Phase.READY
            self.deadline = None

    def _background_eligible(self):
        return (self.quiet_resume and self.background_enabled and self.background_allowed
                and self.ready and not self.preparing and self.locked is True
                and (not self.background_observed or self.power == 3)
                and self.gesture is None
                and self.phase in (Phase.READY, Phase.CHECKING_IDLE))

    def _update_background(self, now):
        if not self._background_eligible():
            self.background_deadline = None
            if self.phase == Phase.CHECKING_IDLE:
                self._cancel_background()
        elif self.phase == Phase.READY and self.background_deadline is None:
            self.background_deadline = now + self.BACKGROUND_GRACE_MS
            if not self.background_observed:
                self.background_deadline += self.RESUME_SETTLE_MS

    def user_activity(self):
        self._cancel_background()

    def background(self, *, now, enabled=None, allowed=None):
        if enabled is not None:
            self.background_enabled = enabled is True
            if not self.background_enabled:
                self._cancel_background()
        if allowed is not None:
            self.background_allowed = allowed is True
        self._update_background(now)

    def _effect(self, kind, value=None):
        self.emit(Effect(kind, self.token, value))

    def _begin(self, phase, now):
        self.token += 1
        self.phase = phase
        self.deadline = now + self.OPERATION_TIMEOUT_MS

    def _fail(self, message):
        self._cancel_background()
        self.token += 1
        self.phase = Phase.SLEEPING if self.preparing else Phase.READY
        self.deadline = None
        self._effect('error', message)

    def available(self, ready):
        self.ready = ready
        if not ready:
            self._cancel_background()
            self.gesture = None
            self.ignore_release = True
            self.token += 1
            self.deadline = None
            self.phase = Phase.SLEEPING if self.preparing else Phase.READY

    def facts(self, *, now, power=None, locked=None):
        if power is not None:
            self.power = power
        if locked is not None:
            self.locked = locked
        if self.quiet_resume and self.locked is False:
            self._cancel_background()
        if self.phase == Phase.LOCKING and (self.locked or self.greeter):
            self._blank(now)
        self._update_background(now)

    def reset_key(self, down):
        self.gesture = None
        self.ignore_release = down

    def wake(self, now):
        if self.lid_closed or not self.ready:
            return
        self._cancel_background()
        if self.preparing or self.phase in (Phase.SUSPENDING, Phase.SLEEPING):
            self.wake_requested = True
            return
        self._begin(Phase.ACTIVATING, now)
        # Grabbing KEY_POWER also hides the press from Mutter's idle monitor.
        # Project only an accepted wake into the desktop as KEY_WAKEUP before
        # setting DPMS. Neither a rejected wake nor a pending suspend does so.
        self._effect('activity')

    def off(self, now, *, suspend):
        if not self.ready or self.preparing:
            return
        self._cancel_background()
        self.suspend_after_blank = suspend
        self.wake_requested = False
        self._begin(Phase.LOCKING, now)
        if self.locked or self.greeter:
            self._blank(now)
        else:
            # Session.Lock is a request, not proof of a lock. LockedHint is
            # the barrier. Never call ScreenSaver.Lock on an existing shield.
            self._effect('lock')

    def _blank(self, now):
        self.phase = Phase.BLANKING
        self.deadline = now + self.OPERATION_TIMEOUT_MS
        self._effect('power', 3)

    def done(self, kind, token, *, now, value=None, error=None):
        if token != self.token:
            return
        expected = {'lock': Phase.LOCKING, 'activity': Phase.ACTIVATING, 'power':
                    Phase.WAKING if value == 0 else Phase.BLANKING,
                    'suspend': Phase.SUSPENDING, 'check-idle': Phase.CHECKING_IDLE}
        if self.phase != expected.get(kind):
            return
        if error:
            self._fail(f'{kind}: {error}')
        elif kind == 'check-idle':
            eligible = self._background_eligible()
            if eligible and type(value) is int and value >= self.BACKGROUND_GRACE_MS:
                self.background_observed = True
                if self.power != 3:
                    # GNOME may have enabled the panel on its own. Keep the
                    # activity watch, and wait for GNOME to blank it naturally.
                    self.phase = Phase.READY
                    self.deadline = None
                    return
                self._cancel_background()
                # The desktop already owns the locked, dark state. Preserve it;
                # a background resume never sends a lock, blank or wake command.
                self.token += 1
                self.phase = Phase.SUSPENDING
                self.deadline = None
                self._effect('suspend')
            else:
                self._cancel_background()
        elif kind == 'lock':
            # A successful logind Lock request can precede LockedHint.
            if self.locked or self.greeter:
                self._blank(now)
        elif kind == 'activity':
            self.phase = Phase.WAKING
            self._effect('power', 0)
        elif kind == 'power':
            self.power = value
            if value == 3 and self.suspend_after_blank:
                self.phase = Phase.SUSPENDING
                # Suspend has crossed the commit boundary. Only logind's
                # result or PrepareForSleep may release it, never a UI timer.
                self.deadline = None
                self._effect('suspend')
            else:
                self.phase = Phase.READY
                self.deadline = None
        # Suspend() acknowledgement is not its completion; wait for logind.

    def sleep(self, preparing, *, at, now, initial=False, down=False):
        if initial:
            self._cancel_background()
            self.preparing = preparing
            self.phase = Phase.SLEEPING if preparing else Phase.READY
            self.reset_key(down)
            return
        if preparing:
            self._cancel_background()
            self.saw_sleep = True
            if self.phase != Phase.SUSPENDING:
                self.wake_requested = False
            self.ignore_release |= self.gesture is not None
            self.gesture = None
            self.token += 1
            self.deadline = None
            self.preparing = True
            self.phase = Phase.SLEEPING
        else:
            self.preparing = False
            self.phase = Phase.READY
            self.deadline = None
            self.token += 1
            self.gesture = None
            self.ignore_release |= down
            self.resume_until = at + self.RESUME_GUARD_MS
            self.resume_wake_sent = self.wake_requested
            self.quiet_resume = self.saw_sleep and not self.wake_requested and not down
            self.saw_sleep = False
            if self.wake_requested:
                self.wake(now)
            self.wake_requested = False
            self._update_background(now)

    def lid(self, closed, *, now, initial=False):
        previous = self.lid_closed
        self.lid_closed = closed
        if previous == closed and not initial:
            return
        if closed:
            self.lid_blanked = True
            if self.gesture is not None:
                self.gesture = None
                self.ignore_release = True
            if self.ready and not self.preparing and self.phase != Phase.SUSPENDING:
                self.off(now, suspend=False)  # logind owns the lid's suspend.
        elif previous and self.lid_blanked:
            self.lid_blanked = False
            self.wake(now)

    def key(self, value, *, at, now):
        if value == 2 or not self.ready:
            return
        if value == 1:
            self._cancel_background()
        if self.preparing or self.phase in (Phase.SUSPENDING, Phase.SLEEPING):
            if value == 1:
                self.wake_requested = True
                self.ignore_release = True
            elif value == 0:
                self.ignore_release = False
            return
        if at <= self.resume_until:
            if not self.resume_wake_sent:
                self.resume_wake_sent = True
                self.wake(now)
            self.gesture = None
            self.ignore_release = value == 1
            return
        if value == 1:
            if self.ignore_release or self.gesture is not None or self.lid_closed:
                return
            wake_only = self.power != 0 or self.phase != Phase.READY
            self.gesture = Gesture(at, wake_only, self.short_action)
            if wake_only and self.phase != Phase.WAKING:
                self.wake(now)
        elif value == 0:
            if self.ignore_release:
                self.ignore_release = False
                return
            gesture, self.gesture = self.gesture, None
            if gesture and not gesture.long_fired:
                duration = at-gesture.pressed_at
                # Preserve long-press semantics even if the main loop was
                # delayed until both physical edges were already queued.
                if duration >= self.LONG_PRESS_MS:
                    if not self.greeter:
                        self._effect('menu')
                elif (not gesture.wake_only and duration >= self.MIN_PRESS_MS and
                      self.phase == Phase.READY and gesture.policy != 'nothing'):
                    self.off(now, suspend=gesture.policy == 'suspend')

    def tick(self, now):
        if self.deadline is not None and now >= self.deadline:
            self._fail(f'{self.phase.name.lower()} timed out')
        gesture = self.gesture
        if (gesture and not gesture.long_fired and not self.preparing and
                not self.lid_closed and now >= gesture.pressed_at+self.LONG_PRESS_MS):
            gesture.long_fired = True
            if not self.greeter:
                self._effect('menu')
        if self.background_deadline is not None and now >= self.background_deadline:
            self.background_deadline = None
            if self._background_eligible():
                self._begin(Phase.CHECKING_IDLE, now)
                self._effect('check-idle')

    @property
    def next_deadline(self):
        deadlines = [] if self.deadline is None else [self.deadline]
        if self.background_deadline is not None:
            deadlines.append(self.background_deadline)
        if (self.gesture is not None and not self.gesture.long_fired and
                not self.preparing and not self.lid_closed):
            deadlines.append(self.gesture.pressed_at+self.LONG_PRESS_MS)
        return min(deadlines) if deadlines else None
