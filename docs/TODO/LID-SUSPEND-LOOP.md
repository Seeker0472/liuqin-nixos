# 盒盖 suspend 循环（lid-suspend-loop）

合盖后每 ~28 s 一轮 suspend/resume 的机理、证据与处置。
循环的**驱动者已定位**（静态核对 systemd v261.2 源码 + 本机运行时属性，2026-10-07 晚）；
**唤醒源尚未定位**，需要一次在机测量（见「下一步测量」）。配置侧的锚点是
`modules/liuqin/gnome.nix` 的 `FIXME(lid-suspend-loop)`。

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

## 下一步测量

1. `pkgs/kernel/config.nix` 打开 `CONFIG_PM_DEBUG`（`CONFIG_PM_SLEEP_DEBUG` 是
   `def_bool y depends on PM_DEBUG && PM_SLEEP`，本机现为未设置）→ 解锁
   `/sys/power/pm_wakeup_irq`（上一次唤醒的 IRQ 号）与 `pm_debug_messages`。
   合盖跑一轮后 `cat /sys/power/pm_wakeup_irq`，按上表映射设备。
2. 不重编内核的替代：合盖前后各存一份
   `grep -E "Hall|nanosic|4-004c|glink|mhi|fingerprint|temp-alarm|rtc" /proc/interrupts`，
   睡眠期间只有唤醒 IRQ 的计数会增长；root 下还可读
   `/sys/kernel/debug/wakeup_sources`（`CONFIG_DEBUG_FS=y`，debugfs 已挂）的
   `active_count`/`event_count` 增量。
3. 对照实验：**拔掉调试线（纯电池）**、**拆掉 folio 键盘**，各自再合盖一次 ——
   区分"线缆/充电栈"、"键盘 MCU"、"板载 hall/PMIC"。
4. 机理复核：`systemctl service-log-level systemd-logind debug` 后合盖，logind 应持续打印
   `Ignoring lid switch request, system startup or resume too close.`（holdoff 正在拦
   `button_recheck`）。

## 候选修复（均未实施）

- **A. 立刻消掉循环**（推荐，符合本仓库"power key 归 `liuqin-power-keyd`"的设计）：
  `services.logind.settings.Login.HandleLidSwitch = "ignore"`；合盖语义改为"锁屏 + 息屏"，
  复用 `liuqin-power-keyd` 现有的 blank 动作（`loginctl lock-sessions` +
  `org.gnome.ScreenSaver.SetActive true` +
  `org.gnome.Mutter.DisplayConfig PowerSaveMode = 3`，见
  `pkgs/power-keyd/liuqin-power-key-action.sh`）——需要把 lid switch 接进该 daemon（现在只
  按名字打开 `pmic_pwrkey` 设备，要再加 `gpio-keys` 的 `EV_SW`/`SW_LID`）。
  **注意**：`HandleLidSwitch=ignore` 之后没有任何东西会息屏（用户库 `idle-delay=0`、
  `sleep-inactive-*='nothing'`），必须显式 DPMS off；代价是合盖不入睡，待机功耗高于 suspend。
- **B. 根因**：按测量结果处理唤醒源（`power/wakeup` 的 udev 规则 / 驱动层按 lid 状态屏蔽 /
  固件侧）。注意"合盖期间屏蔽 hall 唤醒"会同时牺牲"开盖唤醒屏幕"这个体验，取舍要先定。
- **C. 若必须保留"合盖即 suspend"**：由系统级服务持有 `handle-lid-switch` 的 **block**
  inhibitor（`systemd-inhibit --what=handle-lid-switch --mode=block sleep infinity`，
  可用 `BindsTo=sys-subsystem-net-devices-usb0.device` 绑调试线）。已核对
  `src/login/logind-inhibit.c`：`manager_handle_action()` 对 `INHIBIT_HANDLE_LID_SWITCH`
  的抑制器检查是无条件的（`LidSwitchIgnoreInhibited=` 只作用于 sleep 抑制器检查），且无
  session 的 PID 视为"全局活跃"（`pidref_is_active_session()` 返回 1）⇒ root/系统抑制器
  有效。GNOME 自己用的就是这个机制（gsd-power `sync_lid_inhibitor()`，
  `LID_CLOSE_SAFETY_TIMEOUT = 8 s`）。
- **无效做法**：调大 `HoldoffTimeoutSec`（只把周期拉长）；依赖
  `HandleLidSwitchExternalPower`/`HandleLidSwitchDocked`（本机不生效，见机理第 6 条）；
  屏蔽"USB 唤醒"（没有启用的 USB 唤醒源）；指望 `LidSwitchIgnoreInhibited`（不作用于 lid
  抑制器）。

## 参考

- systemd v261.2：`src/login/logind-button.c`（`button_lid_switch_handle_action()`、
  `button_recheck()`、`button_install_check_event_source()`）、`src/login/logind-action.c`
  （`manager_handle_action()` 的 holdoff 早退 + `handle_action_execute()` 的
  `Suspending...`）、`src/login/logind-dbus.c`
  （`execute_shutdown_or_sleep()` 里的 `manager_set_lid_switch_ignore(…
  HoldoffTimeoutUSec)`、`method_do_shutdown_or_sleep()`）、`src/login/logind-inhibit.c`
  （`manager_is_inhibited()`、`pidref_is_active_session()`）。
- 本仓库：`pkgs/kernel/patches/0001-…patch`（两个 hall 都是 `wakeup-source`）、
  `0002-…patch`（hid-nanosic 的 status pin / `enable_irq_wake(data_irq)` /
  suspended 期间的 `pm_wakeup_event()`）、`pkgs/power-keyd/liuqin-power-key-action.sh`
  （blank 动作）、`modules/liuqin/gnome.nix`（`FIXME(lid-suspend-loop)`）。
