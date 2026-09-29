# USB-C 全功能、USB 3 和快充 TODO

状态基线：2026-09-29

本文记录 Liuqin 平板 USB-C 相关功能的现状、原厂证据、实现拆分和验收条件。目标是把 USB 3.2 Gen 1、OTG、DP Alt Mode、标准 PD/PPS 和小米 MiPPS/67W 快充分别做成可以独立验证和回退的阶段。

## 当前结论

硬件侧不是缺少 USB 3 或快充器件。小米 Pad 6 系列资料标明 USB 3.2 Gen 1，Pad 6 Pro 标称 67W 快充。原厂构建里存在完整的 SuperSpeed PHY、DWC3 OTG、UCSI、Type-C mux 和充电模块（`redriver.ko` 只服务其它机型，liuqin 未实例化，见 §3）。

当前 NixOS 端选择的是安全的 USB2 外设路径：

- 主线 DTS 的 DWC3 是 `dr_mode = "peripheral"`、`maximum-speed = "high-speed"`，只连接 eUSB2 PHY；
- 安装器 overlay 也固定为 USB2 peripheral；
- U-Boot 因没有 Type-C role-switch 驱动而强制 peripheral，并删除 `usb-role-switch`；
- 内核侧以本树构建出的 `.config` 为准：`USB_DWC3_GADGET=y`（`kernel/config.nix:140` 强制）、
  `PHY_QCOM_I2C_EUSB2_REPEATER=y`（config.nix:44 + patch 0009）、`USB_XHCI_HCD=y`、`TYPEC_MUX_FSA4480=m`
  与 `DRM_MSM_DP=y` 已由 arm64 defconfig 带来；只有 `PHY_QCOM_QMP_COMBO` 被
  `kernel/liuqin-firstboot.config:9` 显式关掉（`installer.config:31` 另关 XHCI，installer 没有 host 路径）。
  ⇒ 缺的是 DT 与 role 接线，不是这些 Kconfig 开关；
- battmgr 目前主要提供充电遥测和 Xiaomi raw 属性，没有 MiPPS/PPS 认证调用者。

因此需要移植的是整条 Type-C 拓扑和协议链路，而不是只修改一个 `maximum-speed` 属性。

## 已确定的逻辑（静态分析，2026-09-29）

结论先行：**Linux 接口和驱动映射已基本确定**（不需要靠试来“发现”协议与责任划分）；ADSP/VBUS/PPS 的实际行为、PHY 电气、DP 链路和长期稳定性仍需实机验证（§5）。全部静态报告与实施产物在 `liuqin-stock-dump/re/usb/`：`batterysecret.md`、`dp-altmode.md`、`phy-table.md`、`dt-config.md`、`mipps-spec.md`、`phy-table.patch`。

### 1. 充电 / PD 分层（证据：vendor 源码 + 部署模块清单）

- 部署的 vendor 内核内置了通用 Type-C 框架（`TYPEC=y`、`TYPEC_TCPM=y`、`TYPEC_TCPCI=y`、`TYPEC_UCSI=y`），但**没有任何绑定到本板的 Qualcomm PMIC TCPC/PD-PHY AP 驱动**：`TYPEC_QCOM_PMIC` 未启用，`vendor_dlkm` 里也没有 pdphy/tcpm 模块。PD 策略因此由 ADSP 的 charger 服务执行（待 §5 实测确认），AP 只看到
  `XM_PROP_CURRENT_STATE`（PD 状态机名 `SNK_Startup/SNK_Ready/SRC_Ready`，`qti_battery_charger.c:3621`）与协商结果。
- USB psy 上 AP **唯一可写的属性是 `POWER_SUPPLY_PROP_INPUT_CURRENT_LIMIT`**（`usb_psy_set_prop`，:1609/:1623），不能选 PDO/PPS 电压。
- 快充等级由内核读 ADSP 属性算出：`real_type==PD_PPS && XM_PROP_PD_VERIFED==1` → `power_max>=50` 记 SUPER，否则 TURBO；未认证的 PPS 记 FAST（:1497-1509）。
- ⇒ G4 的做法是**通过 UCSI 读取并验证**（`raw_xm_*` 已在 0006 可读），**不新增 AP 侧 PD 协商栈**；Xiaomi 私有档位（67W）由 UVDM 认证解锁，见下。

### 2. MiPPS 认证 = AP 侧用户态守护进程（内核只是中转）

内核的 `verify_process`/`verify_digest`/`request_vdm_cmd`/`authentic`/`pd_verifed` 全部是 userspace store
（`:3383`/`:2671`/`:3542`+`:3559`/`:2847`/`:3696`），内核没有任何发起路径。

部署的 `/vendor/bin/batterysecret` 就是那个调用者（`.gnu_debugdata` 带完整符号表：`main` 0x23b4、`hmac_sha256` 0x289c、`calc_fg_digest` 0x2ea0、`calc_usbpd_digest` 0x38d0、`usbpd_conmunication` 0x4a1c、`verify_pd_digest` 0x4fc0）：

- 启动：`ro.product.device` → 平台号（liuqin=17）→ 读 `/authentic`(+`/slave_authentic`) → `verify_fg_digest` → 读 `/real_type` → `verify_pd_digest` → netlink uevent 循环；重认证触发事件 = uevent 里的 `POWER_SUPPLY_NAME=usb` 或 `DATA_ROLE=ufp`。
- PD 流程：写 `verify_process=1` → 若 `/pdo2 == 00000000`（`usbpd_connect_with_phone()` 判定对端是手机）则直接判不认证；否则 `usbpd_dr_swap()`（写 `/sys/class/typec/port0/data_role`=`host`，等 `[host] device`）→ `usbpd_conmunication()` 依次经 `/request_vdm_cmd` 发 UVDM 命令 `1,2,3,4,5,7,6,0`，并校验 `adapter_svid==0x2717`（小米 SVID）→ 写 `verify_process=0` → 写 `pd_verifed`。
- 摘要算法：**HMAC-SHA-256**，自己实现（无 TEE/keymaster/soter；SHA-256 IV/K 在 .rodata 0x1a20/0x1a40）。
  - FG：32 字节随机 challenge（`rand()`）hex 写 `/verify_digest`，读回 ADSP 的 64 hex digest 比对，写 `/authentic`；
  - PD：20 字节消息 = `BSWAP32(4×challenge word) || adapter_id(u32)`（`calc_usbpd_digest` 0x38d0）+ 32 字节 key，返回 32 字节 MAC 但**只比较前 16 字节**；
