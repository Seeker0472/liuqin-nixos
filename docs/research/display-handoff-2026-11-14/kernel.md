# Linux / 原厂显示接管静态对照

> 归档说明：本子报告原始工作目录为 `/tmp/liuqin-display-systematic-20261114/kernel/`；
> 已归档的同名证据位于 `evidence/kernel/`，完整源码/反汇编工作集仍在原目录。


日期：2026-11-14。本项只读取本地材料、提取固件和反汇编，不访问平板、不构建或部署候选。

## 可用结论

1. 用户已明确补充：ABL 直接 Linux 正常时使用与目前相同的 7.2.5 内核和输入 DTB。应保留这一观测，不能改写成“只是在 Android 上好用”。但是输入 DTB 一样，并不等于 ABL 与 U-Boot 最后交给 Linux 的 live DT、命令行、硬件状态和显示资源相同。
2. 实际 dump 中的原厂 `msm_drm.ko` 有完整的 continuous splash 专用路径：它登记现有显示资源和软件状态，跳过部分 PHY、host 和 panel 的重新初始化。主线 C5 的路径从软件 OFF 状态重置、重新配置，再初始化 panel。两者不能混称为同一种接管。
3. Linux 7.2.5 已有 MDSS CORE_BCR reset；“加一次缺失的 MDSS reset 就能修”与源码不符。该 reset 也不能被当成完成了 external panel 的五路供电、nRESET 或所有 PHY/PLL 状态清理。
4. 找到一个比首次 modeset 更早的具体缺口候选：PHY 的 PLL probe 会主动切换 PLL bias / SYSTEM_MUXES；这不是纯读取。关闭 initial PLL save 的旧补丁仍会在 CCF 注册和 init 显式 recalc 中执行这些写入。旧实验没有排除这条较早路径。
5. 当前还不能由静态分析唯一确定根因。最有依据的问题类别是：继承 ABL 保留显示后，Linux 在缺少统一交接协议的条件下分阶段重置/改写已有链路。具体是 probe 时钟干扰、数字/模拟边界、面板状态或资源交接，必须与 ABL 的实际退出操作继续对齐；现在没有依据直接再堆一项 reset、延迟或重试。

## 材料身份和重要纠正

| 材料 | 本次核对结果 |
| --- | --- |
| `Xiaomi_Kernel_OpenSource` | HEAD `eb49e10028e27fa98856cb5e458c0f0ec5b4554e`。本地没有 `techpack/display`，只有 stub；不能冒充完整原厂显示源码。Makefile 等现有脏改未动。 |
| `linux-sm8450-liuqin` | HEAD `e06846ed9d035161298f1d9fe9a7c83e7ef63059`，干净；作历史实现参考，不替代实际在用的 7.2.5。 |
| C5 实际 source tree | `/tmp/liuqin-power-display-review-20261114/linux`，7.2.5 加当前 C5 BSP。所有下面主线行号对应该树。 |
| dump `vendor_boot_a.img` | SHA256 `10eb7e6b73d36feeb75914d3448a3b859fbb4b9d8402018f49f5c7986a323740`。vendor boot v4，page 4096，vendor ramdisk 23593022 bytes，LZ4 legacy；本次解压 54571008 bytes CPIO。 |
| 从 dump 原样提取 `msm_drm.ko` | `msm_drm-dump.ko`，SHA256 `20d0067a1ebda29967854fd5e90f377efbac397ee53c79dbaa4713effa08e8a7`；vermagic `5.10.160-gki-g13e2f28f61e9`，scmversion `g29ec99da39a5`。 |
| 旧提取模块 | `liuqin-mainline-blobs/extracted/vendor_boot/ramdisk/lib/modules/msm_drm.ko` 与 `gki-mixed-boot/stock/extracted/vendor-ramdisk/lib/modules/msm_drm.ko` SHA256 都是 `15645752…e16ede`，vermagic 5.10.81；**不是上面的 dump 版本**。 |
| Android live DT 文本 | `liuqin-audit/evidence/final-runtime.dts` SHA256 `52f11a4e625875e45524bbdb4ab5845c032fbc92dcfe9ca1d005d5e23907b898`。有活动 M81_42 节点，但不能假定它与 5.10.160 dump 来自同一次启动。 |
| Qualcomm 公开代码 | 固定 commit `e7ab2aa8bd2f6f27b311ccada3722d20dee4bcef`，下载到 `public/`。仅用于理解和对照；没有声称与小米模块逐字节/逐行一致。 |

