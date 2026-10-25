# 显示接管与相机电源管理：审查结论和验证方案

日期：2026-10-23。设备：Xiaomi Pad 6 Pro（liuqin / SM8475）。内核：Linux 7.2.5。

本文记录架构审查中尚未处理的两项：第 3 项是首次 modeset 后延迟 1.5 秒执行
DPMS OFF/ON；第 5 项是相机 GDSC 和 GCC AXI 时钟常开。其他审查项在独立
worktree 中处理，本文不重新确认其完成状态。

审查以 `main` 的 `73e8071` 为基线，也参考了当时主工作区尚未提交的显示补丁和
移植记录修改、历史提交，以及相邻的旧内核仓库。本分支从 `73e8071` 创建，只提交
本文，不携带主工作区的未提交修改，也不包含其他 worktree 的实现。

本文完成了源码、历史记录和公开资料对照，**没有实施驱动修改，也没有进行新的
构建或真机实验**。下文的历史结果来自已有记录；候选原因、实验预期和验收目标均
不代表已在当前版本验证。

**判断与优先级**

- 第 3 项高度指向显示硬件的初始状态及 Linux 接管流程。直接 fastboot 正常、经
  U-Boot 异常是关键证据，但尚不能定位到某个确定的 panel、DSI、PHY 或 DPU 操作。
- 第 5 项存在具体缺口：当前 CAMCC 缺少相机 RCG 在关闭时切回安全时钟源的处理。
  同平台有成功案例和近期上游补丁，是值得优先验证的强候选原因。
- 建议先实现和验证第 5 项，再通过受控启动对照收敛第 3 项。两项都应保留可启动的
  已知正常版本，按阶段撤销 workaround。

**第 3 项：两条启动链交给 Linux 的显示状态不同**

[板级 DTS 补丁](../../pkgs/kernel/patches/0001-liuqin-board-dts-bindings.patch)
记录了 ABL 的 `UpdateSplashMemInfo()` 交接约定，以及 2026-09-28 的相关实验：

| 路径 | ABL 看到的设备树 | 记录中的交接行为 |
| --- | --- | --- |
| ABL → Linux，即直接 fastboot boot | Linux 保留区命名为 `linux_splash` | 找不到约定的 `splash_region`，调用 `DisableDisplay()` |
| ABL → U-Boot → Linux | U-Boot DTB 保留 `splash_region` | 保留显示，供 U-Boot 菜单使用；随后启动 Linux 不再经过 ABL |

这里“冷启动显示”指显示链路已停止后的初始化，不等同于整机断电重启。

[U-Boot video 驱动](../../pkgs/u-boot/files/board/qualcomm/liuqin/video.c)
复用 ABL 位于 `0xb8000000` 的 framebuffer，只绘制像素并维护缓存一致性。它没有
完整的 DSI 初始化流程，也没有显示关闭回调。因此，U-Boot 路径触发故障的合理解释
是它保留了 ABL 的显示状态；现有证据不能证明 U-Boot 主动配置坏了显示硬件。
修改最终 Linux DTB 的节点名称，也不能让已经退出的 ABL 再执行一次关闭。

