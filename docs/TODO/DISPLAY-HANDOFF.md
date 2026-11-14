# liuqin 显示接管：调研记录与修复计划

后续系统调查见 [2026-11-14 ABL / U-Boot / Linux 显示交接报告](../research/DISPLAY-HANDOFF-2026-11-14.md)。
这次只分析固件、源码和既有记录，没有继续试屏。新报告补全了 ABL splash 分支条件、
实际 DisplayDxe 关闭序列和首次 modeset 之前的 PLL probe 写入，并收紧下文历史排除
结论的适用范围；首次黑屏仍未修复。

## 当前状态：2026-11-14，已按用户要求停止测试

**首次启动黑屏尚未修复。** C2–C9 未有候选通过无恢复操作的首次出图验收。
供电引用释放、背光寄存器写入、源码测试或构建成功，都不能替代首次画面验收。
用户要求停止后，没有继续部署新候选、重启或安排 suspend 测试。

### 停止时的运行与下次启动配置

停止前已发起的正常回退版 `deploy-rs --dry-activate` / `--boot` 均已完成；
`--boot` 只安装下次启动配置，**没有切换正在运行的内核，也没有随后重启**。
停止时的只读核对结果如下：

| 项目 | 状态 |
| --- | --- |
| 当前 boot ID | `7aae62ec-6c3f-4019-ba48-0e0bfb62b6d5` |
| 当前内核 | C9，`/nix/store/2i3636rgyyin0g02w32f7zada7rdwar5-linux-aarch64-unknown-linux-gnu-7.2.5/Image` |
| 当前 system | `/nix/store/6b4s8rl22hafab8wazn3bas15vyvi60m-nixos-system-Hippogriff-26.11.20261111.d4f25a3` |
| 当前图形界面 | 受控 OFF/ON 后 `display-manager` active，第二次触摸初始化成功；尚无最后一次恢复后的独立用户视觉确认 |
| 当前实验开关 | `trace_status=N`、`force_long=N`；本轮创建的 kprobe / trace instance 均为空，RTC alarm 为空 |
| 下次默认 profile | `/nix/store/fzjkxrcx8lf7wyi84jzg566m1bywy4g5-activatable-nixos-system-Hippogriff-26.11.20261111.d4f25a3` |
| 下次默认内核 | LPASS 修正版，`/nix/store/kbqp3z1cqqf94ha117mcwva6xz7azpj2-linux-aarch64-unknown-linux-gnu-7.2.5/Image` |

下次默认配置正常启动 GDM，保留原来的 1.5 秒显示 OFF/ON 补救；没有纯文字启动、
跳过触摸或诊断参数。回退版的直接亮屏不能当作新显示驱动已修复。
当前 C9 的 `/proc/cmdline` 仍含诊断参数，表中的 N 是运行时关闭状态；若手动选择
旧 C9 启动项，实验参数会再次生效。后续工作应先核对实际运行内核和 live DT。

### 已获得的证据与边界

- 首次 DSI1 在 panel reset 后、初始化后和 Display On 后均没有读数据；受控
  OFF/ON 后分别返回 power `0x08`、`0x9a`、`0x9e`，触摸从首次 ReK 超时变为成功。
  首次 reset 后读取早于本次触摸固件下载，差异已出现在 panel/DSI 首次接管阶段；
  这仍不能独立区分真实供电、复位或链路发送状态。
- 背光使能及亮度寄存器在黑屏和重亮后相同。C8 的 FLAG=0 读取发生于重亮后，
  不能当成黑屏时的实际电压或电流测量。芯片输出配置码对应 ±5.8 V，DT 声明
  ±5.5 V 的不一致尚待核对，本轮没有改写电压。
- 主/从 PLL mux、PHY 入口状态、DSC 配置前 enable、DSI controller enable、
  INTF timing engine 的已采样项目没有发现支持先前特定猜测的差异；没有覆盖
  全部上电瞬态。PPS 只记录并比较了前 64 字节。
- 原厂长包对照已在 host 请求入口确认 194 条 `0x39`，payload 逐字节匹配原厂；
  用户仍确认全黑。不能再把这处编码差异单独当作修复。

### 工作区与取证位置

正式补丁系列中的显示代码仍为 C5 候选：panel 拥有五路供电和复位，背光负责
LED 电流，使用原厂 burst 模式，恢复上游 host/PHY 与 PLL save/restore，并移除
全局定时 fbdev cycle。其关闭路径和错误处理有测试与真机证据，首次出图未通过，
**不应当作已验收的日常显示版本部署**。LPASS 0024–0026 已纳入系列并独立验证。
C3 的 probe 断电、C4 的 quiesce、C7 的 DTB 删除属性，以及 C6–C9 诊断读取、
追踪和长包开关，没有作为正式修复加入当前系列。本轮未创建提交。

原始日志在平板 `/var/tmp/liuqin-display-*-20261114/`；本机临时工作目录为
`/tmp/liuqin-power-display-review-20261114/`，包含候选 flake、构建/部署日志、
boot ID、寄存器快照和归档。关键结果已写入本文，不能假设本机 `/tmp` 长期保留。
通用追踪脚本 `run-display-probe.py` 写死了 C4 内核，不能不经身份核对用于其他候选。

后续若恢复调查，应先核对首条初始化命令之前两路 host 的准备顺序与实际
电源/复位/LP/HS 状态，不把最终寄存器相同等同于瞬态相同；不继续叠加未经
证据支持的复位或自动重试。待机数据及其比较限制另见
[LID-SUSPEND-LOOP.md](LID-SUSPEND-LOOP.md)。

## 2026-10-26 初始调研（历史）