完整哈希在 `evidence-sha256.json`。实际模块的 `.modinfo`、符号、反汇编和人工可读注释均保存在本目录。反汇编地址是 ELF `.text` 内偏移，不是设备运行虚拟地址；若要换算文件 offset，应使用该 ELF 的 section table，不能套到另一个版本。

## 原厂实际模块：continuous splash 不等于先关再开

下列结论来自 dump 模块的指令、重定位调用目标和分支；公开源码只作第二来源。

| 实际模块函数及 `.text` 偏移 | 核实的操作 |
| --- | --- |
| `dsi_display_cont_splash_config` `0x1376b4` | runtime resume；在 `display+0x40` 写 1；通知 clock manager splash status；配置两 ctrl IRQ；调用 `dsi_display_clk_ctrl(ALL,ON)`；交接 backlight 当前亮度。实际函数不同于公开源码：不能照抄参考源码中的直接 panel regulator call。 |
| `dsi_display_phy_sw_reset` `0x137318` | `+0x28` 读取 splash 标志 `display+0x40`，为真时走跳过分支；否则才调用两 `dsi_ctrl_phy_sw_reset`。另一个跳过标志 `+0x651` 属其它配置，未在本项命名。 |
| `dsi_phy_enable` `0x110968` | 入参 w4（第 5 参数）保存为 w21；`+0xb4`/`+0x12c` 附近的分支为 splash 情况跳过 regulator/hw enable ops，但更新驱动 PHY engine software state。 |
| `dsi_display_prepare` `0x13d308` | `+0x190` 等处 splash=true 跳过 `dsi_panel_pre_prepare`；`+0x79c` 读取同一标志，为真跳过两 ctrl soft reset 及 `dsi_panel_prepare`。其它 host/clock 状态登记仍有工作，不能写成“完全不碰 host”。 |
| `dsi_display_enable` `0x13ebf8` | `+0x88` 判断 splash；true 路径调用 `config_ctrl_for_cont_splash`、`splash_res_cleanup`，更新 panel_initialized/power 软件状态并提前返回；false 路径才调用 `dsi_panel_enable`。 |
| `dsi_display_splash_res_cleanup` `0x13788c` | 清理 splash clock/PM vote，清 `display+0x40`，更新 clock manager。不是 generic power cycle。 |
| `sde_rm_cont_splash_res_init` `0x91774` | 枚举硬件资源，通过 hw_ctl ops 读取既有 CTL/LM/SSPP 状态，记录 splash 使用资源；并非从 DRM 空白软件状态假定硬件全 OFF。 |
| `sde_kms_cont_splash_config` `0x99994` | dump 内保留该符号与相关资源初始化路径；公开固定源码展示 CRTC/encoder/plane 的 splash 状态填充。不能仅凭符号存在断言这次 stock 启动实际执行成功。 |

参考原始代码：

