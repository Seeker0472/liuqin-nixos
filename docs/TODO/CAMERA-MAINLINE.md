# 摄像头主线移植 TODO

状态基线：2026-09-29

本文记录 Liuqin（小米 Pad 6 Pro，SM8475）摄像头从原厂 Android 栈移植到主线 Linux/NixOS 的现状、证据、缺口和验收顺序。

## 当前结论

硬件侧不是缺少摄像头。Android 原厂系统已经探测并初始化三颗物理传感器，以及 CCI、CSIPHY、CSID、IFE/SFE、ICP、JPEG、Camera SMMU、EEPROM、自动对焦和闪光灯。

当前 NixOS 只启用了 Qualcomm Iris 视频编解码器，没有启用摄像头采集链。因此现在的 `/dev/video0`、`/dev/video1` 是编解码器节点，不是 CSI/ISP 摄像头采集节点。

“摄像头已实现”需要先定义目标：

1. **最小目标**：一颗传感器能够通过 Linux media-controller/V4L2 抓取 raw Bayer 帧。
2. **完整目标**：预览、拍照、录像、自动曝光/白平衡/对焦、闪光灯、JPEG 和桌面应用。

第一个目标可以分阶段完成；第二个目标还需要 Qualcomm Spectra ISP/ICP 和 3A 用户空间支持，不能通过单个 DTS 节点或单个内核配置完成。

## 上游现状（2026-09-29 逐项核对）

- **CAMSS 仍无 SM8450。** torvalds master 的 `camss_dt_match[]` 只到 msm8916…sm8250、`qcom,sm8550-camss`、`qcom,sm8650-camss`、`qcom,x1e80100-camss`；`sm8450.dtsi` 里也只有 `camcc`（`clock-controller@ade0000`）和 `cci0/cci1`，没有任何 camss/csiphy/csid/vfe 节点。所以"补 sm8450 资源表 + camss 节点"这件事仍然要做。
- **但 680 代驱动已经在上游。** CSID-680 的提交说明写明 "This version of CSID has been shipped with SM8450 and x1e chips"，VFE-680 同理（`[PATCH v2 3/7]`/`[4/7]`，2025-03-14）；上游 x1e80100 已经用 `csid_ops_680`/`vfe_ops_680` 建资源表，sm8550 用 gen3 ops。需要写的是**资源表与 DTS，而不是 CSID/VFE 驱动本体**。
- **平台外围已就绪。** `i2c-qcom-cci.c` 匹配 `qcom,sm8450-cci`；`camcc-sm8450.c` 提供 `CAM_CC_MCLK0..7`、`CAM_CC_CCI_*`、`CAM_CC_IFE_*`、`CAM_CC_CSIPHY*`、`TITAN_TOP_GDSC`/`IFE_0/1/2_GDSC`/`SFE_0/1_GDSC`；`sm8450.dtsi` 已有 `config_noc`（`SLAVE_CAMERA_CFG`）与 `mmss_noc`（`MASTER_CAMNOC_HF/ICP/SF`）两条 camss 需要的 ICC 路径。
- **传感器：S5KJN1 已有主线驱动。** `drivers/media/i2c/s5kjn1.c`（`CONFIG_VIDEO_S5KJN1`，compatible `samsung,s5kjn1`）：chip id `0x38e1`、4 data lane、700 MHz link freq、4080×3072@30fps、CCI regmap。**24 MHz 是*上游驱动*的限制，不是传感器限制**：驱动在 probe 里断言 `clk_get_rate(mclk) == 24 MHz`（`s5kjn1.c:1313`），而本板 vendor DT 用的是 19.2 MHz（`clock-rates = <0x124f800>`），原厂在 19.2 MHz 下工作正常。两条路都可行：① 板级把 camcc MCLK 配成 24 MHz——**camcc-sm8450 的 MCLK 频表本来就有 24 MHz**（`ftbl_cam_cc_mclk0_clk_src` = 19200000 / 24000000 / 68571429，八个 MCLK 共用该表）；② 给驱动补 19.2 MHz 的 mode/init 表（vendor 表已在 `liuqin-mainline-blobs/camera/` 里）。IMX596、SC202CS 上游仍无驱动。
- **CSIPHY 还差一款 lane 表，且不能照抄 2.1.2。** 上游 `camss-csiphy-3ph-1-0.c` 有 sm8550(2.1.2)/sm8650(2.2.0)/x1e80100(2.1.2)，没有本板 vendor DT 写的 `qcom,csiphy-v2.1.3`（CSIPHY 在上游不是独立 platform driver，选择由 camss 单节点资源表完成）。补 2.1.3 之前必须先确定：lane 数量、lane mapping/顺序、lane enable/mask、settle（T_HS_SETTLE）与 DPHY timing、2.1.3 与 2.1.2 的寄存器差异、原厂实际写入序列。**已核实这些参数不在 vendor DT 里**（runtime DT 与 `dtbo.img` 中 `lane-assign`/`lane-mask`/`csi-lane*` 命中数全为 0），原厂把它们放在 `camera.ko` 的 CSIPHY datarate/settle 表（字符串可见 `Datarate/Settletime/lane_assign/lane_enable`），需要反汇编或按 datasheet/实测确定。
- **TPG 在 680 上没有现成实现。** 上游 `csid_ops_680.configure_testgen_pattern = NULL`（`camss-csid-680.c:426`），VFE-680 也没有 testgen op；有实现的是 gen2 CSID（`camss-csid-gen2.c` 里 `CSID_TPG_*` 寄存器块 0x600+ 与 `csid_configure_testgen_pattern`）。CSID-680 里已经引用了 TPG mux 位（`CSI2_RX_CFG0_TPG_MUX_SEL/TPG_MUX_EN`），所以给 680 补 TPG 是"照着 gen2 写一段小补丁"，但**不能把 TPG 当成阶段 1 的前置条件**。
- **libcamera 侧仍是 RFC。** CAMSS pipeline handler（2026-04，Hans de Goede）仍依赖 software ISP，示例只覆盖 x1e80100/Agetti OPE。

## 当前仓库状态

- 工作树当前修改集中在显示、CPU、温控、USB、Nix 固件和文档，没有摄像头驱动或摄像头设备树补丁。
- [`kernel/config.nix`](../../kernel/config.nix:200) 只显式启用了 `VIDEO_QCOM_IRIS`（`:199` 另有 `MEDIA_SUPPORT=module`）；但 7.2.5 构建以 arm64 defconfig 为基底，生成的 `.config` 里已经带来 `CONFIG_MEDIA_CONTROLLER=y`、`CONFIG_VIDEO_QCOM_CAMSS=m`、`CONFIG_I2C_QCOM_CCI=m`、`CONFIG_VIDEO_S5KJN1=m`（已在本机 `/nix/store/...-linux-...-7.2.5/kernel-config-final` 与 `...-modules/modules.alias` 中确认；`Iris` 能出 `/dev/video0/1` 说明模块树本身可用）。缺的是 DT/资源表——没有 camss/sensor 的 DT 节点，这些模块不会绑定，而不是 Kconfig 开关。
- [`docs/PORTING-NOTES.md`](../PORTING-NOTES.md:41) 记录的摄像头节点只有 Iris 编解码节点，没有 CSI/ISP capture 节点。
- 本地 `linux-sm8450-liuqin` 源码已经包含 `camss-csid-680.c` 和 `camss-vfe-680.c`，但只挂接了已有的 SoC resource table（例如 `sm8550-camss`、`x1e80100-camss`）；没有 `sm8450-camss`/`sm8475-camss` 的 Liuqin 平台资源表和 DT match，也没有本板三个传感器的驱动。

## 逐项缺口与现状（按原调查条目核对）