上游遇到过 bootloader 显示状态残留、Linux 仅重新配置部分 DPU 的问题，采用了在
初始化时复位整个 MDSS 的方案，并要求复位先于子设备 probe。见
[MDSS reset 补丁说明](https://lkml.iu.edu/2204.2/06017.html)和
[关于 probe 顺序的修订](https://lkml.iu.edu/2204.1/01133.html)。

但本次检查的 7.2.5 源码中，`msm_mdss_reset()` 已存在，SM8450 的 MDSS 节点也已
声明 `DISP_CC_MDSS_CORE_BCR`。所以“再加一次 MDSS reset”不是现成答案。需要确认
运行时 DT、reset 执行结果、覆盖范围和执行顺序。该函数目前没有检查
`reset_control_assert()` / `reset_control_deassert()` 的返回值，这值得加诊断，
但不能据此认定 reset 已失败。

**第 3 项：之前的实验为什么不足以确定根因**

历史提交 `2f148f48d06cf761e1f4d4fd592c6b2345ebdf42`（2026-10-07）及
[移植记录](../PORTING-NOTES.md)描述了以下结果：

- 面板 sleep-in、供电循环和 DPU 控制路径 reset 未独立解决问题。
- DSI 编程前停止 controller，以及不保存、恢复 bootloader 的 PLL 状态，也不足以
  独立解决问题；当前显示补丁同时保留了这些改动和 DPMS 补救。
- `clk_ignore_unused` / `pd_ignore_unused` 没有解决问题；背光和显示 runtime PM
  状态也不支持之前对应的猜测。
- 完整 OFF → ON 后可以恢复图像。原先较晚的多次循环会与 GDM 获取 DRM master
  冲突，后来改为首次 fbdev modeset 后的一次早期循环。

局部 reset 不能证明首次初始化已等价于成功的第二次初始化。正常的关闭函数还依赖
Linux 自己维护的软件状态：例如 `msm_dsi_host_power_off()` 在 `power_on == false`
时直接返回。接管 bootloader 时的软件状态与硬件遗留状态可能不同，简单提前调用
普通关闭函数未必有作用；强行绕过判断又可能破坏电源和时钟引用计数。

寄存器快照中的 enabled 位只能证明配置状态，不能证明双 DSI、DSC、时序和面板已经
协同输出。需要对比实际转换过程和帧完成、错误状态。

审查时还发现记录冲突：`PORTING-NOTES.md` 前面的 10 月 7 日记录说局部处理无效、
仍需一次循环；后面的 hand-off 段落却说遗留状态无害、不需 workaround。后者不能
作为已经验证的结论。显示补丁中对 PLL 原因的解释，也应与“该改动单独不足以恢复
图像”的历史结果区分，避免把假设继续写成确定根因。

**第 3 项：建议的实验与最终修复边界**

先固定同一内核和 initramfs，核对最终 Linux DTB、相关启动参数及镜像哈希。关闭
自动 DPMS 补救，暂时不启动 GDM；除了有意改变的 splash 节点命名，保持实验输入
一致，并记录 bootloader 对最终 DT 的修改。

| 实验 | 改变的因素 | 用途与当前状态 |
| --- | --- | --- |
| A：直接 fastboot，ABL 关闭显示 | 基准路径 | 用户观察及旧记录中正常；需用实验版本复核 |
| B：普通 U-Boot，保留 ABL 显示 | 现有 U-Boot 路径 | 故障对照；需排除自动补救掩盖故障 |
| C：诊断版 U-Boot 自身 DTB 取消 `splash_region` 命名，再自动启动同一 Linux | 保持 U-Boot 路径，但让 ABL 先关闭显示 | 新实验，尚未执行 |
| D：直接 fastboot，将 Linux DTB 的显示保留区恢复为 `splash_region` | 不经过 U-Boot，但保留 ABL 显示 | 历史有类似负结果；需用当前版本复核 |

C 会失去继承的可见 U-Boot 菜单，仅用于可自动启动、可通过其他通道取证的诊断版本。
不能把永久取消菜单当作最终修复。

如果故障跟随“是否保留 ABL 显示”变化，就优先定位显示接管。如果 C 仍失败，则继续
检查 U-Boot 带来的其他 DT、时钟、启动参数和硬件状态差异，不能强行维持原假设。

随后比较 A 的正常初始化、B 的失败首次 enable、B 中能够恢复的 disable → enable：

1. 记录 MDSS reset 是否取得，assert/deassert 的返回值和时间点，以及子设备 probe
   的先后关系。
2. 记录双 DSI/PHY 的复位、PLL 配置和恢复顺序，区分软件缓存状态与硬件配置。
3. 对比 DPU/DSC 配置、帧完成和 DSI 错误，定位成功的第二次启动多做了什么。
4. 根据差异修复已存在的 reset 或补齐首次接管遗漏的步骤，每次只验证一个假设。

最终改动应归属相应的 MDSS、DPU、DSI 或 PHY 生命周期。不要把整个显示子系统的
复位放进 panel `prepare()`，也不要把会破坏已初始化子设备的 MDSS 总复位任意后移。
若必须暂时采用板级特殊处理，应限制适用范围、明确资源所有权与执行条件，不能依赖
“等 1.5 秒大概还没有 GDM”的时序。

U-Boot 跳转前完整关闭显示是另一条路线，但现有 U-Boot 只有 framebuffer 驱动，
补齐可靠的关闭流程需要额外实现和验证；优先修 Linux 接管更合理。当前证据还不足以
给出已确认有效的完整硬件关闭顺序，不应靠任意 MMIO 写入拼一个未经验证的序列。

删除定时补救的验收条件：两条启动链均能在第一次 modeset 显示图像，不依赖 fbdev
定时循环或 GDM 重设模式；重复启动、正常 DPMS 和休眠恢复没有退化。先关闭 GDM
定位，最后必须恢复正常桌面启动验证。

**第 5 项：RCG 未停靠安全时钟源是具体缺口**

当前 [camera tuning 补丁](../../pkgs/kernel/patches/0013-liuqin-camera-tuning.patch)
已设置 `RETAIN_FF_ENABLE` 和 GDSC 等待参数，同时把 IFE0/1/2、TITAN_TOP 设置为
`PWRSTS_ON`，并在 GCC probe 中强制开启 HF/SF AXI 时钟、设置 `CLK_IGNORE_UNUSED`。

本次检查的 7.2.5 `camcc-sm8450.c` 中，35 个 RCG 仍使用 `clk_rcg2_ops`；当前补丁
没有改为 `clk_rcg2_shared_ops`。普通 ops 会让关闭后的 RCG 保留之前选择的 PLL。
当 PLL 已停止，电源域的后续转换可能等待不到所需时钟响应。shared ops 则在关闭时
停靠到安全源，并在启用时恢复配置；`clk-rcg2.c` 的 `clk_rcg2_shared_init()` 注释
明确解释了死父时钟可能导致 GDSC 卡住的机制。

因此，单独增加 GDSC 等待时间或状态保持，并不能修复它等待的时钟没有跳变的问题。
这是当前最值得优先验证的原因，尚未在 liuqin 的当前版本上证实。

公开证据与适用范围：

- [Galaxy Tab S8+ 的实验记录](https://github.com/aaronsb/sm-x800-linux/blob/main/docs/11-camera.md#stage-2-second-half-the-second-session-r23)
  描述了 SM8450 首次采集成功、后续电源域无法恢复，修改 retention、等待参数等
  均未解决，最终以 RCG 停靠 XO 修复并验证连续采集。它是其他设备的实测，不是
  liuqin 的验收结果。
- [SM8450/SM8475 修复系列](https://lkml.iu.edu/2610.2/07975.html)在 Nothing Phone
  (2) 上验证了 GDSC retention/等待参数及 RCG 停靠两部分修复。
  [2026-10-20 的 v2 RCG 补丁](https://lkml.iu.edu/2610.2/11080.html)转换 34 个 RCG，
  保留使用常开 sleep clock 的 `cam_cc_sleep_clk_src`；
  [10 月 22 日评审](https://lkml.iu.edu/2610.2/15513.html)已有 Reviewed-by。
  截至本次审查，确认的是提交和评审状态，不能据此声称已合入当前内核。

本地旧 `linux-sm8450-liuqin` 仓库的
`3672dd4ad1520987331d21d897ca7c15d7ef9f94`（2026-09-20）也已对部分 SM8475 RCG
采用 shared ops，但只覆盖部分时钟，并混合了 GDSC 轮询方式等其他改动。不能说过去
完全没尝试该方向，也不应直接整块复制旧补丁。应以当前内核为基线，逐项对照较完整的
上游修复，不凭猜测删除 `POLL_CFG_GDSCR`。

**第 5 项：分阶段撤销常开，而不是重写 runtime PM**

CAMSS、VFE、CAMCC 已有 runtime PM、电源域关联和时钟启停框架。目标是补齐硬件
转换条件和资源归属，而不是另建一套相机电源管理系统。

| 阶段 | 修改 | 进入下一阶段的条件 |
| --- | --- | --- |
| 1 | 引入 RCG 安全停靠修复，核对已有 retention 与等待参数，暂时保留常开兜底 | 首次采集和现有图像功能不退化 |
| 2 | 允许 IFE 电源域 OFF/ON，暂时保持 TITAN_TOP 常开 | IFE 能重复关闭、重新上电，第二次采集正常 |
| 3 | 允许 TITAN_TOP OFF/ON | 整个相机域能关闭和恢复，无挂死、超时或引用泄漏 |
| 4 | 将 GCC HF/SF AXI 时钟接入 CAMSS/VFE 现有资源管理，逐项撤销直接置位和 `CLK_IGNORE_UNUSED` | 使用时正确持有时钟，最后一个使用者退出后可关闭 |

GCC 时钟需要在 DT 的 clocks/clock-names 与
[CAMSS/VFE 资源表](../../pkgs/kernel/patches/0012-liuqin-camera-core.patch)中对应，
复用已有 enable/disable 和错误回滚路径；多个 VFE 共享时依靠时钟框架引用计数。
只需 gate、不需设置频率的资源使用相应的零 rate 项，不能因加一项导致后面的频率表
错位。还要核对时钟启用是否先于依赖它的寄存器访问，以及关闭是否晚于中断和数据
路径的停止。

GCC 部分不能直接照抄过去的尝试：历史 `c157ee5` 中
`docs/TODO/CAMERA-MAINLINE.md` 记录，`0032-liuqin-camera-gcc-axi-clk.patch.disabled`
接入 `gcc_axi_hf` 后 consumer 已绑定，但 `STREAMON` 出现 `-EPIPE`。当时没有定位
到具体失败的 media link。它证明了那次改动有回归，不足以证明按需管理时钟不可行。

重做时需记录实际 ioctl 返回值、link validation、各 pad 的格式，以及 PM/clock
转换的错误；核对运行中的内核、DTB 和模块版本一致。先定位 `-EPIPE` 的返回位置，
不要仅根据进程退出码或改回常开后能运行就宣布根因。

同一历史记录还显示，GCC AXI 常开后当时的全零 payload 仍然存在。因此当前补丁中
“关闭 AXI 出口解释全零 payload”的叙述不能当作已证实因果；图像内容问题与电源域
重复启停问题需要分别验收。

建议的真机验收目标，均尚未执行：

- 每条实际使用的摄像头路径连续采集至少 50 次，验证实际图像内容、帧完成和错误日志。
- 前后摄像头交替使用；只打开后关闭而不取流；取流失败后关闭、重试。
- 相机空闲与使用后的系统休眠恢复，建议至少 10 次循环。
- 检查空闲时相关电源域确实关闭，RCG 停靠 XO，时钟/PM 引用计数无泄漏；检查硬件
  状态时必须保证访问条件，不能读取已经断电、断时钟的相机 MMIO 窗口。
- 各阶段保留镜像标识、补丁差异、完整返回值和日志，再撤销下一层兜底。

第 5 项最有把握的首个实现是完整的 RCG 安全停靠修复。第 3 项最有价值的首个实验
是把“经过 U-Boot”和“继承 ABL 显示状态”分开控制；它能决定后续补丁应该修哪里。