- 密钥在 `.data`：FG key 5×32B @0x7490..（**liuqin/hw_id=17 用 @0x7510**）、PD key 10×32B @0x75d0、session seed 10×16B @0x7530、VDM `{cmd,retry}` 表 @0x7710；选择由 hw_id 决定（"P1 use old key"/"P1.1 P1.2 P1D use new key" 是别的机型分支）。密钥清单在 RE 报告里——**属于小米私有 key，不要提交进会推送的仓库**。
- `is_old_hw` 在部署内核里不存在（daemon 只在 cetus 分支写它，ENOENT）；`BATTERY_DIGEST_LEN=32`（`CONFIG_BQ_FG_2S` 未开、DT 无 `mi,support-2s-charging`）。
- ⇒ 内核侧 0006 的 XM value/words 通道只是基础，**还缺 7 项 ABI 改动**（§4 的 MiPPS 段：52B digest 帧、`pd_verifed=1`、`request_vdm_cmd` 复合读写、stock 输出格式、可写 authentic/slave_authentic、`qcom-battery` class、`verify_slave_flag`），之后才是 userspace 守护进程；BSWAP32 放内核写路径。

### 3. USB3 / Type-C / DP 拓扑与 mainline 映射

- 本机 board-id `0x10008` / miboard-id `0x10` ⇒ 只应用 **overlay-15**；**liuqin 没有 NB7VPQ904M redriver**（`onnn,redriver` 只在 waipio-QRD 的 overlay-25/26/27；`final-runtime.dts` 无）。vendor_dlkm 里的 `redriver.ko` 是同构建覆盖其他机型。
- USB2 HS：eUSB2 PHY + PTN3222（`nxp,eusb2-repeater`，带 `qcom,param-override-seq`/`-host` 板级参数）——mainline 驱动（0009 backport）原生支持这两个属性，参数可从 overlay-15 原样搬。
- USB3 SS：`usb_1_qmpphy`（`qcom,sm8450-qmp-usb3-dp-phy`）。**静态结论：原厂 init-seq（174 条，overlay-15 fragment@49）与 mainline 的 SM8550/V6 表最接近（TX 10/10、PCS 14/14、PCS_USB 4/4 完全一致；COM 偏移集合也一致 48/48，但 24 个值不同；RX lane A 差 3、lane B 差 5），而 7.2.5 给 sm8450 选的却是 sm8350 表**（`phy-qcom-qmp-combo.c:5032 → sm8350_usb3dpphy_cfg`；相对 sm8350：24 COM、8 RX、5 TX、3 PCS 值不同，另有 28 条 sm8350 根本不写的 vendor 寄存器；mainline 也不解析 DT `qcom,qmp-phy-init-seq`。全部数字见 `re/usb/phy-table.md` §4）。⇒ 这块板的 combo PHY 是 V6 布局，**要么给 mainline 补 sm8450/V6 表，要么实现 DT init-seq**，这不是“上机试”的问题而是选表问题。
- Type-C role/orientation：mainline 模型 = `pmic-glink` 下 `connector@0`（`usb-c-connector`）的 graph endpoint 同时给 UCSI 提供 role-switch（`ucsi.c:ucsi_find_fwnode` + `fwnode_usb_role_switch_get`，经 graph）和 altmode 的 mux/switch；orientation 用 `orientation-gpios`（HDK 写 `<&tlmm 91 …>`；GPIO91 在原厂只是 portselect pinctrl，liuqin 上拿它当 orientation 的证据不足——**候选引脚，暂不写入 DTS**，缺省不声明）。vendor 对应物是 `usb-role-switch` + EUD extcon，功能等价。
- DP Alt Mode：**mainline `pmic_glink_altmode.c` 与原厂 `altmode-glink.c` 的 wire format 逐字段一致**（owner 32780、0x15/0x16、SVID 在 opcode 高位、32 字节 notify 的 port/orientation/mux/hpd 布局、PAN_EN 0x10 / PAN_ACK 0x11）。原厂 DP 客户端在闭源 `msm_drm.ko`（`dp_altmode_notify`：payload[0]=port、payload[8]=pin:6|hpd_state:bit6|hpd_irq:bit7，pin→lane 数）⇒ **DP 不需要写协议代码**；但 HPD/AUX 接线、mux 切换、lane mapping 和 `mux_ctrl` 字节语义仍需实机验证（§5）。
- 目前 `/sys/bus/typec/devices` 空：0001 的 `pmic-glink` 节点没有 connector 子节点 ⇒ altmode 建不出端口、UCSI 拿不到 role-switch（UCSI 端口本身不一定因此消失）——还要按 §3 的排查清单查 UCSI aux probe、ADSP `GET_CAPABILITY`、PDR 与 `ucsi_register_port()` 日志。

### 4. 实施清单（已细化到可动笔；详细版在 RE 报告里）

三份可直接照做的产物（归档在 `liuqin-stock-dump/re/usb/`；`/tmp/usb-re/` 只是当时的临时副本，不作为引用来源）：

| 产物 | 内容 |
| --- | --- |
| `dt-config.md` | 可粘贴的 DT 片段（带 patch 0001 锚点）+ 两个 profile 的 config 行 + 8 条未定电气事实 + 首启检查单 |
| `phy-table.patch` | 给 `phy-qcom-qmp-combo.c` 增加 `sm8450_usb3dpphy_cfg` 的补丁草案（已试 `patch -p1` 干净应用）|
| `mipps-spec.md` | 守护进程 ABI/状态机/摘要字节序/密钥选择 + patch 0006 的 7 项最小改动 |

**DT（`patches/kernel/0001-liuqin-dts-bindings.patch`）**

- 新增 `pm8350_l1`（0.912 V，vendor `qcom,vdd-voltage-level=0xdea80`）到 `regulators-0`（patch :956 附近）——combo PHY 的 `vdda-pll`；
- `&usb_1_qmpphy`：`status="okay"`、`vdda-phy-supply=<&pm8350c_l10>`、`vdda-pll-supply=<&pm8350_l1>`、`mode-switch`（`orientation-switch` 上游已有）；
- `&usb_1`（7.2.5 里它就是 dwc3 core 节点，`dwc3-qcom.c:708` 直接 `dwc3_core_probe`）：`dr_mode="otg"`、`maximum-speed="super-speed"`、`role-switch-default-mode="peripheral"`、`phys=<&usb_1_hsphy>,<&usb_1_qmpphy QMP_USB43DP_USB3_PHY>`、**删** `qcom,select-utmi-as-pipe-clk`（`dwc3-qcom.c:682` 强制 UTMI pipe，只对纯 HS 板有效）；
- `pmic-glink` 下加 `connector@0`（`usb-c-connector`、`reg=<0>`、power/data-role dual）+ 三个 port：port@0→`usb_1_dwc3_hs`、port@1→`usb_1_qmpphy_out`、port@2→`fsa4480_sbu_mux`；没有子节点时 **altmode 建不出端口、收不到也回不了通知**，UCSI 则拿不到 role-switch（`fwnode_usb_role_switch_get` 返回 NULL，`usb_role_switch_set_role(NULL,…)` 静默失败）——UCSI 自身仍可能注册出 port，所以 `/sys/bus/typec/devices` 为空要同时查 UCSI aux 是否 probe、ADSP `GET_CAPABILITY` 是否返回连接器、PDR/PMIC GLINK 状态与 `ucsi_register_port()` 的失败日志；
- `fsa4480` 作为 `typec-mux@42` 挂 `&i2c5`（与 repeater 同总线），mainline compatible `fcs,fsa4480` + `mode-switch`/`orientation-switch` + port endpoint；`vcc` 可选、无 IRQ 需求（`fsa4480.c:277`），vendor DT 缺 supply 不阻塞；
- `mdss_dp0` 只需 `status="okay"`（phys/clocks/OPP/MMCX/intf0 全在 `sm8450.dtsi:3450-3510`）；liuqin 上 intf0 空闲（双 DSI 用 intf1/intf2）。