这里的“未知”专门指：现有 probe、原厂 DT、镜像或上游代码不能直接给出答案，不能仅靠打开配置解决。**2026-09-29 复核后的口径**：下面多数条目的事实已经能从原厂运行时 DT / `sensormodule.bin` / `camera.ko` 里读到，真正剩下的是"翻译成主线驱动 + 实机验证"；每条已按当前证据改写，未改写的部分是仍然缺证据的。

### A. SM8475 CAMSS 的平台边界

- **SM8475 的平台资源事实已经拿到，缺的是主线资源表与验证。** runtime DT 给出完整寄存器/中断/时钟/PD 清单：`csid0/1/2` @ `0xacb7000`/`0xacb9000`/`0xacbb000`（+`csid-lite0/1`）、`ife0/1/2` @ `0xac62000`/`0xac71000`/`0xac80000`（+`ife-lite0/1`）、`sfe0/1` @ `0xac9e000`/`0xaca6000`、`csiphy0..5` 从 `0xace4000` 起每 `0x2000`、`cam-cpas` @ `0xac13000` + camnoc @ `0xac19000`、`jpegenc/jpegdma` @ `0xac2a000`/`0xac2b000`、TPG13/14/15 @ `0xacf6000`/`0xacf7000`/`0xacf8000`；节点上带 `clock-names`/`clock-rates`/`clock-cntl-level`、`interrupts`、`gdsc-supply`，以及 CSID 的 `qcom,csid680_110`、VFE 的 `qcom,vfe680_110`、SFE 的 `qcom,sfe680`（与上游 CSID680/VFE680 代码同代）。不能直接照抄 `sm8550_resources`/`x1e80100_resources` 的是**表和 DTS 本身**，但每一项都可以从 vendor DT 填出（x1e80100 用的就是 `csid_ops_680`/`vfe_ops_680`；时钟名 `csid_clk_src`/`csid_clk`/`csiphy_rx_clk` 可对到 `CAM_CC_CSID_CLK_SRC`/`CSID_CLK`/`CSID_CSIPHY_RX_CLK`）。
- **CPAS 到 CAMSS 的绑定方式未知，但不阻塞 raw 路径。** 原厂把 CPAS、CDM、IFE/SFE、BPS、IPE、ICP、JPEG、SMMU 作为一个 Spectra 相机栈管理；主线 CAMSS 直接编程 CSID/VFE，不经过 CPAS。CPAS/CDM 只在需要统计块、带宽投票或 vendor 压缩时才是必需项。
- **680 硬件的实际实例关系部分已知。** 原厂有 8 个 CSID（含 CSID-lite）、3 个 IFE、2 个 SFE 和 6 个 CSIPHY；sensor→csiphy 已知是 3/2/1（sensor 节点 `csiphy-sd-index`），但"哪条 CSID 固定接哪个 IFE、哪个 RDI 实例给哪颗 sensor"仍需从 vendor `camera.ko` 的 route 表或 TPG 实验确认。
- **680_110 与上游 680 ops 的兼容性尚未证明（P0 验证项）。** vendor DT 写的是 `qcom,csid680_110`/`qcom,vfe680_110`（带硬件小版本），上游资源表用的是 `csid_ops_680`/`vfe_ops_680`。CSID-680 的上游提交自述 "shipped with SM8450 and x1e chips"，是很强的旁证，但寄存器偏移、IRQ、reset 与 route 行为是否逐位一致要在实机上验证：先读 vendor `camera.ko` 里该 IP 的寄存器版本/关键寄存器（或对比 vendor DT 的 `reg-cam-base`/`interrupts` 与上游资源表），再以最小 RDI 采集实测确认。
- **TPG 不是阶段 1 前置。** 上游 680 没有 TPG 实现（见"上游现状"），原厂 TPG13/14/15（@`0xacf6000`…）的线路也没被主线验证过。阶段 1 应以"真实 S5KJN1 raw 路径"为主；TPG 若要启用，需要先照 gen2 补 680 的 `configure_testgen_pattern` 小补丁，作为可选项。
- **带宽和格式路径仍未验证。** IFE/SFE 的 AXI/ICC 带宽公式、压缩/非压缩格式、UBWC 或 tile 约束没有可直接复用的 SM8475 文档；不过 vendor DT 已给出 `interconnects`（cam_ahb）与 `camera-bus-nodes` 的 level0/1/2 QoS 拓扑，ICC 表可以由它推导。raw 帧可能能工作，但不能据此推断 YUV/JPEG 会工作。

### B. 三颗传感器的真正缺口

主线已有 S5KJN1 驱动（`drivers/media/i2c/s5kjn1.c`，`CONFIG_VIDEO_S5KJN1`，compatible `samsung,s5kjn1`：chip id `0x38e1`、4 data lane、700 MHz link freq、4080×3072@30fps、CCI regmap），**但硬编码要求 24 MHz MCLK**（`drivers/media/i2c/s5kjn1.c:1313`），本板是 19.2 MHz；`IMX596`、`SC202CS` 则完全没有上游驱动（`drivers/media/i2c/Kconfig` 无对应符号）。

- **寄存器表和 mode table 就在 `.bin` 里；解析器已完成**（`liuqin-mainline-blobs/work/liuqin-sensormodule.py`，产物在 `liuqin-mainline-blobs/camera/`）。剩余工作是：解析结果逐项核对 → 转成 Linux 的 `cci_reg_sequence` mode table → 写驱动 → 实机验证。容器是自描述格式（`QTI Chromatix Header` + `Parameter Parser V3.4.0`），已实测的规模：S5KJN1 有 1173 组 `slaveAddr`/`registerData`/`delayUs` 写入、15 个 `regSetting` 组、6 个 `powerSetting`；IMX596 682 组/15/4；SC202CS 139 组/12/4；三种模式尺寸与 chip id/从地址都能从文件里直接读出（`cameraModuleData` 结构，见 `camera/RESULTS.md`）。
- **vendor mode 与上游 mode 不一致，需单独适配（P0）。** 上游 `s5kjn1.c` 用的是 **4080×3072@30fps**（以及 8160×6144@10fps），vendor `.bin` 给的是 **4080×3060 / 4080×2296 / 3840×2160 / 8160×6120**（crop/VTS/HTS 见 `camera/*.impl.md`），且 mode 表在第 128/249 笔之后与上游出现数值差异（`camera/RESULTS.md` 的校验输出）。⇒ 不能用"init 表对上了"推断上游 mode 表可用：先用上游已支持的一个 mode 验证出帧，再把 vendor 的 4080×3060（等）作为**独立的 mode 适配 + 验证任务**。
- **`.bin` 字段覆盖了原先列为未知的大部分内容。** 每个写入三元组自带 slave address、寄存器数据与微秒延时（分组 hold 与上电时序的原料）；另有 `resolutionInfo`/`streamConfiguration`/`transitionGroups`/`patternType`、`EEPROMDriverData`、`actuatorDriver`（仅 JN1 有）、`flashDriverData`（仅 JN1 有）。"没有公开 schema" 仍然成立，但不影响可行性。
- **I2C/CCI 侧主线已就绪。** `i2c-qcom-cci` 上游匹配 `qcom,sm8450-cci`，`sm8450.dtsi` 已有 `cci0@ac15000`/`cci1@ac16000`（挂 `TITAN_TOP_GDSC` + camcc 时钟）；三颗 sensor 的 CCI device/master 与 slave address 见 runtime DT。⇒ 传感器上电/寄存读写实验可以先于 CAMSS 做，剩下的只有 vendor 验证过的 register width/endian 与 CCI timing 细节。
- **CSI-2 endpoint 部分已知。** S5KJN1 有上游驱动给出的 4 data lane / 700 MHz；IMX596、SC202CS 的 lane 数与 lane 顺序仍要从 `.bin` 的 `streamConfiguration`/`resolutionInfo` 或实机实验确认。`csiphy-sd-index` 只说明绑定到哪条 PHY，virtual channel、data type、settle 需按 mode 填。
- **上电时序的原料在 `.bin` 与 vendor DT 里。** 每个 `regSetting` 自带 `slaveAddr`/`registerData`/`delayUs`，`powerSetting` 组给出 up/down 序列；runtime DT 给出 regulator/MCLK/RESET GPIO 绑定；`Xiaomi_Kernel_OpenSource/drivers/misc/wl2866d.c` 还带 camera PMIC（wl2866d）的 I2C 协议实现。仍需实测确认 enable 顺序、延时与 reset 释放时刻（错误时序会表现为"能读 chip ID 但不能稳定出帧"）。
- **实际模块和硬件 revision 未知。** 当前镜像名称能确认三个 module 名称，但不能证明所有 Liuqin 设备使用相同传感器、镜头、EEPROM 内容和校准版本。驱动不能把 Android HAL 的一组静态 metadata 当成所有设备的实测值。

