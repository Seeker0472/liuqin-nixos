# U-Boot 显示交接实现

2026-11-15 当前状态：**r5 的手动 quiesce 与正常 Linux GO/FDT 发布已通过；
配合 Linux 0027/0028 时钟修复的 c1，两次启动均由用户确认正常显示，RTC deep
恢复后显示和触摸也经确认。** c1 验证明确关闭早期自动 OFF/ON；普通内核仍保留
该旧补救代码。时钟修复与验证边界见[内核补丁说明](../pkgs/kernel/patches/README.md)。

下文 r1-r5 的黑屏与失败记录属于加入时钟修复之前的历史结果；停止合同通过与
Linux 首次出图是分别验证的，不能将后者单独归因于 U-Boot 停机。
背景和证据边界见[系统调查](research/DISPLAY-HANDOFF-2026-11-14.md)。
最初实现轮按用户要求仅构建和 review；后续用户自行刷写并提供的 prepare 反馈见文末。

## 合同与代码边界

U-Boot 菜单借用 ABL 扫描，不初始化显示。进入真正的 Linux GO 时，先准备输出
FDT 和资源，再同步停止显示；Linux 得到停止扫描、host/PHY 关闭、偏压 standby
的状态。此合同名为 `quiesced-v1`，**不表示整个 MDSS 已断电**。

| 代码 | 责任 |
| --- | --- |
| `pkgs/u-boot/files/board/qualcomm/liuqin/display-handoff.c` | 实际停机状态机；注入 MMIO、I²C、延时和 console freeze |
| 同目录 `display.c` | 固定资源校验、DM I²C、真实 GO、恢复路径和 OEM helper |
| 同目录 `display-fdt.c` | 只修改待交给 Linux 的 FDT 副本 |
| `pkgs/u-boot/patches/0014-checked-linux-handoff.patch` | 在清理设备之前调用可返回错误的 hook；USB fastboot 退出 guard |
| `pkgs/u-boot/patches/0015-geni-i2c-bounded-abort.patch` | I²C 出错时 abort 本身也有超时，使用正确的 IRQ_CLEAR |
| `pkgs/u-boot/display-helper.py` | 主机调用一次操作并读回缓存报告；不重试、不重启 |

状态转换：

```text
BORROWED --prepare 成功--> PREPARED --commit 再检查成功--> COMMITTING
   ^                          |                              |
   +----- 检查失败，可重试 ----+                      QUIESCED 或 FAILED
```

`prepare` 不写显示或面板寄存器，不冻结 console。它可能初始化专用 I²C1 的总线
和 pinctrl，以便读 KTZ；这不等于整机所有寄存器都只读。`commit` 总是重新检查，
不信任上次 prepare 的状态。QUIESCED 重复调用不访问硬件；FAILED 保留失败阶段、
错误和已完成的发送掩码，禁止继续操作显示。

真实 GO 的检查失败允许返回菜单。commit 开始后失败，或 Linux 在 cleanup 后
返回，写现有 ABL bootloader restart reason 并进入固定复位路径；reason 设置失败
则 halt，不能掉回不可用的菜单。手动 helper 的失败暂时留在 USB fastboot，供读回
报告；fastboot 退出时同样进入恢复路径。FAKE_GO 不调用显示交接 hook。

## 支持范围与序列

仅接受控制 DT 中启用且 compatible 为 `xiaomi,liuqin-abl-display` 的
`/display-handoff` 板级合同节点、固定 MMIO 地址与范围、
MDSS/MDP 实际硬件版本 8.5（使用 SM8450 8.1 catalog 的布局）、两路 DSI major 2 /
minor 6、正在扫描的四 lane 双 DSI video splash、
KTZ8866 ID `0x21` 和偏压配置 `0x9f`。不支持的硬件/固件状态在停机前拒绝，
不会自动试其它寄存器组合。slave PHY 可使用 master PLL，不要求 slave PLL 启动位为 1。
根节点 compatible 只记录诊断：真机已证实它可以与打包 DTB 中的 Xiaomi 字符串不同。

先检查 GCC 显示 AHB、DISP_CC GDSCR、MDSS AHB/MDP 和 link clocks，再访问 MDSS。
不能在无时钟时先读版本再判断是否安全。

| 顺序 | 操作与完成条件 |
| --- | --- |
| 1 | 冻结 U-Boot console；停两路 INTF TGEN，按 dump HAL 写伴随 `+0x210=1`；等待两路 INTF_STATUS bit0 清零 |
| 2 | 两路 host 先禁用 video/command engine，仅等待命令 DMA/MDP 工作结束；保留访问时钟做 soft reset，reset 后确认全部 busy 位清零，再重建 command 模式 |
| 3 | 依次在两路发送 DCS DisplayOff `0x28`，再在两路发送 SleepIn `0x10`；等待 70 ms |
| 4 | 两路 host disable/reset，关闭内部 clocks；不再访问 host 或 DPU |
| 5 | PHY PLL 保持运行，关闭 8 个显示 link 专用 CBCR（pclk、byte interface、byte、escape），有界确认各自 enable=0 且 CLOCK_OFF=1 |
| 6 | 通过保留的 AHB 访问 PHY APB，PLL_CNTRL=0、CTRL_0=0 并读回 |
| 7 | 单颗 KTZ 关闭 LED current enable，LCD_BIAS_CFG1=`0x98` 并读回；等待 10 ms |