**config**

- `kernel/config.nix`：**真正要新增的只有 `PHY_QCOM_QMP_COMBO`**（且必须同时改 firstboot fragment，见下一条）；`TYPEC_MUX_FSA4480=m`、`DRM_MSM_DP=y`（**bool**，不能写 `=module`）与 `USB_XHCI_HCD=y` 在本树构建出的 `.config` 里已经成立（arm64 defconfig），写进去是把隐式变成断言而不是新增能力；要挂 U 盘再加 `USB_STORAGE`/`UAS`；
- `USB_DWC3_HOST/GADGET/DUAL_ROLE` 在 Kconfig 里是**同一个 choice**：把现有 `USB_DWC3_GADGET=yes` **换成** `USB_DWC3_DUAL_ROLE=yes`（它 select `USB_ROLE_SWITCH`），不能并存；`kernel/installer.config` 保持 `USB_DWC3_GADGET=y`（installer 明确没有 host 路径，且 XHCI 关着）；
- `kernel/liuqin-firstboot.config`：这个 fragment 被**追加到每一个内核变体**（`kernel/default.nix:66`；只有 `installer.config` 是 installer 专用），不是"无模块树镜像"专用 ⇒ 它里面的 `# CONFIG_PHY_QCOM_QMP_COMBO is not set`（:9）同样统治已装系统，改 config.nix 的 COMBO 时必须一起改这里。`CONFIG_PHY_QCOM_I2C_EUSB2_REPEATER` 已经 `=y`（config.nix:44，本树 `.config` 已核对），写进 fragment 只是把它纳入"fragment 必须存活"的构建期断言；`CONFIG_TYPEC_MUX_FSA4480`/`CONFIG_USB_XHCI_HCD`/`CONFIG_DRM_MSM_DP` 同理由 defconfig 满足，**真正的改动是 `CONFIG_USB_DWC3_DUAL_ROLE`**。

**combo PHY 表**

- 采用方案 (a)：新增 `sm8450_usb3dpphy_cfg`（V6/sm8550 表为基底 + 24 条 COM、8 条 RX 板级值 + 9 条 eye-tuning），把 `qcom,sm8450-qmp-usb3-dp-phy` 的 `.data` 从 `sm8350_usb3dpphy_cfg` 指过去；相对现状影响 68 个寄存器（40 个值不同：24 COM + 8 RX + 5 TX + 3 PCS；另 28 个 sm8350 不写，含那 9 条 eye-tuning）——`phy-table.md` §4/§5。
- 原厂 init-seq 里没有任何 DP 侧寄存器（<0x2000），所以 **DP 半边仍沿用 sm8350 值**（未验证，见 §5）。

**MiPPS（内核 + 守护进程）**

- patch 0006 的 7 项最小改动（`mipps-spec.md` §5.2）：(a) 52 字节 `verify_digest` 帧（GET/SET 都要，D52 + slave_fg）；(b) 允许 `pd_verifed=1`；(c) `request_vdm_cmd` 复合读写（含 `UVDM_STATE=21`、VDM 属性 9/10/14/15）；(d) 输出格式与 stock 一致（`adapter_svid %04x`、`adapter_id %08x`、`pdo2 %08x`、`real_type`/`current_state` 用名字）；(e) 可写 `authentic`/`slave_authentic(139)`/`verify_process`/`verify_digest`/`pd_verifed`；(f) 注册 `qcom-battery` class（守护进程/HAL 都按 `/sys/class/qcom-battery/*` 找）；(g) 驱动本地 `verify_slave_flag`。
- BSWAP32 留在**内核写路径**（与 vendor 一致，帧字节序可对照原厂模块验证），读路径不换。
- `qcom-battery` class 的最小 ABI（本期只做 daemon 需要的那部分）：
  - **必须挂到 class**：`mipps-spec.md` §1 的 23 个属性，名字与 stock 一致；写项（`verify_process`、`verify_digest`、`verify_slave_flag`、`request_vdm_cmd`、`authentic`、`slave_authentic`、`pd_verifed`）权限 0600（daemon 以 root 运行），只读项 0644；
  - **只留诊断**：现有 `raw_xm_*` / `sm8475_raw` 可以保留，但它们**不是** daemon ABI；
  - **不在本期范围**：HAL/thermald 用的 `input_suspend`、`cool_mode`、`night_charging`、`smart_batt` 等（我们不复刻 micharge HAL，daemon 不依赖它们）；
  - 权限/ownership 由内核创建时给定（`DEVICE_ATTR_*` + `sysfs_update_group`），不依赖用户态 chown。
- daemon 生命周期：systemd 常驻（无充电器时 idle，uevent 驱动重认证），`Restart=on-failure`；不做 `on charger` 一次性启动（那是 Android 的 init 语义）。
- key 交付（具体机制，避免只有原则）：
  1) operator 在**设备本地**提供密钥文件（如 `/etc/liuqin/mipps-keys`，root:root 0600；或由 oneshot 从 U 盘/手工写到 `/run/liuqin-mipps/keys` 的 tmpfs）；
  2) systemd 单元用 `LoadCredential=mipps-keys:/etc/liuqin/mipps-keys`，进程只读 `$CREDENTIALS_DIRECTORY/mipps-keys`——credential 仅该服务可读，**绝不进 Nix store、不进 git**；
  3) 文件格式：定长二进制（FG key 32 B + PD key 表 10×32 B + seed 表 10×16 B）或带版本头的 JSON，daemon 启动时校验长度与 hw_id；
  4) **缺 key / 校验失败 ⇒ 降级为只观测**：写日志、不写任何 verdict（不允许“没有正向摘要就置位”）；
  5) HMAC 测试向量（见 `batterysecret.md` §4.3）进仓库用于单元测试，真实 key 永不入仓库。
- 分阶段落地（profile 定义见「子目标和依赖」）：`usb3-device`（DT+PHY+config，`dr_mode` 暂留 peripheral）→ `typec-otg`（connector@0/UCSI/role-switch/XHCI）→ `dp`（`mdss_dp0` + aux-bridge 链）→ `pd-observe`（只读验证）→ `mipps`（内核 ABI + 守护进程）。每阶段单独构建、单独验证，默认镜像保持 `usb2-fallback`。
- 另：`pkgs/usb-gadget.nix` 里“没有 UCSI 就强写 `/sys/class/usb_role/*/role=device`”的兜底，在 UCSI 端口出现后要改成不抢占 DFP 角色（否则 host 侧会被拽回 device）。

