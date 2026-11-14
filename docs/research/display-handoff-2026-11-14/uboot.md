# U-Boot → Linux 显示交接静态审计（2026-11-14）

> 归档说明：本子报告原始工作目录为 `/tmp/liuqin-display-systematic-20261114/uboot/`；
> 已归档的同名证据位于 `evidence/uboot/`，完整源码/反汇编工作集仍在原目录。


研究范围：实际 BSP 构建源、板级附加文件、13 个补丁、`sysboot`→`booti` 交接、DM remove、DT 修改、共享电源。未访问平板、未部署、未重新启动、未改变 BSP 或 `/home/seeker/nixos-config`。

## 1. 已证实的核心结论

1. **BSP 中的 U-Boot 不具备显示硬件的初始化或关闭实现。** 菜单能显示，是将像素写进 ABL 留下的 framebuffer；进入 Linux 时，没有对应 DPU/双 DSI/PHY/panel 的关闭流程。`board_quiesce_devices()`、`board_cleanup_before_linux()`、`board_prep_linux()` 都没有 liuqin 实现；通用 ARM cleanup 的 CPU 缓存维护不是显示关闭。
2. **通用 DM remove 不会替我们关闭显示。** `announce_and_cleanup()` 只选 `ACTIVE_DMA` / `OS_PREPARE` 标志的设备，而 `liuqin_video` 只有 `PRE_RELOC`，既没有匹配标志，也没有 `.remove`。video uclass 也没有 `.pre_remove`。因此“U-Boot 退出时自动删除所有设备，应该会关显示”在这个版本不成立。
3. **U-Boot 不是完全不碰显示相关资源。** 板级 UFS/USB bring-up 会设置并启用 PM8350 L5=880 mV、PM8350C L10=1.2 V，它们同时供 DSI PHY 的 vdds 和 DSI host 的 vdda。数值与 Linux DTS 的允许范围/目标相符，暂未发现主动写错电压；但“U-Boot 只写 framebuffer，从不碰任何显示相关电源”太强。没有对应退出时 disable 这两个 rail 的代码路径。
4. **同一个输入 Linux DTB，不意味着两条路径收到的最终 DT 相同。** extlinux 明确装载 Linux FDT，U-Boot 重写 bootargs、memory banks、initrd 范围、版本等；ABL 在它自己的路径还可能加其他属性/overlay。U-Boot 内部 OF_LIVE 对 USB/RPMh 的删改与最终传给 Linux 的另一个 FDT 是两棵树，不能混为一谈。
5. 现有代码最直接解释的是：**ABL→U-Boot 保留并使用 splash 管线；U-Boot→Linux 没有复现 ABL 的关机交接，Linux 首次接管面对遗留硬件状态。** 它确立了有意义的结构差异，但尚不能定位具体是哪项 DSI/PHY/PLL/DPU/panel 状态造成首次无响应。更不能由源码缺少关闭步骤直接宣布“唯一根因已确认”。

## 2. 版本与可复现性

- BSP 定义：`/home/seeker/Develop/liuqin/liuqin-nixos/pkgs/u-boot/default.nix:116` 左右的 `fetchFromGitHub`，固定 `sm8450-mainline/u-boot` commit `a4f9d7fccf2cd2fc68b8496d723cd92fd16ff80f`。
- 原始归档：`https://codeload.github.com/sm8450-mainline/u-boot/tar.gz/a4f9d7fccf2cd2fc68b8496d723cd92fd16ff80f`。
- 归档 SHA-256：`a30cb09e47000e2262cf4d237da7eb09272d9f365d849e7a0c7d1fe7786508c5`。
- 解包后 `nix hash path baseline`：`sha256-VG4TxrLaom56o4RaCHyDGe06paFIUq5A+a+Do16rKE4=`，与 BSP 的固定哈希逐字相同。可确认没有拿上游 master 或另一个 fork 当作实际基线。
- 对固定源依序应用当前 `pkgs/u-boot/patches/*.patch` 13 个补丁并复制 `files/.`，全部无 reject/fuzz。分析目录 `source/` 是此组合；`source-fingerprints.json` 记录关键 17 文件的 SHA-256 与是否与基线相同。
- `port.manifest` 校验通过，完整输出 `port-manifest-check.txt`。
- `/home/seeker/Develop/liuqin/old/liuqin-dualboot/u-boot/source` 的 Git HEAD 是 `918b1f3ece78153bd1108d067e280072b98c8f6f`，属于历史 port commit；不等于固定 fork commit。尤其旧 `.output/.config` 中 `CONFIG_VIDEO_SIMPLE=y`，当前 Nix recipe 显式禁用它。**没有以旧 .output 配置冒充当前构建配置。**
- 原历史 Nix output `/nix/store/zpnxzv8bk6wk87wy3fg50wgwxll6jmdh-liuqin-uboot-aarch64-unknown-linux-gnu-2024.10+a4f9d7fc` 此次本地主机已不可读。未重新构建完整 U-Boot，也未读回平板 boot 分区。因此以上可严格确认的是当前 BSP source composition；当前闪存二进制与它字节相同，仍需已有安装记录/离线 boot.img 的 hash 来补证，不能无条件声称完成运行二进制身份核验。

