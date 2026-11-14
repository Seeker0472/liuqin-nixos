# liuqin 显示交接：ABL、U-Boot 与 Linux 的系统调查

日期：2026-11-14。范围：实际分区 dump、系统 ROM、固定版本 U-Boot、原厂显示模块、
主线 7.2.5，以及已有调查和 C2–C9 原始记录。本轮只做离线调查，没有访问平板、
部署、重启或进行新的试屏。原有运行/下次启动配置记录见
[停止时状态](../TODO/DISPLAY-HANDOFF.md)。

## 结论与把握程度

**可以确认，当前链路缺少明确的显示交接过程；尚不能确认造成黑屏的唯一硬件状态。**
用户已明确确认：ABL 直接启动能出图的对照使用相同的 7.2.5 内核和输入 DTB。
这显著加强了启动前状态差异的解释，不能再把问题泛化为“这个面板初始化表一定错了”。

实际固件和源码形成了以下证据链：

1. ABL 有保留 splash 和请求显示关闭两种路径。正常保留时，后续软件得到的是仍由
   固件配置过的显示链路；关闭路径调用真正的 DisplayDxe，不只是擦 framebuffer。
2. U-Boot 的菜单驱动借用 ABL 的 framebuffer，没有初始化或退出 DPU、双 DSI、
   PHY、PLL、面板的实现。菜单能显示，说明旧链路仍可扫描，不能证明已完成硬件接管。
3. 原厂 Linux 对这种状态实现了专用 continuous splash 接管，登记已有资源并跳过
   部分破坏性初始化。当前主线从软件 OFF 状态开始，执行 BCR、PLL probe、PHY/host
   重配和 panel prepare；它没有等价的连续接管，也没有先执行固件的有序关闭。
4. 找到了比首次 modeset 更早的具体操作：PLL 注册和频率读取会切换 bias/mux。
   旧版删除 initial PLL save 后，这些写入仍存在；此前实验没有排除这一阶段。

因此，证据最集中的解释是：**一条仍承载固件显示状态的链路，进入了没有统一状态
继承或退出协议的 Linux 初始化。** 这解释了为何菜单正常、同核直启正常、经菜单
首次失败、Linux 自己完成一次 OFF/ON 后恢复；但仍未证明 PLL、DSI、偏压或面板中的
哪一个状态是故障的必要或充分条件。不能把这份调查当作某个新补丁已获验证。

## 材料身份：先消除版本混用

| 材料 | 核对结果及用途 |
| --- | --- |
| `liuqin-stock-dump` | 2026-09-20 抓取的 OS2.0.4 / Android 15；此次重算 12 个相关镜像的 SHA256，均匹配原清单 |
| 实际 ABL | `abl_a`、`abl_b` 相同，SHA256 `430d7505414b880fdd4b8e57b3c0275d127604844d0259f64e4ac7e9cfc67293` |
| 实际 UEFI | `uefi_a`、`uefi_b` 相同，SHA256 `6032e749c3204f52d7f988ff063410d97af8385fbff70d0486120cb4a4124538`；实际 DisplayDxe 从这里提取 |
| dump 原厂显示模块 | 从 `vendor_boot_a.img` 重新解包，`msm_drm.ko` 为 5.10.160，SHA256 `20d0067a1ebda29967854fd5e90f377efbac397ee53c79dbaa4713effa08e8a7` |
| 旧 ROM、旧提取模块 | V14.0.9 / Android 13；已有两处 `msm_drm.ko` 为旧 5.10.81，不能当作 dump 模块 |
| `Xiaomi_Kernel_OpenSource` | 本地 `techpack/display` 实现缺失，不能把这个仓库名当作已拿到完整显示源码的证据 |
| U-Boot 基线 | 实际 BSP 固定 `a4f9d7fccf2cd2fc68b8496d723cd92fd16ff80f`；重取源并验证 NAR 与 Nix pin 一致，13 个补丁无 fuzz 应用 |
| 旧 U-Boot checkout | HEAD `918b1f3…`，与当前固定基线不同；旧 `.config` 也不能冒充当前构建结果 |
| 主线源码 | C5 保存树、当前 BSP 0001/0003、HEAD 正常回退版及 `2f148f4` 历史版本分别核对 |
| Android 日志与最终 DT | 用来交叉核对 M81_42 和原厂参数；不是本轮主线故障的最终 live DT |