### 5. 静态分析到此为止的部分（不属于"逻辑未知"）

1. ADSP 固件内部（`dsp_a.img`/`dspso.bin` 无明文 charger/UVDM 字符串）：UVDM 在 ADSP 内部怎么走、cmd 5 何时给响应、失败/重放/断线语义都不可读（`mipps-spec.md` §7 的 8 条）。这不阻塞接口实现，但会影响 MiPPS 的容错与回退设计（daemon 必须按 §2 的超时/重试并在失败时清 verdict），需要在实机验证时专门观察。
2. combo PHY：表已按静态证据定为 V6 基底 + 板级 delta（`phy-table.patch`）；但原厂 init-seq 里没有任何 DP 侧寄存器（全部 <0x2000），DP 半边沿用 sm8350 值，且 SS 侧"必须用这些值"仍属推断——实现后一次插拔/一次 DP 连接即可判定。
3. host 模式 VBUS 供电路径：vendor DT 里没有 VBUS/OCP 节点，role 来自 UCSI，VBUS 由 PM8350B OTG boost（ADSP/charger 服务管）；Linux 是否需要写 `reverse_chg_mode` 属于实现验证。
4. `dt-config.md` §7 的 8 条电气事实（orientation GPIO91 缺证据、FSA4480 供电/IRQ、`vdda-phy`/`vdda-pll` 只按电压映射、vendor 的第三条 0.9V rail 无 mainline 消费者、`pm8350_l1` 初始电压无法在 mainline 表达、`mux_ctrl` 字节语义等）——都是"实现时按缺省值走、上机看结果"的项。

## 未知项和可靠性评估（历史，2026-09-29 前的判断）

需要区分“仓库尚未实现”和“行为目前未知”。前者可以按 DTS、驱动和配置补齐；后者必须通过原厂行为对比、实机测试或 vendor 二进制逆向确认。

本节写就时的“未知”大多已在上文“已确定的逻辑”里定死；这里保留原始清单与当时的修正记录，供核对。仅 §5 的三项仍属静态无法判定。**仅供追溯，禁止作为当前实现依据**——其中 NB7 redriver、`altmode-glink`、PD “未知项”等条目已被推翻或改写（以“已确定的逻辑/实施清单”和 `liuqin-stock-dump/re/usb/` 的产物为准）。

| 功能 | 未知程度 | 当前判断 |
| --- | --- | --- |
| USB3 外设 | 中 | 上游有 QMP、FSA4480 和 NB7VPQ904M 基础，但没有 Liuqin 的完整板级整合和 SuperSpeed 实测 |
| USB3 Host/OTG | 中高 | 需要确认 role/power 切换、VBUS 供电、过流保护、正反插和电池策略 |
| DP Alt Mode | 高 | 原厂有 `altmode-glink`；上游 `pmic_glink_altmode` 就是同一套 SVID/opcode 协议，缺板级整合（mux/redriver/orientation/PHY lane）与 ADSP 报文格式实测 |
| 标准 PD/PPS | 中高 | UCSI/PMIC GLINK 有开源基础，但 PMIC、ADSP charger service 和 PPS 请求路径未确认 |
| Xiaomi MiPPS/67W | 很高 | AP 侧编排已定位：`/vendor/bin/batterysecret`（29 KB，见证据一节）；真正的未知只剩 ADSP 内部与实机行为 |

### USB3 外设模式的未知项

- SM8475 是否可以直接复用 SM8450 的 QMP USB3/DP combo PHY 数据（上游 `phy-qcom-qmp-combo.c` 已有 `qcom,sm8450-qmp-usb3-dp-phy`，`sm8450.dtsi` 也把 DWC3/PHY/DP 连好了；要验证的是这套寄存器表在 SM8475 上够不够）；
- 原厂 `qcom,qmp-phy-init-seq` 中哪些寄存器是必要初始化，哪些是板级 eye-tuning；
- `dwc3-msm.ko` 是否包含上游 DWC3 没有的 Qualcomm glue 行为；
- NB7VPQ904M 的 Gen1、orientation 和 lane 参数；
- 原厂 `qcom,fsa4480-i2c` compatible 是否能直接匹配上游 FSA4480 驱动；
- Linux SuperSpeed 物理链路能否在该板上稳定运行。

上游已经提供 FSA4480、NB7VPQ904M 和 QMP PHY 的可复用组件，但这些组件本身不能证明 Liuqin 的物理链路已经可用。需要用真实 5Gbps 设备进行枚举、吞吐和反复插拔测试。

### USB3 Host/OTG 的未知项

- `data_role` 和 `power_role` 是由 PMIC/ADSP 自动管理，还是需要 Linux 主动控制；
- host 模式下 VBUS 由哪个 PMIC regulator 提供；
- 是否有过流检测、反向电流保护和 host 电流上限；
- redriver、FSA4480 和 PHY 是否会在正反插时同步切换；
- host 模式下的电池消耗、runtime suspend 和拔出恢复行为；
- UCSI role change 是否能正确通知 DWC3、XHCI 和 Type-C mux。

这里通用驱动有开源基础，但电源路径和 role-switch 行为仍是板级未知，不能只靠 `dr_mode = "otg"` 推断完成。

### DP Alt Mode 的未知项

- `altmode-glink` 的 GLINK opcode、消息格式和状态机（vendor 源码 + 上游实现都在手，可静态比对）；
- ADSP 是否负责 SVID discovery、mode enter/exit、HPD 和 AUX；
- HPD/AUX 如何从 vendor driver 传到 Linux DRM；
- FSA4480 在 DP、USB3 和模拟音频之间的完整切换顺序；
- QMP DP lane mapping、orientation 和 link-rate 参数；
- 是否有额外 firmware 或安全服务参与 DP negotiation；
- 主线 DRM bridge 是否能直接连接这套 Qualcomm vendor glue。

上游 `drivers/soc/qcom/pmic_glink_altmode.c` 已经实现同一套协议（`USBC_CMD_WRITE_REQ=0x15`、`USBC_NOTIFY_IND=0x16`、SVID 在 opcode 高位、`pan_en`/`pan_ack` 握手）；原厂 `altmode-glink.c` 是“通用 client 注册 + DP 驱动自解析 notify”的一版，两者可静态比对。剩下的未知是：SM8475 的 ADSP 实际发 sc8280xp 布局还是 vendor 自己的布局，以及 HPD/AUX 怎么接到 msm DRM——这两点靠实机 + 对照 `altmode-glink.c` 的 client 回调解。

### 标准 USB-PD/PPS 的未知项

- PD PHY 是 PMIC 本地硬件处理，还是由 ADSP charger service 处理；
- UCSI connector 出现后，source capability 是否会完整上报；
- PPS request 是走 UCSI、PMIC GLINK，还是 vendor charger property；
- battery charger 是否接受 Linux 请求的 PPS 电压和电流；
- 输入限流、温控和电池保护由哪一层执行；
- 原厂 `qcom,qpnp-pdphy` 节点是否必须恢复到主线 DTS；
- vendor charger firmware 是否包含标准 PD/PPS 之外的必要策略。

