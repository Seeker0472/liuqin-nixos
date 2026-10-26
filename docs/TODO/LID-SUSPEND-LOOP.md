# 盒盖 suspend 循环（默认合盖策略已移除）

本文保留旧的“合盖即 suspend”循环证据和仍未完成的唤醒源定位。循环驱动者已经
定位；现在的默认策略不再经过该路径：logind 忽略 lid action，GNOME 会话立即锁屏/
熄屏，开盖亮出仍锁定的屏幕。实现位于 `modules/liuqin/gnome.nix`、
`pkgs/lid-policy/` 和 `pkgs/kernel/patches/0002-liuqin-input-hid-touchscreen.patch`。

## 现象与代价

- **实测** 2026-10-07：`Lid closed.` 11:17:04.350 → `Lid opened.` 11:41:09.735，窗口内
  15 次 suspend（`PM: suspend entry (deep)`），每次 resume 之后 27.3–27.8 s 发起下一次
  （14/14 个周期一致）。
- 睡眠本身被未知唤醒源截短到 2.9–162.4 s，抖动、无固定周期。
- 每轮代价：USB gadget 重新枚举（host 侧 `usb 1-2: new high-speed USB device`）、
  ath11k 重下固件（`mhi0: Requested to power ON` + `chip_id`/`fw_version`）、
  触摸控制器重刷固件（`nvt_update_firmware … #20`）、NetworkManager 重连
  （`DEAUTH_LEAVING`）、蓝牙控制器 resume。
- 它同时**掩盖**了真正的问题：有设备每几秒到几分钟唤醒 SoC 一次 —— 电池下同样存在，
  只是看不到循环。

| `Suspending...` | 睡眠 | resume → 下次请求 |
| --- | --- | --- |
| 11:17:04.369 | 23.0 s | 27.34 s |
| 11:17:56.163 | 22.2 s | 27.64 s |
| 11:18:46.644 | 102.3 s | 27.57 s |
| 11:20:57.146 | 122.4 s | 27.54 s |
| 11:23:27.706 | 150.7 s | 27.58 s |
| 11:26:26.664 | 84.1 s | 27.55 s |
| 11:28:18.893 | 97.2 s | 27.71 s |
| 11:30:24.421 | 162.4 s | 27.78 s |
| 11:33:35.175 | 46.9 s | 27.82 s |
| 11:34:50.502 | 57.8 s | 27.61 s |
| 11:36:16.429 | 56.5 s | 27.61 s |
| 11:37:41.187 | 47.0 s | 27.59 s |
| 11:38:56.417 | 6.9 s | 27.59 s |
| 11:39:31.522 | 2.9 s | 27.73 s |
| 11:40:02.762 | 40.7 s | （11:41:09 开盖） |

## 循环机理（已核对源码 + 本机值）

1. **lid 策略**：`HandleLidSwitch` 未配置 → logind 默认 `suspend`。本机运行时属性实测
   `HandleLidSwitch="suspend"`、`HandleLidSwitchDocked="ignore"`、
   `HandleLidSwitchExternalPower=""`。合盖 = 立刻 suspend（`Lid closed.` → `Suspending...`
   相隔 19 ms）。
2. **重复请求者是 logind 自己**：合盖期间 logind 装了 `sd_event_add_post()` 的
   `button_recheck()`（`src/login/logind-button.c`，优先级 `SD_EVENT_PRIORITY_IDLE+1`），
   事件循环每轮空闲都重新执行一次 lid 动作（`is_edge=false`）。期间没有任何新的
   `Lid closed.`/`Lid opened.` 事件。
3. **节流**：`lid_switch_ignore_event_source`。它在**每次 logind 真正发起睡眠时**被重置为
   `now(CLOCK_MONOTONIC) + HoldoffTimeoutUSec`（`src/login/logind-dbus.c:
   execute_shutdown_or_sleep()`）；本机 `HoldoffTimeoutUSec=30000000`（30 s）。
   CLOCK_MONOTONIC 在 suspend 期间冻结 ⇒ 唤醒后的有效等待 ≈ 30 s − 发起请求到时钟冻结前
   消耗的清醒时间（~2.4 s）≈ 27.6 s，与表中 27.3–27.8 s 吻合。
4. **`Suspending...` 的归属**：它是 `src/login/logind-action.c: handle_action_execute()`
   的 message_table 日志，**只有内部动作路径**（lid / power key / idle）会打印；
   D-Bus 的 `Suspend()` 走 `method_do_shutdown_or_sleep()` →
   `bus_manager_shutdown_or_sleep_now_or_later()`，不打印这一行。
   ⇒ 不存在"未识别的 D-Bus 请求者"；PORTING-NOTES 2026-10-07 早先版本里"请求来自 D-Bus、
   请求者未识别"的判断是错的，`liuqin-power-keyd` 无日志也与此一致。
5. **唤醒侧不可能是 USB**：host 每轮看到的是 `USB disconnect` → 重新枚举（设备已从总线摘下），
   总线不可能产生 resume 信令；平板内核里 dwc3/USB/tty/smp2p/PCIe root 的
   `power/wakeup` 全部 `disabled`。⇒「在有线时忽略 USB 唤醒」是空操作。
6. **外接供电/扩展坞分支为何不生效**：本机 `qcom-battmgr-usb/online=0`、
   `ucsi-source-psy-…/online=0`、电池 `Discharging` ⇒ logind 的
   `manager_is_on_external_power()` 为假；且 `HandleLidSwitchExternalPower` 未配置
   （`""`）⇒ `button_lid_switch_handle_action()` 直接落到 `HandleLidSwitch`；
   无外接显示器 ⇒ `HandleLidSwitchDocked` 也不适用。所以靠这两个选项在插调试线时
   改写行为是行不通的。