以下 `source/...:行号` 均相对本目录中的确切组合源码，而非在线 master。除非另说，原始基线与对应文件相同。

## 3. ABL → U-Boot 的显示资源

### 3.1 ABL-facing DT 和 framebuffer

板级 DT：`source/dts/upstream/src/arm64/qcom/sm8450-xiaomi-liuqin.dts:41-68`：

- `/chosen/framebuffer@b8000000`，`simple-framebuffer`。
- reg `0xb8000000` / `0x2b00000`，1800×2880，stride 7200，format a8r8g8b8。
- `/reserved-memory/splash_region@b8000000`，同一个 reg，`no-map`（103-106）。
- `&mdss` 从 SM8450 dtsi 继承 `status="disabled"`（`source/dts/upstream/src/arm64/qcom/sm8450.dtsi:3049-3082`）；没有在这个 U-Boot DT 里启用 DPU/DSI，也没有 panel/KTZ8866 节点。

作为对照，Linux 板级 DTS 使用 `/reserved-memory/linux_splash@b8000000`，同一地址尺寸。更名可以影响 ABL 对其正在处理的那个 DT 的决策，**不能让已经跳出 ABL 的 U-Boot→Linux 路径重新执行 ABL 代码**。这一点无需知道 `DisableDisplay()` 的二进制细节也成立。

U-Boot boot.img 打包：`pkgs/u-boot/default.nix` 最后 `callPackage ../bootimg`，`payload=u-boot-nodtb.bin`、`baseDtb=生成的U-Boot DTB`、`cmdlineOverlay=false`、payload pad 到 8 MiB、空 ramdisk。共用 `pkgs/bootimg/default.nix` 的 ABL 元数据/stock DTBO symbol sink 管线。Kernel 直接 ABL 路径与其共享包装机制，但 baseDtb 是 Linux DT。stock overlay 对最终 live DT 的影响需要分别检查，不能只比较 baseDtb。

### 3.2 映射与绘制

- `source/arch/arm/mach-snapdragon/board.c:583-605`：`map_framebuffer()` 取 `/chosen/framebuffer` 的 reg，将尺寸按 2 MiB 对齐，以普通内存映射，只有 MMU 页表操作。
- 同文件 `611-659`：`enable_caches()` 完成映射与 CPU cache enable，没有显示 MMIO 初始化。
- `source/board/qualcomm/liuqin/video.c:35-40`：硬编码 base、geometry、stride。
- `video.c:79-141`：字符写像素，逐行 flush dcache；`early_wrap()` 把可扫描的 20,736,000 字节写黑后 flush。
- `video.c:219-234`：早期 console 转为 DM vidconsole 时清 framebuffer、重置光标。这是像素内容变化，不是 panel DisplayOff/背光或 DSI 链路关闭。
- `video.c:251-287`：probe 只填 video 私有状态，bind 只声明 framebuffer base/size；ops 空，无 remove，无任何 DCS、DSI/PHY/DPU/PLL MMIO。
- `source/board/qualcomm/liuqin/liuqin.c:239-265`：手动 bind `liuqin_video`；console 初始化再 probe。
- 当前 recipe 显式 `-d VIDEO_SIMPLE`，目的为防止与这个手动 video driver 双重绑定。无论旧 simplefb driver 还是当前 liuqin_video，使用固件 framebuffer 都不等价于实现显示硬件初始化。

## 4. U-Boot → Linux 的准确调用链