标准 PD/PPS 协议本身是公开的，但 Qualcomm PMIC、ADSP 和 charger service 的责任边界还没有从实机行为中确认。必须使用 USB 功率计验证真实 VBUS 和输入功率。

### Xiaomi MiPPS/67W 的未知项

- Pad 6 Pro 使用的具体 MiPPS/Mi Turbo Charge 版本；
- M1 认证的完整消息顺序和状态机；
- `XM_AUTHENTIC`、`XM_VERIFY_PROCESS`、`XM_PDO2` 等属性的准确语义；
- 是否需要 TEE、QSEE、secure monitor 或签名数据；
- 认证对象是充电器、线材、设备，还是三者组合；
- `dspso.bin` 或 ADSP firmware 是否包含必要的私有逻辑；
- 67W 是否可以通过标准 PPS 达到，还是必须使用 Xiaomi 私有扩展；
- 认证失败后的安全回退流程；
- Linux 实现认证是否会破坏 ADSP charger state machine。

`0006` 当前只提供 typed transport 和 raw readout，没有可靠的认证调用者。网上的 Xiaomi PPS 模块大多针对其他手机型号的策略切换，不能视为 Liuqin 的 MiPPS 实现。

### 已定位的 AP 侧 MiPPS 编排（2026-09-29，从原厂 super.img 提取）

认证调用者是两个 vendor 用户态组件，都不在 kernel 里：

- `/vendor/bin/batterysecret`（29 KB；`init.batterysecret.rc`：`user root`、`class last_start`、`disabled`，在 `on charger` 与 `sys.boot_completed=1` 时启动）：监听 uevent，按状态机读写
  `/sys/class/qcom-battery/{verify_process,verify_digest,verify_slave_flag,request_vdm_cmd,authentic,slave_authentic,pd_verifed}`，
  日志字符串有 `session seed`、`calc random/digest`、`success to verify pd digest`、`P1 use old key` / `P1.1 P1.2 P1D use new key`、`dr swap … data_role`。
  即（推断，待实机验证）：摘要/密钥运算在 AP 用户态这个二进制里（`P1 use old key` / `use new key` 表明 key 在本地，按 `is_old_hw` 选新旧），ADSP 负责 PD/UVDM 收发与判定。
- `/vendor/lib64/hw/vendor.xiaomi.hardware.micharge@1.0-impl.so` + `/vendor/bin/hw/vendor.xiaomi.hardware.micharge@1.0-service`：给 framework 的读取面（`getBatteryAuthentic`、`getPdAuthentication`、`getChargingPowerMax`、`getPdApdoMax`、`getQuickChargeType`、`isUSB32`、`isDPConnected`、…），背后是同一批 `/sys/class/qcom-battery` 与 `/sys/class/power_supply/*` 属性。
- `/vendor/bin/charge_logger`、`/vendor/bin/mi_thermald` 也碰同一批节点（温控写 `charge_control_limit`）。

⇒ 0006 缺的是这套 sysfs 契约的调用者（= 复刻 batterysecret 的状态机），而不是一个未知的“安全服务”。

## 未知项的解决方法

### 可以通过实验确认

- **不改任何代码**：接 PD 充电器，看 ADSP 是否自己协商 —— 读 `/sys/class/power_supply/usb/`（`usb_type`、`voltage_now`、`current_now`）与 `raw_xm_pd_verified`/`raw_xm_power_max`；
- **不改任何代码**：接小米 67W 充电器，看 `raw_xm_authentic`/`raw_xm_fastchg_mode`/`raw_xm_power_max` 是否自己变（不变 ⇒ 必须复刻 batterysecret；变 ⇒ 只需把 USB-C/PD 通路做出来）；
- `/sys/bus/typec/devices` 为什么是空的：`pmic_glink` 会自建 UCSI aux 设备（`ucsi_glink.c` 是 aux driver，用父节点 compatible 选 quirk），当前 UCSI psy 在而端口不在 ⇒ 查 ADSP UCSI service 的上报/PDR 状态，别先怀疑 DT；
- QMP PHY 是否能使 `current_speed=super-speed`；
- FSA4480 正反插和 lane orientation 是否正确；
- USB3 host 是否能给 SSD 供电并稳定枚举；
- 标准 PD 是否能升到 9V/12V；
- PPS 是否可以动态改变 VBUS；
- DP 显示器是否产生 HPD、AUX 和画面。

### 必须移植或逆向 vendor 行为

- `/vendor/bin/batterysecret` 的状态机与摘要算法（二进制只有 29 KB）；
- ADSP charger service 的 property 语义（`dsp_a.img` 无明文 UVDM/charger 字符串，只能按 vendor 源码里的帧格式 + 实测推）；
- QMP PHY 调参里真正必要的寄存器（原厂 init-seq 在 `evidence/dtbo/overlay-15.dtb.dts`，其余是 eye-tuning）。

已经不用逆向：`altmode-glink` 协议（vendor 源码 + 上游 `pmic_glink_altmode.c` 都有）、`dwc3-msm` 差异（`dwc3-msm-core.c`/`dwc3-msm-ops.c` 源码可 diff）、PMIC Type-C/PD PHY 边界（部署内核与 vendor 模块清单里都没有 AP 侧 PD 栈，`TYPEC_QCOM_PMIC` 未启用 ⇒ 推断 PD 在 ADSP 侧，Linux 只需 UCSI/可观测性，需实机确认）。

风险最低的验证顺序是：

```text
USB3 外设
→ 标准 PD
→ USB3 Host/OTG
→ DP Alt Mode
→ Xiaomi MiPPS/67W
```

## USB 调试器兼容性约束

实现 USB3、OTG、DP 和快充后，不应丢失现有 USB 调试通道。当前调试器是 USB gadget 网络而不是 ADB：它通过 configfs 创建 NCM/ECM，在 `usb0` 上提供 `192.168.7.2/24` 和 telnet root shell。

当前实现有两个会和 Type-C role-switch 冲突的行为：

- `pkgs/usb-gadget.nix` 启动时会把可写的 `/sys/class/usb_role/*/role` 设置为 `device`；
- 服务启动时会把 gadget 绑定到 UDC，进入 host 模式后 UDC 不存在，服务会失败或需要重新绑定。

### 必须保留的行为

- [ ] U-Boot 继续使用 USB2 peripheral fastboot；Linux 侧实现 USB3 不应破坏启动阶段 fastboot；
- [ ] Linux 设备模式下，现有 NCM/ECM 调试器仍能工作；
- [ ] USB3 gadget 增加 SuperSpeed descriptors 后，USB2 fallback 仍然可用；
- [ ] 调试服务只在明确选择 device/debug role 时请求 `device`，不能无条件抢占 UCSI 的 host/DP role；
- [ ] 切换到 host 前先安全解绑 UDC 和 gadget functions；
- [ ] 从 host 回到 device 后可以重新绑定 UDC 和恢复 `usb0`；
- [ ] PD/PPS/快充协商不能因为普通数据角色保持 device 而被破坏；
- [ ] DP Alt Mode 测试必须记录 USB2 debug 是否仍可用；四 lane DP 会占用 SuperSpeed lane，但 USB2 是否保留取决于 Type-C role 和 mux 策略；
- [ ] 调试器不可用时，仍保留 Wi-Fi、UART 或安装器 USB2 作为恢复路径。

