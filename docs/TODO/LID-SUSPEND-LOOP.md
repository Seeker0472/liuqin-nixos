# 合盖 suspend 循环与待机测量

本文保留旧循环的证据；下文“历史处置”描述曾采用的只熄屏方案。当前配置恢复了
logind 合盖 suspend（`HoldoffTimeoutSec=5s`），并关闭键盘的默认唤醒能力。
2026-11-14 起，锁定、熄屏和开盖恢复统一由 `pkgs/power-keyd/` 的活动会话
控制器处理，独立的 `liuqin-lid-policy` 用户服务不再启用。真实睡眠功耗与未知
唤醒源仍需实测，不能从 `PM: suspend entry (deep)` 单独推断 SoC 已进入最低功耗。

## 当前结论：2026-11-14，已停止测试

用户要求停止后，没有安排新的 suspend 或过夜测试。已验证的修正是 LPASS
MACRO/DCODEC 时钟生命周期：上游改造作为 0024–0026 纳入补丁系列，修正版中
ADSP 能累计休眠。**约八分钟提前恢复仍未解决，整机待机续航尚未验收。**

| 已记录窗口 | 实际睡眠 | 余量下降 | 窗口估算功率 | 条件 |
| --- | --- | --- | --- | --- |
| 原内核通知追踪 | 477.930 s | 28000 uAh | 0.806 W | 55%，GDM |
| LPASS 正式回移 | 476.253 s | 20000 uAh | 0.620 W | 81%，用户图形会话 |
| LPASS + 屏幕供电候选 C5 | 478.788 s | 13000 uAh | 0.377 W | 56%，GDM；该候选首次出图失败 |

这些是包含准备/恢复的单次窗口估算，电量、会话和计量分辨率限制了比较，
不能从表格推导确定的节电比例或过夜续航。C5 的 0.377 W 不是正常回退版的
验收结果，也不证明新屏幕驱动已经可交付。

恢复首批 IPCC/GLINK 消息与 `NOTIF_BAT_STATUS` 紧邻的现象在修正后仍存在。
尚未区分真正触发硬件唤醒的消息和恢复时立即处理的排队消息；没有屏蔽共享
IPCC，也没有发送未验证的固件屏幕状态属性。GNOME 电池空闲自动 suspend 的
现有关闭偏好未改，非交互恢复后长期清醒的策略问题仍待处理。