完整输入哈希、提取方法和关键反汇编摘录在
[证据目录](display-handoff-2026-11-14/README.md)。此次没有读回当前平板 boot 分区，
所以 U-Boot 结论严格对应已核实的 BSP 构建源；不宣称完成了当前闪存镜像的逐字节核验。

## ABL 的 splash 决策：旧结论需要补全条件

从实际 ABL 解压后的 PE 定位到 splash 更新函数，再根据指令和调用关系核对，
并非只搜索到字符串就给函数命名。关键地址采用 **PE RVA**；PE 位于解压结果
`0xb8`，不能把解压文件 offset 原样当作 RVA。

实际决策如下：

| 条件 | 实际行为 |
| --- | --- |
| 读取 `DisplaySplashBufferInfo` 失败 | 直接返回，不执行本函数的关屏分支 |
| 变量读取成功，找不到 `/reserved-memory/splash_region` | 请求 `DisplayPowerStateOff` |
| 找到节点，`reg` 长度为 16 字节 | 更新 splash 地址/尺寸字段，保留此路径的显示状态 |
| 找到节点，但 `reg` 缺失或长度错误 | 返回错误；这里不调用 Off，调用者也未据返回值关屏 |

此处不检查节点的 `status`。**只把 `splash_region` 标为 disabled，并不等于让 ABL
执行关闭。** Linux DTS 的 `linux_splash@b8000000` 和 U-Boot DTS 的
`splash_region@b8000000` 可能因此改变 ABL 的选择；但是修改 U-Boot 后面才装载的
Linux DTB，不能让已经退出的 ABL 再执行一次决策。

带 unit-address 的匹配也已核对：离线执行实际 ABL 节点名比较器及其比较/扫描
机器码，`splash_region` 能匹配 `splash_region@b8000000`，不能匹配
`linux_splash@b8000000` 或 `splash_region2@b8000000`。这是具体比较器的静态仿真，
不是实际启动分支的动态记录，详见归档仿真输入和结果。

实际 ABL RVA `0x2a8f4` 附近装载路径，`0x2a904` 判断查找结果，负值路径
`0x2a960` 调用显示关闭包装函数 `0x2cd30`。后者通过协议 GUID
`f352021d-9593-4432-bf04-67b9f3b76008` 请求 Off；已追到真实 UEFI DisplayDxe
协议表和处理函数。变量的 GUID 另有用途，不能误标为 DisplayUtils 协议。
详见 [ABL / UEFI 逆向记录](display-handoff-2026-11-14/abl.md)。

这是静态调用关系。旧的 ~1.9 秒直启记录和用户本轮同核确认支持它的解释，但现有
档案没有保存成功/失败对照的全部最终 FDT、固件变量返回值及成对镜像哈希。
不能把“按这个 DT 设计应走此分支”写成“本轮已动态抓到此分支”。

ExitBootServices 本身也不意味着关屏。DisplayDxe 的退出事件根据显示状态/标志
决定是否 deinit 和释放资源，可以为 continuous splash 保留显示；它与 ABL 在 DT
更新时显式请求 Off 是两条不同的路径。

## DisplayDxe 的关屏，比 reset 或清屏多做了什么

已经从 dump 的 UEFI 提取真实 DisplayDxe、M81 两款原始 XML，并把 ABL 的协议调用
接到实际 Off 分支。函数名由调用、字符串和公开同族代码辅助恢复；原始 RVA 和
关键指令在子报告中保留。以下是活动视频屏需要转到 Off 时的正常分支；重复 Off、
旁路和引用计数未归零时另有跳过/保留条件。

```text
ABL 请求 DisplayPowerStateOff
  → DisplayDxe SetDisplayPowerState
  → MDPDeInit
      → MDPStopPipe
      → MDPPanelDeInit
          → 调整 host 控制状态并执行 host soft reset
          → 解释 M81 DSITermSequence，向双控制器发关屏/休眠命令
          → Display_Close、释放 DSI clock 引用、Device_Close / PHY shutdown
  → MDPPower(off)：板级 M81 关电处理
  → 后续 power property / clock termination
  → ABL 完成退出并进入载荷
```

M81_42 XML 的终止序列为：

```text
FD 03       固件解释器设置双控制器 mask=3，不是发给面板的 DCS 包
05 28       Display Off
05 10       Sleep In
FF 46       固件延迟 70 ms
```