### C. EEPROM、自动对焦和闪光灯

- **EEPROM layout 部分可得。** 芯片型号已知（GT24P128E/GT24P64E），三份 `.bin` 各带 `EEPROMDriverData` 段，`vendor/lib64/camera/com.qti.eeprom.liuqin_*.so` 是解析校准块的用户态实现；校准块偏移/CRC/内容仍需从这两处提取并在设备上用 CCI 读回验证。没有这些内容时可以先抓 raw，但不能声称照片校准正确。
- **GT9764 actuator 协议和校准部分可得。** JN1 的 `.bin` 带 `actuatorDriver` 段，`com.qti.actuator.liuqin_qtech_s5kjn1_gt9764_wide_i_actuator.so` 是 HAL 侧实现；I2C 地址、步进/绝对位置模式、限位与 EEPROM 中的 AF calibration 需从这两处提取。通用 V4L2 actuator 框架不能替代模块专用参数。
- **LED flash 控制路径部分已知。** runtime DT 有 `qcom,camera-flash@0`（指向 `pm8350c-flash-led` 的 flash/torch/switch source）与 JN1 的 `led-flash-src`；JN1 的 `.bin` 带 `flashDriverData`（含 strobe 寄存器等）。Linux 侧接到 `leds-qcom-flash`/flash class 的具体方式仍未验证，电流/超时/热保护也无主线基线。

### D. Spectra ISP/ICP 的闭源接口

- **`CAMERA_ICP` firmware ABI 未知，但 raw 不依赖它。** 固件文件（`bundle/camera/CAMERA_ICP.*`）已在手，`camera.ko` 里有 `CAMERA_ICP` 固件加载与 `cam_icp_*` 接口字符串可作逆向入口；没有公开的 mailbox、共享内存、命令、版本选择、崩溃恢复和 memory carveout 说明。
- **CPAS/CDM/IFE/SFE/BPS/IPE 的寄存器接口未公开。** 原厂下游驱动可以绑定这些组件，不等于它们的主线编程模型已知。尤其是 CPAS vote、CDM packet、IFE resource、SMMU SID 和中断事件之间的关系仍需逆向。
- **JPEG 硬件路径未知。** 原厂 JPEG 节点与 SMMU CB 已知（`jpegenc@ac2a000`/`jpegdma@ac2b000`，CB `jpeg` SID `0x20e0`/`0x24e0`），但没有证明主线 JPEG 驱动支持这组地址、clock、IOMMU 和格式，也没有确认 JPEG 是否依赖 ICP/CPAS 初始化。
- **固件变体选择未知。** `CAMERA_ICP`、`CAMERA_ICP_170`、`CAMERA_ICP_480` 的硬件目标、版本兼容性和选择条件没有公开定义，不能把所有文件一起安装后假定驱动会自动选对。
- **主线 ISP 处理能力未知。** 先实现 CSID/RDI raw capture 可能完全不需要 ICP；一旦要求 YUV、统计块、3A、JPEG 或多路并发，就会进入没有公开主线实现的 Spectra 产品接口。

### E. 调参、3A 和图像质量

- **vendor tuning 格式未知。** 镜像中有 `com.qti.tuned.*.bin`、`CFR_para_*`、LDC、AF、bokeh、motion tuning 和多个 AI 模型，但这些是 CamX/Xiaomi 私有格式，不是 libcamera IPA 的公开配置。
- **3A 算法没有开源替代物。** AE、AWB、AF、lens shading、black level、defect pixel、HDR 和噪声模型都缺少传感器专用参数。抓到 raw 帧不等于能生成稳定可看的预览。
- **多摄像头关系未知。** Android 有 6 个 HAL 逻辑设备、3 个物理 sensor；逻辑设备的复制、depth 配对、bokeh、同步和切换规则没有完整公开映射。主线初期应只暴露物理 sensor，不能直接仿造 6 个 HAL 节点。
- **镜头/方向/颜色元数据未知。** focal length、aperture、CFA 和 orientation 目前主要来自 Android metadata，不是对镜头和光学模块的独立测量；libcamera 需要重新定义这些 controls 和 metadata。

### F. 用户空间和 API 边界未知

- **没有 Liuqin 的 libcamera pipeline handler。** 上游 CAMSS handler 仍在演进，不能假设它已经支持 SM8475 的 680 路径、这些三个 sensor 或 vendor 的 ISP。
- **没有 sensor-specific IPA/tuning。** 即使 V4L2 raw capture 成功，libcamera 仍缺少曝光/白平衡/镜头校准和格式转换策略。
- **Android Camera HAL 不可直接移植。** `vendor.qti.camera.provider`、CamX provider 和 Xiaomi quickcamera 都是 Android HIDL/AIDL、ION/DMABUF、vendor metadata 和 Spectra API 的组合，不能作为 Linux V4L2 用户空间后端直接运行。
- **帧时间戳和控制语义未知。** sensor exposure 的 frame-sync、SOF/EOF timestamp、异步 control 生效帧、metadata buffer 和错误恢复语义，需要在主线管线中重新定义。

### G. 可验证性和安全边界未知

- **没有已知的硬件 lane probe 方法。** 不拆机时只能通过原厂日志、二进制和失败码推断 lane；错误 lane 可能表现为静默无帧，而不是明确的 probe error。
- **camera SMMU 的 SID 已在 vendor DT 里，缺的是主线映射。** runtime DT 的 `qcom,cam_smmu` 节点给出各 context bank 的 `iommus` 三元组：ife/sfe 用 `0x800/0x820/0xc00/0xc20/0x840/0x860/0xc40/0xc60`，cpas-cdm/rt-cdm 用 `0x20c0/0x24c0/0x20a0/0x24a0`，icp 用 `0x2020/0x2000/0x2420/0x2400/0x2040/0x2060/0x2440/0x2460/0x2100/0x2500/0x2080/0x2480/0x2120/0x2520`，jpeg 用 `0x20e0/0x24e0`。主线 camss 节点用 `iommus = <&apps_smmu <SID> <mask>>`（sm8550 是 `0x800 0x20`），所以这些值可以作为**初始假设**照填；但 `iommus`/context bank/mask 与实际 DMA 路径必须用**首次 DMA、SMMU fault 检查与长时间采集**验证（映射错误只在起流后才触发 fault）。
- **stream on/off、异常恢复和 suspend/resume 未验证。** 原厂 camera driver 的完整状态机包含 CPAS vote、ICP、sensor、PHY、SMMU 和 IFE；主线需要单独测试重复开关流、进出待机和传感器探测失败后的回滚。
- **多路并发和显示协同未知。** 同时预览、拍照、录像或摄像头与显示/GPU 高负载运行时的内存带宽、温控和功耗限制没有基线。
- **无公开可重现的测试夹具。** 目前没有平场、色卡、几何失真、AF chart 或高频率长时间采集的标准测试数据；验收必须先以 raw checksum、帧率和错误统计为主。