```text
liuqin.env boot_nixos / boot_nixos_menu
  -> sysboot scsi ... /boot/extlinux/extlinux.conf
  -> label_boot()
     装载 LABEL 对应 kernel、initrd、FDT
     APPEND -> env bootargs
  -> do_booti()
     装载/解压/必要时移动 ARM64 Image
     -> bootm_run_states(... OS_PREP / OS_GO)
        -> boot_prep_linux()
           -> image_setup_linux() -> image_setup_libfdt()
        -> boot_jump_linux()
           -> announce_and_cleanup()
              -> board_quiesce_devices() [weak empty]
              -> print Starting kernel
              -> dm_remove_devices_flags(ACTIVE_ALL | NON_VITAL)
              -> dm_remove_devices_flags(ACTIVE_ALL)
              -> cleanup_before_linux()
                 -> board_cleanup_before_linux() [weak empty]
                 -> CPU IRQ/cache/MMU cleanup
           -> do_nonsec_virt_switch()
           -> ARM64 entry(x0=FDT, x1=x2=x3=0), configured switch to EL1
```

证据：

- env 的两条路径：`source/board/qualcomm/liuqin/liuqin.env:87,95`。Android 菜单项不是“U-Boot 直接启动 Android kernel”，而是选 A slot 后 reset，让 ABL 重新启动；**不能用 Android 菜单可正常显示证明 U-Boot 直接接管 stock kernel 正常**（同文件 29-44）。
- FDT 获取、APPEND、booti 分支：`source/boot/pxe_utils.c:599-621,643-741,783-791`。
- ARM64 booti：`source/cmd/booti.c:22-106,109-154`。
- Linux PREP/GO：`source/arch/arm/lib/bootm.c:198-240,291-329`。
- cleanup：`source/arch/arm/lib/bootm.c:45-83`，`source/arch/arm/cpu/armv8/cpu.c:35-71`。
- `CONFIG_USB_DEVICE` 的旧 UDC conditional 在 cleanup 中，但 qcom 配置不是该老 USB device 模型。即便编入，它也只涉及 USB，不是显示。
- 没有 EFI boot path 的 `ExitBootServices()` 或 ABL DisplayPower protocol 调用。启用 U-Boot 自己的 EFI_LOADER 不会恢复 ABL 已结束的 EFI Boot Services。

### 4.1 退出阶段的硬件写/不写表

| 阶段/资源 | 静态代码行为 | 显示意义/证据边界 |
| --- | --- | --- |
| board_quiesce_devices | weak 空；liuqin 无实现 | 无面板或链路停机 |
| CPU IRQ、I/D cache、MMU | disable/flush/invalidate | 不改变 DPU/DSI/PLL、panel 电源 |
| DM removal 选择 | 仅 ACTIVE_DMA / OS_PREPARE 标志；分 non-vital 与 vital 两遍 | 不是 remove 所有设备 |
| liuqin_video | PRE_RELOC；无 ACTIVE/OS 标志，无 remove | 不会被本次移除选中，也无显示 shutdown 可执行 |
| video uclass | post_bind/post_probe/destroy；无 pre_remove；destroy 只取消 video cyclic callback | 不含自动清屏/背光关机或硬件复位 |
| GCC clk/reset/GDSC drivers | PRE_RELOC 或普通驱动，未设 ACTIVE/OS 标志；没有统一关显示 callback | 不会在退出自动屏蔽 DSI/MDSS 时钟；表中存在 DISPLAY_BCR 不代表曾调用它 |
| RPMh regulator driver | 无 ACTIVE/OS 标志，无 remove | 不是“退出时自动关掉所有被 U-Boot enable 的 regulator” |
| qcom-hyp-smmu | 有 OS_PREPARE；remove 是空函数 | 出口不复位 SMMU；初始化阶段可能配置 UFS/USB SID，但没有显示设备连接 |
| DPU / DSI / PHY / panel / KTZ8866 | 没有匹配显示硬件驱动，MDSS disabled | 没有 DisplayOff/SleepIn、TGEN/CTL stop、ULPS/PHY/PLL 停机、panel reset 或 rail OFF |

DM 选择逻辑精确证据 `source/drivers/core/device-remove.c:179-195,198-260`：没有 DM_REMOVE_NORMAL 时，需要 drv flags 与 ACTIVE_ALL 有交集。通用 video 证据 `source/drivers/video/video-uclass.c:697-719`。SMMU `source/drivers/iommu/qcom-hyp-smmu.c:374-406`。QCOM clock `.flags` 与 ops 在 `source/drivers/clk/qcom/clock-qcom.c:348-364`；没有 clk disable ops。`CONFIG_VIDEO_REMOVE` 本身只是给实现了 remove 的特定 driver 一个构建开关；为 liuqin 打开这个 Kconfig **不能凭空补出 shutdown**。