## 唤醒源盘点（本机 sysfs；只有 enabled 的才可能唤醒）

| 设备 | IRQ | 备注 |
| --- | --- | --- |
| Hall Lid（TLMM 10，gpio-keys） | 255 | 启用；**已排除**，见下 |
| Hall Tablet Mode（TLMM 23，gpio-keys） | 256 | 启用；静默候选 |
| Volume Up（spmi-gpio 5，gpio-keys） | 257 | 启用；静默候选 |
| `liuqin-keyboard` `nanosic-data`（TLMM 50） | 264 | 启用；驱动 suspend 时自己 `enable_irq_wake` |
| `liuqin-keyboard` 专用唤醒线（TLMM 46） | 265 | 启用；I2C core 认领的 dedicated wake IRQ |
| pmic_glink 电源/UCSI（battmgr-usb/-bat/-wls、ucsi-source-psy） | glink-smem | 启用；ADSP 侧上报 |
| fingerprint（TLMM 40） | 258 | 启用 |
| rtc0 / alarmtimer | 22 | 启用，但 `wakealarm` 为空 → **排除** |
| c263000/c265000.thermal-sensor（TSENS）、3×remoteproc、mhi0 | — | 启用；可能性低 |

已排除的依据：

- **Hall Lid**：gpio-keys 对 EV_SW 走 `gpio_keys_gpio_isr()` /
  `gpio_keys_gpio_report_event()`（`drivers/input/keyboard/gpio_keys.c`），去抖后**每次都上报
  当前电平、不去重**；logind 对每个 `SW_LID` 事件都会打印 `Lid closed.`/`Lid opened.`。
  循环窗口内只有首尾两行 ⇒ 它没有触发过。
- **RTC**：`/sys/class/rtc/rtc0/wakealarm` 为空。
- **USB**：见机理第 5 条。

余下候选都是"静默"的（日志里天然不留痕）：键盘 folio 的 status pin / data IRQ、
SW_TABLET_MODE、Volume Up、pmic_glink 的 ADSP 侧电源/UCSI 栈。
其中键盘一侧是**完全 arm 好的**：DTS 里 `interrupt-names = "data","wakeup"`、
`wakeup-source`，驱动 `nanosic_suspend()` 还会 `enable_irq_wake(nano->data_irq)`，且
suspended 期间对到达的数据帧调 `pm_wakeup_event()`（`pkgs/kernel/patches/0002-…patch`）。

## 已采用的处置

`modules/liuqin/gnome.nix` 明确把 `HandleLidSwitch`、
`HandleLidSwitchExternalPower`、`HandleLidSwitchDocked` 全部设为 `ignore`，避免
供电或扩展坞识别状态变化后重新落入 suspend。图形会话中的
`liuqin-lid-policy` 直接读取 UPower 的 `LidIsClosed`：

1. 合盖调用 `org.gnome.ScreenSaver.Lock`，再把 Mutter `PowerSaveMode` 设为 `3`；
2. 开盖只把 `PowerSaveMode` 设为 `0`，不解锁；
3. 会话启动时若盖子本来就是关闭状态，也会应用同一动作；
4. 服务自己的 runtime marker 区分“由合盖熄屏”和“用户按电源键熄屏”，所以在普通
   开盖状态启动服务不会错误地点亮屏幕。

键盘驱动读取同一个 `SW_LID` 状态。合盖只把发给硬件的有效背光设为 `0`，
`led_classdev::brightness` 中的用户请求值不变；开盖、folio 重新出现或 resume 时
恢复该值。即使用户在合盖期间移动 Quick Settings 滑块，也不会把盖内键盘点亮。

该策略的明确代价是：合盖不进入系统 suspend，待机功耗高于 deep sleep。它解决的是
默认合盖行为和重复 suspend，不等于找到了旧循环里的未知唤醒源。

## 仍可进行的 suspend 唤醒源测量

这些测量只影响手动 suspend 或未来重新评估“合盖即 suspend”，不阻塞当前 lid 策略：

1. `pkgs/kernel/config.nix` 打开 `CONFIG_PM_DEBUG`，读取
   `/sys/power/pm_wakeup_irq` 并按上表映射设备；
2. 或在 suspend 前后比较 `/proc/interrupts` 和
   `/sys/kernel/debug/wakeup_sources`；
3. 分别在纯电池、拆掉 folio 的条件下对照，区分充电栈、键盘 MCU 与板载
   hall/PMIC；
4. 若未来恢复“合盖即 suspend”，必须先消除未知唤醒，再重新验证 logind holdoff，
   不能仅调大 `HoldoffTimeoutSec`。

## 参考

- systemd v261.2：`src/login/logind-button.c`（`button_lid_switch_handle_action()`、
  `button_recheck()`、`button_install_check_event_source()`）、`src/login/logind-action.c`
  （`manager_handle_action()` 的 holdoff 早退 + `handle_action_execute()` 的
  `Suspending...`）、`src/login/logind-dbus.c`
  （`execute_shutdown_or_sleep()` 里的 `manager_set_lid_switch_ignore(…
  HoldoffTimeoutUSec)`、`method_do_shutdown_or_sleep()`）、`src/login/logind-inhibit.c`
  （`manager_is_inhibited()`、`pidref_is_active_session()`）。
- 本仓库：`pkgs/kernel/patches/0001-…patch`（lid hall 的
  `wakeup-source`）、`0002-…patch`（hid-nanosic 的 status pin、
  `enable_irq_wake(data_irq)`、suspend 唤醒和合盖背光抑制）、
  `pkgs/lid-policy/main.py`（锁屏/DPMS 状态机）以及
  `modules/liuqin/gnome.nix`（logind 与 user service 接线）。