FD 的 bit0/bit1 遍历和 FF 延迟乘 1000 后进入微秒 Stall，均已从解释器确认。
这条路径包含停止扫描、面板命令、链路关闭、板级偏压和时钟处理；不能用
“framebuffer 清黑”“只停 controller”或“只 toggle reset”替代其语义。

在已选择的 DSI backend，Device_Close 会依次将 `PHY_CMN_PLL_CNTRL` 和
`PHY_CMN_CTRL_0` 写 0；MDPTerm 通过资源表释放显示 clocks/GDSC 引用。
这些动作有明确调用和寄存器证据，但 clock API 的调用仍受引用计数控制，不能把
顺序直接抄成若干次无条件 disable。部分 HAL/host 寄存器尚未命名，**未证明 ULPS
进入/退出握手**，不能把整个序列当作已经可等价移植的停机实现。

同时，**它并不是已证明的五路完整冷断电**。M81 板级 off 回调可确认的操作包括
两次 GPIO `ConfigGpio(DISABLE)`、给两个 KTZ 写 `0x09=0x98`、等待 10 ms。
尚不能把该 GPIO API 直接翻译成物理拉低，也没有据此证明 VDDI 等所有供电归零。

按 [KTZ8866 原厂手册](https://www.kinet-ic.com/uploads/web/KTZ8866/KTZ8866-04b.pdf)
第 22 页表 4，`0x98` 选择内部控制并关闭正负偏压，属于 bias standby 配置；
当前 `0x9f` 选择外部 ENP/ENN 控制。两者的关闭实现不同。这是寄存器配置的解释，
不是实测电压波形，也不是让我们直接去改写 `0x98` 的修复依据。

## 三条路径的真实区别

下表组合了静态实现与用户观测，不冒充新采集的启动 trace。

| 路径 | 交接行为 | 后续软件的状态模型 | 已知结果 |
| --- | --- | --- | --- |
| ABL → 同一主线 Linux | 按上述变量/节点条件可先执行 DisplayDxe Off | 若 Off 分支成立，Linux 面对已执行固件关闭的链路 | 用户确认可正常首次出图 |
| ABL → U-Boot 菜单 | 保留 splash，菜单写既有 framebuffer | 借用固件的扫描和显示配置 | 菜单正常 |
| U-Boot → 主线 Linux | 当前代码没有等价的显示关闭/状态移交 | 主线从软件 OFF 开始分阶段重配固件遗留链路 | 无自动补救时首次黑屏 |
| ABL → 原厂 Linux | 可以保留 splash | 原厂专用 continuous splash 登记/继承资源，跳过部分重初始化 | 有相应实际模块实现；本轮未新增动态验证 |

U-Boot 退出的通用设备清理不会自动补上缺口：`liuqin_video` 既没有 `.remove`，
也没有被该退出流程选中的 DMA/OS_PREPARE 标志；video uclass 也没有关闭显示的
pre_remove。`VIDEO_REMOVE` 开关不能凭空生成停机实现。

还要收紧“U-Boot 只写 framebuffer”的说法：板级 UFS/USB 初始化会设置共享的
PM8350 L5=880 mV 和 PM8350C L10=1.2 V，DSI PHY/host 也使用它们。当前未找到
电压值与 Linux 约束冲突，但这些是实际写操作，不能宣布所有显示相关资源未变。

此外，输入 DTB 相同不保证最终 live FDT 相同。U-Boot 从 extlinux 装载新的 Linux
FDT，改写 bootargs、memory banks、initrd 等；它对内部 OF_LIVE 的 fixup 是另一棵
树。不能把内部删除 RPMh 引用的操作误认为删除了 Linux 的供电依赖。精确调用链和
副作用表见 [U-Boot 审计](display-handoff-2026-11-14/uboot.md)。

## 原厂 Linux 为什么不能拿来类比普通 prepare

从 dump 重新提取的 5.10.160 `msm_drm.ko` 中，已根据符号、重定位和分支确认：

- continuous splash 设置显示状态、clock/PM 资源和控制器状态，登记硬件正在使用的
  CTL、LM、SSPP 等资源；不是认为硬件一开始全部 OFF。
- splash 标志为真时，跳过 PHY 软件 reset、部分 PHY enable 硬件操作、host soft
  reset 和 panel prepare/enable；再执行资源交接与清理。
- 这些专用分支不是普通 Linux OFF/ON。存在实现不等于本轮已观察到每一分支执行，
  但足以证明原厂针对继承显示做了明确的状态和资源处理。

主线已有 MDSS CORE_BCR reset，且在创建 PHY/DSI 子设备之前执行。外部面板、
供电 GPIO、KTZ 偏压并不由这个 API 控制；缺少硬件规格时，也不能声称该 BCR
覆盖了全部 PHY/PLL 模拟状态。再增加一次相同 reset 不是已有证据支持的方案。

原厂模块还存在 TDDI/双击唤醒条件下的 M81 专用供电分支。它说明动态生命周期不能
仅从 DT 五路供电列表推导；不说明这些保留分支在原厂冷启动必然执行，也不自动
否定 C5 的供电所有权改动。详见 [内核对照](display-handoff-2026-11-14/kernel.md)。

## 更早的具体候选：PLL probe 本身会改硬件

在实际 7.2.5 源码中，以下链路位于首次 modeset 和此前 C4 controller quiesce
之前：

```text
MDSS CORE_BCR → 创建 PHY 子设备
  → dsi_pll_7nm_init，软件 pll_enable_cnt 从 0 开始
    → 注册 VCO clock
      → CCF __clk_core_init 调 recalc_rate
        → enable_pll_bias：置 PLL_SHUTDOWNB，SYSTEM_MUXES=0xc0
        → 读取频率寄存器
        → disable_pll_bias：计数回 0，SYSTEM_MUXES=0，清 PLL_SHUTDOWNB
    → C5 的 save_state 再做 enable/read/disable
    → 显式 recalc_rate 再做 enable/read/disable
  ……之后才进入 bridge power_on / 首次 panel prepare
```

HEAD 正常回退版和 `2f148f4` 只是删掉中间的 initial save；注册时和显式 recalc
都仍存在。因此两项旧推论均不成立：

- “不保存 initial PLL 仍黑，所以可以排除所有早期 PLL 干扰”。
- “锁定后 mux 两次都是 `0xc0`，所以 probe 过程中不可能有不同”。

这项发现已经过两个子任务独立核对；关键源码和 CCF 调用保存在
[PLL probe 摘录](display-handoff-2026-11-14/evidence/kernel/pll-probe-source-excerpts.txt)。
它确定的是主动写入与软件引用模型，不是这些写入造成黑屏的因果证明。更早的 BCR
也可能已改变链路；不能声称 PLL 是全系统第一项破坏动作，更不能据此删除 recalc、
伪造引用计数或开始另一轮试补丁。

## 历史结论的修订

| 旧说法或实验 | 本轮可保留的结论 | 必须撤回的扩大解释 |
| --- | --- | --- |
| C2/C3 供电关闭或循环 | 记录中的引用/GPIO确实释放；C3 的具体首次关电实现仍不够 | 已复现 ABL Off；所有电压/放电/复位时序已排除 |
| C4 提前停 controller 仍失败 | 该步骤不足 | 所有比 bridge enable 更早的 probe 操作无关 |
| C4 禁止触摸 probe 仍失败 | 本次 NVT 下载不是黑屏发生的必要直接触发 | TDDI 共享硬件/固件状态无关 |
| C6 DSI1 首次无 payload，恢复后 `08/9a/9e` | 命令读返回有明确差异 | 直接证明物理断电、两路链路都无响应或所有 write 未到达 |
| C7 去掉四个 boot-on 仍失败 | 仅改这四项不够 | 全部供电相关原因已排除 |
| C8 TGEN 入口两次为 0 | 到该 Linux 采点已为 0 | U-Boot 出口原始 TGEN 为 0；更早交接不可能出问题 |
| C9 194 个长包匹配原厂仍失败 | 匹配 Android DT 的请求类型/payload 不足以修复 | 匹配 UEFI 的全部启动行为；线端已成功接收 |
| 第二次 OFF/ON 出图 | Linux 建立状态后的正常关闭/再启动能恢复 | 仅某一条 panel 命令、延迟或电源操作就是根因 |

C6–C9 的状态读取是主动 DCS 访问，不是无副作用的被动快照；C5 没有这些读取时
也已失败。DSI0 的 bonded trigger 还有不触发 read 的限制，不能将它的无返回作为
双路都坏的额外证据。C9 host 入口计数也只证明软件请求。

此次还程序化比较了真正 UEFI XML 与 Android M81_42 的初始化表：UEFI 有 195 个
普通 DSI 包，Android 有 194 个；page `0x27` 的 `D1=28/20` 不同，UEFI 在 page
`0x25` 多一条 `0F 20`。两版系统 ROM/UEFI 的 XML 本身逐字节相同。差异已经保存，
但原厂 splash 和 Android 可以有不同设置，不能据此宣布 Android 表错误或直接换表。

完整逐项审查和新发现的 GPIO116 相关性在
[历史证据复核](display-handoff-2026-11-14/history.md)。

## 架构方向：建立一个可证明的交接边界

当前最适合现有主线驱动的目标是：**菜单期间继续借用固件显示；真正进入 Linux
之前，完成一次有明确前提、顺序和结果的停机；Linux 再执行正常初始化。**
这是建议的目标契约，不是已完成、已验收的实现。它不要求先移植原厂完整 seamless
splash，也不能靠永久取消菜单来满足。

优先评估 U-Boot 的借用显示组件能否以资源受控的小型实现承担释放责任。若需要
复制大半套 DSI/PHY 驱动，应选择 Linux 协调的归一化阶段；不能为了放置位置整齐
而在 U-Boot 堆一套不完整的固定寄存器序列。

若交接由 U-Boot 负责，应将 framebuffer 借用和退出责任放在同一个板级显示组件，
将 DPU/双 DSI/PHY/PLL/偏压的有序关闭作为一次明确阶段：

1. 在仍可返回菜单时，只检查所需资源、映射、寄存器版本和镜像/FDT/initrd 的前提；
   检查失败不改变显示。
2. 确认进入真实 OS_GO，排除 OS_FAKE_GO，且电源/时钟/总线仍可访问，再进行一次
   同步停机并交给 Linux。
   不能把已经停止扫描后的失败当成能正常返回可见菜单。
3. 不依赖通用 `.remove` 传播错误：当前 U-Boot 的 cleanup/board hooks 是 void，
   `dm_remove_devices_flags` 也丢弃 remove 返回值；仅添加回调无法实现可靠的失败契约。
4. ABL 进入载荷前已经退出 UEFI Boot Services；U-Boot 不能调用旧 DisplayPower
   协议来省略实现。实际 ABL `0x16384…0x16398` 调用 ExitBootServices，并在成功
   返回后才于 `0x1ba30…0x1ba50` 以 DT 为 x0 跳到 raw AArch64 载荷，见
   [本机二进制调用链](display-handoff-2026-11-14/abl.md)和
   [UEFI 的服务退出约定](https://uefi.org/specs/UEFI/2.10/07_Services_Boot_Services.html)。

若最终选择 Linux 归一化固件状态，应先明确要避免哪些 probe/clock 副作用，再设计
资源和阶段边界。等到 panel prepare 或首次 modeset，已无法避免前述 probe 对继承
链路的改写，不能再假定收到的是未经改变的固件状态；这不证明晚期完整归一化一定
无法恢复。也不能在已初始化子设备后任意执行整个 MDSS 总复位。不能让 U-Boot、
PLL、host、panel、fbdev 各持有一套独立补救策略。

## 调查尚未证明什么，以及下一步的边界

目前没有下列因果证明：

- 哪一次写入首次让对端无法响应；PLL probe 是具体候选，尚非定因。
- CORE_BCR 的全部硬件覆盖范围，以及调用前后真实 PHY/PLL/面板状态。
- 固件所有 DSI close / clock termination 细节已可逐项等价移植。
- 同核两条路径在完全相同采点的最终 FDT、共享电源 vote、IOMMU/内存状态也一致。

下一步应先完成一个有资源前提和完成条件的交接设计，把 DisplayDxe 已核实的动作
逐项对应到实现层，保留尚未解码的操作，不进行组合猜测。若静态材料确实无法回答
最后一个状态差异，未来取证必须针对 **U-Boot 出口与 Linux 首次改写之前** 的同一
边界，带明确预期和反证；现有晚期 dump 不能代替这个边界。本轮没有实施此取证。

此轮成果是确定交接结构差异、找回真实固件退出序列、收紧历史排除结论，并提供
可追溯的源码/二进制证据。首次黑屏仍未修复；不能据此部署 C5–C9 为日常版本。
