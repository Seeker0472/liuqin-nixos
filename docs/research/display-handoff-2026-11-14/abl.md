# Liuqin ABL / UEFI 显示交接静态调查

> 归档说明：原始工作目录为 `/tmp/liuqin-display-systematic-20261114/abl/`；
> 下文同名证据已归档在 `evidence/abl/`。完整 PE/反汇编可由脚本离线重建。


日期：2026-11-14。范围：读取既有固件、解包、反汇编和公开 ABI 对照。没有连接平板，没有修改 BSP，没有部署或试屏。本文的函数名若没有符号，来自字符串、实参、返回值、协议表和调用关系共同识别；下面的 RVA 是可复查定位，函数名字本身不是调试符号。

## 结论及限制

1. **实际 dump ABL 根据传入 DT 是否保留 splash 区域，确实可能调用一个完整得多的显示关闭入口。** 该入口不是 ABL 自己的 GPIO 函数，而是早于 ABL 载入的 UEFI `DisplayDxe` 的 `EFI_DISPLAY_POWER_PROTOCOL.SetDisplayPowerState(Off)`。
2. **这条入口有前置条件。** ABL 必须先读到 `DisplaySplashBufferInfo` 变量。变量读取失败，或节点存在但 reg 错误，都不会走同一 Off 路径。`status="disabled"` 也不能当作节点不存在。
3. **该 Off 路径具有实际可证明的步骤：停止 DPU 接口，发面板 TERM，关闭 DSI display/device，释放 DSI clocks，关闭 PHY 的 PLL_CNTRL 和 CTRL_0，调用 M81 电源回调，最后释放 MDP 公共 clocks/GDSC。** 并不等同于 Linux C5 候选的五路供电全断。不能把“模仿某几项寄存器写入”说成“已复现 ABL 关闭”。
4. **ExitBootServices 本身不保证关屏。** DisplayDxe 注册的 EBS 回调检查每个显示的 bit24 等状态后决定是否关闭；可以保留扫描和资源以便 continuous splash。必须区分 ABL 的 DT 更新时显式 Off 与 EBS 后台清理。
5. **尚不能由静态二进制单独确定本机黑屏根因。** 用户报告同一 Linux 7.2.5 / DTB 经 ABL 直启正常，使交接边界成为高价值对照；还要与 U-Boot 的实际输入 DT、输出 DT 和交接前硬件状态合并。本文没有运行时记录证明最近一次 ABL 直启实际走了哪一分支，也没有证明 U-Boot 的某一行代码已构成充分原因。

## 固件来源、哈希和地址规则

完整清单在 `manifest.json`；复现入口为 `reproduce.sh` / `reproduce.py`。

| 来源 | 文件 | SHA256 |
|---|---|---|
| 分区 dump | abl_a.img / abl_b.img | 430d7505414b880fdd4b8e57b3c0275d127604844d0259f64e4ac7e9cfc67293 |
| 分区 dump | uefi_a.img / uefi_b.img | 6032e749c3204f52d7f988ff063410d97af8385fbff70d0486120cb4a4124538 |
| 分区 dump | imagefv_a.img | 35b1d5d471da1692d6781a5b72f2521697c6471bad85cdc1b6f3f527df05735e |
| 分区 dump | xbl_a.img | 0e1c07280278f528e07a66cd31c965f95552ea49b705d1f5fa4396e50eb709ba |
| 分区 dump 解包 | DisplayDxe.pe | d6a934cc70f37310984d44757662d5a25ea659f7da84a20425bbdf61260d55b0 |
| V14.0.9.0.TMYCNXM_13.0 ROM | abl.elf | 90163027da1f5c2a61234bf5c28094297e2b25066c0ef2550ac44184dac53a1b |
| 同上 ROM | uefi.elf | 5412df1242821b736353cb690abfefbf1d4385368e5d0d59cc8d4011c1d4f4ab |
| 同上 ROM 解包 | DisplayDxe.pe | 915f7ee9cb6f5219e173481ff4e1596b0e18ea589879c06a4e4eaf174863cc4c |