- [Qualcomm dsi_display.c at fixed commit](https://android.googlesource.com/kernel/msm-extra/display-drivers/+/e7ab2aa8bd2f6f27b311ccada3722d20dee4bcef/msm/dsi/dsi_display.c)，本地 `public/dsi_display.c:4688,6946,7383`。
- [Qualcomm dsi_phy.c at fixed commit](https://android.googlesource.com/kernel/msm-extra/display-drivers/+/e7ab2aa8bd2f6f27b311ccada3722d20dee4bcef/msm/dsi/dsi_phy.c)，本地 `public/dsi_phy.c:863`。
- [Qualcomm sde_kms.c at fixed commit](https://android.googlesource.com/kernel/msm-extra/display-drivers/+/e7ab2aa8bd2f6f27b311ccada3722d20dee4bcef/msm/sde/sde_kms.c)，本地 `public/sde_kms.c:2678`。

这些路径证明存在系统性的资源和软件状态继承机制；它们不能证明主线必须实现同样复杂的 seamless splash。受控地停止旧链路后从已知状态启动，也可成为正确架构，但必须先明确停止操作的顺序和覆盖范围。

## 主线 C5：首次启动与 OFF/ON 的差异

| 阶段 | 第一次 Linux 初始化 | Linux 已启用后的关闭/再启用 |
| --- | --- | --- |
| MDSS probe | `msm_mdss_init:372` 做 CORE_BCR assert→20ms→deassert，之后才 populate 子设备 (`msm_mdss.c:488`) | 不重新 probe MDSS。runtime PM 处理 clocks/interconnect。 |
| PHY probe | 注册 PLL clocks，读回已有 rate/dividers，同时有 bias/mux 写入；见下一节 | 不重复注册 clocks；正常路径保存自身 PLL 状态。 |
| panel probe | C5 `GPIOD_OUT_HIGH` 配合 ACTIVE_LOW 把 nRESET 置物理 low；读 regulator/backlight；登记 panel/attach dual DSI | 不再 probe；后续 panel `.prepare/.unprepare` 控制 reset/电源。 |
| bridge pre_enable | `dsi_mgr_phy_enable:150` 先 reset 两 PHY，再 enable clock-master0 和 slave1；`host_power_on` 配置两 host，开 IRQ，再 enable host engine；panel `prepare_prev_first=true` 保证 link 先于 panel commands。 | 先走真实 host disable/power_off/PHY disable、panel OFF/sleep/reset/supply release；下一 enable 从 Linux 建立并关闭过的状态开始。 |
| PLL/PHY | PHY enable 会 restore saved state；link rate/enable 使 PLL prepare 锁定、PHY digital reset、RBUF/global clock enable | `vco_unprepare:545` 先 gate global clock、停 PLL，再关 master/slave RBUF/bias；PHY disable 还禁 LPCDRX、关 lanes/blocks。 |
| panel | 五路 regulator enable→reset 序列→init/Sleep Out→PPS→compression→Display On；在首次 inherited 情况并没有先完整走 `.unprepare` | `.disable` 发 OFF / sleep，再 `.unprepare` 拉 reset low 并释放五路，随后重新执行 prepare。 |
| 软件标志 | `power_on` 等初始 false；`host_power_off:2567` 会直接返回，不能用它盲目清理 firmware 的 ON 硬件 | power_on 已经 true，正常关闭函数实际执行。 |

相关源码：`dsi/dsi_manager.c:124–317`、`dsi/dsi_host.c:2496,2561`、`dsi/phy/dsi_phy.c:724`、`dsi/phy/dsi_phy_7nm.c:491,545,1201`、`panel/panel-novatek-nt36532.c:618–713,756,791`。这些 source excerpts 不证明真实电压边沿或 DSI 线端波形。

### MDSS BCR 的能力边界

- DTS `sm8450.dtsi:3405` 指向 `DISP_CC_MDSS_CORE_BCR`；`dispcc-sm8450.c:1763` 映射 `0x8000`。DSI PHY 另有 host `REG_DSI_PHY_RESET` 操作（`dsi_host.c:2393`）和 PLL/PHY digital reset；源码把它们作为不同步骤。
- 该 BCR API 没有 panel GPIO 或外部 regulator 操作，故**不能**等价于 panel 物理断电、复位；也不能把 “MDSS” 名字当作所有 DSI analog/PLL 域都清零的证据。
- `msm_mdss_reset` 不检查 assert/deassert 返回值；`drivers/clk/qcom/reset.c:28` 又忽略 regmap write/read 错误。调用链成功返回不是硬件覆盖证明。
- 源码能证明 BCR 调用早于子设备 populate；不能从这里得知调用后、PLL probe 前 DSI host 是否真的已停、PHY/PLL 模拟状态是什么。需要 firmware 关机实现/硬件定义补齐，不能靠名字推断。

## 具体的较早缺口候选：PLL probe 的主动写入

完整原始 excerpt 保存在 `pll-probe-source-excerpts.txt`，两版旧补丁原样保存在 `normal-HEAD-0003.patch` 和 `normal-2f148f4-0003.patch`。

成功 probe 的源码调用链是：

```text
mdss_probe
  msm_mdss_init -> msm_mdss_reset (20ms CORE_BCR)
  of_platform_populate (创建 DPU/DSI/PHY 子设备)
    dsi_phy_driver_probe
      devm_pm_runtime_enable + pm_clk_add("iface")
      cfg->ops.pll_init = dsi_pll_7nm_init
        kzalloc dsi_pll_7nm（pll_enable_cnt = 0）
        pll_7nm_register
          devm_clk_hw_register
            clk_hw_register -> __clk_register -> __clk_core_init
              core->ops->recalc_rate
                dsi_pll_7nm_vco_recalc_rate
                  enable_pll_bias
                  read DEC/FRAC registers
                  disable_pll_bias
        C5: msm_dsi_phy_pll_save_state -> enable/read/disable bias
        C5/旧normal: 显式 dsi_pll_7nm_vco_recalc_rate -> enable/read/disable bias
```

具体行号：

- `msm_mdss.c:372,476,488`；`dsi_phy.c:694,706`；`dsi_phy_7nm.c:865,875,883,886,891`。
- `pll_7nm_register:747` 调 `devm_clk_hw_register`。`drivers/clk/clk.c:4672`→`4448`→`4368`→`4028` 调实际注册的 `.recalc_rate` (`dsi_phy_7nm.c:622`)。因此不是一个未被调用的辅助函数。
- `vco_recalc_rate:578,603` 确实 enable/disable bias。`save_state:638,650` 也如此。
- `enable_pll_bias:423` 增加软件计数、置 `CMN_CTRL_0.PLL_SHUTDOWNB`、写 `PLL_SYSTEM_MUXES=0xc0`。
- `disable_pll_bias:398` 减少软件计数；归 0 时写 `PLL_SYSTEM_MUXES=0` 并清 `PLL_SHUTDOWNB`。
- PLL 的 flags=`CLK_IGNORE_UNUSED`，不会跳过注册时的 recalc。CCF 初始化 rate 早于对应 critical-clock prepare 逻辑；此 PLL 也未声明 `CLK_IS_CRITICAL`。

HEAD 正常回退版和历史 commit `2f148f48d06cf761e1f4d4fd592c6b2345ebdf42` 的 0003 删除的是 `msm_dsi_phy_pll_save_state()` 两行；它们保留紧接着的显式 recalc，CCF 注册回调亦未改变。所以“删掉初始 PLL save 仍黑”不能推出“所有 probe 期 PLL 干扰都已排除”。C4 后续锁定后 mux=0xc0，也不覆盖更早的 probe 阶段。

这里确定的是代码会尝试这些写入，以及普通软件计数没有接纳 firmware 的 bias 使用引用；还不能确定这些操作是不是屏黑的必要或充分条件。原因包括 BCR 可能已使链路停止、读写时供电条件未知、面板可能已在其它步骤被复位。不能据此直接删整个 recalc 或假造 firmware 引用计数。

## 双 DSI 发送目标核对

- `dsi_manager.c:47–65`：`qcom,dual-dsi-mode` 设置 bonded；bonded 时 `qcom,sync-dual-dsi` 设置 `IS_SYNC_NEEDED`。C5 板 DTS 的双 host 均声明这两项；DSI0 还声明 `qcom,master-dsi`。clock master 固定 DSI0；command trigger 固定 DSI1；它们不是同一个“master”概念。
- C5 panel 的 `nt36532_cmd_dsi` 选择 DSI1。write 进入 `msm_dsi_manager_cmd_xfer` 时 `need_sync=IS_SYNC_NEEDED&&!is_read`，对两 host 分别 `xfer_prepare`；`cmd_xfer_trigger` 先 commit DSI0 再 commit DSI1。**软件设计是向双链路广播，不是只发右半屏。**
- C9 194 个 0x39 的 host 入口计数只证明上层 request/payload/type；没有证明两条物理链路都发送成功、面板接收到或接受了命令。
- read 的 `need_sync` 关闭，但 trigger 仍按全局 `IS_SYNC_NEEDED` 处理，DSI0 直接 false。这是 DSI0 诊断无返回的明确限制；不能据 DSI0 无数据额外证明两个 panel input 都坏。DSI1 首次无返回、OFF/ON 后有效，仍是可比证据。

## 真实 UEFI XML 与 Android DT 不是完全相同命令表

对 ABL 子任务从 `uefi_a.img` 提取的 `Panel_M81_42_02_0b_dualdsi_dsc_lcd_video.xml` 与 active Android DT 的 `qcom,mdss-dsi-on-command` 做逐包 payload 比较，结果在 `panel-init-uefi-android-diff.json`：

| 项目 | UEFI XML | Android DT / C5/C9 |
| --- | --- | --- |
| 普通 DSI 包数 | 195 | 194 |
| page 0x27，D1 | `d1 28` | `d1 20` |
| page 0x25，0F | 有 `0f 20` | 无此条 |
| 其它 payload | 与 Android 相同 | 与 UEFI 相同 |
| XML 特殊指令 | `fd 03`, `ff 78`, `ff 14` | 用 DT 描述头/延迟/broadcast properties 表达，不能直接按 DCS 包比较 |

分辨率、DSC几何、时序在两个原厂材料之间一致。上面的差异**不等于错误**，原厂 boot splash 与 Android 可以选择不同的 dimming/动态设置。C9 已证明“匹配 Android DT”，没有证明“匹配所有原厂启动行为”；同核 ABL 直启成功也削弱了单纯初始化 payload 错误作为唯一解释。

## 原厂 TDDI 电源状态也比 DT 五路静态列表复杂

本项在 dump 模块发现小米 M81 专用分支，不应只拿 Qualcomm 通用 `dsi_panel.c` 解释：

- `mi_dsi_panel_parse_config` `0x169174` 中 `0x169654` 读取 `mi,is-tddi-flag` 存入 panel+0x8e8；初始化 +0x8e9/+0x8ea 为 0。
- 导出函数 `dsi_panel_doubleclick_enable` `0x176d48` 把 enable 写 panel+0x8e9。
- `dsi_panel_pre_prepare` `0x14c1c0` 对 M81 ID（0x004d383150420200 / 0x004d383150360200）有专门处理。TDDI、doubleclick 与另一个 flag 满足时，reset 拉 low，按供电数组索引 1→2 重新 enable；其它条件调用完整 regulator enable。
- `dsi_panel_post_unprepare` `0x14e6e4` 的相应路径记录 “M81 dont reset”，按索引 2→1 disable；并不是永远释放所有供电。
- `mi_dsi_pwr_enable_vregs` `0x176658` 的第三参数是数组索引（乘 80 字节），不是 enum。从实际 dump 的 `dtbo_a.img`（SHA256 `84a684ced68f8f0600d2d79a08b9889a252f375cf238d6a66532f60158c93b6b`）index 15 提取的 M81 原始 child 顺序为 `iovdd,dvddbuck,dvddldo,vsp,vsn`，支持索引 1/2 对应两路 1.3V；实际 parse_supply_node 逐 child 遍历并 index++，没有按 `reg` 排序。注意该 overlay 的最后三项 `reg` 都=2，按reg排序会出错。证据为 `stock-supply-order.py/json` 及 `dsi_pwr_parse_supply_node.annotated.S`。还须确认 ABL 合并 overlay 后的最终 FDT 顺序，不能直接拿 `final-runtime.dts` 的文本排列或 raw overlay 冒充最后的运行数组。

这说明原厂根据触摸唤醒策略选择不同生命周期；它不证明 C5 的全关策略错误，也不证明 doubleclick 路径在这次 stock cold boot 实际执行。它要求今后的架构明确 TDDI、panel 和共享 supply 的所有权，避免把用户态“禁用 touch probe”的结果扩大成“所有 TDDI/面板联动都已排除”。

## 对历史解释的审查

| 解释 | 本次判断 |
| --- | --- |
| “U-Boot破坏了显示硬件” | 本轮 ABL / U-Boot 分项已补齐有序 Off 与缺失对应退出的证据；仍未定位是哪项状态造成黑屏，不能泛称 U-Boot 配置坏了硬件。 |
| “PLL save覆盖导致频率错” | 旧源码注释写成定因过强；C5恢复上游仍失败，旧版跳过save也失败。probe期其它主动PLL写未被排除，但这也只是候选。 |
| “完全没MDSS reset” | 错；7.2.5已有。 |
| “有MDSS reset所以硬件全干净” | 也不成立；源码缺硬件覆盖证明，外部panel根本不在该API内。 |
| “controller/PHY/DSC/INTF最后值相同就排除了接管问题” | 不成立；最终寄存器不记录此前瞬态、模拟状态和对端状态。已有采样只削弱各自具体假设。 |
| “MIPI host transfer返回成功，所以命令一定到达面板” | 不成立；request/本地DMA完成与对端响应不是同一证据。 |
| “194条与stock一致因此命令表无任何差异” | 只能说对Android on-command一致；UEFI有上表两差异，packet目标/间隔另需核对。 |
| “C7去掉boot-on失败已排除供电问题” | 只排除那一项属性变化作为充分修复；未测真实每条电源波形/放电和reset时序。 |
| “no-touch仍黑排除了TDDI” | 只能排除本次Linux触摸probe/下载是必要的直接触发；不能排除共享硬件状态或面板对触摸固件的需求。 |
| “panel注册后DSC赋值发生竞态” | 没有发现支持。DPU component matching等待两DSI，component_add发生于attach；C5给每host赋DSC/format/flags后才attach，双host完成才正常bind。 |

## 后续研究应补的证据，而非新一轮参数尝试

1. 把 ABL/DisplayDxe 真实 power-down 的顺序，与上面主线 probe/first modeset的操作放在同一张表：哪些动作发生在 Linux 触碰 PLL 之前，哪些只在普通 Linux OFF 路径发生；分别记录时钟/电源/复位/等待完成条件。
2. 核实“同输入DT”的最终交接内容：ABL选择 splash_region 的行为、传到Linux的chosen/reserved-memory/simplefb/命令行、reset/clock相关live properties。不能只比仓库 DTS 文件。
3. 若继续实施，先选定唯一责任边界：由 bootloader 在菜单后完成一次有依据的 shutdown，或由 Linux 在首次主动修改前建立一致的接管/停止流程。不要在panel、PLL、host、msm_kms各加独立定时补救。
4. 硬件未知应在证据表中留空；当前静态证据不足以承诺哪一寄存器就是根因，也不足以开始再一个无区分度的“试试看”。