显示核心的寄存器轮询上限 50 ms，间隔 10 µs；I²C provider 的 abort 上限另为 1 秒。
最后一个 host 访问发生在其内部时钟关闭之前。link gate 开始后不再访问 host
或 DPU；PHY APB 仍通过保留的 MDSS AHB/GDSC 访问，直到后续 PHY 关闭结束。
状态报告始终只读缓存，不通过读寄存器重新取证。

TERM 使用 Qualcomm 的 TPG DMA FIFO 发送方式，LP、独立触发两路；4 byte DCS
short packet 后补一个硬件 FIFO padding DWORD，DMA_LENGTH 仍为 4。传输完全不使用
系统内存 DMA，因此无需借用 ABL 的缓冲区或假设显示 SMMU 映射有效。发送前显式
清理 stale DMA_DONE，检查清理结果；轮询新完成或 error，不用“DMA 当前不忙”代替
完成事件。prepare、发送前后还检查原始 PHY/FIFO/ACK/TIMEOUT/CLK/STATUS 错误
位，防止 ABL 的 ERR_INT_MASK0 把错误 summary 屏蔽掉；报告保留第一个错误的
偏移和值，不在检查时擅自清掉继承错误。它没有请求 panel ACK：完成掩码证明本地发送完成，**不证明面板收到、
电压正确或光学上已关屏**。