## 5. 已发现的共享资源副作用，不能凭空排除

### 5.1 PMIC rails

`source/board/qualcomm/liuqin/liuqin.c:281-293,501-514`，`qcom_board_late_init():295-330` 会：

- LDO b7 2.504 V（UFS VCC）、b9 1.2 V（UFS VCCQ）。
- LDO b5 0.88 V（UFS/USB/DSI PHY 共用）。
- LDO c10 1.2 V（UFS/USB/DSI host 共用）。
- USB 还设 c1 1.8 V、b2 3.072 V；PTN3222 设置 b10 1.8 V/相关 rail。

这些 helper 最终 `regulator_set_value()` + `regulator_set_enable(true)`；不是 passive readback。DSI 对应消费者见此次 C5 内核源 `.../linux/arch/arm64/boot/dts/qcom/sm8475-xiaomi-liuqin.dts:1174,1238,1244,1266`。其 L5 range 0.88–0.912 V、L10 1.2–1.224 V，与 U-Boot请求不冲突；但没有 ABL 直接路径同点电压/vote状态快照，不能说“完全等价”。

### 5.2 GPIO/I2C

U-Boot 的 I2C 5 / GPIO26、27 给 PTN3222 使用；KTZ8866 在 Linux I2C1、GPIO14/15，是不同 controller/pads，当前 U-Boot DT 无 KTZ 实例。UFS reset 使用 TLMM210，PTN reset 使用 PM8350C GPIO7，与 panel reset TLMM0、四条 panel 固定 regulator GPIO2/93/66/53 不同。查到的板级代码没有重置/改写这些 panel GPIO。全局 TLMM controller probe 本身也不自动将所有 pin 改为默认；per-device pinctrl 才配置声明的 state。不能仅凭启用了 GPIO 驱动就认定它重置了 panel。

### 5.3 SMMU

`qcom_smmu_probe` 先读取资源/EL；EL>1 时 connect 被 disable，EL1 则可能为 UFS/USB 分配 context bank 和 SID。算法保留已匹配的 SID（`qcom_smmu_connect:294-297`），MDSS disabled 且手绑 video 无显示 IOMMU 连接。其 context bank “空闲”启发式不是严格保证，因此若将来发现 Linux takeover 前已有 IOMMU fault，应看原始 SMR/S2CR/CB，而不是彻底排除。但当前证据不支持把它排在有效 DSI 传输/面板无响应之前。

## 6. Final FDT 与 U-Boot 内部控制树必须分开

### 6.1 控制树

- ABL 交给 U-Boot 的 FDT 在入口 `board_fdt_blob_setup()` 选择（`source/arch/arm/mach-snapdragon/board.c:78-129`）。若内置 DT 有效优先内置，否则采用 x0 的外部树。这里 payload 为 nodtb，包装中的 DTB由ABL传入；这一格式本身不等于简单“u-boot.bin appended dtb”。
- `qcom_of_fixup_nodes()` 在 `board_init()` 对 OF_LIVE 改 USB以及删 RPMh PD 引用（`board.c:191`；`of_fixup.c:104-157`）。
- 这些更改只影响 U-Boot 的 livetree：该源码的文件头亦说明其设计避免更改交给 Linux 的原始 flat tree。

### 6.2 Linux final FDT

NixOS 指定 `hardware.deviceTree.name=qcom/sm8475-xiaomi-liuqin.dtb`（`modules/liuqin/default.nix:233-240`），extlinux FDT 使用此文件。如果显式 FDT装载失败，该 label 会直接 skip；不是默默改用 U-Boot DT（`pxe_utils.c:712-724`）。仅缺少 FDT声明等其他分支才可能 fallback。

`image_setup_libfdt()`（`source/boot/image-fdt.c:567-685`）主要调用：

