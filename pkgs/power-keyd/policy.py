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

    def _effect(self, kind, value=None):
        self.emit(Effect(kind, self.token, value))

    def _begin(self, phase, now):
        self.token += 1
        self.phase = phase
        self.deadline = now + self.OPERATION_TIMEOUT_MS

    def _fail(self, message):
        self.token += 1
        self.phase = Phase.SLEEPING if self.preparing else Phase.READY
        self.deadline = None
        self._effect('error', message)

    def available(self, ready):
        self.ready = ready
        if not ready:
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
        if self.phase == Phase.LOCKING and (self.locked or self.greeter):
            self._blank(now)

    def reset_key(self, down):
        self.gesture = None
        self.ignore_release = down

    def wake(self, now):
        if self.lid_closed or not self.ready:
            return
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
                    'suspend': Phase.SUSPENDING}
        if self.phase != expected.get(kind):
            return
        if error:
            self._fail(f'{kind}: {error}')
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
            self.preparing = preparing
            self.phase = Phase.SLEEPING if preparing else Phase.READY
            self.reset_key(down)
            return
        if preparing:
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
            if self.wake_requested:
                self.wake(now)
            self.wake_requested = False

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

    @property
    def next_deadline(self):
        deadlines = [] if self.deadline is None else [self.deadline]
        if (self.gesture is not None and not self.gesture.long_fired and
                not self.preparing and not self.lid_closed):
            deadlines.append(self.gesture.pressed_at+self.LONG_PRESS_MS)
        return min(deadlines) if deadlines else None
