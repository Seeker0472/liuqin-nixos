# 自动亮度（automatic-brightness）

环境光自动亮度的现状、实测与替换方案。面板磁贴（A）已落地：
`pkgs/gnome-autobrightness`（Quick Settings 开关，绑定 gnome-settings-daemon 的
`ambient-enabled`），demo 已接线。本文记录**为什么还需要 B**：gsd 的 claim
生命周期与相对映射，以及我们自己的曲线/守护进程要怎么接。

## 现状链路（源码核对 + 本机实测，2026-10-09，GNOME 50.4 / gsd 50.1）

```
SSC ALS → iio-sensor-proxy(LightLevel，仅在有人 claim 时轮询)
        → gsd-power(ambient-enabled 为真时 ClaimLight)
        → 低通 → org.gnome.Shell.Brightness.SetAutoBrightnessTarget
        → shell: target = clamp(abTarget + 滑块 - 0.5, 0, 1)   ← 滑块是偏置
        → mutter → logind SetBrightness → /sys/class/backlight/ktz8866-backlight
```

- 前置条件实测：`org.gnome.Shell.Brightness.HasBrightnessControl=true`；
  `ambient-enabled` 为 schema 默认 `true`（dconf 无用户值）。
- **开机后 gsd 不 claim**：屏幕点亮、已解锁、用户活跃时 `LightLevel` 仍冻结在
  10.9 分钟级不变。原因（gsd-power-manager.c 50.1）：
  - 首次 `iio_proxy_maybe_claim_light()` 发生在 gnome-shell 拥有
    `org.gnome.Shell.Brightness` 之前，`shell_brightness_has_control()` 读到
    false，claim 落空；
  - 该代理上只订阅 `BrightnessChanged`，`HasBrightnessControl` 之后变 true
    没有任何重新评估；
  - `iio_proxy_vanished_cb()` 只清代理、不清 `light_claimed`，所以
    `liuqin-sensor-proxy-refresh` 的每次 proxy 重启都会让 gsd 误以为仍持有 claim。
  - ⇒ 只有 `ambient-enabled` 变化、熄屏/亮屏周期、会话 active 变化、或
    SensorProxy 在 gsd 之后出现，才会重新 claim。实测：`gsettings set …
    ambient-enabled false` 再 `true`，数秒内读数开始动（10.9 → 8 → 7.1）。
    这也是面板磁贴**必须写键、而不仅仅是显示键值**的原因。
- **映射是相对的**（gsd）：claim 后第一个 >0 读数 $L_0$ 定标 $N=1.5L_0$，
  累加器初值 $100/1.5\approx66.7\%$，之后对 $\min(100, 100L/N)$ 做 $\alpha$
  由 0.1 Hz 带宽换算的指数平均，最多 10 Hz 下发。
  - 亮处开启后走进暗处 → 目标趋 0（面板几乎全黑）；
  - 暗处开启 → 基线 66.7%（过亮）；
  - 每次重新 claim（熄屏-亮屏/开关一次）都以当时读数重新定标，绝对值漂移；
  - shell 侧滑块只是偏置：`target = clamp(target + slider − 0.5)`。
- 传感器本身未标定：前后摄（TCS3701 / TSL2522）不区分、CCT/RGB 未实现、
  无融合（详见 `docs/PORTING-NOTES.md`，Sensors）。

## B：替换目标亮度来源（待实现）

目标：保留面板开关这一唯一 UI 与 shell 的钳位/动画语义，把"目标亮度从哪来"
换成我们的绝对曲线，并让 claim 生命周期归我们管。

### B1（推荐）：会话内策略服务

- 形态照抄 `pkgs/panel-posture.nix`：`systemd.user.services` + shell 脚本/小二进制，
  跑在会话里（polkit `subject.local` 已实测可 `ClaimLight`：
  `systemd-run --user --scope monitor-sensor --light` 20 s 拿到 7.8–29.3 lux）。