下一次默认启动已安装 LPASS 修正版与原有显示补救的正常配置；停止时仍运行
实验开关已关闭的 C9 内核，没有重启进入回退版。实际内核标识、清理结果和
两种配置的区别见 [显示接管记录的当前状态](DISPLAY-HANDOFF.md#当前状态2026-11-14已按用户要求停止测试)。
RTC alarm、私有 ftrace instance 和本轮 kprobe 均已清理；未测试扬声器。

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

此表记录旧启动中的 IRQ 编号；编号会跨启动变化。复测必须重新查询
`/proc/interrupts`，不能拿表中的编号直接判断当前设备。

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

## 2026-11-03 PM_DEBUG 实机测试

fast 代启动了 `CONFIG_PM_DEBUG=y` 内核，`/sys/power/pm_wakeup_irq` 可读。
在充电状态用 `rtcwake -m mem -s 45` 测试：

- 第一次（16:48:42–16:48:46）内核输出 `Wakeup pending. Abort CPU freeze`，
  `rtcwake: write error`，`suspend_stats` 为 success=0、fail=1。
  `/sys/power/pm_wakeup_irq` 为 **264**；该次启动的 `/proc/interrupts` 把
  264 映射为 `4-004c:wakeup`，即键盘 I2C 设备专用唤醒线，而不是旧表中的
  `nanosic-data`。测试残留的 RTC alarm 已清除。
- 临时把 `/sys/bus/i2c/devices/4-004c/power/wakeup` 设为 `disabled` 后重试：
  16:54:05–16:54:39 完成一次 deep suspend/resume，success=1、fail=0；
  `pm_wakeup_irq` 返回 `No data available`。实测约 35 s，短于设定的 45 s，
  因此不能据此断定由 RTC 唤醒，其他提前唤醒源也未排除。随后已恢复
  `wakeup=enabled` 并清除 RTC alarm；系统保持 `running`。

这证明键盘专用唤醒线至少能阻止本次入睡，但**不能**推断 2026-10-07
所有短睡眠均由它造成，更不能单凭这两次测试量化整晚耗电。

## 历史处置：只熄屏

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

当前配置已恢复合盖 suspend；下列检查仍用于确认唤醒来源和实际功耗：

1. `pkgs/kernel/config.nix` 已打开 `CONFIG_PM_DEBUG`；fast 的最终
   `.config` 为 `CONFIG_PM_DEBUG=y`、`CONFIG_PM_SLEEP_DEBUG=y`，且实机
   `/sys/power/pm_wakeup_irq` 已捕获一次键盘 wake IRQ。后续复测每次按当次
   `/proc/interrupts` 映射 IRQ；
2. 或在 suspend 前后比较 `/proc/interrupts` 和
   `/sys/kernel/debug/wakeup_sources`；
3. 分别在纯电池、拆掉 folio 的条件下对照，区分充电栈、键盘 MCU 与板载
   hall/PMIC；
4. 同时记录真正睡眠时长与 APSS、ADSP、CX/AOSS、DDR 低功耗计数，
   区分频繁唤醒和未进入平台最低功耗；调节 logind holdoff 不能替代这些测量。

## 2026-11-14 受控 RTC 短测

纯电池、键盘 wakeup disabled、`mem_sleep=s2idle [deep]`，独立 systemd 单元在
本地保存电池、SMEM/debugfs 统计、私有 ftrace 与日志；测试期间不进行 SSH 轮询。
仅抑制 lid/idle 动作，保留系统正常的 sleep delay inhibitors。

- 设置 RTC 60 秒；实际睡眠 60.228 秒，准备/恢复清醒时间 3.649 秒。
- success +1、fail +0；唤醒 IRQ 22 映射本次启动的 `pm8xxx_rtc_alarm`。
- APSS 累计睡眠增加 1156322875 ticks（19.2 MHz，约 60.225 秒）。
- ADSP `Count=17`、累计 9930221 ticks，前后均未增加；PCM 均为 closed。
- AOSD/CXSD/DDR 低功耗记录均为零，DDR 频率统计也没有变化。运行 DT 存在
  `qcom,qmp`；不能把这组不更新的 DDR 统计单独视为可靠的功耗测量。
- 余量计数前后均为 4928000 uAh，不能用这个短窗口得出零功耗。
- RTC alarm 与私有 ftrace instance 在测试后已清理。

## 2026-11-14 长测与 LPASS 实验

原内核设定 RTC 1800 秒，实际只睡 478.710 秒，准备/恢复 2.838 秒，success +1、
fail +0；余量减少 30000 uAh，按两端平均电压估算整个窗口约 0.901 W。
固件百分比 66% 前后未变化。没有电源键动作，RTC IRQ 也未增加；
`pm_wakeup_irq` 为 ENODATA。ftrace 在恢复后依次记录 IPCC、GLINK、
`qcom-battmgr-bat` wakeup-source 激活。该次 GLINK IRQ 213 的 hwirq 为
196608，即 IPCC client 3（LPASS），signal 0；跨启动必须重新查映射。

原内核的 RX/TX/VA 与 LPI 均显示 runtime suspended，但 MACRO/DCODEC 两个
硬件投票各持有 3 个引用。代码在 probe 申请这些投票，仅 remove 释放，
runtime_suspend 只管理其余时钟。这个生命周期缺陷与实机状态相符；它对
整机耗电的贡献尚不能只由引用计数定量推断。

临时对照内核回移了正式上游的宏时钟改造，包括 fsgen/SoundWire 的运行时 PM
引用。一次 60.755 秒 RTC 短测成功，ADSP 开始累计休眠，但 CX/AOSS 仍为零；
后续设定 600 秒的测试只睡了 0.481 秒，恢复首批中断仍是 LPASS GLINK
（新启动为 IRQ 206，同一 hwirq 196608）。这次不能计算可靠功耗，也不能视为
续航修复通过。对照跨重启且活动会话从用户变成 GDM，不能忽略该条件变化。

恢复原内核后，另一次 GDM suspend 在 RTC 闹钟已清除的情况下，也从
01:54:41 睡到 02:02:41，约 480 秒后恢复。这个间隔值得与固件通知对齐，
但还不能证明 GLINK 包就是导致唤醒的消息。

这组早期临时对照当时未纳入正式补丁系列；后续正式回移见下文。实验文件留在本机
`/tmp/hippogriff-fast-telemetry/lpass-experiment/`，供后续隔离通知、音频资源与
电源域时序使用。相关上游为
[TX/RX 合并](https://github.com/torvalds/linux/commit/a5ee3180a2a7)、
[VA](https://github.com/torvalds/linux/commit/eb667d0fbdd38d5a800b9e7aafc9a6c14530b9bf)、
[WSA](https://github.com/torvalds/linux/commit/cd054a6e272caa97ab808ef6f5588749a1429108)。

下一步应针对 LPASS 来包标识和 PMIC 通知的 suspend 策略测量，区分电池通知
唤醒与恢复时才处理的排队消息。不能仅禁用共享 IPCC 中断：它还承载电源、
充电和其他 ADSP 通道。用户当前关闭了 GNOME 电池空闲自动 suspend，非交互
唤醒后可能长时间只熄屏；这项现有偏好本次未改。

### 原内核上的消息追踪复测

电源键重构的最终 Fast 配置冷启动后，再设 RTC 600 秒，以独立 ftrace instance
和两个临时 kprobe 记录 PMIC 分发及 battmgr 回调的消息头。实际睡眠 477.930 秒，
窗口 487.030 秒，准备/恢复 9.100 秒，success +1、fail +0，消耗 28000 uAh，
按窗口和两端电压估算 0.806 W。固件百分比 55% 未变化，RTC 与 PMIC 电源键
IRQ 增量均为零。APSS 累计休眠增加约 477.9 秒，ADSP 的 Count/Duration 未变，
CX/AOSS/DDR 深层统计仍为零；不能把 APSS 睡眠等同于整个 SoC 进入最低功耗。

恢复时序在 `syscore_resume` 后、其他 CPU 上线前为：IPCC IRQ 13 → LPASS
GLINK IRQ 205（hwirq 196608）→ PMIC `owner=32778 type=2 opcode=7 len=16`
→ payload `0x80` → `qcom-battmgr-bat` wakeup-source 激活。
这已识别为 `NOTIF_BAT_STATUS`，而不是普通属性查询回复。首条通知与最早恢复
中断紧邻，比仅观察恢复后的 wakeup-source 更直接；仍需对照实验排除同时排队的
其他 LPASS 消息，不能由这条轨迹独断硬件最初的唤醒原因。

同机原厂 `liuqin-t-oss` 的 `qti_battery_charger.c` 在通知后调用
`pm_wakeup_dev_event(..., 50, true)`；其面板 notifier 还通过
`XM_PROP_FB_BLANK_STATE` 上报屏幕状态（受 `support_soc_update` 条件控制）。
当前移植没有后者，这是一条需要核对原厂 DT 和 OS2 固件协议的候选路径，
尚未发送未验证的属性写入。Android 的
[SystemSuspend](https://source.android.com/docs/core/power/systemsuspend)
会循环等待 wake lock 释放后再次 suspend；GNOME/logind 的空闲策略需要单独
处理非交互恢复，不能直接假设具有相同行为，也不能盲目恢复后立即再睡。

记录位于平板 `/var/tmp/liuqin-pmic-long-2-20261114/`，本机
`/tmp/hippogriff-fast-telemetry/liuqin-pmic-long-2-20261114/`。
该轮 RTC 闹钟、ftrace instance 和临时 kprobe 均已清除，当时未部署额外内核补丁。

### LPASS 正式回移后的复测（2026-11-14 午间）

将上述上游 WSA、VA、TX/RX 改造作为 0024–0026 纳入补丁系列，保留其
fsgen/SoundWire 的运行时引用、100 ms autosuspend 和失败清理。最终配置确认
`CONFIG_PM_CLK=y`，RX/TX/VA 均为 built-in、WSA 为模块，未通过关闭音频驱动
规避投票问题。按用户要求，不进行扬声器功能验收。

纯电池、用户图形会话下设 RTC 600 秒；实际睡眠 476.253 秒，准备/恢复
4.032 秒，success +1、fail +0。余量减少 20000 uAh，窗口估算约 0.620 W，
固件百分比 81% 不变。APSS 休眠增加约 476.250 秒；ADSP 休眠增加
477.966 秒、Count +44，证明这版允许 ADSP 在本次待机中休眠。
CX/AOSS/DDR 深层统计仍未增加。旧版 0.806 W 的测量处于不同电量和会话条件，
两数不能直接当作补丁节电比例。

提前唤醒仍存在：本次恢复最早的 IPCC IRQ 13 后紧跟 GLINK IRQ 203，仍收到
`owner=32778 type=2 opcode=7 payload=0x80 len=16` 的电池状态通知。
这与原内核复测一致；LPASS 时钟生命周期修正没有消除约八分钟的恢复。
仍需区分真正触发硬件唤醒的消息和恢复时立即处理的排队消息。

记录在平板 `/var/tmp/liuqin-lpass-controlled-20261114/`，本机
`/tmp/liuqin-power-display-review-20261114/liuqin-lpass-controlled-20261114/`。

### LPASS 与 panel 供电生命周期候选 C5 的复测

2026-11-14 午后，C5 `gfrdpdip64zn9ar1y5k7a8cysk6vax23` 在纯电池、
GDM 图形界面恢复后进行单次 600 秒 RTC 测试。没有通过网络轮询睡眠中的平板。
实际睡眠 478.788 秒，窗口 482.739 秒，清醒 3.950 秒；success +1、fail +0。
余量减少 13000 uAh，窗口均压 3.886 V，估算约 0.377 W；电量 56% → 56%。
前轮 LPASS-only 约 0.620 W 发生在 81% 电量、用户会话；本轮初始会话和电量不同，
单次短测及电量计分辨率也限制比较，不能据此认定确定的节省比例。

APSS 累计睡眠增加 478.786 秒，ADSP 增加 481.176 秒（count +132），
SLPI/CDSP 的睡眠时间同样覆盖窗口；CX/AOSS/DDR 的对应计数仍没有变化。
恢复初始轨迹依然为 IPCC IRQ 13 → GLINK IRQ 213 → PMIC 电池通知
（owner 32778、type 2、opcode 7、word 0x80、len 16）→ battmgr wakeup source。
这与前轮约八分钟提前醒的时序相符，仍须区分最初硬件唤醒原因与恢复后消息。
轨迹记录了恢复后的五路 panel regulator enable；没有记录到它们的 disable，
不能单凭这份轨迹断言睡眠前实际关闭动作发生于何时。

本轮 RTC 闹钟、私有 trace instance 及 kprobe 均已清理。未测试扬声器。
原始数据在平板 `/var/tmp/liuqin-display-c5-suspend-20261114/`，本机任务目录
同名目录及 `display-c5-suspend.tar`。

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
  `pkgs/power-keyd/policy.py`（当前锁屏/DPMS 状态机）以及
  `modules/liuqin/gnome.nix`（logind 与 root broker 接线）；旧
  `pkgs/lid-policy/main.py` 保留为兼容包，已不运行独立 user service。