### H. 固件和资料的可发布性未知

- `CAMERA_ICP`、sensor module、tuning 和 CamX 二进制的再分发许可没有在当前仓库中确认。
- 即使技术上需要这些文件，也不能直接把原厂 `super.img` 中的全部 camera blob 提交到公共 Nix 包；应使用 operator-supplied firmware、哈希清单和明确的本地安装路径。
- 传感器寄存器表、校准数据和 vendor tuning 可能受模块厂商或 Xiaomi 许可限制；是否能把逆向得到的表写进 GPL 驱动，需要单独记录来源和许可判断。

## 未知项的优先级

| 优先级 | 必须先解决的未知 | 原因 | 建议方法 |
| --- | --- | --- | --- |
| P0 | SM8475 CAMSS resource table + camss 单节点 DTS（资源事实已从 runtime DT 取得） | 没有它们无法判断主线 raw capture 是否可行 | 以 `sm8550_resources` 为骨架、用 runtime DT 逐项填；再照 x1e80100 用 `csid_ops_680`/`vfe_ops_680`；**接真实 S5KJN1 的 RDI 路径**验证（TPG 不是前置） |
| P0 | `csid680_110`/`vfe680_110` 与上游 680 ops 的寄存器/IRQ/reset/route 是否一致 | 不一致则 CSID/VFE 驱动要改，资源表假定失效 | 对比 vendor `camera.ko` 的版本/关键寄存器与上游资源表，再用最小 RDI 采集实测 |
| P0 | CSIPHY 2.1.3 参数：lane 数/mapping/enable-mask、settle、datarate、与 2.1.2 的寄存器差异 | PHY 不对齐则 CSID 收不到数据（参数不在 vendor DT 里，见"上游现状"） | 反汇编 `camera.ko` 的 CSIPHY datarate/settle 表，或按 datasheet 推 + 实测调 settle |
| P0 | 第一颗 sensor 的 mode table、上电时序与 endpoint | 决定 raw capture 能否出帧 | 解析产物在 `liuqin-mainline-blobs/camera/`；用 CCI 起上电/探测实验（阶段 0.5） |
| P0 | vendor mode 与上游 mode 的差异（JN1：4080×3060 vs 上游 4080×3072 等） | init 表一致 ≠ mode 表可用；直接套上游 mode 可能出不了正确帧 | 先用上游已支持的 mode 验证出帧，再把 vendor mode 作为独立适配 + 验证任务 |
| P0 | S5KJN1 的 MCLK 约束（上游驱动只收 24 MHz） | 不解决则上游驱动 probe 直接失败 | 板级把 camcc MCLK 配成 24 MHz（频表里已有），或给驱动补 19.2 MHz 表（vendor 表已就绪） |
| P1 | CSID/VFE 与 CPAS/IFE 的边界 | 决定只做 RDI 还是必须移植 vendor Spectra 部分 | 先做 RDI；按是否需要 YUV/统计块划分驱动边界 |
| P1 | CAMERA_ICP ABI 和固件变体 | 完整 ISP/JPEG/3A 可能依赖它，但 raw MVP 不依赖 | 先不接 ICP；需要时从 `camera.ko`（`cam_icp_*`、`CAM_ICP_CMD_GENERIC_BLOB_CFG_IO`）逆向 |
| P1 | EEPROM、AF、flash 数据格式 | raw 可先绕开，但完整后置拍照绕不开 | 解析 `.bin` 的 `EEPROMDriverData`/`actuatorDriver`/`flashDriverData` + 读 `com.qti.*.so` 实现 + 上机读 EEPROM |
| P2 | tuning、3A、libcamera IPA | 不影响最初 raw 帧，但决定是否能有可用预览 | 先采用 raw + 软件 ISP，再评估公开 tuning 格式 |
| P2 | 多摄像头逻辑设备、bokeh、depth 同步 | 属于完整 Android 功能，不应阻塞单 sensor bring-up | 单 sensor 稳定后再从 HAL metadata 和运行时序列还原 |

除非 P0 项目已有实验数据，否则文档中“支持某个 sensor”只能写成“已确认硬件存在”，不能写成“已有可用驱动”。

## 原厂硬件证据

审计报告确认三颗物理传感器：

| 位置 | 传感器 | 原厂连接和附属器件 |
| --- | --- | --- |
| 后置主摄 | Samsung S5KJN1，ID `0x38e1` | CCI0、CSIPHY3、GT24P128E EEPROM、GT9764 自动对焦、LED flash |
| 前置 | Sony IMX596，ID `0x0596` | CCI0、CSIPHY2、EEPROM，无独立对焦马达 |
| 深度/黑白 | SmartSens SC202CS，ID `0xeb52` | CCI1、CSIPHY1、EEPROM |

完整传感器节点、GPIO、regulator、MCLK 和 I2C 地址见 [`LIUQIN-HARDWARE.md`](../../../liuqin-audit/LIUQIN-HARDWARE.md:762)。SMMU 的 SID/context bank 已可由 runtime DT 的 `qcom,cam_smmu` 节点直接读出（见 G 节）；现在仍未独立确认的关键参数是 IMX596/SC202CS 的 CSI-2 lane 数量/映射、三颗 sensor 的实测 EEPROM 内容，以及六个 Android HAL 逻辑设备与三颗物理传感器的全部对应关系。

原厂运行时 DT 可以看到：

- `qcom,cam-cpas@ac13000`
- CCI0/CCI1
- CSIPHY0-5
- CSID、CSID-lite
- IFE、SFE、BPS、IPE、ICP、JPEG
- `qcom,msm-cam-smmu`
- camera clock controller 和多个 camera power domain

节点和地址见 [`final-runtime.dts`](../../../liuqin-audit/evidence/final-runtime.dts)。原厂 dmesg 还记录了所有组件绑定成功、`Spectra camera driver initialized`，以及 `CAMERA_ICP` 下载成功。这证明硬件连接和下游驱动链已经在设备上工作过。

## 小米镜像中的固件证据

官方镜像提取结果包含：

- `CAMERA_ICP.b00` 到 `CAMERA_ICP.b21`
- `CAMERA_ICP.mdt`、`CAMERA_ICP.elf`
- `CAMERA_ICP_170.elf`、`CAMERA_ICP_480.elf`
- `evass`、`evautil64`

这些文件记录在 [`liuqin-mainline-blobs/extracted/EXTRACTION.md`](../../../liuqin-mainline-blobs/extracted/EXTRACTION.md)。同一提取树里还有：三份 `super/fs_vendor_a/lib64/camera/com.qti.sensormodule.*.bin`（sensor 寄存器/mode/上电/EEPROM/AF/flash 数据）、`lib64/hw/camera.qcom.so`（CamX 核心、`.bin` 的解析者）、`super/fs_vendor_dlkm_a/lib/modules/camera.ko`（vendor camera 内核栈，含 `cam_icp_*` 与源码路径字符串）、以及 `com.qti.eeprom.*.so`/`com.qti.actuator.*.so`/`com.qti.sensor.*.so`（HAL 侧小库，导出 `Get*LibraryAPIs`）。

当前 [`pkgs/firmware.nix`](../../pkgs/firmware.nix:87) 的固件契约没有 `CAMERA_ICP` 或 `evass` 条目，只覆盖其他已经接入的固件。只有在主线驱动实际请求这些文件时，才应将其加入 Nix 固件包，并补上来源、哈希和许可证记录。原厂 `camera.ko` 等 vendor `.ko` 不能直接复用，它们依赖 Android 5.10 GKI 和下游 Spectra 架构。

## 缺口 → 来源对照（哪些能从小米产物里得到）

结论：**平台资源、sensor 寄存器/mode/上电序列、EEPROM/AF/flash 数据、ICP 固件都已经在手上**；只有"主线驱动代码、ICP ABI 语义、3A/tuning 消费方"需要新写或逆向。