日期：2026-10-26。设备：Xiaomi Pad 6 Pro（liuqin / SM8475）。
审查基线：`48a08b7de3d0b7991c494a74e5a6abcfc3062361`，内核为仓库锁定的 Linux 7.2.5。

用户报告：ABL → Linux 可以正常显示，ABL → U-Boot → Linux 的首次显示存在异常，
目前依靠 workaround 恢复。本文记录本轮源码调研，以及接下来应执行的诊断、实验和
修复步骤。它补充 [2026-10-23 的显示/相机审查](DISPLAY-CAMERA-REVIEW.md)，只讨论显示。

**初始调研的验证范围：当时完成了仓库代码、历史提交、锁定的内核源码和公开上游资料核对；
没有修改驱动，没有进行新的内核构建、刷写或真机实验。** 下文分别标明源码事实、
历史实测记录和待验证推断，不能把实验预期当成当前版本的验证结果。

**结论与目标**

保留 ABL → U-Boot → Linux 启动链和可见的 U-Boot 菜单。优先修复 Linux 从固件遗留
显示状态进入自身管理状态的首次初始化，使第一次 modeset 就能出图。当前 1.5 秒
DPMS OFF/ON 保留为已知可用的回退方案，待修复通过真机验收后撤销。

已有证据很强地指向显示接管缺陷，但尚不能确认具体失效的 panel、DSI、PHY、PLL、
DPU 或 DSC 操作。尤其不能把“PLL 恢复覆盖了 Linux 配置”直接当成已证实根因。

**主流实现应如何处理 bootloader 留下的显示**

Bootloader 可以把已经点亮的屏幕交给内核。原生显示驱动必须让软件状态与实际硬件
状态一致，通常有两条路线：

| 路线 | 内核的责任 | 本项目的选择 |
| --- | --- | --- |
| 停止、复位、重新初始化 | 清除遗留状态，按内核配置重新建立显示链路；允许短暂黑屏 | 当前优先目标 |
| 无缝接管 | 读取和接纳固件配置，建立对应的软件状态及资源引用，再切换 framebuffer | 长期可选，当前不作为修复前提 |