分区 dump 在 `/home/seeker/Develop/liuqin/liuqin-stock-dump/images`；ROM 在 `/home/seeker/Develop/liuqin/liuqin_images_V14.0.9.0.TMYCNXM_13.0/images`。两者 ABL/UEFI 代码不是同一版本，不能混用 offset。

ABL ELF 是包裹格式；其 0x1078 是 LZMA-alone 数据。解压 966856 字节后，PE 从 **0xb8** 开始，ImageBase 0，.text RVA 和 PE 文件偏移相同。**本文 ABL RVA + 0xb8 才等于解压大块文件偏移**。历史文档“VA 等于解压文件偏移”有这个偏差。DisplayDxe 的 RVA 等于导出 PE 内同一段的文件偏移，不能直接加到压缩 `uefi_a.img` 上。

DisplayDxe FFS GUID 为 `4138022f-06c7-4f79-9c94-7e33b511a4e7`，位于 uefi_a 的第二个嵌套压缩 FV 中。不是 `abl_a` 或 `imagefv` 内的驱动。`imagefv_a` 此处主要是 logo 等素材，UEFI 自身还携带 Panel XML。没有证据把所有这些统称为“ABL 源码”。

## ABL 的 splash 契约

`annotated-excerpts.txt` 的第一组给出了实码。

ABL RVA `0x2a778`：

- `0x2a7f0` 取 runtime services 的 +0x48（GetVariable）。实参为 UTF16 `DisplaySplashBufferInfo`（RVA `0xb3e26`），vendor GUID `882f8c2b-9646-435f-8de5-f208ff80c1bd`，初始 DataSize=12（RVA `0xbe1b8`），返回结构 `{u32 version, u32 address, u32 size}` 到 `0xc2ea0`。
- **该 GUID 是 GetVariable 的 vendor/token-space GUID，不能误叫 DisplayUtils 协议 GUID。**
- `0x2a81c` 检查 EFI_STATUS；失败在 `0x2a880` 跳函数结束；不执行关闭。
- `0x2a8ec` 把当前 DT 地址放 x0，x1 为 `/reserved-memory/splash_region`（字符串 RVA `0xb38a1`），调用 `0x51788` 的 libfdt 风格路径查找。
- `0x2a904` 检查返回值 w0 的符号位；非负跳 `0x2a974`，负值继续到 `0x2a960` 调 `0x2cd30`（关闭），函数返回 `EFI_NOT_FOUND`。
- 节点存在：`0x2a9fc` 查 `reg`，`0x2aa7c` 要求长度16；错误分支仅返回，不执行 `0x2cd30`。
- 正常分支更新 reg 的 address/size **低32位 cell**，并通过 setprop 写回，未见检查 `status` 或任何“Linux display enabled”状态。已有高32位 cell 保留，并不是此函数强制写零。
- 调用者 `0x29210` 调它之后没有测试返回码，接着继续其它 DT 修正。不能凭“最终成功启动”证明 splash 更新成功。

| GetVariable | 节点查找 | reg | 该函数行为 |
|---|---|---|---|
| 失败 | 不执行 | 不执行 | 返回失败，不关屏 |
| 成功 | 负值 | 不执行 | 调显示 Off；返回 NOT_FOUND |
| 成功 | 存在，包含 disabled 也一样 | 缺失/长度非16 | 返回错误，不关屏 |
| 成功 | 存在 | 16字节 | 更新 framebuffer address/size，不关屏 |

**本机实际比较器支持这里的 unit-address 匹配：`splash_region` 能匹配 `splash_region@b8000000`。** `0x51788` 按 `/` 分段，`0x51a78` 迭代子节点，`0x51c64` 调名字比较器 `0x52368`。后者先比较前namelen字节（`0x523c4`），节点下一字节NUL时直接true；`0x52420..0x52434`另有接受下一字节为`@`的分支。对本机常量query `0xb38b2` / len13，这条分支实际成立。因此不能因U-Boot输入叫`splash_region@b8000000`而认为ABL找不到它。