- `fdt_chosen()`：bootargs 来自 APPEND env，并加 u-boot,version；随机种子取决于配置。
- `arch_fixup_fdt()`（`source/arch/arm/lib/bootm-fdt.c:34-78`）：用 bd->bi_dram 替换 memory banks，相关 PSCI/spin table 由配置决定。
- ethernet/可选 pstore、OP-TEE节点拷贝、initrd 起止、FDT收缩/重保留。
- `ft_board_setup()`（`source/arch/arm/mach-snapdragon/of_fixup.c:159-174`）：只有 qcom,qrb4210-rb2 的 dr_mode 改动；liuqin 无显示分支。
- 当前 board没有 `ft_system_setup` 实现。不存在 Linux final DT 的 splash rename、panel时序、DSI clock parent 等改写。

`VIDEO_DT_SIMPLEFB` 默认无启用，qcom路径也没有 `fdt_simplefb_enable_and_mem_rsv()` 调用。已有 framebuffer node不会因为 DM video 被使用就自动补充 clock/reset/power domain phandle。

LMB 从控制 DT 的 reserved-memory 预留内存（`source/lib/lmb.c:247-252`，`source/boot/image-fdt.c:97-137`），因此声明的 framebuffer carve-out 与其他 secure reservation 被排除在普通 load buffer 分配之外。保留 framebuffer 内存与正确继承 DPU/DSI 硬件状态是不同条件；不能由“no-map 还在”推出显示交接成立。

## 7. 对已有结论的批判性复核

| 常见/历史说法 | 本轮判断 |
| --- | --- |
| U-Boot能显示，所以已正确初始化显示 | 错：源码是复用 ABL 管线和像素缓存 |
| U-Boot出口应已关显示，因为 DM 会 remove | 错：flags不匹配且没有关闭函数 |
| 改 Linux splash node 名即可修复 U-Boot路径 | 不成立：ABL不再执行；若只改内存名，没有硬件副作用 |
| 开 VIDEO_REMOVE 会自动关显示 | 不成立：没有对应实现，必须先有完整驱动/板级关机过程 |
| OF_LIVE fixup_power_domains 删掉Linux电源依赖 | 此路径不成立：Linux装载新FDT；是两个树 |
| U-Boot从未触及任何显示相关资源 | 过强：确实写过共享 L5/L10 rails，还可能配置 apps SMMU |
| C8 首次 TGEN_EN=0 排除了固件遗留扫描 | 过强：采点已经是 Linux执行初始化之后，不能反推raw U-Boot出口原始值；只能限制该采点的状态 |
| C4 PHY入口/PLL值相同，说明全部PHY状态相同 | 不成立：只取了几个寄存器与一个时刻，不是完整 state machine/ULPS/stopstate/clock-domain历史 |
| 第二次 OFF/ON 成功就证明 panel初始命令错误 | 不成立：第二次包含完整 Linux state建立后的关闭，可能清理 host/PHY/PLL/DPU/电源等多种状态 |

用户已补充：ABL 直接正常与 U-Boot异常使用同一7.2.5内核与DTB。这显著增强“进入同一Linux时硬件/交接元数据状态不同”的判断；仍应记录确切 Image/原始DTB hash、包装DTB与最终liveDT差异，避免以“相同源码配置”代替字节身份。

## 8. 推荐后续研究与架构方向（未执行测试）

### 8.1 先补证，不再按猜测写补丁

1. 与 ABL 子任务交叉，得到 **dump固件实际** 的 splash-preserve / DisableDisplay调用及 EFI display实现；明确完整 shutdown 是先停TGEN/CTL还是先发panel命令、双DSI停机、ULPS/PHY/PLL、电源pin顺序。公开 ABL同族源码仅作导航，不能代替这个确认。
2. 用已有文件补齐同版本两条路径的 Input Image/DTB、最终 FDT/cmdline、黑屏前最后已知可见阶段；不必先让用户再试屏。
3. 列出每一项 vendor关闭动作在主线首次enable前有无对应处理。将“完全没有做的动作”优先于已经失败的 packet type/reset延时等猜测，避免直接加多个workaround。
4. 若静态分析最终仍缺一个状态，未来只做一组带辨识力的只读handoff采集：**U-Boot最后入口点**（固件扫描仍活跃）与 **Linux第一次任何改写前**；随后在同一组与ABL直启等价采点对照。不要拿 Linux late probe 的0读数当固件出口。具体读寄存器需先核实clock域可读，避免无时钟总线fault。此计划本轮未实施。

### 8.2 应选择明确的交接模型