DRM 的软件状态初始化不等于硬件复位。`drm_mode_config_reset()` 等机制不能替驱动
自动关闭固件留下的活动链路。参见
[DRM atomic 状态初始化说明](https://docs.kernel.org/gpu/drm-kms-helpers.html#atomic-state-reset-and-initialization)。

上游 drm/msm 曾遇到 bootloader 保留显示、内核仅重新配置部分 DPU 而造成异常的
问题，采用了初始化时复位 MDSS 的方案；补丁说明把完整无缝接管列为更长期的工作。
参见 [MDSS reset 补丁](https://lkml.rescloud.iu.edu/2204.2/06017.html)。

`simple-framebuffer` 描述的是固件已建立的 framebuffer 和相关资源，并不实现
DPU、双 DSI、DSC 和面板的完整接管。保留固件 framebuffer 供 U-Boot 菜单使用，
本身不是错误。参见
[simple-framebuffer binding](https://raw.githubusercontent.com/torvalds/linux/master/Documentation/devicetree/bindings/display/simple-framebuffer.yaml)。

**两条启动路径的已知差异**

本轮读取了 Qualcomm 公布的
[`UpdateDeviceTree.c`](https://git.codelinaro.org/clo/la/abl/tianocore/edk2/-/blob/LA.VENDOR.1.0.r2-09400-WAIPIO.QSSI14.0/QcomModulePkg/Library/BootLib/UpdateDeviceTree.c)，
tag 为 `LA.VENDOR.1.0.r2-09400-WAIPIO.QSSI14.0`。其中 `UpdateSplashMemInfo()` 在
取得 splash 信息后查找 `/reserved-memory/splash_region`；找不到节点时调用
`DisableDisplay()`，后者通过 EFI display power protocol 请求关闭显示。
源码注释列出关闭显示电源、显示时钟和复位 TE/RST 引脚的效果。

这是公开源码中的行为，不能单凭它证明当前机器每次启动都成功执行了关闭；本机的
关联证据来自仓库已有实验记录，当前固件版本仍需复核。

| 路径 | ABL 检查的 DTB | 仓库设计及历史记录中的结果 |
| --- | --- | --- |
| ABL → Linux | Linux 保留区名为 `linux_splash` | ABL 找不到约定节点，执行关闭流程，再交给 Linux |
| ABL → U-Boot → Linux | U-Boot 保留区名为 `splash_region` | ABL 保留显示，U-Boot 菜单复用；进入 Linux 不再经过 ABL |

对应本地证据：

- [Linux 板级 DTS 补丁](../../pkgs/kernel/patches/0001-liuqin-board-dts-bindings.patch)：
  `linux_splash@b8000000` 及其 2026-09-28 实验注释。
- [U-Boot DTS](../../pkgs/u-boot/files/dts/upstream/src/arm64/qcom/sm8450-xiaomi-liuqin.dts)：
  `splash_region@b8000000` 和继承的 framebuffer。
- [U-Boot video 驱动](../../pkgs/u-boot/files/board/qualcomm/liuqin/video.c)：
  复用 `0xb8000000`、1800×2880、stride 7200 的 framebuffer，只绘制像素和维护缓存；
  没有完整的显示初始化或关闭回调。

合理推断是 U-Boot 路径暴露了 Linux 接管遗留显示状态的缺陷，尚无证据证明 U-Boot
主动把显示硬件配置坏了。修改最终交给 Linux 的 splash 节点名，不能让已经退出的
ABL 再执行一次 `DisableDisplay()`。

**现有 workaround 及其证据边界**

[显示补丁 0003](../../pkgs/kernel/patches/0003-liuqin-display-panel-msm.patch) 同时包含：

1. `msm_dsi_host_power_on()` 在写入 timing 前停止 controller 并执行软件 reset。
2. `dsi_pll_7nm_init()` 不再保存初始 PLL 状态，避免首次 enable 恢复该快照。
3. `msm_kms.c` 在 fbdev client 初始化后调度一次延迟 1.5 秒的 `fb_blank()` OFF/ON。

历史提交 `2f148f48d06cf761e1f4d4fd592c6b2345ebdf42` 和
[PORTING-NOTES](../PORTING-NOTES.md) 记录了 2026-10-07 的观察：

- 初期写入 ABL framebuffer 的日志可见，第一次 modeset 后画面消失。
- 提前停止 controller、取消初始 PLL 保存，两项处理仍不足以独立恢复显示。
- 一次早期 OFF/ON 可恢复图像；当时约在启动后 4.4 秒亮屏。
- 较晚的多次 fbdev blank/unblank 会受到 GDM 获取 DRM master 的影响。
- 当时的 `clk_ignore_unused` / `pd_ignore_unused`、背光和 runtime PM 检查没有支持
  相应猜测；这些结论属于当时实验，不代表排除了所有时钟或电源转换问题。

首次初始化时，Linux 的软件状态从关闭开始，但硬件可能保留固件配置。正常关闭
函数依赖软件状态，例如 `msm_dsi_host_power_off()` 在 `power_on == false` 时直接
返回。因此，在首次 enable 前调用普通关闭函数，不保证真正停止了遗留硬件。

第一次 modeset 后，Linux 已建立自身的运行状态；再 OFF/ON 会走实际的关闭、PLL
状态保存、链路停用和重新初始化路径。这能解释第二次启动为何不同，但不能单凭
恢复成功判定究竟是哪一步起作用，也不能证明 1.5 秒等待本身是必要条件。

该定时补救位于通用 `msm_kms.c`，依赖 fbdev 和 DRM master 的时间窗口，不适合作为
最终的硬件初始化设计。当前正常关闭流程也不等于整条显示链路物理断电，见下文。

**本轮进一步发现的排查重点**

以下内核检查基于 [构建定义](../../pkgs/kernel/default.nix) 指定的 Linux 7.2.5
源码包，而不是用在线 master 代替仓库基线。源码包可用
`nix eval --raw .#packages.x86_64-linux.kernel.src.outPath` 定位；上游内核文件路径
下文按源码树内路径书写。

**MDSS reset 已存在，须验证实际效果。**

- `drivers/gpu/drm/msm/msm_mdss.c` 的 `msm_mdss_init()` 已调用
  `msm_mdss_reset()`，assert 后等待 20 ms 再 deassert。
- `mdss_probe()` 随后才通过 `of_platform_populate()` 创建显示子设备。
- `arch/arm64/boot/dts/qcom/sm8450.dtsi` 已声明
  `resets = <&dispcc DISP_CC_MDSS_CORE_BCR>`。
- `drivers/clk/qcom/dispcc-sm8450.c` 把该 reset 映射到 DISPCC 的 `0x8000` 偏移。

所以“缺少 MDSS reset，补一个即可”不符合当前源码。需要核实最终运行 DT、reset
执行顺序、访问条件和复位覆盖范围。

还有一个诊断陷阱：`msm_mdss_reset()` 没有检查 assert/deassert 返回值，而
`drivers/clk/qcom/reset.c` 的 `qcom_reset_set_assert()` 又忽略 regmap 写入和读回
错误并返回 0。仅记录上层返回成功不足以证明硬件完成了复位。应记录底层操作错误、
BCR 的有效读回和关键显示状态的变化；BCR 位变化本身也不能证明所有子模块都已清理。
参见 [上游 reset 实现](https://raw.githubusercontent.com/torvalds/linux/master/drivers/clk/qcom/reset.c)。

**现有停止 controller 的位置晚于 PHY 和时钟操作。**

检查 `dsi/dsi_manager.c`、`dsi/phy/dsi_phy.c`、`dsi/dsi_host.c`，结合本地补丁，
首次启动的相关顺序为：

```text
dsi_mgr_bridge_power_on()
  → dsi_mgr_phy_enable()
      → 双 PHY reset
      → PHY enable / 按条件恢复 PLL
  → msm_dsi_host_power_on()
      → 设置并启用链路时钟
      → 本地补丁停止 DSI controller
      → 写入 timing、reset、启用 controller
```

如果异常发生在旧链路尚未停止时重置 PHY 或切换时钟，当前局部处理可能太晚。
这是待验证假设。不能简单把 MMIO 写入搬到更早的位置，因为访问及复位 controller
本身也有时钟、电源前提。

上游已特意让 bonded DSI 的两个 PHY 都在 PLL 时钟操作前 reset/enable；修复要
保持这种成对协调，不能只处理 DSI0。板级 DTS 还把 DSI1 的 byte/pixel 时钟父源
指向 DSI0 PHY，诊断时必须同时核对两边的父源和硬件配置。

**取消初始 PLL 保存还不能证明修复了时钟问题。**

`msm_dsi_phy_enable()` 的注释说明，PHY reset 会改变 PLL 寄存器，使 Common Clock
Framework（CCF）的缓存与硬件状态不一致；恢复状态正是为了解决这个问题。

本地补丁删除初始保存后，不能假定一次 `clk_set_rate()` 就会重写所有必要的
divider/mux。另一方面，PLL restore 之后仍有 host 的链路时钟配置，不能仅凭
restore 存在就推断最终输出一定保持 ABL 的频率。

应对比三层信息：请求值、CCF 记录值、硬件寄存器解码值，并记录实际执行了哪些
set-rate/set-parent 操作。PLL lock 和 `clk_summary` 单独都不足以证明输出正确。
正常 OFF/ON 中保存、恢复 Linux 自己的 PLL 状态也不能与固件首次接管混为一谈。

**当前 panel 关闭路径不等于完整断电或保持复位。**

板级 DTS 中 `display_panel_dvdd_buck`、`display_panel_dvdd_ldo`、
`backlight_gpio_vsp` 和 `backlight_gpio_vsn` 都带有 `regulator-always-on`。
普通 `regulator_bulk_disable()` 不能关闭这些受约束电源。`regulator-boot-on` 与
`regulator-always-on` 的含义不同，前者不禁止后续关闭。参见
[regulator binding](https://raw.githubusercontent.com/torvalds/linux/master/Documentation/devicetree/bindings/regulator/regulator.yaml)。

因此，旧记录中的“供电循环无效”需要找到当时具体补丁、运行 DT 和实际电源变化
才能作为排除依据；本轮没有找到足以确认该实验实现了完整物理断电的记录。

此外，当前 `GPIO_ACTIVE_HIGH` 配合 `pipa_reset()` 的 0→1→0→1 输出保留了已知
可用的物理波形，最后为高电平；`nt36532_unprepare()` 和错误清理同样写入 1，
没有把面板保持在与运行结束电平相反的复位状态。这里需审查生命周期语义，不能把
它直接宣布为黑屏根因。若规范化 GPIO 的逻辑极性，必须同步修改 DTS、初始化、
prepare、unprepare 和错误路径，保持正确的物理波形。参见
[GPIO descriptor 逻辑电平说明](https://docs.kernel.org/driver-api/gpio/consumer.html)。

NT36532 与触摸共享 TDDI，实际修改面板 reset 或电源顺序时，还需核对
[触摸驱动的 panel follower](../../pkgs/kernel/patches/0002-liuqin-input-hid-touchscreen.patch)
及其固件下载时序；目前没有证据认定触摸驱动是本次故障根因。

**接下来执行的工作：先建立可复现对照**

- [ ] 保存可启动的 U-Boot、系统 generation 和对应镜像标识作为回退。
- [ ] 固定同一内核、initramfs、固件版本、120 Hz 模式及相关启动参数。
- [ ] 在诊断版本关闭内核定时 DPMS 补救，保留明确可识别的开关状态。
- [ ] 暂不启动 GDM；若使用 installer，还要关闭
  [其中的 `liuqin-screen-refresh`](../../config/installer.nix)，避免自动重亮掩盖失败。
- [ ] 验证 USB 日志通道能在黑屏时获取完整启动记录。
- [ ] 保存输入镜像哈希、最终 Linux DT 和命令行，记录 ABL/U-Boot 的动态修改。

第一轮仍保留现有 controller-stop 和 no-initial-PLL-save 两项改动，仅去掉自动
补救以观察首次 modeset。之后再分别检验这两项改动的必要性，避免同时改变多个因素。

| 实验 | 启动路径与变化 | 目的 | 当前状态 |
| --- | --- | --- | --- |
| A | ABL → Linux，使用 `linux_splash` | ABL 关闭显示的正常基准 | 历史正常；当前诊断版本待测 |
| B | ABL → 普通 U-Boot → 同一 Linux，保留 ABL 显示 | 无自动补救的故障基准 | 历史异常；当前诊断版本待测 |
| C | U-Boot 自身 DTB 改掉 `splash_region` 名称，再自动启动同一 Linux | 保持 U-Boot 路径，但让 ABL 先关闭显示 | 待测 |
| D | ABL → Linux，把 Linux 保留区改回 `splash_region` | 不经过 U-Boot，但保留固件显示 | 历史有类似异常记录；当前版本待测 |

C 是没有继承画面的诊断版本，必须自动启动并可通过 USB 取证。它不能作为取消菜单
的最终方案。改变 splash 节点名称时保持内存保留范围，并核对其他打包和 DT 差异。

结果判读：A、C 正常而 B、D 异常，将强力支持“显示遗留状态触发缺陷”。如果 C 仍
失败，应继续排查 U-Boot 的其他 DT、时钟、内存布局和硬件状态影响；如果 D 正常，
也不能继续假设保留显示是唯一变量。

另加一组时间对照：在 B 首次失败后只等待、完全不 modeset，与经过相同等待时间后
受控执行 OFF/ON 比较，区分“经过一定时间就恢复”和“必须发生状态转换”。记录
实际提交结果，不把 `fb_blank()` 表面返回成功当成完整 DPMS 已执行。

**随后定位第一次与第二次初始化的差异**

对比 A 的首次成功、B 的首次失败、B 中受控 OFF/ON 后的成功三段轨迹。插桩放在
状态转换边界，避免只重复半秒间隔的大范围寄存器快照。

| 层次 | 记录内容 | 要回答的问题 |
| --- | --- | --- |
| MDSS / DISPCC | reset 获取、底层错误、BCR 读回、关键状态变化、子设备 probe 时间 | 复位是否实际发生，是否足够早、覆盖了什么 |
| DSI0/1 与 PHY0/1 | reset/enable/disable 顺序、PLL 保存恢复、父时钟、divider/mux、lane 和错误状态 | 双链路是否协调，硬件与 CCF 是否一致 |
| DPU / DSC | INTF、CTL、split、DSC 配置及 flush/start，帧计数、underrun、IOMMU fault | 是否实际产生并传递了有效帧 |
| Panel / backlight | reset 电平、电源是否改变、DCS/PPS 顺序和错误、背光状态 | 面板是否退出旧状态并接受新数据 |
| Touch follower | prepare/unprepare 回调、下载和复位时间 | 是否有共享 TDDI 状态干扰 |

寄存器读取必须满足对应电源和时钟的访问条件，避免为了取证唤醒设备而改变待观察
状态。尽量使用少量有时间戳的事件和受控快照；需要额外日志能力时仅在诊断配置
启用，不能假定当前构建已开启全部 dynamic-debug 调用点。

- [ ] 加入能区分首次 enable、首次 disable、第二次 enable 的事件标识。
- [ ] 检查 MDSS reset 的实际效果，不能只检查函数返回值。
- [ ] 比较两路 DSI/PHY 的请求频率、缓存频率和寄存器实际配置。
- [ ] 比较第一次与第二次启动的帧完成、错误和 panel 命令序列。
- [ ] 找到差异后，一次只验证一个候选原因；保留失败实验和反证。

**修复落点与补丁安排**

先提交独立、可关闭的诊断改动与实验配置，再根据真机证据制作最小修复。不要将
诊断输出、猜测性寄存器写入和最终修复混成一个不可区分的补丁。

| 确认的问题 | 对应修复位置与要求 |
| --- | --- |
| MDSS 清理没有生效或不完整 | 修正 MDSS/reset 的访问条件、错误处理或清理流程；保持总复位在相关子设备初始化之前 |
| DSI/PHY/PLL 的顺序或状态不一致 | 在 DSI manager、host、PHY 或时钟驱动中修正；同步处理双链路、软件状态及资源引用 |
| DPU/DSC 遗留路由或首次提交缺项 | 修复 DPU 初始化或提交过程，覆盖实际生效的通路及 flush/start |
| Panel 退出旧状态不完整 | 修复 panel 的 reset、供电或命令顺序，并协调 backlight 和触摸 follower |

DSI 正常生命周期应建立明确的 PHY/lane 状态，再准备面板和开始传输，关闭时执行
相应的逆向流程。本驱动已有 `prepare_prev_first = true`，应核对实际执行效果，
不能把“再添加此标志”作为缺失修复。参见
[DRM DSI 生命周期约定](https://docs.kernel.org/gpu/drm-kms-helpers.html#mipi-dsi-bridge-operation)。

不要在 panel `prepare()` 中复位整个 MDSS，也不要随意后移总复位而破坏已初始化
的子设备。若证据最终要求板级或 SoC 特殊处理，应明确匹配范围、资源所有权和执行
条件，不能用固定延迟替代状态判断。

U-Boot 在 OS 交接前完整关闭显示是备选路线，需要实现实际的硬件关闭流程并验证。
当前 framebuffer 驱动无法仅靠清屏完成这一工作；优先修 Linux 接管。也不以实现
完整 Android continuous-splash、放弃菜单或添加通用 userspace 重亮服务为前提。

涉及 Nix 配置或构建定义的后续修改，应遵守仓库维护要求：执行相关 flake checks、
目标 dry-build 和实际诊断镜像构建。`nix flake check --no-build` 只覆盖求值层面，
`nix build --dry-run` 只说明构建计划；两者都不能代替编译和真机验证。具体输出以
届时诊断配置为准，现有相关输出包括 `kernel`、`dtb`、`demo-bootimg`、`uboot-bootimg`。

**撤销 workaround 的验收条件（均待执行）**

- [ ] ABL → Linux 和 ABL → U-Boot → Linux 均在第一次 modeset 显示正确图像，
  不依赖内核定时循环、installer refresh 或 GDM 再次 modeset。
- [ ] 两条路径各至少重复启动 10 次，记录冷启动、重启及菜单停留时间。
- [ ] 连续 DPMS OFF/ON、休眠恢复各至少 10 次，无新黑屏、超时或明显资源引用异常。
- [ ] 恢复正常 GDM/桌面启动后仍稳定；U-Boot 菜单保持可用。
- [ ] 按实验结果逐项评估 controller-stop 和 no-initial-PLL-save，保留必要的最小
  改动；更新补丁注释，去掉未经证实的因果断言。
- [ ] 最后删除 `msm_kms.c` 的定时 DPMS 补救，并更新移植记录及旧审查文档的状态。

每个实验至少保存：日期、代码与镜像标识、改动因素、固件版本、最终 DT/命令行、
完整日志、第一次出图情况、是否执行补救、结果与反证。第一次 modeset 正确且
后续正常生命周期稳定，才算修复完成。

## 2026-11-14：面板生命周期修正与首次接管实测

以下为新的修改和真机记录；前文“未修改/未刷写”只描述 10 月 26 日的审查。

本轮候选将 Liuqin 从 pipa 描述中分离，按原厂 M81 reset 波形将 nRESET
规范为低有效，unprepare 保持物理低电平。五路面板供电统一归 panel 管理，
移除四路固定 regulator 的 always-on，保留 boot-on；KTZ8866 不再永久持有
ENP/ENN 供电引用。KTZ8866 的 `LCD_BIAS_CFG1=0x9f` 设置 EXT_EN，偏压由
外部 ENP/ENN 管脚控制，见
[原厂数据手册](https://www.kinet-ic.com/uploads/web/KTZ8866/KTZ8866-04b.pdf)
表 4 和寄存器 0x09。LED 亮度写入先于开启，初始化和 I2C 错误向上传递。

Panel prepare 发送 Sleep Out、PPS 和 compression enable，enable 仅发送一次
Display On；不再在 prepare 提前 Display On 或在 enable 后重发 PPS。
候选恢复上游的初始 PLL save/restore，删除全局 1.5 秒 fbdev OFF/ON；保留
原有 controller-stop。新增 `liuqin-panel-lifecycle` 检查编译实际 C helpers，
覆盖供电逆序回滚、复位物理波形、DSC/Display On 顺序和背光总线失败。
Bindings 文档和最终 DTB 的相关 schema 检查已通过。

候选 C2 的 kernel store 前缀为 `4zwrwgaacbqc9msrlfaw99c5lzqal9kg`；
boot ID 为 `7595837f-537a-46b5-8409-a7dcebd5059b`。诊断配置使用
`systemd.unit=multi-user.target`，不启动 GDM，也没有自动重亮。

| 操作 | 触摸 follower | 用户观察 |
| --- | --- | --- |
| 第一次 modeset | 固件下载成功，ReK 始终为 0xa0，失败后保持 IRQ/ESD 关闭 | 全黑；首次 marker 不可见 |
| 等待约八分钟，不进行额外 modeset | 未重试 | 仍未自行恢复 |
| 受控 fbdev OFF/ON | follower resume #2 正常完成 | 可见 `LIUQIN DISPLAY CHECK - AFTER POWER CYCLE` |

在 OFF 状态，五路供电 use count 全部归零，TLMM GPIO0、2、53、66、93
分别为 reset 和四路 enable，均读到物理低电平；ON 后恢复高电平。
这验证了新关闭路径确实能释放电源，但不能当作首次黑屏已修复。

失败首次与成功第二次的快照中，双 DSI controller/PHY 配置相同，显示时钟
频率及父源相同；PLL 仅观察到一个状态寄存器变化。DPU INTF 的帧/行计数不同，
DSC encoder 的变化位于 status 寄存器。当前没有找到支持“请求频率配置不同”
的证据，也不能据此排除时序或未覆盖的状态。取证后已启动 GDM 恢复桌面。

当时提出的 C3 单因素实验是：在 panel 注册前、reset 保持断言时，使用成对的
regulator 引用将固件遗留供电转换到已知 OFF，再执行正常首次 prepare。
这是待实测假设，不能以冷启动步骤已实现或单元测试通过代替首次出图验收。
原始日志、前/关/后快照与候选标识留在本机
`/tmp/liuqin-power-display-review-20261114/`，平板快照在
`/var/tmp/liuqin-display-handoff-20261114/`。

### C3：首次接管前断电，未解决黑屏

C3 只增加上述 probe 阶段的完整断电步骤，kernel store 前缀为
`wpnrml8zlnb5m0jj06y8br2cknq3g30b`，boot ID 为
`12ce62ec-0859-41ad-8add-5e7dcafe0806`。同样不启动 GDM，不自动重亮。
第一次 follower resume 仍停留在 ReK 0xa0，用户确认全黑；受控 OFF/ON 后
resume #2 成功，用户随即报告有画面。随后已启动 GDM。

该结果否定了“首次 prepare 前将 panel 供电转换到 OFF 就足够”的假设。
无效的 probe 断电步骤已从下一候选撤销；保留正常生命周期中的供电归属、
复位与错误处理修正。C3 原始快照在平板
`/var/tmp/liuqin-display-c3-20261114/`，本机任务目录保留完整归档。

随后构建的 C4 把 controller quiesce 移到 PHY reset 之前：先以 runtime PM
取得总线访问条件，停止两侧 controller，再复位任一 PHY。新增测试编译实际
host/manager 函数，覆盖单/双链路顺序、总线恢复失败时不得复位、PHY enable
失败回滚，以及已经活动的双链路不能被再次停止。尚需真机验证，不能当作已修复。

### C4 与跳过触摸驱动的对照：均未解决首次黑屏

C4 kernel store 前缀 `b4szwglxhx9ha9mrvzmh4mg3apqcf1dm`，普通诊断启动
`55a4adf2-8e22-42b7-9fa1-ef8dffedc353` 仍发生首次 ReK 超时，用户报告黑屏。
随后使用同一内核，仅增加 `initcall_blacklist=nvt_spi_driver_init`，boot ID
`36c45f83-4e9a-4f83-8fcb-44d416acb8bc`。运行命令行确认参数存在，完整 dmesg
中没有 NVT probe/固件下载；未进行重亮，用户确认 `TOUCHLESS HANDOFF` marker
仍不可见。这证明未执行本次触摸固件下载时同样可以黑屏，但不足以证明整个
TDDI 启动过程与触摸完全无关，或 LCD 不需要固件。提前停止双 controller
也不足以修复。两组首次状态保存在各自 `/var/tmp/liuqin-display-c4*-20261114/`。

另外将原厂 M81 的 194 条 on-command payload 与当前 prepare 的 193 条及 enable
的 Display On 逐条比较；归一化 Sleep Out/Display On 的零参数填充后，内容完全
一致。名称复用 pipa 不是这组初始化命令的数据错误。

已恢复 LPASS 修正版及旧显示补救的正常桌面，boot ID
`d521b4a1-bd35-4b2f-a79c-2863b071b351`；GDM active，触摸第二次初始化成功。
没有将跳过触摸或纯文字启动作为日常配置保留。下一步使用 C4 的实际 BTF 类型
布局，记录早期 PHY/PLL 状态和正常 OFF/ON 对照，避免仅凭最终缓存频率推测根因。

### C4 的早期寄存器追踪与 C5 候选

使用该内核实际嵌入的 BTF 提取结构偏移，核对编译后的 AArch64 指令后，以启动
kprobe 只读采样。测试在 GDM 停止、无自动重亮的配置下保存首次轨迹，再进行
受控 OFF/ON；采样点的 MMIO 读取均位于相关电源/时钟已经开启的驱动路径中。

| 采样点 | 首次 | 受控重亮 | 结论边界 |
| --- | --- | --- | --- |
| PLL prepare 成功后，主/从 PLL SYSTEM_MUXES | 两侧 0xc0 | 两侧 0xc0 | 未观察到首次漏配该输出选择器 |
| PHY enable 入口，PHY0/1 CTRL_0、CLK_CFG0、RBUF | 两侧 0、0xf1、0 | 相同 | 没有观察到首次仍打开模拟/通道或 FIFO 的状态差异 |
| DSC config 入口，两路 DSC_CFG | 第一对配置前均 0 | 第一对配置前均 0 | 不是在固件保持启用的 DSC 上直接首次重配 |
| 停止 controller 前读取 DSI_CTRL | 两侧 0 | 两侧 0 | 额外 controller-stop 在本轮没有实际启用位可清除 |

这些结果只排除对应的具体猜测，不代表覆盖所有时钟/复位时序。
采样归档为本机 `display-trace-short.tar`、`display-trace-phy.tar`、
`display-c4-trace-dsc.tar`、`display-c4-trace-ctrl.tar`，均在本机任务目录。
每轮取证后已删除所建 kprobe 并恢复桌面。

一次完整 13 点追踪配置的 APPEND 约 1.6 KiB，超过实际 U-Boot 基线
`qcom_defconfig` 的 `CONFIG_SYS_CBSIZE=512`。`pxe_utils.c` 检查长度后跳过
该启动项，实际进入了仍有自动重亮的旧内核；镜像身份校验及时识别出这一点。
不能把那次直接亮屏当作候选成功。随后拆成每轮一处、总参数低于 500 字节的
追踪配置；这些轮次确认实际运行的是无自动重亮的 C4。

C5 改为核对已确定的配置差异：原厂 M81 声明 `traffic-mode = "burst_mode"`，
原驱动只设 `MIPI_DSI_MODE_VIDEO`，实际选择 non-burst sync-event。
为 Liuqin 增加 `MIPI_DSI_MODE_VIDEO_BURST`，pipa/yudi 描述不变。
根据 controller 采样结果，删除 C4 的提前 quiesce 和旧 controller-stop，恢复
上游 host/PHY 生命周期；无效的 C3 probe 断电步骤亦不保留。此处记录的是候选
设计，首次出图及正常待机仍须实机验证。

### C5：burst 模式仍首次黑屏，硬件背光寄存器已核对

C5 kernel store 前缀 `gfrdpdip64zn9ar1y5k7a8cysk6vax23`，boot ID
`e73e999b-9534-4a88-b90f-31fe2009ed62`。运行镜像和命令行均已确认；无自动
重亮、GDM initially inactive。用户确认 `BURST MODE` marker 不可见，仍全黑。
触摸首次固件下载完成，但 ReK 停留 0xa0；受控 OFF/ON 后 resume #2 成功，
启动 GDM 后用户确认恢复画面。因此 burst 修正不是首次黑屏的充分解法。

本轮直接读取 KTZ8866 的配置寄存器，首次和恢复后的值完全相同：
`02=b3 03=bd 04=04 05=bb 08=5f 09=9f 10=80 11=77 14=11`。
`08` 的 LED enable 位为 1，`04/05` 对应亮度 1500；OFF 状态读到
`04=00 05=00 08=1f`。这些读数证明写入硬件的使能和亮度状态，不能证明
实际 LED 电流或面板图像正常。使用 debugfs 的定位单寄存器读取，未读取
可能清除故障状态的 FLAG 寄存器。原始前/关/后记录保存在平板
`/var/tmp/liuqin-display-c5-20261114/` 和本机任务目录的
`display-c5-snapshots.tar`。

随后 C6 采用临时附加内核补丁，默认关闭的 `trace_status` 参数在 reset、
初始化和 Display On 后分别读取两路 DSI 的 power/signal mode。该补丁仅存在于
任务目录的诊断 flake，不纳入正式 patch series。读取本身会增加总线事务和
时序扰动，若因此首次恢复，仍需在关闭诊断的配置中独立验证。

### C6：DSI1 的首次读无响应，重亮后返回有效状态

临时诊断内核 store 前缀 `r5if9nf69lbxadkpjhyfyvr5vx9sc5xb`，boot ID
`f4641979-e40e-496f-ae92-46ea9adb70ad`。本轮启动参数 452 字节，同时启用
面板状态读取和 PPS 前 64 字节的只读 kprobe。实际镜像、参数、probe 和
`trace_status=Y` 均已核对；没有自动重亮。

首次 marker 仍黑。`fb0/blank` 初始为 4，而 DRM/背光开启；单独写 0 并启动
GDM 后，日志确认仍只有一次 panel 初始化，用户再次确认全黑。因此该矛盾
不是仅解除控制台 blank 或启动图形界面就能解决的原因。停止 GDM 未引发
额外 panel 初始化，随后才执行受控 fbdev OFF/ON。

| DSI1 的状态读取 | 首次 | 受控 OFF/ON 后 |
| --- | --- | --- |
| reset 后、初始化命令前 | power 返回 ENODATA，signal 长度 0 | power 0x08，signal 0x00 |
| Sleep Out、PPS、compression 后 | 同上 | power 0x9a，signal 0x80 |
| Display On 后 | 同上 | power 0x9e，signal 0x80 |

首次 reset 后读取在 1.228 秒，触摸 follower 固件下载从 1.836 秒才开始。
可观察的差异因此已经存在于触摸下载之前的 panel/DSI 首次接管阶段。
这不能独立区分物理供电、复位和链路初始状态。DSI0 前后均无读数据：当前
manager 的 trigger 对同步双 DSI 的 id 0 无条件返回 false，与上层对读事务
不作同步的处理不一致，DSI0 读结果不能作为这块面板无响应的额外证据。

实际发送的两次 PPS 前 64 字节完全一致；该覆盖范围包含图片/切片尺寸、
延迟与部分 RC 参数，不能代替未记录的后 64 字节比较。触摸首次 ReK 超时，
第二次成功；启动 GDM 后用户确认恢复画面。已删除创建的 kprobe，并将
`trace_status` 运行时关闭。前/后原始记录在平板
`/var/tmp/liuqin-display-c6-20261114/` 和本机 `display-c6-snapshots.tar`。

随后 C7 仅变更 DTB，使用完全相同的 C6 内核，移除四路 GPIO regulator 的
`regulator-boot-on`。`fixed.c` 会因该属性在 probe 时选择 GPIOD_OUT_HIGH；
已提前拉高的电源在首次 prepare 中不再有按顺序上升的边沿。
测试 DTB 已逐项比较，确认只有这四个属性被删除；实际验收结果见下段。

C7 boot ID 为 `9175900a-a3da-4b13-a518-2ddd6e4bd261`，已在 live DT 确认四个
属性不存在，实际内核仍为同一个 C6 镜像。DSI1 三阶段首次读取仍无数据，
触摸首次 ReK 仍超时，用户确认全黑；随后受控 OFF/ON 的第二次触摸恢复成功，
GDM 已启动。该结果否定“只移除 boot-on 就足够”的假设；未将 C7 的 DTB
修改写入正式补丁。后续只读追踪恢复原 DTB，检查首次配置前的 INTF timing
engine enable，以区分静态配置相同与上电时已有活动视频流的情形。

### C8：INTF 首次配置前均关闭；KTZ 未报告锁存故障

C8 保持 C6 内核和原 DTB，boot ID `aa1ebb74-f045-43b2-b372-65b67bed5eab`。
启动 kprobe 位于实际 `dpu_hw_intf_setup_timing_engine()` 入口，只读已上电硬件。
INTF id 3、2 在首次配置前的 timing-engine enable 均为 0，受控 OFF/ON 后
再次配置前亦为 0。该采样未支持“原有 INTF timing engine 一直开启”的猜测，
未增加针对该假设的复位代码。首次 DSI1 状态读取仍为空、触摸 ReK 超时；
取证后执行了受控 OFF/ON，第二次 DSI1 返回 0x08/0x9a/0x9e，触摸成功，
已删除创建的 probe、关闭额外状态读取并启动 GDM。

随后第一次显式读取 KTZ8866 的 FLAG（0x0f），值为 0x00，一秒后仍为 0x00。
该读取发生在本轮受控重亮后，不能记作黑屏当时的即时电压测量。
同次输出配置为 `0a=11 0b=00 0c=28 0d=24 0e=24`，使能为 `09=9f`。
按 [KTZ8866 Rev 04b 数据手册](https://www.kinet-ic.com/uploads/web/KTZ8866/KTZ8866-04b.pdf)
寄存器定义，0d/0e 的配置码对应 ±5.8 V，与 fixed-regulator 声明的 ±5.5 V
不一致；驱动目前继承芯片配置，没有改写这些电压。本轮不据此改变实际电压，
还需核对原厂动态配置与这块面板的要求。FLAG 为 read-clear 的锁存状态，
读取前已保存其他配置，FLAG 首次值亦单独保存。

### C9：原厂长包编码对照，首次仍全黑

原厂 M81 on-command 的 194 条数据类型全部为 DCS long write 0x39，原驱动
短命令由通用 DCS helper 选择 0x15/0x05。临时候选添加默认关闭、仅匹配
Liuqin 的 `force_long` 开关；开启时 prepare 初始化和 enable 的 Display On
使用 0x39，Sleep Out/Display On 保留原厂的 00 填充。PPS、compression、
供电、复位和显示生命周期不变；未增加自动重亮或失败重试。

临时 helper 的实际 C 测试已通过机型范围、LP 标志和传输错误处理；从实际
候选 C 源码提取的 194 条 payload 与原厂 M81 完整逐字节一致。临时 flake
检查、dry-build 和交叉内核构建均已通过。另用启动 kprobe 记录
host 收到的数据类型及命令字，启动参数 486 字节。该候选不在正式 patch series。

实际内核 store 前缀 `2i3636rgyyin0g02w32f7zada7rdwar5`，boot ID
`7aae62ec-6c3f-4019-ba48-0e0bfb62b6d5`，已核对镜像和两个实验参数均开启。
首次 host 请求记录为 DCS read 12 条、DCS long write 194 条、PPS 1 条、
compression 1 条，Sleep Out/Display On 亦确认为 0x39；额外出现命令字
0x11/0x29 的私有页寄存器写入不能误计为真正的 Sleep Out/Display On。
首次三阶段 DSI1 仍返回空数据，触摸仍停在 ReK 0xa0。单独将控制台 blank
从 4 写到 0 后写入 marker，没有先做 OFF/ON；用户确认依旧全黑。

随后将 `force_long` 运行时关闭，以已验证的普通 DCS 路径执行受控 OFF/ON：
DSI1 返回 0x08/0x9a/0x9e、触摸 resume #2 成功，已启动 GDM。该次恢复使用
的是普通短包路径，不能记作长包候选的第二次成功。已关闭状态读取并删除
本轮创建的 `lq/t` kprobe。C9 归档的首次轨迹在本机 `display-c9-first.tar`，
完整恢复后记录在平板 `/var/tmp/liuqin-display-c9-20261114/`。