另外发现一个应保留原样的实现细节：`0x5240c` 调 `0x65d74` 时，实参为x0=query,x1=64,x2=13；后者最终调用`0x66034`，机器码将w2当扫描字节、x1当长度。这并非标准libc memchr的参数顺序；这里实际扫描64字节中的0x0d，而不是假设的13字节中的`@`。对此未推广其他query，也没有提出修补这个旁支。窄匹配结论由真实指令仿真再验证：`emulate_name_match.py` / `unit-address-emulation.json` 在Unicorn2.1.4执行原始比较器、CompareMem和ScanMem8机器码，仅替代合法FDT节点指针读取与关闭debug assert，结果 `splash_region`和`splash_region@b8000000`均true，`linux_splash@...`与`splash_region2@...`均false。**这是离线比较器仿真，不是完整FDT解析或设备启动trace。**

## ABL 显式 Off 如何进入 UEFI

ABL `0x2cd30`：通过 BootServices->LocateProtocol(+0x140)，取得 GUID `f352021d-9593-4432-bf04-67b9f3b76008` 对应接口；成功且接口非空才调用接口 +8，传 `(This,1)`。错误只记日志。

DisplayDxe PE：

- GUID 常量 RVA `0x48108`。
- 接口 RVA `0x48370`：revision `0x10000`；+8 指针 `0x36a0`；+16 指针 `0x3a34`。
- `0x1c20` 把该 GUID 放入 InstallMultipleProtocolInterfaces 参数，与 `0x48370` 成对安装。
- `0x36a0` 检查 PowerState 只接受1/2；1为Off，2为Maximum。Microsoft 的公开同 GUID ABI 与布局一致：[EFI_DISPLAY_POWER_PROTOCOL](https://learn.microsoft.com/en-us/windows-hardware/drivers/bringup/efi-display-power-protocol)、[EFI_DISPLAY_POWER_STATE](https://learn.microsoft.com/en-us/windows-hardware/drivers/bringup/efi-display-power-state)。这些是 ABI 依据，不能当成本机实现源码。

正常 active display 从 On 到 Off 的分支 `0x39b8` 循环 active 显示：

1. `MDPDeInit(display)` → stop pipe → panel deinit。
2. `MDPPower(display, off, phase0)`。
3. `MDPPower(display, off, phase1)`。
4. `MDPSetProperty(display,4,off)` 更新状态。
5. `MDPTerm` 释放公共 clocks，失败返回 device error。

状态不变时可跳过第一组动作，避免重复关闭，但 Off 请求仍会进入公共 term 分支。需要保留这些状态条件，不能把每次 Off 调用都画成无条件相同轨迹。

## 实际退出顺序与硬件范围

下表是 dump DisplayDxe 的可复查正常 DSI 视频屏退出路径。`M` 表示 DisplayDxe 全局 `*(u64*)0x54670` 的 MDSS MMIO 映射基址。寄存器名字通过本地 Linux 7.2.5 的 dsi.xml、dsi_phy_7nm.xml 和 dpu_hw_intf.c 对照；原始 offset / 写入值来自固件指令。

| 顺序 | 实际函数 / RVA | 已证明动作 | 尚未证明的部分 |
|---|---|---|---|
| 1 | MDPDeInit `0x1cb50` → MDPStopPipe `0x1f8e4` | 对 panel 的每个接口调用 HAL `0x32a94` 配置关机，然后 `0x33744` 写 `M+0x35000+intf_offset=0`，写同块+0x210=1；后续按刷新率上限轮询接口状态 `0x332a8`，每轮等1ms，默认60Hz时上限约17ms。 | `0x32a94` 涵盖多种接口/模式，未逐一完成所有寄存器解码；`intf_offset` 数组由 HAL 初始化填充，不能把枚举值直接乘0x1000。+0x210具体寄存器名未确认。 |
| 2 | MDPPanelDeInit `0x1dbcc` → `0x13814` | 先对DSI状态有界等待，再在视频接口分支调用property2（重建host控制字）和property13（`0x1404c`→`0x15cec` host soft reset）；非 bypass 分支取 panelinfo+0x330 的 TERM buffer，调用 `0x12d6c`；M81 XML 的 `FD03;05 28;05 10;FF46` 发双路 DisplayOff、SleepIn、等70ms。 | 正常配置依赖 panel 已初始化且非旁路。没有抓取最近启动的 DSI 电气波形。 |
| 3 | DSIDriver_Close `0x12440` → Display_Close `0x149d0` | 清 `M+0x94004+id*0x2000` bit0；`0x15cec` 对 `M+0x94118+id*0x2000` bit0置1后清0（host reset），修改 HS timer 低20bit为300000，并对 +0x941ec 写1再0；`0x15e38` 改 host CLK_CTRL；释放一次对应 DSI clock 引用。 | +0x941ec寄存器名未确认；不是已经证明所有 lane 都进入 ULPS。 |
| 4 | 同上 `0x12440` → Clock group release `0x1ac48` | 按 clock 表反序查 clock ID，计数减到0才调用 DisableClock。DSI group还先尝试把对应 clock rate请求设为19200000。 | ClockProtocol后端实际门控/重置动作未反汇编；不等于已经断了PLL模拟电源。 |
| 5 | `0x12440` → Device_Close `0x146ec` → `0x17f68` → PHY backend `0x180a8` | refcount归零且非skip条件：先写 host控制字（`0x16578`），再PHY backend写 `M+0x9443c+id*0x2000=0`，之后 `M+0x94424+id*0x2000=0`；对照Linux寄存器是 `PHY_CMN_PLL_CNTRL=0` 后 `PHY_CMN_CTRL_0=0`。 | backend由 DSI HW_VERSION major2/minor6 选择（`0x17e90`），其它版本不是相同分支。未证明执行ULPS进入/退出握手。 |
| 6 | MDPPower phase0 `0x1b870` → MDPPlatformConfigure `0xc5e0` case3 → M81 callback `0x106a4` | 两次 TLMM ConfigGpio(DISABLE)，写双KTZ8866寄存器09=0x98，然后等10ms。 | ConfigGpio(DISABLE)的最终引脚电平未通过TLMM后端反汇编或测量证明，不能写“物理拉低reset/TE”。回调内没有C5那样逐一切断GPIO2/93/66/53及VDDI NPA的轨迹。 |
| 7 | MDPPower phase1 | case3检查phase1后跳过相同板级关电回调；common状态清理位于前一个phase0分支返回处。MDPPower还会更新核心clock/bandwidth需求为0。 | 不应把phase0/1画成两次面板电源循环。 |
| 8 | MDPTerm `0x1cc7c` → `0x1ac48` type0,1,2,3,4 | 释放MDP与其它display clock group；type0额外处理common clocks、`disp_cc_mdss_core_gdsc` power domain及NPA带宽引用。 | 计数未归零/skip旗标时有保留分支。不能从表里“有名字”推断所有gate都关闭。ClockProtocol实际power-domain实现未继续反汇编。 |

特别注意：`Display_Close` 里面已释放一次 DSI clocks；外层 DSIDriver_Close 随后还有一次显式释放；Device_Close/PHY shutdown 发生在这些调用之后。这些是引用计数驱动的 API 顺序，不能简单改写成“先disable所有DSI clocks，然后再access PHY”，更不能直接照抄数次 disable 到 Linux。

### Clock 表的确切内容

资源选择函数 `0x1d154` 通过 major/minor 表。8.1 的链：`*(0x3fdc0+8*8)=0x3fbb8` → 表minor1项+8=`0x3fb98` → `0x3f9b8`。

- common/GDSC：`disp_cc_mdss_core_gdsc`。
- common clocks：`gcc_disp_ahb_clk`、`disp_cc_xo_clk`。
- type0 / MDP：`gcc_disp_hf_axi_clk`、`gcc_disp_sf_axi_clk`、`disp_cc_mdss_ahb_clk`、`disp_cc_mdss_mdp_clk`、`disp_cc_mdss_rot_clk`、`disp_cc_mdss_vsync_clk`、`disp_cc_mdss_rscc_ahb_clk`、`disp_cc_mdss_rscc_vsync_clk`。
- type1 / DSI0：`disp_cc_mdss_esc0_clk`、`disp_cc_mdss_byte0_clk`、`disp_cc_mdss_byte0_intf_clk`、`disp_cc_mdss_pclk0_clk`、`disp_cc_mdss_byte0_div_clk_src`。
- type2 / DSI1：同上五项的1号版本。
- type3直接返回；本资源表其它group为空。

这些字符串来自被反向引用的实际资源表，而不是全镜像 strings 命中。具体释放受记录+0x50标志和+0x54引用计数控制。结构和资源表也另存于 `clock-resources-8.1.json`。公开EFIClock ABI对照（并非本机同版本实现）见[固定版本EFIClock.h](https://github.com/edk2-porting/edk2-msm/blob/e1952621f419f8db60ed28271264e1b5184c571d/Silicon/Qualcomm/QcomPkg/Include/Protocol/EFIClock.h)：接口+0x18=DisableClock、+0x30=SetClockFreqHz、+0x60=DisableClockPowerDomain；freq匹配类型3为HZ_EXACT。调用参数与此ABI一致。

### M81 KTZ8866 关闭语义

M81 callback并非仅关背光，也没有完整冷断电：`0x1077c` 设置addr=09、value=98，调用 `0x2e8c4`，该函数对两只I2C handle各写一次。根据[KTZ8866 Rev04b 官方手册](https://www.kinet-ic.com/uploads/web/KTZ8866/KTZ8866-04b.pdf)寄存器09：0x98的 `LCD_EN_MODE=1, EXT_EN=0, OUTP_EN=0, OUTN_EN=0`，意图切到内部控制的bias standby；OUTP/OUTN关闭，boost关闭。**这是配置解读，并非实测电压**；与0x9f使用外部ENP/ENN控制不同。

## 实际 BootServices 退出与载荷入口

这一步也可从 dump 证明，不仅是 UEFI 规范要求：

- ABL `0x1b8fc` 调 `0x16208`，后者通过同一个 `gBS` (`*(u64*)0xc2da0`) 的 +0x38 获取 GetMemoryMap，读取 map key。
- `0x16384..0x16398` 取 `gBS+0xe8` 函数指针，即 ExitBootServices，x0为 `ImageHandle=*(u64*)0xc2d90`，x1为刚获得的 MapKey，执行 BLR。失败时 `0x163d4` 检查错误并回到 `0x16264` 重取映射再试。
- `0x1b908` 检查包装函数返回的 EFIerror；成功才到 `0x1b96c`，继续最后内存/cache/架构处理。
- AArch64分支 `0x1ba30..0x1ba50` 从保存的 kernel entry 取x8，x0=DT，x1=x2=x3=0，BLR x8；32位分支另在 `0x1ba0c`。

所以对于这个 dump 的正常 Android boot raw AArch64 载荷路径，进入 U-Boot/Linux **之前已经成功执行 ExitBootServices**。U-Boot raw Image不是依然持有可用UEFI BootServices的 EFI application，不能假设还能回头 LocateProtocol / 调DisplayDxe完成关屏。该结论仅覆盖上述正常 raw路径，不概括所有可能的EFI chainload或非正常调试入口。

## EBS：单独的条件路径

- DisplayDxe `0x17ac..0x1814` 注册事件类型0x201，Notify函数 `0x154c`，TPL8。
- `0x154c`先取消/关闭相关事件，然后调用 `MDPExitBoot(0x1cd94)`。
- `0x1ce00..0x1ce24` 对active显示读 `panelinfo+0x4c8` bit24，且额外状态=1才执行 deinit/powerdown。
- `0x1ce0c..0x1ce10` / `0x1cf38` 共同决定是否释放公共MDP clocks。某个active display没有该退出关闭位时可以保留。
- M81 XML没有显式 `DisplayPrimaryFlags`；但不能因此断言运行时 bit24必然0，因为其它配置/参数路径仍可能修改flags。

因此，“ABL EBS 会总是关闭屏幕”的历史解释不成立。ABL直启Linux与ABL进U-Boot的差别，应优先检查传给ABL的DT如何使显式 Off 分支被选中；EBS是更晚的另一条条件路径。

## 原始 UEFI Panel XML，与系统ROM的交叉验证

实际导出：

- `Panel_M81_42_02_0b_dualdsi_dsc_lcd_video.xml`，SHA256 `a3e7649ab12793d1656247ecd548313e3d59899b884e12b00bd92a2c27190b0c`。
- `Panel_M81_36_02_0a_dualdsi_dsc_lcd_video.xml`，SHA256 `d8fb21cb7452966bee0cde7066a6e4ecfb55ed828ce9f352c00ff6f37155a99d`。

**两款XML在分区dump和V14.0.9.0 Android13 ROM里分别逐字节一致**。这是内容对照结论，不意味着DisplayDxe实现相同。

42版参数：active1800x2880；H front/back/sync=100/46/2；V26/214/2；120Hz；DSITrafficMode1；controller mapping00/01；DSC1.1 profile4、slice450x20、bitclock1007032320；slave skew=-2 lines。不要只从PanelDescription里过时的1600x2560文字提取分辨率。

`FD03`解释来自parser指令，不是猜测：`0x12e48`比较0xfd；取下一字节&3写全局mask `0x4b530`，mask0被改为1；`0x12fd4`以后按controller序号右移mask检测bit0，再调用对应DSI handle发送。`FF46`用 `0x21928` 先乘1000再调用UEFI Stall，所以单位ms。

`DisplayResetInfo=0 10 1000 10000 0` 通过 `0x13714`被重新排列到reset参数：GPIO来自panelinfo+0x4d0，0为默认reset模式，第一段delay1000us，第二段10us，最后10000us。M81回调 `0x10d74` 的默认分支 `0x10e20`，以及 `0x10e7c` helper，证明正常GPIO输出请求是 **High → 1000us → Low → 10us → High → 10000us**。第五个值在这条M81回调未被读取，不擅自给它命名。GPIO输出请求与真正引脚波形仍有驱动/硬件层间隔；不能拿此XML覆盖Android kernel里另一个已知可工作的reset序列。

## 对历史结论的必要修订

- ABL splash节点缺失不是无条件关屏：先GetVariable成功，且确实找不到节点才调用Off。
- `status=disabled`不是删除节点；reg错误也不等于缺失分支。
- UEFI DisplayDxe与ABL是不同二进制，不可把可见logo、UEFI初始化和ABL DT fixup统归成同一函数。
- 仅有framebuffer保留内存不等于原有显示硬件已完整关闭或被Linux接管。
- Off不是仅写LED，但也不是五路供电全部断开；不应把Linux手动OFF/ON能恢复解释为“已经复现ABL退出”。
- 未追到ULPS的明确写入/握手；本调查不能支持“原厂ABL通过ULPS解决黑屏”。
- 后续实验若只确认TGEN=0，尚未覆盖TERM、host reset、PLL_CNTRL、GDSC/clock引用等其它原厂退出步骤。但既有失败实验也必须列入，不能以这个静态调用链保证某一组合必修复。

## 建议交接给总调查的最小对照项（不在本轮执行）

1. 逐项解析ABL直启Linux时的真实输入DT，和ABL启动U-Boot所用overlay：splash节点路径、unit-address匹配、reg长度、GetVariable是否预先可用。
2. 逐项列U-Boot交Linux前有没有调用等价的DPU stop/TERM/host close/PHY close/clock-GDSC/bias standby；哪些只是把DT或framebuffer复制过去。
3. 若准备修复，先选择“保留continuous splash并一致接管”或“原owner有序退出后cold init”的明确合同，给每一阶段的owner、时钟引用和可验证退出状态。不要把散落的不同策略拼在一起。
4. 一次验证只针对有实码证据且既有失败结果未排除的差异；先设计决定性观测，再谈部署。

## 复现及审阅入口

`./reproduce.sh`通过Nix提供临时Python工具；只读原镜像并在当前研究目录输出。要在新目录独立复现：`LIUQIN_RESEARCH_OUT=/tmp/liuqin-abl-independent ./reproduce.sh`。脚本不连接设备。`manifest.json`列原图和导出组件SHA；`annotated-excerpts.txt`给关键RVA窗口；`abl.disasm`和`DisplayDxe.disasm`用于检查完整上下文。

公开对照只使用ABI/寄存器定义；没有找到与dump精确对应的原厂完整EDK2源树。所有本机行为结论以dump的调用关系为准，版本外的公开代码不能替代该二进制。