### 不能同时成立的组合

同一个 DWC3/Type-C 端口不能在同一时刻既是 USB host 又是 USB device。因此：

- USB3 device + NCM/ECM debug：可以同时成立；
- 充电 + USB device debug：通常可以同时成立，但必须测试 role 和 PD 状态机；
- USB host + 同一端口的 USB device debug：不能同时成立；
- DP Alt Mode + USB3：取决于二 lane/四 lane DP 配置；
- DP Alt Mode + USB2 debug：物理上可能共存，但需要实际验证 Type-C mux、partner 和 role 策略。

### 调试兼容性验收

- [ ] 无线/无外设启动后，连接电脑可以得到 debug network；
- [ ] USB3 device 模式下 `usb0` 和 NCM/ECM 正常；
- [ ] 插入普通充电器后，充电和 debug channel 都不被意外解绑；
- [ ] 切换到 host 后 gadget 干净解绑，不留下旧的 `usb0` 或 UDC 状态；
- [ ] host 拔出、重新切回 device 后 debug channel 能自动恢复；
- [ ] DP 插拔、PD/PPS 重协商和 USB role 变化都记录到 `PORTING-NOTES.md`。

## 证据位置

### 当前仓库

- [主线 DTS 与 USB2 配置](../../patches/kernel/0001-liuqin-dts-bindings.patch:725)
- [主线 DWC3 high-speed peripheral 节点](../../patches/kernel/0001-liuqin-dts-bindings.patch:2020)
- [安装器 USB2 overlay](../../dts/liuqin-installer-overlay.dts:3)
- [U-Boot 强制 peripheral](../../u-boot/files/arch/arm/dts/sm8450-xiaomi-liuqin-u-boot.dtsi:77)
- [USB/DWC3 内核配置](../../kernel/config.nix:140)
- [firstboot 配置中关闭 QMP USB/COMBO](../../kernel/liuqin-firstboot.config:9)
- [当前实机验证记录](../PORTING-NOTES.md:20)
- [当前 Type-C、USB3、PD/PPS 状态](../PORTING-NOTES.md:45)
- [默认未启用项](../PORTING-NOTES.md:522)
- [battmgr/M1 传输限制](../../patches/kernel/0006-liuqin-power-pon-battmgr.patch:434)

### 小米原厂镜像和 probe

原厂最终运行时 DTS：

```text
/home/seeker/Develop/liuqin/liuqin-audit/evidence/final-runtime.dts
```

重点节点：

- `qcom,ucsi`、`qcom,altmode-glink`：约 15086 行；
- eUSB2 repeater、FSA4480：约 15288 行；
- `qcom,usb-ssphy-qmp-dp-combo`：约 17266 行；
- DWC3 SuperSpeed OTG、双 PHY、`usb-role-switch`：约 24679 行；
- USB3 PHY port-select GPIO：约 28766 行。

原厂选择的 DTBO：

```text
/home/seeker/Develop/liuqin/liuqin-audit/evidence/dtbo/overlay-15.dtb.dts
```

其中包含 UCSI/DWC3 endpoint、SuperSpeed DWC3、`qcom,force-gen1` 和完整 QMP PHY 初始化序列。

probe 的 vendor module 还确认了以下下游组件：

```text
dwc3-msm.ko
phy-msm-ssusb-qmp.ko
ssusb-redriver-nb7vpq904m.ko
fsa4480-i2c.ko
ucsi_glink.ko
altmode_glink.ko
qti_battery_charger.ko
repeater-i2c-eusb2.ko
```

### 原厂 super.img 里的 AP 侧组件与部署模块（2026-09-29 提取，已复核）

`liuqin-stock-dump/images/super.img` 是原样的 LP 容器（不是 sparse），逻辑分区如下（同一批内容也在
`liuqin_images_V14.0.9.0.TMYCNXM_13.0/images/super.img`，固件包与设备 dump 两者取一即可）：

| 分区 | 大小 | 内容 |
| --- | --- | --- |
| `vendor_a` | 1337.5 MiB | vendor EROFS：HAL 二进制、firmware、init rc |
| `vendor_dlkm_a` | 28.2 MiB | 部署的 vendor 内核模块（EROFS 里 `/lib/modules`） |
| `system_a` / `system_ext_a` / `product_a` / `odm_a` | 735/616/4191/502 MiB | Android 侧 |

读取方式（不用 `lpunpack`，本仓库新工具 + `erofs-utils`）：

```sh
python3 liuqin-stock-dump/tools/extract-super.py list liuqin-stock-dump/images/super.img
python3 liuqin-stock-dump/tools/extract-super.py extract \
    liuqin-stock-dump/images/super.img vendor_dlkm_a /tmp/vendor_dlkm_a.img
nix shell nixpkgs#erofs-utils --command \
    fsck.erofs --extract=/tmp/vdlkm /tmp/vendor_dlkm_a.img
```

`vendor_dlkm_a` 里部署的（与 probe 报告的名字不同的）关键是：
`dwc3-msm.ko`、`phy-msm-snps-eusb2.ko`、`phy-msm-ssusb-qmp-m81.ko`（板级变体）、`redriver.ko`、`repeater.ko`、
`repeater-i2c-eusb2.ko`、`fsa4480-i2c.ko`、`ucsi_glink.ko`、`altmode-glink.ko`、`charger-ulog-glink.ko`、
`qti_battery_charger_main_m81.ko`（板级变体）。全部可以和我们手上的 5.10.81 源码逐一 diff。

`vendor_a` 里与本主题直接相关的：

- `/vendor/bin/batterysecret`（MiPPS 认证守护）、`/vendor/etc/init/hw/init.batterysecret.rc`；
- `/vendor/bin/hw/vendor.xiaomi.hardware.micharge@1.0-service` +
  `/vendor/lib64/{vendor.xiaomi.hardware.micharge@1.0.so,hw/vendor.xiaomi.hardware.micharge@1.0-impl.so}`；
- `/vendor/bin/charge_logger`、`/vendor/bin/mi_thermald`；
- `/vendor/etc/init/vendor.xiaomi.hardware.micharge@1.0-service.rc`（把 `/sys/class/qcom-battery/*` 和
  `/sys/class/power_supply/*` 的 charge 节点 chown/chmod 给 `system`，是那批属性的完整清单）。