- 逻辑：
  1. 读我们的开关键（新增 `io.github.liuqin.power automatic-brightness`，schema
     与 power-keyd 同源；磁贴 `extension.js` 在同一提交里改绑它）；
  2. 开关为真：`ClaimLight` → 订阅/轮询 `LightLevel` → 绝对曲线
     （分段/对数 + 迟滞 + 平滑滤波，锚点待机上标定，例如
     0 lx→5 %、10 lx→20 %、100 lx→45 %、1000 lx→80 %、10000 lx→100 %）；
  3. `org.gnome.Shell.Brightness.SetAutoBrightnessTarget(曲线值)`（保持 shell 的
     钳位、动画和滑块偏置）；
  4. 熄屏/会话非 active：`ReleaseLight`（与 gsd 同样的功耗策略），恢复时重新
     claim 并按曲线重新求值（不回退到"相对定标"）。
- 与 gsd 的关系：**同一个键双 claim 会互相打架**，所以 B 落地时必须在
  `modules/liuqin/gnome.nix` 的 dconf 默认里把
  `org.gnome.settings-daemon.plugins.power ambient-enabled` 钉为 `false`，
  gsd 只当播放器（不 claim、不下发 target），开关语义整体移交给我们。
- 验收（必须在机上做）：
  - 遮光/开灯阶梯：0 → 30 → 300 → 3000 lx，亮度单调跟随且无可见抖动；
  - 连续 1 h 观察无振荡（迟滞/滤波参数）；
  - 熄屏 → 亮屏后 claim 自动恢复（对比 gsd 的 one-shot 缺陷）；
  - 维持 claim 的功耗代价（ALS 轮询只在屏幕点亮时保持）；
  - 与手动滑块的交互仍是"偏置"（`test`：滑块居中时曲线说了算）。

### B0（半修，可选）：只修 gsd 的 claim 生命周期

保留 gsd 的相对映射，在 `pkgs/sensor-proxy-refresh.nix` 完成一次 claim 验证后
再补一个 nudge：读当前 `ambient-enabled`，若为真则 `false` → `true`（原先无用户
值时以 `dconf reset` 还原）。收益是让 gsd 的循环在开机后真正可用、磁贴行为更
"即时"；代价是算法仍是相对曲线，且这是对 gsd 内部状态的绕行。
（若采纳 B1，本条作废——我们的服务取代该循环。）

### B2（不推荐）：自持亮度写路径

自己写 `/sys/class/backlight/ktz8866-backlight/brightness` 或经 logind
`SetBrightness`。放弃 shell 的钳位/动画，且必须自己与 mutter 滑块状态同步
（mutter 只在自身 `_sync()` 中回读背光），收益仅是绕开 `SetAutoBrightnessTarget`
的偏置语义。

## 参考

- gsd 50.1 `plugins/power/gsd-power-manager.c`：`iio_proxy_should_claim_light()`、
  `iio_proxy_claim_light()`、`iio_proxy_vanished_cb()`、
  `engine_settings_key_changed_cb()`、`iio_proxy_changed()`（$1.5L_0$ 定标、
  `GSD_AMBIENT_TIME_CONSTANT`）、`shell_brightness_has_control()` 与
  `shell_brightness_proxy` 的创建顺序。
- gnome-shell 50 `js/misc/brightnessManager.js`（`target = clamp(abTarget +
  scale.value − 0.5)`）、`js/ui/shellDBus.js`（`SetAutoBrightnessTarget`）、
  `js/ui/status/brightness.js`（滑块磁贴）。
- gnome-control-center 50 `panels/power/cc-power-panel.c`（同一 `ambient-enabled`
  开关的行可见性：`HasAmbientLight && HasBrightnessControl`）。
- 本仓库：`pkgs/gnome-autobrightness/`（磁贴）、`modules/liuqin/sensors.nix`
  （`claim-sensor` polkit 规则、`liuqin-sensor-proxy-refresh`）、
  `pkgs/panel-posture.nix`（会话内服务 + 手动 claim 的先例）、
  `docs/PORTING-NOTES.md`（Sensors 一节：claim 生命周期与未标定项）。