序列参考实际 DisplayDxe 停机，而不是调用其 EBS 后已经无效的 EFI protocol。
FIFO transport、LED current disable、专用 CBCR 门控是本实现的明确工程选择，
不是声称逐条复现固件内部 API 的引用计数。对应 Qualcomm 原始实现固定在
[`e7ab2aa8bd2f` 的 dsi_ctrl_hw_cmn.c](https://android.googlesource.com/kernel/msm-extra/display-drivers/+/e7ab2aa8bd2f6f27b311ccada3722d20dee4bcef/msm/dsi/dsi_ctrl_hw_cmn.c)。

地址单位必须分清：版本采点使用与固件一致的独立 MDSS `0xae00000` 窗口。
DPU 窗口是 DT 的 MDP `0xae01000`，INTF1/2 相对偏移
`0x35000/0x36000`，物理地址为 `0xae36000/0xae37000`。DSI 窗口是原始
`0xae94000/0xae96000`，CTRL 偏移 `0x004`；不能混用主线 host 已加 4 的逻辑偏移。
DISP_CC GDSCR 为 `0x9000`，`0x8004` 是 pclk0 gate。

## 刻意保留的资源

- 保留 MDSS AHB/MDP、GDSC、parent RCG、GCC/ICC/RPMh 共享资源；Linux 正常
  MDSS reset/probe 负责接管。没有可调用的固件 clock 引用计数，不能仿造数次
  DisableClock，更不能先关访问时钟再读 PHY。
- 不关闭 L5/L10 等 USB/UFS 共用 PMIC rail，不动 panel 的四路固定 regulator、
  数字电源、HWEN、reset 和 TE pad。原调查尚未证明 ConfigGpio(DISABLE) 的物理
  电平，因此没有将它猜成一个 GPIO reset pulse。KTZ `0x98` 是偏压 standby，
  不是整个 TDDI 冷断电。
- 固件 callback 对两个 handle 的循环不证明这块板有两颗芯片。当前板级 Linux
  DTS 只声明 I²C1 `0x11`；U-Boot 只访问这颗。固定源 sm8450.dtsi 的 I²C1
  pinctrl 是 GPIO4/5；先前子报告的 GPIO14/15 描述不适用于这个实际 DTS。

这定义了一个可检查的 quiescence 边界，尚不能证明它消除了进入 Linux 的全部
有害遗留状态。若真机 prepare 拒绝，应读报告核对条件；不能将严格检查直接改成
无条件写入。若 quiesce 成功但首次仍黑，应比较同一内核两条入口的早期状态。

## Linux FDT 发布

镜像、initrd 和 FDT 由正常 loader 装载/校验后，hook 将 Linux FDT 复制到 scratch，
在任何显示写入前完成所有可能失败的分配和 libfdt 操作：

- 删除 `simple-framebuffer` 节点；保留全部 reserved-memory 和 carve-out。
- 删除指向 simplefb 的 `stdout-path` / `linux,stdout-path`，解析 alias 与冒号选项。
- 删除匹配的 `earlycon=simplefb`（含逗号参数）；若 stdout 原为 simplefb，也去掉
  裸 `earlycon`。保留其它 console、参数和引号内的内容。
- `/chosen/liuqin,display-handoff="quiesced-v1"` 记录合同。

只有硬件 commit 成功才 memcpy 发布到原 LMB 预留的 FDT 地址，大小不增长；空间
不足在关屏前报错。U-Boot 的控制 DT / OF_LIVE 从不由此路径修改。当前 Linux
没有消费该合同标记的专用驱动，它仍通过正常 MDSS/DSI/panel 初始化启动。

## 离线验证与后续真机入口

```sh
nix build .#checks.x86_64-linux.liuqin-uboot-display-handoff \
  .#checks.x86_64-linux.liuqin-uboot-port-manifest \
  .#checks.x86_64-linux.liuqin-patch-hunks --no-link -L
nix flake check --no-build
nix build .#uboot .#uboot-bootimg --no-link --print-out-paths
```

原生测试执行同一核心 C 源，模型实现 W1C、延迟完成和时钟访问限制；覆盖全部
383 个成功路径 I/O 的逐点失败、16 种卡住/错误情形、检查重做和终态幂等。
正常模型默认 VIDEO_BUSY 仅在 soft reset 后清除；reset 后仍 busy 则超时失败。
pixel/byte 门控确认要求其 PLL 源仍运行，PHY APB 独立依赖 AHB；覆盖八个 gate
各自卡住、enable 写入未生效、延迟确认，以及用户 r4 的真实停机前寄存器组合。
FDT 测试使用真实 libfdt，包括分配失败、空间不足、串口保留和源树不变。
启动/USB 测试从固定基线应用 0014 后提取实际生产函数编译执行，检查 PREP、
GO、FAKE_GO、外层 `boot_selected_os` 拒绝时不 cleanup/RESET、kernel return、
USB exit 在 provider teardown 前。错误没有仅在 ARM 内层返回后被外层吞掉。
板级 adapter 测试执行真实发布函数，覆盖旧 ft_len 比最终 blob 大/小、发布前失败
保持源树不变、终态拒绝恢复和物理窗口边界。GENI abort 测试执行应用 0015 后的
实际函数，覆盖立即完成、延迟完成和永不完成（1 秒上限）。主机 helper 测试检查
失败仍读报告、读取数量限制和超时不重试。

下一轮若明确开始硬件验收，在**这个候选 U-Boot 的 fastboot** 中可执行：

```sh
python3 pkgs/u-boot/display-helper.py prepare
python3 pkgs/u-boot/display-helper.py status
python3 pkgs/u-boot/display-helper.py quiesce
python3 pkgs/u-boot/display-helper.py status
```

可用 `--serial` / `--fastboot` 指定设备和程序。`status` 只返回缓存；首次 prepare
之前没有寄存器快照。原始协议是 `fastboot oem board:display-prepare`，然后读取
`fastboot getvar display-count`、`display0` 到 `display<N-1>`。报告快照为停机前数据，
失败时可能只采集了一部分。quiesce 是单向操作，屏幕将不可用于菜单；报告读完后
可由操作者选择 reboot-bootloader。工具不会替操作者执行重启。

验收分开记录 helper 完整退出合同和 Linux 无补救的首次出图；当前 r5 已通过
前者的寄存器检查及熄屏观察。本轮没有改 Linux
显示补丁；已提交回退内核仍有 1.5 秒 DPMS cycle，不能用它后来的亮屏证明交接
修复。下次首次出图验收必须明确使用禁用该补救的 Linux 候选，并与同版本
ABL 直启对照；不要恢复整个 stash 或叠加 C2–C9 实验来混淆条件。

## 最初实现轮收尾记录（r1）

全新独立 reviewer `/root/display_handoff_review_fresh` 在实现完成后启动，最终
复查未发现尚未修复的 P0/P1/P2。审查和主代理复查中关闭了以下问题：

- 外层 `boot_selected_os()` 吞掉 ARM 内层错误，导致检查拒绝仍 RESET：检查已
  移到真实 Linux GO 的外层、cleanup 之前，普通拒绝码不与 BOOTM_ERR_RESET 混用。
- `image_setup_linux()` 没有更新输入 `ft_len`，最终 FDT 却已 shrink 并重建 LMB：
  现在使用最终 blob 的 totalsize，发布后同步更新 ft_len。
- GENI transfer 超时后无界等待 abort、向 IRQ_STATUS 写清除：0015 改为有界等待，
  使用 IRQ_CLEAR。
- 单看 IRQ summary 会遗漏被继承 mask 屏蔽的错误：加入原始状态检查和 masked-error
  回归。独立 MDSS 版本窗口属于与固件证据对齐的改进，没有宣称旧 MDP 版本采点已证实错误。

主代理最终三个针对性 Nix checks、`nix flake check --all-systems --no-build`、
U-Boot/boot.img 交叉构建和 dry-build 全部成功。reviewer 独立运行三个 checks
及 `nix flake check --no-build` 成功。没有执行硬件命令。

本机候选镜像链接为 `out/uboot-display-handoff-20261114/boot.img`，对应输出：

```text
/nix/store/yvn0g4kdf6wc16by6whfc730yc11caml-liuqin-bootimg-2024.10+a4f9d7fc+liuqin/boot.img
SHA256 4ece755b259de09bebc37cd5313a06130c47012d29dd59e8f93764db2dc61692
```

构建日志和本轮原始验证结果在本机 `/tmp/liuqin-display-handoff-refactor-20261114/`。
旧显示实验 stash 对象为 `204ac75cdf38314a4069a853f0a04b554bf4ff38`，名称
`display experiments before U-Boot handoff refactor 2026-11-14`；本轮结束时为
`stash@{0}`，此前的另一个 stash 保留。实现改动留在工作区，未创建提交。

## 首次 prepare 反馈与资源诊断修订

用户第一次真机执行 prepare 返回 `state=borrowed`、`stage=access error=-19`，
全部寄存器快照为零。这个组合来自 adapter 的 `display_resources()` 失败：核心
访问时钟检查不会返回 ENODEV，版本不匹配则应处于 identify 阶段。因此零表示
尚未采集寄存器，不是实测 MDSS/DSI/PHY 都为零；本次没有执行显示停机。

离线核对原候选打包 DT：root compatible 与八个窗口的路径、地址和尺寸都与代码
相符。经当前 U-Boot USB fastboot 只读获取的缓存 con 日志覆盖了晚期 slot claim，
未包含足以区分该失败的资源信息；没有从这些日志推断具体是哪项不匹配。

r2 诊断修订保持同一停机序列和严格检查条件，增加缓存资源检查报告：

- `resources=root/window/i2c-node/i2c-bus/i2c-chip/ready` 指出检查/获取的环节；
  `error` 为该层错误，`bad` 为首个失败窗口索引（无窗口失败时为 -1）。
- `dt-match` 记录两项 root 匹配和节点存在位图；`dt-compatible0..2` 记录实际
  控制树前三项 compatible（单项最多 43 字符）。
- `dt.gcc/dispcc/mdss/mdp/dsi0/dsi1/phy0/phy1` 记录八个窗口实际解析的地址/尺寸。
  所有窗口均在 probe 或 MMIO 前检查，失败报告不会把未执行项伪装成硬件快照。

报告共 30 行，仍在 host helper 的 32 行上限内，status 只读缓存。新增测试直接
执行实际 `display_resources()` 和报告函数，覆盖 root、每个窗口的缺失/错址/
尺寸不足、I²C 节点/bus/chip 失败、纠正后的重试、长 compatible 和报告长度限制。
原测试将 provider 获取整体替换成 stub，未覆盖这层，这是本次补齐的测试缺口。

下一次只需先执行 prepare 并保存完整 JSON；这份原始反馈尚不足以放宽检查或
改变停机顺序。本机证据在 `/tmp/liuqin-display-prepare-enodev-20261114/`。

r2 已通过三个针对性 checks、完整交叉构建和 flake 全系统求值检查。独立窄审查
未发现 P0/P1/P2，指出的跨次诊断残留也已修正：资源拒绝清空旧 host/raw-error，
终态 FAILED 则继续保留原证据；真实 OEM 入口测试覆盖了这两个分支。
最终打包 DTB 与 r1 逐字节相同。尚未获得 r2 的真机 prepare 结果，未宣称解决 ENODEV。

```text
out/liuqin-uboot-display-handoff-20261114-r2.img
SHA256 a63e744fdd1677b6c43ba328e1f8d6861f8c2493d99c7adb1891f8a3469e5913
/nix/store/fd2bbbhafqf70s5n1c7r6kvh16fw0qkz-liuqin-bootimg-2024.10+a4f9d7fc+liuqin/boot.img
```

## r3：修正运行时控制树的板型识别

r2 真机报告明确拒绝点是 `resources=root`；八个窗口都匹配（`nodes=ff`），
实际 root compatible 为 `qcom,cape-mtp`、`qcom,cape`、`qcom,mtp`，因此原先两项
Xiaomi/SM8475 匹配都为 0。这确认了软件识别条件错误，还没有进入 I²C probe、
显示访问检查或停机。根属性从打包 DTB 到运行时发生了变化；本轮未定位具体的
固件改写指令，不能仅凭这个报告认定是哪一条 DTBO 或哪个 ABL 函数造成。

r3 在 U-Boot 专用 DTS 增加 `/display-handoff` 节点，使用
`compatible="xiaomi,liuqin-abl-display"` 明确选择本板的固件显示退出合同。
资源检查要求节点存在、启用且 compatible 匹配；root 字符串保留为诊断数据。
仅有通用 Cape/MTP 字符串无法选择 liuqin 的板级停机操作。合同检查位于缓存
I²C 句柄捷径之前，随后仍要通过全部窗口、时钟和真实硬件版本/状态检查。
不会为了身份识别去回写控制树的 root 属性。

报告仍为 30 行，`dt-match` 行增加 `cfg`：固件 root 被改写时允许出现
`cfg=1 board=0 soc=0 nodes=ff`。`resources=contract`、`cfg=0` 则意味着该专属
节点不存在、被禁用或不匹配，继续拒绝并保留报告。

新增回归覆盖用户真实的 Cape 三字符串：有合同通过资源识别，无合同拒绝；
Xiaomi root 同样不能绕过缺失、禁用或错误 compatible 的合同。八窗及 I²C 错误
仍拒绝。这里修改的是控制树策略，重新加载的 Linux FDT 仍须有 `xiaomi,liuqin`，
并新增了 Cape Linux 目标树被拒绝的测试。

构建阶段用 fdtget 断言编译 DTB 含专属合同；主代理还检查最终打包 DTB。
这些只能证明交给固件之前节点存在，ABL 之后是否保留仍须 r3 的实际 `cfg` 读回。
本轮结果与原始验证记录在 `/tmp/liuqin-display-identity-20261114/`。

r3 已通过主代理和独立 reviewer 的三个 targeted checks、交叉构建、全系统
flake 求值及 dry-build；最终打包 DTB 的合同 compatible/status 也已用 fdtget
核对。未执行 r3 真机 prepare 或停机，尚不宣称硬件交接已验收。

```text
out/liuqin-uboot-display-handoff-20261114-r3.img
SHA256 5fe2e7b6258a6e4f1f6618de0ddd6d94fe3bb4b0e50621a38c1a6e53df147040
/nix/store/d4mzckyswfvpisv9fwa01zzc3hfgkqfm-liuqin-bootimg-2024.10+a4f9d7fc+liuqin/boot.img
```

## r4：实际 8.5 版本、完整只读采点与 VIDEO_BUSY

r3 真机已通过合同、八窗与访问时钟检查，读到 `mdss=80050000` 后被旧 8.1 条件
拒绝。复查发现 C3/C6/C8/C9 的原始日志和 KMS top dump 早已包含 `0x80050000`；
Linux 的打印来自 MDP `mmio+0`。最初把 `dpu_8_1_sm8450.h` 的 catalog 名称当成
本机精确硬件 revision，是实现核对错误，并非新出现的硬件异常。

[原始证据摘要](research/display-handoff-runtime-2026-11-14/revision-evidence.json)
记录各历史日志 hash/行号、DisplayDxe hash、版本分派和常量比较：

- 固件 8.1/8.5 分派分别到 `0x36a10` / `0x3746c`；两个 HAL 都调用同一
  `0x36d6c` 初始化布局，16 处引用的常量块逐字节相同。
- 时钟资源链对 minor1/5 都是 `0x3fbb8+minor*16+8 → 0x3fb98 → 0x3f9b8`。
  因此 8.5 使用这套已分析布局有直接依据，不是把新读数盲目追加进允许列表。
- 资源合同现在严格选择本板的 MDSS/MDP 8.5；DSI raw `+0` 仍按固件检查 2.6。
  历史 KMS 的 DSI base 已加 4，logical `+0x1f0=03000104` 属于另一个版本寄存器，
  不用它覆盖 raw `+0` 的版本识别。
- 固件 KTZ 初始化表 `0x46413` 写 bias=`9f`、BL=`7f`；Linux 历史 BL=`5f`。
  两者都测试按原值清 bit6，保留其余配置。

独立复查另发现此前停机顺序的 P1：实际 Linux `dsi_host.c` 明确说明禁用 INTF
后 video engine 可能不停止，需要 reset 才能发送 off 命令；固件在有限 busy
等待后也继续 reset。原实现在 reset 前要求 VIDEO_BUSY 清零，会把正常情况判为
终态超时；旧模型却模拟成 VIDEO_EN 清零后自动 idle，掩盖了这个错误。

现在 reset 前只确认命令工作（STATUS bits0–2）结束；video/global busy 可保留至
reset，reset 后再有界检查 bits0–4 全部 idle。命令仍在途或 reset 后仍 busy 均
失败。新增模型默认“只有 reset 才清 VIDEO_BUSY”，并覆盖 reset 后仍 busy 的超时。

prepare 先读取 MDSS、MDP、两路 DSI 的独立 ID，然后验证布局；未知 ID 不读
模式相关寄存器。布局确认后先采集两路 host/PHY、全部原始错误状态和 KTZ，再判断
状态。历史 Linux 后采点中两路 TIMEOUT_STATUS=1 并不能证明原始 ABL 状态也如此；
r4 只记录并拒绝有效错误，不擅自清掉或放行继承 latch。

报告增加 MDP 版本、两路 PHY/FIFO/ACK/TIMEOUT/CLK 原始状态、其它 INTF 状态，
以及缓存的 `last-read` 窗口/偏移/值/错误码；仍不在 status 中读 MMIO。共 32 行，
符合 host helper 上限。资源失败通过重新初始化核心状态清理旧采点，终态错误继续保留。
本轮日志在 `/tmp/liuqin-display-revision-20261114/`。

r4 已通过三个 targeted Nix checks、全系统 flake 求值、交叉构建和 dry-build。
独立 reviewer 重跑三个 checks 并复查版本检查、完整采点、reset 顺序、32 行长度
限制和终态缓存，未发现新的代码问题。最终 Android v2 镜像内的 DTB 也已重新提取，
用 fdtget 确认板级合同 compatible/status 均存在。Linux 显示代码未改。

```text
out/liuqin-uboot-display-handoff-20261114-r4.img
SHA256 7541e4ef6dd4441ed9c499b3e856cbe85e9e17e623aab02caa65211709c01f38
/nix/store/bkz35rjv4xyiwqf9bgwmxl1az1br8v6w-liuqin-bootimg-2024.10+a4f9d7fc+liuqin/boot.img
```

用户可从 ABL fastboot 刷写此 U-Boot，再在 U-Boot 菜单中进入 Enable Fastboot Mode：

```sh
fastboot flash boot_b out/liuqin-uboot-display-handoff-20261114-r4.img
fastboot reboot
# 在 U-Boot 菜单中选择 Enable Fastboot Mode 后：
python3 pkgs/u-boot/display-helper.py prepare
```

下一次先核对完整 prepare 报告。实际 DSI ID、reset 后 idle、停机和 Linux 无补救
首次出图均仍待真机验证；本轮没有连接设备、刷写或执行 quiesce。

### r4 发布后的运行版本核对

用户随后再次反馈同一份 30 行、仅含 `mdss=80050000` 的报告。主代理这次连接
USB 只读查询，设备 `version-bootloader=U-Boot 2024.10`、`current-slot=b`；执行
只读 `display-status` 重新发布报告后仍为 30 行，且没有 `mdp` / `other-intf` /
`last-read` 字段。r4 的报告固定为 32 行；本机解压 r3/r4 的实际镜像 payload，
确认上述三组格式字符串仅存在于 r4。因此这次反馈来自仍在运行的旧实现，不能作为
r4 的 prepare 失败。没有重启、刷写、重新 prepare 或执行 quiesce。

完整 status 保存在本机
`/tmp/liuqin-display-revision-20261114/runtime-identity-after-r4-feedback.json`。
刷写分区不会替换当前内存中正在运行的 U-Boot，验证新镜像前必须重新启动并进入
其 fastboot。`version-bootloader` 只含通用版本号，不能单独区分这些候选。

### r4 prepare 真机通过

用户重新进入新 U-Boot 后，提供了完整的 32 行成功报告，已原样保存在
[`r4-prepare.json`](research/display-handoff-runtime-2026-11-14/r4-prepare.json)。
`state=prepared`、`stage=identify error=0`、`resources=ready`；没有执行停机，
两路 `off-done` / `sleep-done` 都仍为零。本轮主代理只核对用户提供的数据和本地
源码，没有连接设备或发出硬件命令。

该原始 ABL/U-Boot 扫描状态确认：

- MDSS/MDP 均为 `80050000`，两路 DSI raw HW_VERSION 均为 `20060000`。
- 两路 CTRL=`1f7`，INTF1/2 enable/status 均为 1；其它两个 INTF status 为 0。
- master/slave PHY CTRL 都为 `7f`，PLL 分别为 `1` / `0`，符合共享 master PLL
  的检查条件。这里没有要求 slave 另启一个 PLL。
- 单颗 KTZ ID=`21`、bias=`9f`、BL=`7f`，与固件初始化表一致。
- 两路 TIMEOUT_STATUS 和 ACK_ERR_STATUS 均为 0，IRQ ERROR bit24 未置位。
  `phyerr=88888` 与定义错误掩码 `11111` 的交集为零；`fifo=1210` 与
  `cccc0480` 的交集为零；`clk=8067c3` 的 PLL unlock bit16 也为零。
  原始寄存器非零不能直接等同于错误。
- 两路 STATUS bit3（VIDEO_BUSY）均为 1，命令工作 bits0–2 均为 0。
  这是停机前的扫描采点，尚未证明停掉 INTF 后 busy 会如何变化或 reset 是否有效。
  DSI0 额外 bit13 也有保留，当前没有赋予它未经证实的含义。

下一步为一次 `display-helper.py quiesce`，执行时会再次做 prepare。成功应为
`state=quiesced`、`stage=done error=0`、`off-done=3 sleep-done=3`；屏幕熄灭
是预期，但本地发送完成仍不证明面板收到命令。报告中的寄存器继续是停机前快照。
无论成功或失败，先保存完整报告和用户视觉观察，再安排恢复或 Linux 验收；不要
通过反复执行或提前重启丢掉失败阶段。无需为这次通过修改代码或重建镜像。

## r5：先门控链路，再停止 PHY PLL

用户随后执行一次 quiesce，完整报告保存于
[`r4-quiesce.json`](research/display-handoff-runtime-2026-11-14/r4-quiesce.json)，
并明确反馈“全黑”。结果为 `state=failed`、`stage=clocks error=-110 host=1`、
`off-done=3 sleep-done=3`，最后读回 `dispcc+8004=00000000 rc=0`。

由 r4 实际序列可知，两路 INTF 停止、host reset 后 idle、四个本地 DCS 完成、
最终 host/PHY 关闭及 KTZ standby/LED enable 清除读回已通过。失败的是首个
`DISP_CC_MDSS_PCLK0_CLK`：SW enable 已为 0，但 CLOCK_OFF bit31 始终没有置位。
其余七个 link gate 尚未尝试。r4 此时的 `host=1` 是前一阶段遗留的主机序号，
不能据此说 pclk1 失败。画面全黑和本地 DCS 完成不证明面板收到了命令或交接完整。

### 顺序依据与推断边界

r4 先把 PHY PLL/CTRL 关闭，再等待由 PHY 供时的 pixel/byte 分支给出停钟确认。
这违反了先停止消费者、再停止时钟源的依赖顺序：源先停会使后续的停钟握手失去
时钟。这个原因与当前 `enable=0, CLOCK_OFF=0` 相符，但报告没有采集完整时钟
状态机，**仍属于有源码依据的根因推断，不能当作硬件内部原因已测定**。

- 本地 Linux 7.2.5 `dsi_manager.c:dsi_mgr_bridge_post_disable()` 先调用
  `msm_dsi_host_power_off()`，再 `dsi_mgr_phy_disable()`；前者通过
  `dsi_link_clk_disable_6g()` 关闭 pixel/byte interface/byte/escape clocks。
- `dispcc-sm8450.c` 将 pclk0 的 enable/halt 都映射到 `0x8004`，branch2 的
  disable 确认使用 CLOCK_OFF。没有证据支持把这个普通分支当成 voted gate
  或无条件忽略 CLOCK_OFF。
- 两路 PHY 的 `sm8450.dtsi` clocks 是 `iface=DISP_CC_MDSS_AHB_CLK` 与
  `ref=RPMH_CXO_CLK`；`dsi_phy.c` 将 iface 加入 runtime PM，并在 PHY disable
  的 MMIO 完成之后才 runtime put。pixel/byte/escape gate 不等于 PHY APB 的
  AHB 访问时钟。r5 明确保留 AHB/GDSC/XO，只允许随后访问 PHY APB。
- dump 的 `0x124b8` 调 Display_Close，`0x124cc` 释放 DSI clock group，之后
  `0x12530` 才调用 Device_Close/PHY shutdown。这支持 API 层顺序；实际分支
  仍受引用计数及 SetClockFreqHz 的 19.2 MHz 请求影响，不能声称 r5 逐条复现了
  ClockProtocol 的全部硬件行为。

### 修正与验证

r5 使用明确的 `host → link gates → PHY → bias` 顺序。命令和所有 host/DPU
访问先结束，PLL 保持运行直到全部八个 CBCR 确认 `enable=0 && CLOCK_OFF=1`。
随后只通过保留的 AHB 关闭 PHY，最后 KTZ standby；不修改 parent RCG，不重新
打开已关闭的 PLL，不通过更长延时或放宽条件将超时变成成功。

报告仍为 32 行，原完成掩码行增加 `gates-done`；按当前 gate 表顺序，只有一个
gate 真正读回确认后才置对应位，全部完成为 `ff`。失败阶段的 host 也按当前
gate 所属 link 更新；FAILED 重试不清除证据。该掩码记录成功步骤，不表示
在报告期间重新读取了 CBCR。寄存器表仍是停机前快照。

新的时钟依赖模型保留“源先停时 HALT 状态不更新”的约束。用保留的 r4 原始
core/header 执行，重现 `-110 / stage=clocks / gate1 / 8004=0`；r5 通过。
这用于检验依赖顺序，不是对真实 CBCR 内部状态机的独立证明。

全新 reviewer `/root/display_clock_order_review_fresh` 在实现完成后独立复查，
没有发现 P0/P1/P2；独立跑最终三个 targeted checks 均通过，包括 383 个逐点
I/O 故障和 16 个卡住/错误场景。主代理本轮没有连接设备、刷写、重试 quiesce
或重启。构建与模型日志保存在本机 `/tmp/liuqin-display-clocks-20261114/`。

主代理的三个 targeted checks、全系统 flake 求值、U-Boot/boot.img 交叉构建与
dry-build 均通过。最终 Android v2 镜像已解压确认包含 `gates-done` 报告格式，
重新提取的 DTB 合同 compatible/status 也已用 fdtget 验证。Linux 代码未改。

```text
out/liuqin-uboot-display-handoff-20261114-r5.img
SHA256 37fd15ea6abdf34b6814e9162f8f8924eea494d1c6e4bbc9d0e29834b039c094
/nix/store/ign2gr265wxgvhn17c5s99jwvx0j3qhi-liuqin-bootimg-2024.10+a4f9d7fc+liuqin/boot.img
```

当前 r4 已进入 FAILED，恢复应由 `fastboot reboot bootloader` 回到 ABL，再刷
此候选并重启。在新 U-Boot fastboot 中先 prepare，确认报告含 `gates-done=00`，
通过后再执行一次 quiesce。成功应为 `state=quiesced`、`stage=done error=0`、
`off-done=3 sleep-done=3 gates-done=ff`；保留完整结果后再安排后续验收。

### r5 手动停机合同真机通过

用户提供的完整成功报告保存于
[`r5-quiesce.json`](research/display-handoff-runtime-2026-11-14/r5-quiesce.json)，
随后确认“已完全熄灭”。fastboot 记录本次操作约 93 ms：

- `state=quiesced`、`stage=done error=0`，已执行到最终阶段；
- `off-done=3 sleep-done=3`，两路的 DisplayOff/SleepIn 本地发送均完成且检查无错；
- `gates-done=ff`，全部八个 link gate 都在 PLL 关闭之前读回 enable=0 且
  CLOCK_OFF=1；旧的首个 pclk 超时已不再出现；
- 随后的 PHY PLL/CTRL 关闭和 KTZ standby/LED enable 清除读回也通过，
  最后一次 MMIO 是 `phy1+24=0`。93 ms 包含规定的 70 ms / 10 ms 等待。

因此可以将 **r5 手动 helper 的 quiescence 合同**记为已通过。这个结果进一步
支持 r4 时钟依赖顺序有误的诊断，但仍不是对 CBCR 内部握手机制的直接测量。
报告中的 MDSS/DSI/INTF/KTZ 表是停机前快照，不能误读为停机后仍在扫描；
光学灭屏也不等同于对每个 DCS 的面板 ACK，当前合同仍只承诺本地发送和上述读回。

手动 quiesce 之后 console 不能恢复借用扫描。下一步由操作者执行：

```sh
fastboot reboot bootloader
# 回到 ABL fastboot 后重新启动 r5：
fastboot reboot
```

随后在 U-Boot 选择 Boot NixOS，让真实 Linux GO 自己准备目标 FDT 并执行相同
停机序列。不能用手动 quiesce 后的 fastboot continue 代替：USB exit guard
会恢复到 ABL，避免返回不可用的菜单。

正常启动后先只读核对 `/proc/device-tree/chosen/liuqin,display-handoff` 是否为
`quiesced-v1`（末尾 NUL），确认真实 GO 的 FDT 发布路径。当前已提交 Linux
内核保留 1.5 秒自动 DPMS cycle，所以这一轮普通启动只能验证正常启动/交接标记，
其后的亮屏不能独立证明首次出图已修复。严格验收需要同一 7.2.5、同一 DTB、
仅关闭自动恢复的测试内核，并与 ABL 直启对照。

本次主代理只保存用户反馈、复查本地正常 GO/USB guard 路径并更新文档；没有
重新连接设备、发硬件命令、编译或部署新的 Linux 配置。

### r5 正常 GO/FDT 已通过，Linux 仍黑屏

用户正常启动后报告“好像没有自动亮起”，并要求 SSH 检查。本次通过
`seeker@100.4.1.3` 只读采集内核日志、DRM 软件状态、背光和 KTZ regmap、
GPIO/regulator 状态。证据摘录及原始日志 hash 保存于
[`r5-linux-black-screen.json`](research/display-handoff-runtime-2026-11-14/r5-linux-black-screen.json)；
完整原始数据在本机 `/tmp/liuqin-r5-linux-20261114/`。

本次 boot ID 为 `d9596ff0-dba0-4e3f-b88a-61425abaabd0`，运行已提交 LPASS
修正版 7.2.5：

```text
/nix/store/kbqp3z1cqqf94ha117mcwva6xz7azpj2-linux-aarch64-unknown-linux-gnu-7.2.5/Image
/nix/store/6wyapnnkcg9fwg0p1byqkgas4cqh1z9k-nixos-system-Hippogriff-26.11.20261111.d4f25a3
```

live DT 的 `/chosen/liuqin,display-handoff` 确为 `quiesced-v1`；命令行的
`earlycon=simplefb` 已移除。这验证了正常 Linux GO 的停机成功和 FDT 发布，
不只是手动 helper 路径成功。

内核自身的 monotonic dmesg（不是 journald 接收早期缓冲的时间）记录：

| 时间 | 事件 |
| --- | --- |
| 1.918824 s | msmdrmfb 注册 |
| 2.028705 s | 触摸 follower resume #1 开始；固件下载成功，但 ReK 一直为 `a0` |
| 3.418747 s | 第一次 ReK 超时，IRQ/ESD fail-closed |
| 3.422510 s | 原有 1.5 秒 fbdev 自动 pipeline OFF/ON 确实执行 |
| 3.611494 s | panel unprepare |
| 4.454463 s | panel prepare |
| 4.462816 s | follower resume #2 开始，第二次固件下载也成功 |
| 5.558210 s | 第二次 ReK 同样超时，IRQ/ESD 继续关闭 |

因此这次不能解释为“没有触发自动补救”，也不能继续用内核里的固定 cycle
作为可用回退保证。早期硬件初始化异常在 GDM 约 11.8 s 启动之前已经出现。

当前读回还有以下边界：

- GDM active；DRM CRTC active=1，模式 1800×2880@120，主 plane 挂接
  gnome-shell 的 framebuffer。DSI sysfs 为 connected/enabled/DPMS On。
  这些证明软件已提交显示状态，不能据此宣称物理扫描或面板接收正确。
- 背光软件 brightness/actual_brightness 都为 1500，bl_power=0；KTZ 实际
  regmap 读回 `08=5f`、`09=9f`、`0f=00`。偏压配置已从 U-Boot 的 `98`
  恢复，不能把当前黑屏归结为 Linux 忘记恢复该配置。
- TLMM GPIO0（reset）以及 GPIO2/6/53/66/93 的当前读回均为 high；四路
  固定 regulator 的软件使能仍在。当前电平/名义电压不能证明上电、复位波形
  或实际模拟输出正确。
- `disp_cc_mdss_mdp_clk_src: rcg didn't update its configuration` 和 RPMh
  `tcs_tx_done` 警告在 C9/C8 等旧记录也存在，并非本次才出现。不能仅凭
  相同日志就排除它们对硬件状态的影响，也不能将其直接定为 r5 新引入的问题。
- 上一个 Linux boot 实际为 C9 诊断镜像 `2i3636…`，带 trace/force_long
  参数；本次是 `kbqp3z…` 正常镜像。前一轮第二次触摸 resume 能成功，不构成
  这次交接改动的同内核/同 DTB 对照证据。

本次没有读 `clk_summary`：已知 PHY 的 recalc 路径会写 bias/mux，不能把这类
操作当作无副作用的读回。空闲两秒内 MDSS/DSI IRQ 计数未增长也不能证明停扫，
因为 vblank IRQ 可以关闭。本轮没有发起额外 modeset，黑屏现场保留。

该次时钟修复前的结论是 **r5 完成已定义的停止合同，但该合同尚不足以保证现有 Linux
重新点屏**。现有证据不能把 panel/TDDI、DSI、DPU/时钟中的任一项唯一定位为
根因，也不能仅归咎于 GNOME。下一项有判别力的验证应使用同一内核与 DTB 的
ABL 直启对照，并比较 Linux 最早初始化前后的资源/复位/链路状态；不能恢复
整个 stash、叠加自动重试或继续仅靠可发送 DMA_DONE 宣称完成了固件全部退出。

### 后续离线驱动对照

后续离线驱动对照补充了真实运行源码与dump中显示/触摸/时钟模块的逐项证据。原厂Cape PLL配置会
保留正在运行的PLL；当前SM8475 OLE无此保护，而且在MDP shared-init parking之前
配置PLL。r5保留parent/MDP/GDSC，所以这一更早的Linux接管差异应优先采证，尚不能
将0.146s RCG超时定为根因。报告还核对了供电所有权、原厂13批命令、DSC四字节差异、
宽度域与触摸late通知，并给出按最早失败边界选择单个修复变量的路线。
该轮只做离线研究和复算，没有进一步真机操作或生产代码修改。

后续已经完成上述时钟方向的 c1 对照，结果见本文开头及
[0027/0028 说明](../pkgs/kernel/patches/README.md)。本段保留其原始调查时序。