固件包里的 `boot.img` 是 header v4；kernel 内嵌 IKCONFIG（blob 在 kernel 段 offset 27476512），
`Xiaomi_Kernel_OpenSource/scripts/extract-ikconfig` 抽出来是 **GKI 风格的 .config**
（`TYPEC=y`、`TYPEC_UCSI=y`、`TYPEC_TCPM=y`、`USB_DWC3=y` dual-role、`USB_XHCI_HCD=y`，
但没有任何 `QTI_*`/`USB_MSM_*`）——vendor 的 USB/充电栈全部是 `vendor_dlkm` 里的模块，
其开关在 `arch/arm64/configs/vendor/liuqin_GKI.config`，不在内核 .config 里。`dspso.bin`（=dump 的 `dsp_a/b.img`）
里没有明文 UVDM/charger 字符串，ADSP 内部逻辑仍是黑盒。

## 子目标和依赖

**实现 profile（按依赖排序；编号不是依赖关系）**：

```text
usb2-fallback      # 现状：USB2 peripheral + NCM 调试通道（保持不变，始终可回退）
usb3-device        # peripheral + SS PHY/表；不依赖 connector/UCSI（G1）
typec-otg          # connector@0 + UCSI + dual-role + XHCI（G0/G2）
dp                 # 在 typec-otg 之上启用 mdss_dp0 + aux-bridge（G3）
pd-observe         # 只读 UCSI/PD class + battmgr，验证协商（G4）
mipps              # battmgr ABI + qcom-battery class + daemon（G5）
```

关键点：**`usb3-device` 不依赖 G0**（没有 connector 也能跑 SS 外设）；`dp`/`pd-observe`/`mipps` 才依赖 `typec-otg`。
G0–G5 的原始目标划分保留如下：

```text
G0 Type-C 公共基础层 ──┬── G2 USB3 Host/OTG ── G3 DP Alt Mode
                      └── G4 标准 USB-PD/PPS ── G5 Xiaomi MiPPS/67W
G1 USB3 外设模式（独立，不依赖 G0）
```

U-Boot SuperSpeed 是独立的后续目标。早期阶段可以继续使用 USB2 fastboot，让 Linux 侧先完成 SuperSpeed 验证。

## G0：Type-C 公共基础层

### 工作项

- [ ] 在 `pmic-glink` 下补 `connector@0` + 三个 port（altmode 按子节点 `reg` 建端口；UCSI 按子节点顺序取 fwnode 绑 role-switch——没有子节点时 altmode 建不出端口、UCSI 拿不到 role-switch，但 UCSI 端口本身仍可能注册，见 §3 的排查项）；
- [ ] 保留并验证 `usb-role-switch` 与 connector graph（Linux DTS 从 `sm8450.dtsi` 继承，不需要“恢复”；只有 U-Boot 的 DT 会 `/delete-property/` 它，两边互不影响），先保持可回退到 USB2；
- [x] 接入 eUSB2 repeater 的电源、reset 和参数序列（已做：`patches/kernel/0009` + `config.nix` 的 `PHY_QCOM_I2C_EUSB2_REPEATER`，与 `nxp,eusb2-repeater` 直接对上）；
- [ ] 接入 FSA4480 mux 的 I2C、供电和方向控制（注意 compatible 不同：原厂 `qcom,fsa4480-i2c`，上游驱动认 `fcs,fsa4480`；我们自己的 DTS 直接用上游 compatible 即可）；
- [x] ~~NB7VPQ904M redriver~~ 已核实 liuqin 没有：`onnn,redriver` 只在 waipio-QRD 的 overlay-25/26/27，DTS 不要实例化，`TYPEC_MUX_NB7VPQ904M` 不需要；
- [ ] 恢复 QMP USB/DP combo PHY 的 clocks、regulators、reset（板级证据见 `dt-config.md`；**GPIO91 不要照抄**：原厂是 pinctrl 的 portselect state，mainline 用软件 port-select + `orientation-gpios`，而 liuqin 的 orientation GPIO 证据缺失，先不声明）；
- [x] 原厂 `qcom,qmp-phy-init-seq` 的落地方式已定：**不做 DT init-seq 解析**，改为在 `phy-qcom-qmp-combo.c` 给 sm8450 加独立 cfg（V6 基底 + 板级 delta，`phy-table.patch` 草案，173 条全部映射到具名寄存器）；DP 半边保持 sm8350 值（无原厂数据）；
- [ ] 建立一个实验用 DT overlay，默认系统仍保持现有 USB2 overlay。

### 验收

- [ ] `/sys/bus/typec/devices/` 出现 Type-C port；
- [ ] `/sys/class/typec/port0/` 可读取 role、partner 和 power 状态；
- [ ] 插拔和正反插会产生 UCSI/role 事件；
- [ ] 未插入 USB3 设备时，USB2 gadget 和充电不退化。

## G1：USB3 外设模式

这是第一个硬件 bring-up 目标，只做平板作为 USB 设备连接电脑，不同时引入 host、DP 和 MiPPS。

### 工作项

- [ ] 启用 QMP USB/SS PHY 所需内核配置；
- [ ] DWC3 设置为 SuperSpeed gadget，保留 USB2 fallback；
- [ ] 先复用现有 NCM/ECM gadget；
- [ ] 增加 DWC3 trace/debugfs 采集脚本；
- [ ] 保留一个可快速回退的 USB2 kernel/DT profile。

### 验收

- [ ] `current_speed=super-speed`；
- [ ] 主机端 `lsusb -t` 显示 5000M；
- [ ] NCM/ECM 能稳定工作；
- [ ] 连接、拔出、重新连接至少重复 10 次；
- [ ] USB3 失败时仍能回退到 USB2。

## G2：USB3 Host/OTG

### 工作项

- [ ] 启用 USB host/XHCI；
- [ ] 完成 Type-C data role 和 power role 切换；
- [ ] host 供电：确认 VBUS 由谁打开（PM8350B OTG boost / ADSP charger 服务）、限流、OCP/反向电流保护，以及是否需要写 `reverse_chg_mode`；
- [ ] **默认安全行为**（先于任何 VBUS 实验写死）：host VBUS **默认不开**（DT 不声明 `vbus-supply`/OTG regulator，进入 host 角色本身不会供电）；在确认 ADSP/PMIC 的接管方式前**不写 `reverse_chg_mode`**；host 启动失败回落 device/none；VBUS 缺失或过流时报错并停止枚举，不允许“盲枚举”；
- [ ] 接入 FSA4480 方向/mux 控制；
- [x] ~~验证 redriver 在正反插和 Gen1 下的参数~~ 本机无 redriver；改为验证 combo PHY + HS repeater 在正反插下都稳定；
- [ ] 增加 host、device、none 三种 role 的状态机日志；
- [ ] 处理外设拔出后的 VBUS 和 runtime suspend。

### 验收

- [ ] USB3 SSD/U 盘可以被识别；
- [ ] `role=device` 和 `role=host` 可以切换；
- [ ] 正插、反插都能枚举；
- [ ] host 模式不会让电池持续异常放电；
- [ ] USB2 外设仍然可用。

## G3：DP Alt Mode

### 工作项

