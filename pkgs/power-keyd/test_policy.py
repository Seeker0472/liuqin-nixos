# SPDX-License-Identifier: MIT
"""User-visible sequences, including the races seen on the tablet."""
import unittest
from policy import PowerPolicy, Phase


class PolicyTests(unittest.TestCase):
    def setUp(self):
        self.effects = []
        self.auto_activity = True
        self.p = PowerPolicy(self.emit)
        self.p.available(True)
        self.p.facts(now=0, power=0, locked=True)

    def emit(self, effect):
        self.effects.append(effect)
        if effect.kind == 'activity' and self.auto_activity:
            self.p.done('activity', effect.token,
                        now=self.p.deadline-self.p.OPERATION_TIMEOUT_MS)

    def press(self, at=1000, duration=100):
        self.p.key(1, at=at, now=at)
        self.p.key(0, at=at+duration, now=at+duration)

    def finish(self, effect=None, now=1200, **kwargs):
        e = effect or self.effects[-1]
        self.p.done(e.kind, e.token, now=now, value=e.value, **kwargs)

    def commands(self):
        return [(e.kind, e.value) for e in self.effects if e.kind != 'activity']

    def test_wake_activity_ack_is_required_before_dpms(self):
        self.auto_activity = False
        self.p.facts(now=0, power=3)
        self.press()
        activity = self.effects[-1]
        self.assertEqual(activity.kind, 'activity')
        self.assertEqual(self.commands(), [])
        self.finish(activity)
        self.assertEqual(self.commands(), [('power', 0)])

    def test_lid_cancelled_wake_does_not_light_on_late_activity_ack(self):
        self.auto_activity = False
        self.p.facts(now=0, power=3)
        self.press()
        activity = self.effects[-1]
        self.p.lid(True, now=1150)
        self.finish(activity)
        self.assertEqual(self.commands(), [('power', 3)])

    def test_lit_locked_button_blanks_without_relocking(self):
        self.press()
        self.assertEqual(self.commands(), [('power', 3)])
        self.finish()
        self.assertEqual(self.commands(), [('power', 3), ('suspend', None)])

    def test_unlocked_waits_for_locked_hint_not_method_ack(self):
        self.p.facts(now=0, locked=False)
        self.press()
        self.finish()
        self.assertEqual(self.commands(), [('lock', None)])
        self.p.facts(now=1200, locked=True)
        self.assertEqual(self.commands()[-1], ('power', 3))

    def test_hint_can_arrive_before_lock_method_reply(self):
        self.p.facts(now=0, locked=False)
        self.press()
        request = self.effects[-1]
        self.p.facts(now=1200, locked=True)
        self.finish(request)
        self.assertEqual(self.commands(), [('lock', None), ('power', 3)])

    def test_black_button_wakes_on_press_and_release_is_consumed(self):
        self.p.facts(now=0, power=3)
        self.p.key(1, at=1000, now=1000)
        self.assertEqual(self.commands(), [('power', 0)])
        self.finish()
        self.p.key(0, at=1200, now=1200)
        self.assertEqual(self.commands(), [('power', 0)])

    def test_cancelled_lock_does_not_suspend_on_late_completion(self):
        self.p.facts(now=0, locked=False)
        self.press()
        lock = self.effects[-1]
        self.press(1300)
        self.p.facts(now=1500, locked=True)
        self.finish(lock, now=1500)
        self.finish(now=1600)
        self.assertEqual(self.commands(), [('lock', None), ('power', 0)])

    def test_cancelled_blank_does_not_suspend_on_late_completion(self):
        self.press()
        blank = self.effects[-1]
        self.press(1300)
        self.finish(blank, now=1500)
        self.finish(now=1600)
        self.assertEqual(self.commands(), [('power', 3), ('power', 0)])

    def test_committed_suspend_defers_wake_until_resume(self):
        self.press()
        self.finish()
        self.press(1300)
        self.p.tick(10000)
        self.assertEqual(self.commands(), [('power', 3), ('suspend', None)])
        self.p.sleep(True, at=1500, now=1500)
        self.p.sleep(False, at=2000, now=2000)
        self.assertEqual(self.commands()[-1], ('power', 0))
        self.finish()
        self.assertEqual(self.p.phase, Phase.READY)

    def test_physical_wake_edges_before_resume_are_consumed(self):
        self.p.sleep(True, at=1000, now=1000)
        self.press(1100)
        self.p.sleep(False, at=1201, now=1201)
        self.assertEqual(self.commands(), [('power', 0)])
        self.finish(now=1250)
        self.press(1800)
        self.assertEqual(self.commands()[-1], ('power', 3))

    def test_wake_press_after_resume_is_consumed_until_release(self):
        self.p.sleep(True, at=1000, now=1000)
        self.p.sleep(False, at=1200, now=1200)
        self.p.key(1, at=1205, now=1205)
        self.finish(now=1210)
        self.p.key(2, at=2000, now=2000)
        self.p.key(0, at=2100, now=2100)
        self.assertEqual(self.commands(), [('power', 0)])

    def test_rtc_resume_does_not_invent_a_power_press(self):
        self.p.sleep(True, at=1000, now=1000)
        self.p.sleep(False, at=1200, now=1200)
        self.assertEqual(self.effects, [])
        self.p.facts(now=1250, power=0)
        self.press(1800)
        self.assertEqual(self.commands(), [('power', 3)])

    def test_resume_guard_uses_event_time_not_delayed_processing_time(self):
        self.p.sleep(False, at=1200, now=5000)
        self.p.key(1, at=1205, now=5000)
        self.p.key(0, at=1300, now=5000)
        self.assertEqual(self.commands(), [('power', 0)])

    def test_bounce_repeats_and_unpaired_release_do_nothing(self):
        self.p.key(0, at=500, now=500)
        self.press(duration=20)
        self.p.key(2, at=1200, now=1200)
        self.assertEqual(self.effects, [])

    def test_handoff_held_key_is_consumed(self):
        self.p.reset_key(True)
        self.p.key(1, at=1000, now=1000)
        self.p.key(0, at=1100, now=1100)
        self.assertEqual(self.effects, [])
        self.press(1500)
        self.assertEqual(self.commands(), [('power', 3)])

    def test_long_press_once_and_never_short_action(self):
        self.p.key(1, at=1000, now=1000)
        self.p.tick(2500)
        self.p.tick(3000)
        self.p.key(0, at=3500, now=3500)
        self.assertEqual(self.commands(), [('menu', None)])

    def test_queued_long_release_keeps_physical_duration(self):
        self.press(duration=1600)
        self.assertEqual(self.commands(), [('menu', None)])

    def test_lost_desktop_cancels_pending_callbacks(self):
        self.press()
        blank = self.effects[-1]
        self.p.available(False)
        self.finish(blank)
        self.p.key(1, at=1500, now=1500)
        self.assertEqual(self.commands(), [('power', 3)])

    def test_timeout_recovers_without_late_suspend(self):
        self.p.facts(now=0, locked=False)
        self.press()
        lock = self.effects[-1]
        self.p.tick(7000)
        self.finish(lock, now=8000)
        self.assertEqual(self.p.phase, Phase.READY)
        self.assertFalse(any(e.kind == 'suspend' for e in self.effects))

    def test_failed_blank_does_not_suspend(self):
        self.press()
        self.finish(error='display gone')
        self.assertEqual(self.p.phase, Phase.READY)
        self.assertFalse(any(e.kind == 'suspend' for e in self.effects))

    def test_blank_policy_never_suspends(self):
        self.p.short_action = 'blank'
        self.press()
        self.finish()
        self.assertEqual(self.commands(), [('power', 3)])

    def test_nothing_policy_still_allows_waking_and_long_press(self):
        self.p.short_action = 'nothing'
        self.press()
        self.assertEqual(self.effects, [])
        self.p.facts(now=1200, power=3)
        self.press(1500)
        self.assertEqual(self.commands(), [('power', 0)])

    def test_action_change_during_hold_applies_to_next_gesture(self):
        self.p.key(1, at=1000, now=1000)
        self.p.short_action = 'nothing'
        self.p.key(0, at=1100, now=1100)
        self.assertEqual(self.commands(), [('power', 3)])

    def test_initial_open_lid_never_wakes_user_blanked_display(self):
        self.p.facts(now=0, power=3)
        self.p.lid(False, now=1000, initial=True)
        self.assertEqual(self.effects, [])

    def test_lid_close_blanks_but_logind_owns_suspend(self):
        self.p.lid(True, now=1000)
        self.finish()
        self.p.lid(True, now=1300)
        self.press(1500)
        self.assertEqual(self.commands(), [('power', 3)])
        self.p.lid(False, now=2000)
        self.assertEqual(self.commands()[-1], ('power', 0))

    def test_greeter_does_not_wait_for_a_user_lock_or_show_menu(self):
        self.p.greeter = True
        self.p.facts(now=0, locked=False)
        self.press()
        self.assertEqual(self.commands(), [('power', 3)])
        self.finish()
        self.p.sleep(True, at=1300, now=1300)
        self.p.sleep(False, at=1400, now=1400)
        self.p.key(1, at=2000, now=2000)
        self.p.tick(4000)
        self.assertFalse(any(e.kind == 'menu' for e in self.effects))