- **保留扫描并接管**：应传递/保留 scanout framebuffer、DSI/PLL/clock/PD/IOMMU真实状态，并由Linux的连续splash接管流程处理。当前只有 simplefb 的 memory/geometry，未实现完整接管。
- **交接前完整关闭，再由Linux冷启动**：应在 ABL仍掌握的DisplayPower流程中做，或由U-Boot一个有明确资源边界的板级display shutdown实现；必须来自vendor真实时序，不是临时向未知寄存器写reset。
- **Linux归一化未知启动态**：适合提升对各种 bootloader 的鲁棒性；需要一次可证明的同步停机/资源建立状态机，不依赖 Linux `power_on` 软件布尔初值去猜固件状态。实现应有正确的 host/PHY/DPU阶段边界，不能藏在通用fbdev延迟1.5秒OFF/ON工作项。

目前可确定当前实现没有完整选择上述任一模型。哪一层最终修复，需依据固件真实shutdown中缺失的具体动作；本轮不预先把“缺口”升级为某个寄存器根因。

## 9. 参考原始资料

- [本fork固定commit的 ARM bootm](https://github.com/sm8450-mainline/u-boot/blob/a4f9d7fccf2cd2fc68b8496d723cd92fd16ff80f/arch/arm/lib/bootm.c)，已与本地固定NAR源交叉。
- [AArch64 Linux boot protocol](https://docs.kernel.org/arch/arm64/booting.html)：CPU寄存器、cache/MMU和DMA设备交接要求。该文档不能代替设备具体显示sequence，也不能仅凭持续读scanout就推断有破坏Linux内存的DMA。
- BSP自己的 `pkgs/u-boot/default.nix`、`files/`、`patches/`、`pkgs/bootimg/default.nix`、`modules/liuqin/default.nix`。

## 10. 结合 dump 的 shutdown 路径：可行架构和生命周期审查

主任务已从 dump 固件确认 `DisplayPowerOff -> DisplayDxe MDPStopPipe -> 双路DSITerm (FD03 mask=3、0528/0510、70ms) -> DSI关闭 -> M81板级off -> clockterm`，其中 M81 off **不等于五条 panel rail 全部断开**。上述事实需要总报告引用 ABL 子任务反汇编地址，不以我方猜测代替。它进一步支持应先保证 host/PHY 的 orderly termination，而不是继续试 packet/延时/强制五 rails断电。

### 10.1 首选边界：借用 ABL framebuffer 的 U-Boot driver 同时拥有退出职责

当前 `liuqin_video` 已掌握“这是ABL遗留扫描”这一上下文，也直接拥有菜单写像素的行为。因此最局部、清楚的责任是把它扩展为 **借用固件显示的驱动**：probe记录/校验已启动硬件、保持菜单可用；真正交接 Linux时严格按所确认M81/SM8475流程停止它。它不应伪装成一个自己完成panel冷初始化的普通driver。

此方案的前提是可以把 vendor 的 terminal shutdown 化为有限且可检查的硬件操作，并清楚标注资源所有权。它需要 U-Boot自己的 MMIO/clock/PMIC访问，不可在 EBS后跳回 ABL/DisplayDxe函数指针或调用已结束的UEFI协议。虽然原DXE代码还可能残留在DRAM，Boot Services、事件、NPA/clock handle、stack和内存生命周期都不能再假定有效。

建议驱动有显式状态：

```text
BORROWED_ACTIVE
  -> PREPARED (所有资源/地址/支持机型已核对；仍未改显示，可失败回菜单)
  -> COMMITTING (进入真实 Linux OS_GO，最后日志已flush；不得回可见菜单)
  -> QUIESCED (vendor定义的停机目标达成)
  -> 立即进入Linux
```

`PREPARED` 不可提前停止扫描、拉reset、关rail或clock。不得借助“后续再probe一次就恢复”作错误回滚，因为这个driver没有 ABL全套显示初始化能力。

### 10.2 .remove 是可接入点，但不是完整方案

最小的DM集成可以在 `source/board/qualcomm/liuqin/video.c` 增加 `.remove` 并设置 `DM_FLAG_OS_PREPARE`（与 PRE_RELOC 共存）。`announce_and_cleanup()` 两次active remove发生在CPU caches/MMU关闭之前，所以MMIO和PMIC/GCC服务仍可用。当前 PMIC、SPMI、GENI、GCC provider没有匹配active remove标志，仍保持probe状态；依赖资源应提前获取并核对，不可在terminal阶段才懒加载一个未知driver。

但这里有四个必须显式处理的问题：

1. **错误被吞掉。** `source/drivers/core/root.c:144-148`：`dm_remove_devices_flags()`调用`device_remove()`后无条件返回0；ARM cleanup也不检查返回。driver `.remove`返回错误并不等于“中止启动”。`device_chld_remove()`还会在某个回调报错时提前结束遍历，造成其他active设备未remove，外层仍继续进Linux。不能以为“写个返回ret的remove”已经有正确失败生命周期。
2. **weak board hook也没有错误通道。** `board_quiesce_devices()`、`board_prep_linux()`、`board_cleanup_before_linux()`都是void。单独重载它们无法在做任何破坏前优雅返回extlinux菜单。若要新的可失败前置检查，需增加有返回值的PREP阶段接口，或在video probe/boot前执行完纯检查，让commit阶段只使用已验证资源。
3. **FAKE_GO。** `boot_jump_linux()`在fake分支之前调用cleanup，`CONFIG_TRACE`的`OS_FAKE_GO`也会remove设备。通过.remove无从知道这次是真正交给Linux还是fake。若采用 terminal shutdown，必须显式传递/检查真实`OS_GO`语义，不可让fake trace关掉屏幕后再执行调试命令。当前CONFIG_TRACE通常未启用，仍应纳入设计边界。
4. **手绑driver不形成完整资源拓扑。** `liuqin_video`是root下的手动driver，无DT资源引用；它与GCC/PMIC不是严格DM parent-child。当前flags让provider保留，但未来修改其他驱动标志时不可依赖偶然兄弟遍历顺序。资源检查/commit必须发生在provider消失前，或以明确的pre-cleanup调用建立顺序，不要只靠“video驱动通常最后remove”。

比较之下，board_quiesce_devices在active remove之前执行，更容易保证provider仍活着；**合适用途是薄的board调用层，将真实OS_GO的terminal动作委托给同一video驱动**，而不是把一组硬编码MMIO写埋在ARM通用cleanup。需要对fake和错误通道作小且明确的接口设计。

### 10.3 回菜单与失败策略

- kernel/initrd/FDT加载、头检查、内存分配、FDT修正、机型/资源检查失败：不修改显示，返回现有菜单并显示原因。不要在`boot_nixos`脚本刚开始就关屏，因为后面还可能找不到分区、加载失败或APPEND溢出。
- 调用位置应在所有可失败准备完成之后、真实OS_GO决定之后、DM/provider/CPU清理之前。代码审计锚点 `bootm_run_states():1051-1063,1082-1084`，`boot_jump_linux():291-329`。
- 已执行 MDPStopPipe 或 DSI terminal动作后，屏幕即不再属于可用console：之后不能打印“返回菜单”然后让`bootmenu_redisplay`继续在死framebuffer绘制。应写出有界DRAM/持久诊断，然后立即进已经验证的Linux，或进入明确terminal失败处理；哪一种由无法完成的动作是否破坏Linux冷初始化前提决定。
- 若terminal失败必须abort，可使用明确的进入ABL fastboot失败模式恢复可见/USB诊断，不能普通reset回默认NixOS形成自动重启循环。任何自动重启策略都需单次/持久失败标记，不能“再试一次就好”。若要直接回菜单，则必须实现且验证完整display恢复，这会把工作扩大成U-Boot显示初始化驱动，已不再是小型handoff修复。
- `.remove`只应保证幂等，QUIESCED时不重复发送vendor命令；idempotence是软件重复调用保护，不意味着可以把硬件错误重复reset到碰巧成功。
- 不清除Linux还需要的shared rail/vote；vendor M81 off没有断全部五rail，不能自行扩大成全断。停止display专属clock也需区分GCC/PMIC共享资源与DSI/MDP专属资源。

### 10.4 Linux pre-probe/first-enable方案的取舍

Linux侧归一化未知初始硬件状态也可成立，但代码边界比“在panel prepare之前调用普通power_off”更重要：

- panel driver仅拥有panel/reset/rails，无权偷偷停止DPU/DSI/PHY/PLL；且它未必知道当前有哪条固件扫描管线。
- DSI host的`power_on=false`、PHY未init、PLL未enable都是**Linux软件状态**，不能表示固件已停机。归一化阶段必须单独建模BOOT_INHERITED，不复用那些根据false立即返回的normal关闭函数。
- 时序必须在clock/regulator/MMIO可访问、双DSI及PHY身份明确之后、首次时钟rate/parent重设及panel reset之前，必要时由MDSS/DSI manager协调。普通早期probe时依赖还可能缺失；不能为了“尽早”在clock off区域裸读写。
- 从前子任务的TGEN=0等late读数不能证明无需更早归一化；vendor涉及DSI terminate、PHY/PLL等未完整观察状态；是否进入ULPS尚未证明。
- Linux层方案有利于任意bootloader鲁棒性，但要产生可上游审阅的通用state模型；只对`xiaomi,liuqin`匹配然后向display任意寄存器写magic，仍与临时workaround相同。

优先级：先从实际dump明确vendor terminal动作的输入条件/预期输出，再估计U-Boot借用driver能否以很小的、资源受控实现完成。如果可以，U-Boot拥有“借用和释放”是最清楚的局部架构；Linux cold-init继续处理正常关闭态。若动作需要 Linux已有DSI/PHY基础设施且U-Boot将不得不复制大半驱动，则应选择Linux协调的BOOT_INHERITED归一化阶段，仍不能继续用fbdev延时OFF/ON。当前尚未实施任一路线。

## 11. Kernel 子任务 PLL probe 发现的独立 cross-review

我读取了 `../kernel/pll-probe-source-excerpts.txt`，并直接复查 `/tmp/liuqin-power-display-review-20261114/linux` 的实际7.2.5源码与 `git show HEAD:pkgs/kernel/patches/0003-liuqin-display-panel-msm.patch`。结论同意，且足以否定旧实验“已经在所有PHY/PLL动作之前停了controller”的解释。

代码链可严格成立：

1. `dsi_pll_7nm_init():863` 用 `devm_kzalloc()` 分配 PLL对象，`pll_enable_cnt`初始0；只有enable_bias/disable_bias两处改变该计数，没有从固件实际物理开关状态继承它。
2. `pll_7nm_register():747` 调用 `devm_clk_hw_register()`。CCF 注册的 `__clk_core_init():4028-4030` 主动调用 `.recalc_rate`，不是等到首次modeset才调用。
3. `dsi_pll_7nm_vco_recalc_rate():578,603` 读DEC/FRAC前后包着 `enable_bias/disable_bias`。enable将CTRL0的PLL_SHUTDOWNB位置1并写SYSTEM_MUXES=0xc0；disable使计数由1回0，写SYSTEM_MUXES=0并清PLL_SHUTDOWNB。**名叫recalc/read rate，不是只读操作。**
4. `dsi_pll_7nm_init():891` 还显式调用一次recalc。旧patch删除`msm_dsi_phy_pll_save_state()`，但保留这个显式recalc，也未改变注册时的recalc，因此未阻止这些probe写入。
5. 从 `dsi_phy_driver_probe():698-703` 的PLL init到 `dsi_mgr_bridge_power_on():223-227` 的PHY enable、host_power_on，是前后两个生命周期阶段。旧patch在`msm_dsi_host_power_on()`里新增的 stop/reset 更晚；C4即便把stop提前到bridge PHY reset前，仍晚于PHY时钟提供者注册。

这与从 U-Boot 源推得的状态相容：U-Boot没有DSI正常停机，把固件状态交给Linux；Linux此时以0软件引用计数进入PLL probe，即可能在未进行vendor双DSI终止之前切bias/mux。ABL直启已有DisplayPowerOff则不会面对同一个“仍处在固件活跃链路中”的初态。该差异比packet type、单纯reset延时更值得优先研究。

仍需保留三条边界：

- `msm_mdss_init():372` 在populate子设备之前先调用`msm_mdss_reset()`，assert20ms后deassert。故PLL probe不是系统绝对第一项可能影响固件扫描的动作；必须把MDSS reset、DISPCC、PHY CCF注册以及DSI host注册排序合并分析。
- 代码能证明early写入及软件/硬件初态脱节，不能证明这些具体写入必然造成当前面板不可恢复。旧“删除save_state”试验失败恰好没有隔离掉这些动作，不能作其反证；但也还没有选择性隔离的运行证据可宣布唯一root cause。
- 此发现不授权简单删掉recalc或保留固件PLL常开：读寄存器有clock/bias条件，后面set_rate、master/slave关系、CCF状态要整体正确。架构目标应是 **若要避免这类probe写入，应在此前停止继承链路**，或者正确地继承并保持物理状态，之后才按完整state machine接管。不能仅再加一个晚期reset。