| 缺口 | 来源 | 具体位置 | 剩余工作 |
| --- | --- | --- | --- |
| CAMSS 寄存器/中断/时钟/PD/SID/ICC | 原厂运行时 DT（已 merge 的最终结果）与 `dtbo.img` | `liuqin-audit/evidence/final-runtime.dts`（csid/ife/sfe/csiphy/cpas/cam_smmu/camcc 节点）；`liuqin_images_.../images/dtbo.img`、`liuqin-stock-dump/images/dtbo_a.img` 含 `qcom,cam-sensor`/`csiphy-sd-index`/camcc 覆盖 | 翻译成 camss 单节点资源表 + sm8450 DTS |
| sensor 寄存器表 / mode table / 上电序列 | `com.qti.sensormodule.*.bin` | `liuqin-mainline-blobs/extracted/super/fs_vendor_a/lib64/camera/`（三份）+ `lib/`（32 位副本） | **已解析完成，实现级产物已生成**：`liuqin-mainline-blobs/work/liuqin-sensormodule.py`；每颗 sensor 的 `camera/*.txt`（逐笔写表）、`*.impl.md`/`*.impl.json`（模式/分辨率/VTS/HTS/crop/lane/PLL/帧率 + 全部写表）；S5KJN1 的 init 表与上游驱动 30/30 校验一致；详见 `camera/RESULTS.md` |
| sensor 上电时序 / PMIC | vendor DT + Xiaomi 开源内核 | runtime DT 的 `qcom,cam-sensor*`/`qcom,eeprom*`/`qcom,actuator0`；`Xiaomi_Kernel_OpenSource/drivers/misc/wl2866d.c` | 按 `.bin` 的 `powerSetting`/`delayUs` 实测核对 |
| EEPROM / AF / flash 数据 | `.bin` 的 `EEPROMDriverData`/`actuatorDriver`/`flashDriverData` + HAL `.so` | `lib64/camera/com.qti.eeprom.*.so`、`com.qti.actuator.*.so`、`com.qti.sensor.*.so`；runtime DT 的 `qcom,camera-flash@0`（`pm8350c-flash-led`） | 提取格式并读回设备实测值 |
| ICP 固件 | 已在 `liuqin-mainline-blobs/extracted/bundle/camera/` | `CAMERA_ICP.*`、`evass*` | raw 阶段不需要；需要时从 `camera.ko` 逆向 ABI（`cam_icp_*`、`CAM_ICP_CMD_GENERIC_BLOB_CFG_IO`） |
| vendor 编程参考 | `camera.ko`（6.5 MB，stripped 但含源码路径与命令字符串） | `super/fs_vendor_dlkm_a/lib/modules/camera.ko`（+`cameralog.ko`） | 反汇编/字符串对照 CSID/VFE/CPAS/ICP 寄存器序列 |
| sensor 驱动 | **上游主线**（部分） | `drivers/media/i2c/s5kjn1.c`（S5KJN1）；IMX596/SC202CS 无 | IMX596/SC202CS 需新写；S5KJN1 需解决 MCLK 24 MHz 约束 |
| 3A / tuning / 用户空间 | 无主线等价物 | `com.qti.tuned.*.bin` 是同一容器格式的 Chromatix 模块表 | 走软件 ISP（libcamera CAMSS RFC）或后续自研，不复用 vendor tuning |

注意：`Xiaomi_Kernel_OpenSource` 是 GKI 树 + `techpack/stub`（`techpack/` 下只有 `stub/`），**没有 camera 驱动或 sensor 寄存器表**，不要指望从那里补驱动；它对本项目有用的只有 `wl2866d.c` 这类少量外设驱动与 `build.config.msm.liuqin`。

## 缺失的实现层

### 1. 内核采集核心

- [ ] 启用或适配 `VIDEO_QCOM_CAMSS`、media-controller、V4L2 subdev、videobuf2 DMA-SG。
- [ ] 适配 SM8475/Waipio 的 CSIPHY、CSID、VFE/IFE/SFE 资源。
- [ ] 接入 camera clock、reset、power-domain、interconnect 和 runtime PM。
- [ ] 接入 camera SMMU/IOMMU 以及正确的 stream ID/context bank。
- [ ] 确认通用 CAMSS 驱动能否覆盖该平台的 680 系列 CSID/VFE；不能覆盖的部分需要补平台驱动。