- [ ] 启用 DP altmode（mainline **没有** `altmode-glink` 这个符号：`QCOM_PMIC_GLINK` 带出 `pmic_glink_altmode`，配上 `connector@0`、combo PHY、`mdss_dp0` 即可）；
- [ ] 恢复 QMP DP combo PHY（注意：原厂 init-seq 没有 DP 寄存器，DP 半边沿用 sm8350 值，见 §5）；
- [ ] 连接 FSA4480 的 DP/USB mux 状态；
- [ ] 确认 USB-C connector 的 SVID/Alt Mode endpoint；
- [ ] 明确双 C 显示器和 DP 转接线的测试矩阵。

### 验收

- [ ] USB-C 显示器或 DP 转接线被识别；
- [ ] 能输出至少一个稳定显示模式；
- [ ] 测试矩阵：2-lane/4-lane、正反插、直连显示器与 DP 转接器、DP+USB2 并存、DP+充电、反复插拔后 USB3/充电恢复；
- [ ] 拔出显示器后 USB3/充电恢复；
- [ ] DP、USB3、充电三者切换不会卡死 Type-C 控制器。

## G4：标准 USB-PD/PPS

### 工作项

- [ ] 先确认 UCSI port 和 partner 能力正常上报；
- [ ] **读取接口（只读；不新增 AP 侧 PD 协商栈）**：
      `/sys/class/typec/port0/{data_role,power_role}`、`/sys/class/typec/port0-partner/`（`usb_power_delivery_revision` 判是否 PD 伙伴）、
      `/sys/class/usb_power_delivery/pd*/{source,sink}-capabilities/<pos>:<type>/`——固定档是 `*:fixed_supply`，PPS/APDO 是 `*:programmable_supply`（属性 `maximum_voltage`/`minimum_voltage`/`maximum_power`/`pps_power_limited`）、
      battmgr 侧 `/sys/class/power_supply/usb/{usb_type,voltage_now,current_now,input_current_limit}` 与 `raw_xm_{apdo_max,power_max,pd_verified}`；
- [ ] **PDO 缺失时的诊断顺序**：`UCSI_GET_PDOS failed` 日志 → `port0-partner/` 是否存在 → `usb_power_delivery_revision` → ADSP UCSI service / PDR 状态；
- [ ] 固定档与 PPS 分开记录（9V/12V/15V vs `programmable_supply` 的动态电压），并写 USB 功率计读数；
- [ ] 唯一允许的写是 UCSI 暴露的 `data_role`/`power_role`（MiPPS daemon 需要 dr_swap）；**不允许** AP 侧发 PDO/PPS request；
- [ ] 增加充电失败后的 5V fallback；
- [ ] 增加 USB 功率计读数记录，不把 `charge_type=Fast` 当作协商成功。

### 验收

- [ ] `/sys/class/typec/` 能反映 partner 和 power role；
- [ ] USB 功率计确认 VBUS 从 5V 升到目标 PD 电压；
- [ ] 反复插拔和低电量/高温条件下能安全回退；
- [ ] 电池电流、输入功率和充电器协商状态一致。

## G5：Xiaomi MiPPS/67W 快充

### 工作项

- [ ] 明确 ADSP charger service 的启动、PDR 和断线行为；
- [ ] 复刻 `/vendor/bin/batterysecret` 的状态机（sysfs 契约见“已定位的 AP 侧 MiPPS 编排”一节），或先证明 ADSP 自己会认证；
- [ ] 实现适配器识别、认证和失败回退；
- [ ] 处理 `XM_AUTHENTIC`、`XM_PD_VERIFIED`、`XM_FASTCHG_MODE`、`XM_POWER_MAX`；
- [ ] 加入电池温度、SOC、输入功率和充电器温控限制；
- [ ] 不允许用户态直接写任意 PMIC/XM property；
- [ ] 记录认证失败原因，避免只显示一个模糊的 `Fast`。

### 验收

- [ ] `raw_xm_authentic=1`；
- [ ] `raw_xm_pd_verified=1`；
- [ ] `raw_xm_fastchg_mode` 进入有效模式；
- [ ] `raw_xm_power_max` 非零且与适配器能力相符；
- [ ] USB 功率计确认真实高功率输入；
- [ ] 使用非小米充电器时仍能安全回退到标准 PD/5V；
- [ ] 低电量、满电附近、高温和拔线场景均能正确退出快充。

测试应使用支持高功率的 Xiaomi 充电器、6A Type-C 线和 USB 功率计。67W 是产品额定上限，实际功率还会受电量、温度和适配器影响。

## U-Boot 后续目标

- [ ] 先保持 U-Boot USB2 fastboot，不阻塞 Linux USB3；
- [ ] 明确是否需要 U-Boot SuperSpeed；
- [ ] 若需要，补充 U-Boot QMP SS PHY、FSA4480 和 Type-C role 驱动（本机没有 redriver，不需实现）；
- [ ] 验证 ABL 到 U-Boot 到 Linux 的 DT handoff，不让 U-Boot 的 peripheral 强制属性覆盖 Linux overlay。

## 实验和回归要求

- [ ] 每个阶段使用独立 kernel config 或 DT overlay；
- [ ] 所有测试记录线材、充电器、转接器、SOC、温度和插入方向；
- [ ] USB3 使用真实 5Gbps SSD/U 盘，不只看枚举速度；
- [ ] 快充使用 USB 功率计，不只看 power_supply 文本；
- [ ] 保留 USB2 peripheral 的可启动回退镜像；
- [ ] 每个阶段完成后更新 `docs/PORTING-NOTES.md`，记录“已验证”和“未验证”；
- [ ] 不把原厂 DT 的存在误认为 Linux 驱动已经可用。

## 公开资料

- [Xiaomi Community：Pad 6 系列 USB 3.2 Gen 1、Pad 6 Pro 67W](https://c.mi.com/global/post/587730)
- [Xiaomi 67W GaN Charger：高功率线材要求](https://www.mi.com/global/product/xiaomi-67w-gan-dual-port-charger/)
- [Linux DWC3：peripheral、host、dual-role 和 SuperSpeed 支持](https://www.kernel.org/doc/html/v5.18/driver-api/usb/dwc3.html)
- [Linux 上游 Type-C mux：FSA4480 和 NB7VPQ904M](https://github.com/torvalds/linux/blob/master/drivers/usb/typec/mux/Kconfig)
- [Linux 上游 UCSI PMIC GLINK](https://github.com/torvalds/linux/blob/master/drivers/usb/typec/ucsi/Kconfig)
- [Linux 上游 SM8450 USB-C connector/PMIC GLINK 示例](https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/qcom/sm8450-hdk.dts)
- [Linux 上游 Qualcomm QMP USB3/DP PHY 示例](https://github.com/torvalds/linux/blob/master/arch/arm64/boot/dts/qcom/sm8250.dtsi)
- [Xiaomi Pad 6 Pro 拆解资料：充电器件和电池架构](https://www.techinsights.com/blog/deep-dive-teardown-xiaomi-pad6-pro-23046rp50c)