上游已经在逐步补充 SM8450/X1E 使用的 CSID680 和 VFE680 支持，但这仍不是 Liuqin 的完整摄像头支持：[CSID680 patch](https://lists.openwall.net/linux-kernel/2025/03/14/1749)、[VFE680 patch](https://lists.openwall.net/linux-kernel/2025/03/14/1750)。SM8450 相机还有多个独立 VFE 电源域：[CAMSS power-domain 讨论](https://www.spinics.net/lists/linux-media/msg215018.html)。

### 2. 设备树和 media graph

- [ ] 添加 camss 单节点（sm8550 形态：`reg`/`reg-names` 覆盖 csid0..2、csid-lite、vfe/ife0..2、ife-lite、csiphy0..5、csid_wrapper）、power-domain、interconnect、SMMU 与 media graph。
- [ ] 补 `camss-csiphy-3ph-1-0.c` 的 2.1.3 lane 表。
- [ ] 添加 camera power-domain、interconnect、pinctrl、reset 和 regulator。
- [ ] 添加 SMMU stream ID 与 mask（vendor DT 已给出 SID 清单）。
- [ ] 为每个 sensor 建立标准 `ports`/`endpoint`/`remote-endpoint` 连接。
- [ ] 从 `.bin`/原厂 DT 和实机测试恢复 IMX596/SC202CS 的 CSI-2 lane 数量、lane mapping、settle 参数和 Bayer 格式。

vendor DT 中的 `csiphy-sd-index` 不能直接代替标准 Linux media graph；部分 lane 和 mode 信息藏在 vendor sensor library 中，必须单独提取和验证。

### 3. 传感器驱动

- [ ] 接入上游 S5KJN1 驱动并解决 MCLK 24 MHz 约束（改板级 MCLK 或补 19.2 MHz mode table）。
- [ ] 实现或移植 IMX596 驱动。
- [ ] 实现或移植 SC202CS 驱动。
- [ ] 实现 MCLK、regulator、reset GPIO 和 runtime suspend/resume（三颗共用 19.2 MHz cam_clk 配置）。
- [ ] 实现 Bayer 格式、分辨率、帧率、曝光、增益和 V4L2 controls。
- [ ] 建立 GT24P128E/GT24P64E EEPROM 支持。
- [ ] 为 S5KJN1 增加 GT9764 自动对焦和 LED flash 支持。

第一颗 sensor 的取舍：S5KJN1 有上游驱动但带 AF/flash、且要处理 24 MHz MCLK；IMX596 没有驱动但模块最简单（无对焦/闪光灯）、`.bin` 里只有 682 组写入。若目标是"最快看到 raw 帧"，先做 S5KJN1（复用上游驱动 + 修 MCLK）；若目标是"最小新代码路径"，先做 IMX596（自己写一份最简单的 CCI 驱动，后续 IMX596 驱动骨架还能复用到 SC202CS）。

### 4. ISP、ICP 和图像处理

- [ ] 先验证 CSID/RDI 到 V4L2 的 raw Bayer 路径。
- [ ] 再验证 IFE/VFE/SFE 的处理路径。
- [ ] 决定是否需要 `CAMERA_ICP` 固件，并确认主线驱动的 firmware ABI。
- [ ] 实现或接入 3A（AE/AWB/AF）和 sensor tuning。
- [ ] 验证 JPEG、闪光灯和自动对焦。

主线 CAMSS 的视频节点是 media-controller/V4L2 管线，需要先建立 subdevice 链路再启动 DMA：[Linux `qcom-camss-video.c`](https://github.com/torvalds/linux/blob/master/drivers/media/platform/qcom/camss/camss-video.c)。它不等于 Android Camera HAL，也不会自动提供厂商的 3A、tuning 或 Spectra ICP 行为。

### 5. 用户空间

- [ ] 使用 `media-ctl` 验证实体、链路和格式协商。
- [ ] 使用 `v4l2-ctl` 抓取并校验 raw 帧。
- [ ] 评估 libcamera CAMSS pipeline handler。
- [ ] 加入软件 ISP 或硬件 ISP 的格式转换路径。
- [ ] 最后再接 PipeWire/GStreamer 和桌面相机应用。

libcamera 的 CAMSS 支持仍在推进，早期方案依赖软件 ISP：[CAMSS pipeline RFC](https://lists.libcamera.org/pipermail/libcamera-devel/2026-April/058088.html)。因此用户空间不应先于内核 raw capture 开始。

## 分阶段实施顺序

### 阶段 0：只读取证和平台建模

- [x] 写 "QTI Chromatix / Parameter Parser V3.4.0" 容器解析器（`liuqin-mainline-blobs/work/liuqin-sensormodule.py`），导出三颗 sensor 的 `regSetting`/`resolutionInfo`/`streamConfiguration`/`powerSetting`/`EEPROMDriverData`/`actuatorDriver`/`flashDriverData`；结果见 `liuqin-mainline-blobs/camera/`（S5KJN1 的 init 表已与上游驱动 30/30 校验一致）。
- [ ] 从 runtime DT 汇总 camss 资源表（基址/中断/时钟/PD/SID/ICC）与 sensor 电源/GPIO/MCLK/CCI 绑定。
- [ ] 读取或整理 EEPROM 内容；记录校准数据是否必须才能出图。
- [ ] 在设备上确认 camera clock、power-domain 和 interconnect 的实际启停顺序。

### 阶段 0.5：CCI / MCLK / 上电实验（不依赖 CAMSS）

- [ ] 在主线内核打开 cci0/cci1、camcc MCLK 与 sensor regulator，用 i2c 工具读三颗 sensor 的 chip ID（`0x38e1/0x0596/0xeb52`）。
- [ ] 用解析出的 `powerSetting` 校正上电顺序/延时，直到三颗都能稳定读 ID。

### 阶段 1：CAMSS 骨架 + 真实 S5KJN1 raw 路径（TPG 为可选实验）

- [ ] 写 sm8450 camss 资源表 + 单节点 DTS（含 CSIPHY 2.1.3 参数），**直接接真实 S5KJN1**。
- [ ] 建立 `media-ctl -p` 可见的媒体拓扑。
- [ ] 让 V4L2 DMA 节点能够稳定抓取 raw 帧（RDI 路径）。
- [ ] 检查无 SMMU fault、DMA timeout、clock/power-domain 错误。
- [ ] （可选，不阻塞）照 `camss-csid-gen2.c` 给 680 补 `configure_testgen_pattern`，再用 TPG 做无传感器自检。

### 阶段 2：单颗传感器 raw capture

- [ ] 按上面的取舍选定第一颗 sensor（S5KJN1 走上游驱动 + 处理 24 MHz MCLK，或 IMX596 从零写驱动）。
- [ ] 验证 I2C/CCI 探测、reset、MCLK、CSI-2 链路和 Bayer 帧。
- [ ] 保存帧尺寸、帧率、checksum 和完整 dmesg 作为回归基线。

### 阶段 3：其余传感器和附属器件

- [ ] 接入第二颗 sensor。
- [ ] 接入第三颗 sensor。
- [ ] 加入 EEPROM、GT9764 自动对焦和 LED flash。

### 阶段 4：处理后图像和应用

- [ ] 验证 IFE/VFE/SFE。
- [ ] 处理 ICP firmware、JPEG 和 3A/tuning。
- [ ] 接入 libcamera、PipeWire/GStreamer 和相机应用。

### 阶段 5：收尾（相机链路稳定后）

- [ ] **删除 `modules/liuqin/camera-debug.nix`**，并从 `modules/liuqin/default.nix` 的 imports、
      `config/example.nix`（已注释的 `cameraDebug.enable` 行）、`pkgs/camtest.nix` 与 `overlay.nix` 的
      `liuqinCamtest` 条目里一并清掉——它是 bring-up 台架工具（`v4l-utils`/`i2c-tools`/`liuqin-camtest`，
      默认关），不是运行时依赖；判据：三颗 sensor 的 raw 采集、模式矩阵与 suspend/resume 连续通过，
      且不再需要手工 `media-ctl`/`v4l2-ctl` 排查。
- [ ] 若 `i2c-tools` 在调试结束后仍被需要（例如读 EEPROM 校准），把该用途单独记录成一个明确的操作流程，
      而不是继续挂着整包工具。
- [ ] 复核本文档里的临时说明（"待确认/占位/样板值"）是否已全部变成实测值或删除。

## 传感器 endpoint 表（可直接写 DTS / 驱动）

数据来源：runtime DT（`liuqin-audit/evidence/final-runtime.dts` 的 `qcom,cam-sensor0/1/2`）、
`sensormodule.bin` 的 `cameraModuleData`（`liuqin-mainline-blobs/camera/*.impl.json`）、
`LIUQIN-HARDWARE.md` 的 HAL 交叉表。标"待确认"的必须靠实机确认（见下节测试阶梯）。

| 项目 | S5KJN1（后置主摄） | IMX596（前置） | SC202CS（深度） |
| --- | --- | --- | --- |
| vendor DT 节点 | `qcom,cam-sensor0` | `qcom,cam-sensor1` | `qcom,cam-sensor2` |
| CCI（vendor `cci-device`/`cci-master`） | 1 / 1 | 1 / 0 | 1 / 0 |
| 主线 CCI 总线（阶段 0.5 用 `i2ctransfer` 确认） | 审计判 `cci0`；vendor `cci-device` 三颗都是 1，不能据此区分 `cci0`/`cci1` | 审计判 `cci0`（同上） | 审计判 `cci1`，但它的 `cci-device` 与上两行同值，该判定来源未说明——按待确认处理 |
| I2C 8 位写地址 / 7 位 | 0x20 / 0x10 | 0x20 / 0x10 | 0x6C / 0x36 |
| chip-id 寄存器 / 期望值 / 掩码 | `0x0000` / `0x38E1` / `0xFFFFFFFF` | `0x0016` / `0x0596` / `0xFFFFFFFF` | `0x3107` / `0xEB52` / `0x0000FFFF` |
| camcc MCLK | `CAM_CC_MCLK2_CLK`（DT clocks 0x50） | `CAM_CC_MCLK5_CLK`（0x56） | `CAM_CC_MCLK1_CLK`（0x4e） |
| MCLK 频率 | 19.2 MHz（vendor）/ 24 MHz（上游驱动约束） | 19.2 MHz | 19.2 MHz |
| MCLK / RESET（TLMM GPIO） | 102 / 126 | 105 / 127 | 101 / 24 |
| regulators（vendor DT 顺序） | cam_clk, cam_vdig, cam_vana, cam_vio, cam_vaf, cam_v_custom1, cam_vana1 | cam_clk, cam_vana, cam_vdig, cam_vio, cam_v_custom1, cam_vana1 | cam_clk, cam_vana, cam_vio |
| CSIPHY | 3 | 2 | 1 |
| data lane 数 | 4（上游驱动 + `0x0114`=0x300/0x301） | 4（`0x0114`=0x03） | 待确认（文件无 `0x0114`） |
| link frequency | 700 MHz（由 mode 数与上游交叉推出） | 待确认（PLL 寄存器待解/实测） | 待确认 |
| 首个验证 mode | 4080×3060（rec 904；或先用上游 4080×3072） | 2592×1952（rec 291） | 1600×1200（rec 132） |
| 寄存器访问宽度 | 16 位地址 + 16 位数据 | 逐字节（MSB@低地址） | 逐字节 |
| CFA / Bayer（HAL 元数据） | GBRG | BGGR | MONO |

写表、模式参数（VTS/HTS/crop/PLL/推算帧率）见 `liuqin-mainline-blobs/camera/*.impl.{md,json}`。

## 命名、内核集成与部署

- **命名**：硬件是 SM8475，但主线按家族命名（`sm8450.dtsi`/`qcom,sm8450-camcc`/`qcom,sm8450-cci` 已如此）。
  CAMSS 沿用同一规则：在 `sm8450.dtsi` 增 `camss: isp@acb7000 { compatible = "qcom,sm8450-camss"; }`，
  liuqin.dts 继承；**不新建 `sm8475-camss`**，避免资源表命名分裂。
- **补丁落点**：`liuqin-nixos/patches/kernel/`（构建的 7.2.5 树是交付树）；`linux-sm8450-liuqin`（6.17）
  只作参考。CAMSS 资源表补丁 → `patches/kernel/00xx-liuqin-camss-sm8450.patch`，传感器驱动/DT 同理。
- **Kconfig 显式化**（不要依赖 defconfig 偶然带出）：`MEDIA_SUPPORT`、`MEDIA_CONTROLLER`、
  `VIDEO_V4L2_SUBDEV_API`、`VIDEOBUF2_DMA_SG`、`VIDEO_QCOM_CAMSS`、`I2C_QCOM_CCI`、`VIDEO_S5KJN1`
  （+ 新传感器符号）、`ARM_SMMU`/`IOMMU_SUPPORT`、`INTERCONNECT_QCOM` 与所需 ICC provider。
- **DTB 来源**：内核构建输出（NixOS 的 kernel 包会带 DTB；本仓已用 `patches/kernel/0001-*` 加板级 DTS），
  不需要单独 DTB 通道。
- **模块部署**：NixOS 系统闭包自带 kernel modules（Iris 出 `/dev/video0/1` 已证明）；新驱动进
  `boot.kernelModules` 或由 DT compatible 触发 udev 自动加载。
- **回滚**：NixOS generations（菜单 2 = Generations / `nixos-rebuild --rollback`）；
  **不要**动 `boot_a`，也不要把自研镜像刷进任何槽位（见 AGENTS.md §7）。

## 一次写完再上机：信息完备性审计（2026-09-29）

要写的产物 × 输入齐备度：

| 产物 | 已有输入 | 仍缺 / 需要写与验证 | 补齐方式 |
| --- | --- | --- | --- |
| S5KJN1 驱动（扩上游 `s5kjn1.c`） | probe（0x0000→0x38E1@0x20）、init（30/30 已校验）、lane=4、link=700 MHz、寄存器宽度、曝光/增益寄存器；**上游 2 个 mode**（4080×3072@30、8160×6144@10，PLL 为 24 MHz 版）+ **vendor 4 个 mode**（4080×3060 / 4080×2296 / 3840×2160 / 8160×6120，PLL 为 19.2 MHz 版，见 `camera/*.impl.md`） | 没有"未知信息"；但 **vendor 的 4 个 mode 还不是上游代码**，要新增 mode 表并逐个实机验证；上电时序/延时、Bayer(=GBRG?)、VC/data type/lane 顺序待实测 | 写代码（mode 表直接照 `camera/*.impl.json`）+ 上机 |
| IMX596 驱动（新写） | probe（0x0016→0x0596@0x20）、init（364 笔）、4 个 mode 表（VTS/HTS/crop）、lane=4（`0x0114`=3）、逐字节访问 | **MIPI 数据率（link freq）**、每 mode 的绝对 fps | 见下方 Android 采集（**命令待实跑验证**）；或 datasheet |
| SC202CS 驱动（新写） | probe（0x3107→0xEB52@0x6C）、117 笔 mode 表、HTS/VTS（`0x320c/0x320e`）、逐字节访问 | **lane 数**（`0x301f=4` 语义未证）、**数据率** | 同上 |
| CAMSS 资源表（`qcom,sm8450-camss`） | 全部基址/IRQ/时钟名与速率/PD/ICC/SID/bus 拓扑（runtime DT） | CSIPHY 2.1.3 的**寄存器数值**：lane enable/mask、settle、datarate 对应表（数据结构、寄存器布局、初始化流程、代码框架可复用 2.1.2） | 框架抄 2.1.2；数值上机调 + vendor 日志对照 |
| **CAMSS 路由表（P0）** | `csiphy-sd-index`（wide=3 / front=2 / depth=1）；CSID↔PHY 的 mux 是**可编程**的 | 每颗 sensor→哪条 CSID、用哪个 RDI、CSID→哪个 IFE、media-graph 的 endpoint、VFE 出来后对应哪个 `/dev/videoN`。**这些由我们定义**（不是硬件未知），但必须写进 DTS 并实测；vendor 实际用的路由可从 `camera.ko` 日志交叉确认 | 设计 + 上机（`media-ctl -p` / `v4l2-ctl`） |
| `sm8450.dtsi` camss 节点 + binding yaml | reg-names/clock-names/PD/ICC 可按驱动源码推导（camss 按名字匹配，顺序不敏感） | 无 | — |
| `liuqin.dts` sensor 节点 | CCI/MCLK（MCLK2/5/1）/复位 GPIO（126/127/24）/全部供电轨 | 无 | — |
| Kconfig / 模块装载 | 符号清单与 defconfig 现状已知 | 无 | — |
| 上电顺序与延时 | `.bin` 的 `powerSetting` 候选 + 电平 | 精确顺序/延时未证 | 首版常规顺序 + 0 延时，上机按 chip-id 读数调 |

**MCLK 冻结（写代码前定案，时钟与表必须配套，不可混用）**

| sensor | camcc MCLK | 频率 | 配套表 |
| --- | --- | --- | --- |
| S5KJN1 | `CAM_CC_MCLK2_CLK` | **24 MHz** | 上游表（VCO = 24/4×140 = 840 MHz） |
| S5KJN1（vendor mode 任务） | 同上 | 19.2 MHz | vendor 表（VCO = 19.2/3×131 = 838.4 MHz） |
| IMX596 | `CAM_CC_MCLK5_CLK` | 19.2 MHz | vendor 表 |
| SC202CS | `CAM_CC_MCLK1_CLK` | 19.2 MHz | vendor 表 |

⇒ 第一版 JN1 直接用**上游 2 个 mode + 24 MHz**（不改上游驱动）；vendor 的 4 个 mode 作为独立任务（要么切 19.2 MHz，要么按 24 MHz 重算 PLL 值）。

**clock / regulator / GDSC / reset 分开表达**（避免写错 binding）：

- sensor 节点：`clocks = <&camcc CAM_CC_MCLKx_CLK>`、`clock-names = "xvclk"`、`reset-gpios`、各 `*-supply`；
- `TITAN_TOP_GDSC`（vendor 的 `cam_clk-supply`）属于 CCI/CAMSS 平台节点的 `power-domains`，**不要**塞进 sensor 的 regulator 列表；
- CSIPHY 的 0.9 V/1.2 V（`pm8350_l5`/`pm8350c_l10`）属于 CAMSS 节点的 `vdda-phy`/`vdda-pll`；
- 板的 AMOLED/相机 LDO 是 `regulator-fixed` + TLMM GPIO，按下面表写。

`liuqin.dts` 需要的供电轨（全部已从 runtime DT 解析，极性 `enable-active-high`）：

| 轨 | 节点类型 | 值 |
| --- | --- | --- |
| camera_wide_dvdd_ldo | fixed + TLMM 85 | 1.1 V |
| camera_wide_avdd_ldo | fixed + TLMM 52 | 2.8 V |
| camera_front_vdig_ldo | fixed + TLMM 74 | 1.1 V |
| camera_front_avdd_ldo | fixed + TLMM 119 | 2.9 V |
| camera_deep_avdd | fixed + TLMM 118 | 2.8 V |
| sensor vio | `pm8350c_l1`（wide/front）/ `pm8350c_l4`（depth） | 1.8 V |
| wide vaf / v_custom1 / vana1 | `pm8350c_l7` / `pm8350c_s1` / `pm8350_s12` | 2.75 / 1.9 / 1.35 V |
| CSIPHY 0.9 V / 1.2 V | `pm8350_l5` / `pm8350c_l10` | 0.9 / 1.2 V |

（PMIC LDO 节点按 `sm8450-xiaomi-cupid.dts` 的写法在 liuqin.dts 里定义；主线的 `pm8350*.dtsi` 只提供 PMIC 骨架。）

**S5KJN1 的"输入齐全"要读作"已知输入齐全，仍需实机确认"**，残留项：① vendor 4 个 mode 的移植与验证；② `csid680_110` 与上游 680 ops 的逐位一致性；③ CSIPHY 2.1.3 数值；④ sensor→CSID→RDI→IFE 路由与 video node；⑤ 上电时序/延时与关断顺序；⑥ Bayer(=GBRG)、VC、data type、lane 顺序。

**Android 采集（注意：命令来自 vendor `camera.ko` 的打印字符串，尚未在任何真机上实跑验证；若打不出这些字段就退化为 datasheet/逆向）**：

```sh
# 打开相机 App 之后：
adb shell dmesg | grep -iE 'datarate|settle|lane_assign|lane_enable|lane_cnt'
adb shell dumpsys media.camera | grep -iE 'availableStreamConfigurations|fpsRange|pixelArraySize'
```

第一条若成立，可同时给出三颗 sensor 的每 mode MIPI 数据率、lane 数/映射与 settle；第二条给出每 mode fps。

**测试工具（已落地，默认关闭）**：`liuqin-nixos/modules/liuqin/camera-debug.nix` 提供
`hardware.liuqin.cameraDebug.enable`，打开后装 `v4l-utils`（`media-ctl`/`v4l2-ctl`）、
`i2c-tools`（`i2ctransfer`）和 `liuqin-camtest`（一条命令打印拓扑/格式并抓 N 帧 + 逐帧 checksum；
脚本本体在 `liuqin-nixos/pkgs/camtest.nix`，由 overlay 暴露成 `liuqinCamtest`）。
**这是 bring-up 用的台架工具，不是运行时依赖**：默认关、BSP 不启用（与 `usb-shell` 同一约定），
生产系统不要开（size + root 级裸 I2C 写权限）。
**`i2cdetect` 在 CCI 上未必可靠**（会发不适合传感器的探测序列）：首选手法是让 sensor 驱动 probe
（看 `dmesg` / `v4l2-ctl --list-devices`），其次用 `i2ctransfer` 明确读寄存器。

**不需要在写代码前拿到的**：EEPROM 实际内容、vendor tuning、ICP ABI、actuator/flash 细节（后续阶段）。

## 实机测试阶梯（每步都有可判定的判据）



日志通道：屏幕拍照（`IMG_*.jpg` 惯例）、`dmesg`、`/sys/fs/pstore`（ramoops）；没有 UART。

1. **阶段 0.5 — CCI / MCLK / regulator / chip id（不需要 CAMSS）**
   - 需要：`cci0`/`cci1` 使能 + 一颗 sensor 的 MCLK（camcc）+ regulator（可用 `regulator-always-on` 先简化）+
     reset GPIO 释放。
   - 做法：**先让 sensor 驱动 probe**（看 `dmesg` / `v4l2-ctl --list-devices`），必要时用 `i2ctransfer` 按表里的
     寄存器宽度显式读 chip-id（JN1 读 `0x0000`、IMX596 读 `0x0016`、SC202CS 读 `0x3107`）；
     `i2cdetect -y <adapter>` 只当枚举地址的交叉验证——它发的是 SMBus quick write，传感器不一定接受
     （见本节末的告警），期望地址 0x20（JN1/IMX596）与 0x6c（SC202CS）。
   - 判据：连续 10 次上电/读取都得到正确 ID；失败时看 i2c 错误码决定是电源、MCLK 还是 GPIO 时序。

2. **电源/复位时序**：按 `.bin` 的 `powerSetting`（含 19.2 MHz 与延时）调整 enable 顺序与 reset 释放点；
   判据：chip id 稳定 + 无随机 i2c NAK。

3. **CSIPHY/CSID 骨架（接真实 S5KJN1）**：`media-ctl -p` 出拓扑；`v4l2-ctl --list-formats-ext`；
   `v4l2-ctl --stream-mmap=4 --stream-count=30`；同时 `dmesg | grep -iE 'smmu|iommu|csid|overflow|camss'`。
   判据：30 帧无 DMA/SMMU fault，无 CSID overflow。

4. **模式矩阵**：JN1 四个 mode 各抓 30 帧，记录尺寸/CRC 与实测 fps，和表里 VTS×HTS 推算值比对
   （期望 10/30/30/60）；IMX596/SC202CS 同法。

5. **稳定性**：连续 5 分钟采集、start/stop 50 次、suspend/resume 各 5 次。

6. **EEPROM/OTP**：主线 CCI 下直接读 EEPROM（0xA0/0x50）或经 sensor 的 OTP 窗口（rec 3517 序列），
   保存原始 dump 作为校准基线。

7. **可选对照（Android 侧）**：`adb shell dumpsys media.camera` 取每 mode 的 fps/分辨率；
   vendor `dmesg` 里的 `Datarate/Settletime/lane_assign/lane_enable` 打印可直接校准 CSIPHY 参数。

Android ↔ NixOS 往返：NixOS 里重启进 U-Boot 菜单 → 菜单 0 `Boot Android`（= `liuqin_setactive a; reset`）；
回程 `adb reboot bootloader` → `fastboot set_active b` → `fastboot reboot`。

## 来源与许可门槛（合入 GPL 驱动前必须记录）

- 哪些表来自 `.bin`（vendor 数据，来源=MIUI 固件）、哪些来自 datasheet、哪些是自行逆向；
- 进入内核的 `cci_reg_sequence` 表：注明出处与再分发判断（vendor 寄存器表可能受模块厂/小米许可限制）；
- `CAMERA_ICP`/`evass`/tuning 等二进制保持 operator-supplied（不进仓库、不随 Nix 包分发）。

## 验收标准

每个阶段都应保留可重复的日志和结果：

- `media-ctl -p` 的实体和链路完整；
- `v4l2-ctl` 能抓到固定数量的帧；
- raw 帧尺寸、Bayer 顺序和帧率符合 sensor mode；
- 连续采集无 DMA/SMMU fault、CSID overflow 或 camera clock 错误；
- suspend/resume 后可重新开始采集；
- 三颗传感器分别测试，不用“Android HAL 节点存在”代替 Linux capture 验收；
- 完整相机功能还要单独验证曝光、白平衡、自动对焦、闪光灯、JPEG 和录像稳定性。

## 外部参考

- [Linux qcom-camss video driver](https://github.com/torvalds/linux/blob/master/drivers/media/platform/qcom/camss/camss-video.c)
- [Linux CSID680 support](https://lists.openwall.net/linux-kernel/2025/03/14/1749)
- [Linux VFE680 support](https://lists.openwall.net/linux-kernel/2025/03/14/1750)
- [SM8450 CAMSS power-domain discussion](https://www.spinics.net/lists/linux-media/msg215018.html)
- [libcamera CAMSS pipeline RFC](https://lists.libcamera.org/pipermail/libcamera-devel/2026-April/058088.html)
