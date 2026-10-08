# liuqin 的 NixOS 启动菜单：已定方案与实现记录

**状态（2026-09-25）：两侧都实现完，离线验证过。** 目标链路是 **ABL → `boot_b` 中的 U-Boot → NixOS**；Android 仍由 ABL
从 `boot_a` 启动。

| 项 | 状态 |
| --- | --- |
| NixOS 侧（extlinux generation 列表） | 已实现：`liuqin-nixos` 的 `modules/liuqin/default.nix`，旧的三文件 `/boot` 通路已删除 |
| U-Boot 侧（`sysboot` + 按键可用） | 已实现：本仓库 `pkgs/u-boot/`（`files/board/qualcomm/liuqin/liuqin.env`、`patches/` 里的 `boot/pxe_utils.c`） |
| 镜像 | `nix build .#uboot-bootimg`。菜单修正之前的一次性 env 产物 `liuqin-uboot-nixos-menu.img` 不可复现，不要再用 |

## 结论

采用 **NixOS 自带的 extlinux generation 列表**（[NixOS wiki: U-Boot][wiki]
指定的机制：`boot.loader.generic-extlinux-compatible`），U-Boot 侧只做两件
事：把 `sysboot` 编进镜像并按 GPT 分区名 `linux` 定向调用它；让 extlinux
菜单吃这台机器**仅有的三个按键**。设备菜单因此有两个 NixOS 入口：

```text
ABL
 ├─ boot_a → Android（ABL 自己加载）
 └─ boot_b → U-Boot（设备菜单，音量键移动 / 电源键确认 / 5 s 无输入走第 0 项）
               ├─ 0 Boot NixOS          → extlinux 的 DEFAULT（= 最后一次安装的
               │                          generation），不显示菜单
               ├─ 1 NixOS Generations   → 同一个 extlinux 文件，逐个 generation
               │                          列出来给按键选（含 "Back to device menu"）
               ├─ 2 Boot Android        → 完整切到 A 槽、复位、交还 ABL
               ├─ 3 Enable Fastboot Mode / 4 Reset / 5 Power Off
               ├─ 6 Reboot to ABL
               └─ 7 GPT Probe / 8 Scan ABL Log（只读诊断）
```

倒计时只挑 `Boot NixOS`：它失败时会在面板上说明原因并 `pause`，而
`Boot Android` 是**持久槽位选择**（下面），不能被没人看的倒计时碰到。

这里是 **NixOS system generation** 之间的选择，不是 derivation：每一代记录
了配套的 kernel、initrd、DTB、内核参数与 `init=/nix/store/.../init`，而
extlinux 的每个 `LABEL` 正好承载这一整套。`boot_b` 只承载 U-Boot 镜像，
NixOS 的引导文件由 NixOS 自己管理。Android 的切槽仍由设备菜单负责，不混进
generation 列表。

**不增设 `NIXOSboot` 分区。** `/boot` 就是 `linux` ext4 根分区里的目录：
NixOS 的 extlinux 装载器向 `/boot/extlinux` 写菜单、向 `/boot/nixos` 复制
每代的 kernel/initrd/dtbs。这样不再改 GPT，也不需要把 `boot_b` 当成文件系统。
只有在确实要加密根分区、换成 U-Boot 读不了的文件系统，或实测发现引导文件
必须与根分区隔离时，才考虑独立 ext4 `/boot`（判据见「关于独立
`NIXOSboot` 分区」一节的表格）。

[wiki]: https://wiki.nixos.org/wiki/U-Boot

## NixOS 侧：就用 loader 模块，别自己写生成器

[wiki][wiki] 的结论是 NixOS 仍以 "Generic Distro Configuration Concept" +
extlinux-compatible 作为可发现启动的机制；[U-Boot 的 extlinux 文档][ubdoc]
也明确说 `pxe_process()` "may boot an operating system or provide a list of
options to the user, perhaps with a timeout"。所以 NixOS 侧只启用模块、不发明
格式。`modules/liuqin/default.nix` 在 `hardware.liuqin.boot.loader = "uboot"`
时设的就是这四条（`lib.mkIf` 包着，`loader = "abl"` 时一切照旧）：

```nix
boot.loader.grub.enable = false;
boot.loader.generic-extlinux-compatible = {
  enable = true;
  configurationLimit = lib.mkDefault 8;   # 保留代数；面板按 MENU LABEL 列名
};
boot.loader.timeout = lib.mkDefault 5;    # 秒；生成器 ×10 写成 TIMEOUT 50（=5 s）
hardware.deviceTree = {
  name = "qcom/sm8475-xiaomi-liuqin.dtb"; # 写死 FDT，别让 loader 猜
  filter = "*liuqin*.dtb";                # 见下
};
```

每一条的理由都对着锁定的 nixpkgs（`eaad0894`）核过：

- `configurationLimit` 决定菜单里有几代；**回滚就是选旧代**，与
  `nix/var/nix/profiles/system-*-link` 由同一个生成器枚举，不重复实现。
- `hardware.deviceTree.name` 让生成器写 `FDT ../nixos/<store>-dtbs/qcom/
  sm8475-xiaomi-liuqin.dtb`；不设它就只有 `FDTDIR`，而 U-Boot 会拿
  `$fdtfile` 或 `$soc`+`$board` 拼板名（本镜像的 env 里都没有），拼不出来。
  注意 `useGenerationDeviceTree`（默认已是 true）只是"是否写 FDT/FDTDIR"的
  总开关，不负责写明确路径。
  - **尖角**：`-n` 一旦设置，只要**任何保留代**没有 `dtbs` 目录，生成器会
    `exit 1`（`Explicitly requested dtbName …, but there's no FDTDIR -
    bailing out.`）⇒ 整个装载器安装失败。本机每代都来自同一块板的配置，
    成立；但如果哪天把别的板/别的来源的 generation 混进 profile，要先清掉。
- `filter` 是容量问题：生成器把 `$toplevel/dtbs` **整个目录**复制进
  `/boot/nixos`，而 arm64 defconfig 会为绝大多数 `ARCH_*` 建 dtb。按本板名
  过滤后只剩一个文件；`filterDTBs` 用 `cp --parents`，`qcom/…dtb` 的相对
  路径不变，`FDT` 行照旧成立。
- `boot.loader.timeout` 决定 `TIMEOUT`，单位是**秒**（nixpkgs 默认 5）：
  模块把 `boot.loader.timeout` 当 `-t` 交给生成器，生成器用
  `timeout=$((OPTARG * 10))` 换算成 1/10 秒再写 `TIMEOUT $timeout`
  （`extlinux-conf-builder.sh`）；**按十分之一秒解释的是 U-Boot**
  （`pxe_menu_to_menu()` 的 `DIV_ROUND_UP(cfg->timeout, 10)`，而
  `menu_create()` 收的是秒）。所以这里配 **5**（`lib.mkDefault 5`）即
  `TIMEOUT 50` = 5 s；`null` 会写 `TIMEOUT 0`，即"无限等待"。
  - 倒计时只存在于**交互**入口：`Boot NixOS`（`pxe_no_menu`）完全不过菜单，
    `TIMEOUT` 对它没有意义。

`$toplevel/dtbs` 与 `dtbs/` 里的文件确实存在：`nixos/modules/system/boot/
kernel.nix` 在 `hardware.deviceTree.package != null` 时把
`hardware.deviceTree.package` 链进 toplevel，而 `hardware.deviceTree.enable`
默认取 `kernel.buildDTBs`，aarch64 上默认为 true。

`APPEND init=…` 由模块生成，和旧的"命令行烘进 DTB、U-Boot 不设 `bootargs`"
约定**互斥**：`label_boot()` 会 `env_set("bootargs", …)`。所以
`pkgs/bootdir.nix`、`system.build.liuqinBootDir`、flake 的 `bootdir` 输出与
demo 的 `demo-bootdir` 已随这次迁移删除，`boot.loader = "uboot"` 现在的含义
就是这条 extlinux 链路。

## U-Boot 的构建（在本仓库）

```sh
nix build .#uboot           # u-boot-nodtb.bin + sm8450-xiaomi-liuqin.dtb
nix build .#uboot-bootimg   # 上面那份 + ABL 打包（pkgs/bootimg/default.nix）
```

产物在 `liuqin-nixos/pkgs/u-boot/`，三部分：

| 路径 | 内容 |
| --- | --- |
| （基线） | **`sm8450-mainline/u-boot`**（`caleb/rbx-integration`，该 fork 唯一分支，2024-10-27 后再无推送），`fetchFromGitHub` 按 `pkgs/u-boot/default.nix` 里的 pin 取，不落任何二进制到仓库。它就是官方 master（v2024.10 之后 9 天）＋199 个 Qualcomm 手机 bring-up 提交，没有 release tag 对得上（Makefile 仍写 2024.10）。**这是移植的历史基底**：移植动过的文件它都有，所以移植以补丁序列原样落上去，不需要逐 hunk 适配，也不必把新上游缺的东西一件件补回来——framebuffer 映射、SM8450 GCC 时钟、PMIC GPIO 的 compatible 与输入上拉、SM8450 SMMU id、`DWC3_DEPCMD_STATUS`、`dram.c` 的 SMEM 解析它都自带。 |
| `files/` | 移植**新增**的 15 个文件，按树内路径放：`board/qualcomm/liuqin/`（含 `liuqin.env`）、两个 DTS（`arch/arm/dts/` 与 `dts/upstream/src/arm64/qcom/`）与 `cmd/partlog.c`。构建时覆盖到基线之上。 |
| `patches/` | 对基线**已有**文件的 30 处改动，切成 13 个 topic patch。分组之间**文件互不重叠**，所以顺序无关、也不会互相 fuzz：Kconfig 符号、mach 板级钩子（含跨复位 stage log 的标记）、`Makefile` 的 `pwd` 修正、console/input、UFS+QMP-UFS PHY、eUSB2 PHY、dwc3（含端点状态机）、fastboot 弱钩子、f_fastboot 请求池、pinctrl/PMIC GPIO/RPMH regulator/SMMU、`cmd` 的 partlog 接线、bootmenu 重绘、`boot/pxe_utils.c` 的 extlinux 按键菜单。 |

`pkgs/u-boot/default.nix` 固定 `scripts/config` 清单与 `DEVICE_TREE`（**构建期
不对结果做断言**）；`boot.img` 的契约（ids、`__symbols__` 并集 1744、惰性
sink、`base 0`/`kernel_offset 0x8000`/`dtb_offset 0x1f00000`、8 MiB padding、
空 newc ramdisk）由 `pkgs/bootimg/default.nix` 统一实现，内核镜像走同一条管线。
构建把实际用的 `.config` 装进产物（`$out/uboot.config`）。

## U-Boot 侧：两处必要修正

单靠上游 U-Boot 2024.10 + 本镜像，**这个菜单用不了**，两个独立原因：

1. **extlinux 菜单只接受打字的编号。** `pxe_menu_to_menu()` 给
   `menu_create()` 传 `item_choice = NULL`，于是 `menu_get_choice()` 落到
   `menu_interactive_choice()` 的 `cli_readline_into_buffer("Enter choice: ")`
   分支；而本板的 `button-kbd` 只能产出音量键（→`ESC [ A/B`→`^P/^N`）与
   电源键（→`\r`），既打不出数字，也退不出去。
2. **`bootretry` 会把这个提示直接判成超时。** 镜像配置打开
   `CONFIG_BOOT_RETRY`（`BOOT_RETRY_TIME`/`BOOT_RETRY_MIN` = 30），env 里
   `bootretry=0` 会被抬到 30；而 `cread_line()` 第一句
   `if (bootretry_tstc_timeout())` 拿的 `endtime` 只由 shell 路径
   （`cli_simple`/`cli_hush`）设置，走 bootcmd→bootmenu→sysboot 时它一直是
   静态初值 0，源码注释写得很直白：*"must be set, default is instant
   timeout"*。结果是菜单**零等待**、直接启动 `DEFAULT`，`TIMEOUT` 完全不生效。

所以 `boot/pxe_utils.c` 里加了一个 `item_choice` 回调（约 240 行，含注释），
键解码复用 `bootmenu_conv_key()`（顶层菜单已经在用同一条链路，音量/电源键的
映射因此一致），高亮项反显，`cfg->timeout` 变成真正的倒计时；菜单最后加一项
`Back to device menu`（`LOCALBOOT -1`，`label_boot()` 接受但不启动任何东西），
这是没有 ESC 键的板子上唯一的"取消"出口。等待键盘期间照旧 `schedule()`，
Gunyah 的 vWDT 不会咬。

**菜单自绘、按行落位。** 通用 menu 代码的重绘是"再调一次
`menu_display()`"，而它只把内容**接着往上一次的下面**打印；原来的
`label_print()` 用相对打印，于是每按一次音量键，整份菜单（标题+提示+全部
generation）就在下面再印一份，键按几下就滚出屏幕。现在 `label_print()` /
`pxe_menu_statusline()` 一律先 `ANSI_CURSOR_POSITION` 定位：标题在第 1 行
（通用代码打的）、提示在第 2 行、第 N 项在第 N+1 行；`pxe_choice()` 在让
菜单重绘前把光标送回 (1,1)，所以重绘是原地覆盖。进入菜单先清屏并收起倒计时行
（`pxe_choice_wait()` 无论被按键打断还是数完，都会把自己的行收回），选定后
`pxe_menu_done()` 清屏再交棒，`label_boot()` 那句"回显选中项"因为
`pxe_menu_open` 已经落下而退回普通打印，不会再去定位。
`menu_display()` 里那份相对标题打印仍然保留，改动只在 `boot/pxe_utils.c`，
`common/menu.c` 未动。

补丁引入的全部新接口只有两个 env 开关（都是通用的、可上游化）：

- `pxe_no_menu=1`：跳过菜单，直接取 `DEFAULT`（"Boot NixOS"用它）；空/未设
  即正常显示菜单。
- 既有的 `pxe_label_override=<label>` 仍然有效（`DEFAULT` 的覆盖），本次没用
  到，留着给"从主机/RAM 镜像钉某一代"用。

`liuqin.env` 的两项与地址：

```sh
boot_nixos=…setenv pxe_no_menu 1; …sysboot scsi 0:${linux_part} any ${pxefile_addr_r} ${linux_conf}
boot_nixos_menu=…setenv pxe_no_menu; …sysboot scsi 0:${linux_part} any ${pxefile_addr_r} ${linux_conf}
```

- `sysboot` 的参数顺序（`cmd/sysboot.c` 的 `U_BOOT_CMD`）是
  `<interface> <dev[:part]> <ext2|fat|any> [addr] [filename]`。
- 地址用 pxe 装载器认识的名字：`kernel_addr_r=0xb3000000`、
  `ramdisk_addr_r=0xa7400000`、`fdt_addr_r=0xb2000000`；`pxefile_addr_r`
  只在解析期间存放配置文件（早于任何 payload 载入），所以只要避开解析期间
  必须存活的东西（ramoops `0xa7000000`、splash framebuffer `0xb8000000`、
  MPSS/mailbox `0x8bc00000..0x9ee00000`）即可，这里取 `0xb0000000`。
- `liuqin_vwdt ${vwdt_linux_ms}` 仍在交接前调用；`linux_part` 缺失、`sysboot`
  失败都会在面板上留话再 `pause`。
- 打包配置增加 `-e CMD_SYSBOOT`；它只 `select PXE_UTILS`（`BOOTMETH_
  EXTLINUX` 已经把 PXE_UTILS 打开），不会牵进网络代码。

U-Boot 侧的 `oem run` 是关的、`CONFIG_SAVEENV` 也是关的，所以菜单本身没有
"从主机改一次"的入口：**面板是唯一入口**，菜单项也就必须只用
音量键/电源键能操作——这也是把 generation 选择放进设备菜单而不是让
extlinux 自己提示的根本原因。

**不碰 GPT 的 bootable 标志。** wiki 提到 distro-boot 扫描要求分区带
"bootable" 标志，但那是给 `bootflow`/distro 扫描用的：这里 `sysboot` 是**显式
指定** `scsi 0:<part>`，不经过扫描，所以标志无关紧要。而 GPT attributes 是
ABL 的槽状态所在（bits 48–55），把 bit 2 当成"能写"的开关去动它，收益是零、
风险是碰坏槽位。

## 已做的验证（离线）

1. **生成的 extlinux 列表实跑**：用配置里真正的那条生成器
   （`…-extlinux-conf-builder.sh -g 0 -t 5 -n qcom/sm8475-xiaomi-liuqin.dtb`，
   只输出 default 条目）对着一个假 toplevel 跑，产物为：
   ```text
   DEFAULT nixos-default
   TIMEOUT 50
   MENU TITLE ----…
   LABEL nixos-default
     MENU LABEL NixOS - Default
     LINUX ../nixos/<name>-kernel
     INITRD ../nixos/<name>-initrd
     APPEND init=/nix/store/.../init qcom_q6v5_pas.slpi_auto_boot=0 … cpuidle.governor=teo root=fstab loglevel=7 lsm=landlock,yama,bpf
     FDT ../nixos/<name>-dtbs/qcom/sm8475-xiaomi-liuqin.dtb
   ```
   `TIMEOUT 50` → 5 s ✓（生成器把 `-t 5` ×10 写成 1/10 秒单位）；`FDT` 是
   明确路径 ✓；`MENU LABEL` 会被面板显示（`label_print()` 优先用
   `label->menu`）✓；旧代由同一个生成器追加 `LABEL nixos-<N>-default` +
   `MENU LABEL NixOS - Configuration <N> (时间 - 版本)`。
2. **两个 NixOS 配置 eval 通过**：demo → `extlinux=true, timeout=5,
   name/filter` 正确；installer 不受影响（`extlinux=false`，走
   `checks.x86_64-linux.eval-installer`）。
3. **镜像**：编译、链接、打包通过，ABL 头断言全过
   （`ANDROID!`、`kernel@0x8000`、`text_offset 0`、`flags 0xa`）；解开 boot.img
   的 gzip payload 后，两个入口、`pxe_no_menu`、四个地址与新菜单项都在镜像里。
4. **菜单行为（2026-09-30，qemu，与固件同一份源码）**：把补丁后的树编成
   `qemu_arm64` 目标（只额外打开 `CMD_SYSBOOT`/FAT/NVMe，`bootdelay=-1`），
   在 `sysboot nvme 0:1 … /extlinux/extlinux.conf` 下跑测试用 extlinux 文件
   （每项都是 `LOCALBOOT -1`，选中即返回、不引导任何东西）；串口字节流喂给
   一个小 ANSI 终端模拟器还原成屏幕来断言。结果：
   - generation 菜单依次按 下/下/上：屏幕上始终只有**一份**菜单（每个
     `MENU LABEL` 只出现一次、固定在第 2..N+1 行、下方无输出），高亮依次落在
     第 3/4/5/4 行；按电源键后选中项回显在第 1 行、菜单消失；
   - `TIMEOUT` 3 s 无输入取 `DEFAULT`，倒计时行被收回；中途按键则菜单留在
     原地、高亮下移、屏上没有倒计时残留；
   - 设备菜单同样的倒计时代码（`bootmenu 3`）：无输入跑第 0 项，中途按键停住
     倒计时、电源键跑高亮项。
   同一套探针在**修前**的树上复现了"每按一键整份菜单往下多印一份"的现象。
   这套探针是一次性脚本（未入库）；要复跑，按上面三步重编 qemu 目标即可。

## 配对与回退

- 新的 `/boot` 布局（只有 extlinux）与带 `sysboot` 的 U-Boot 镜像是一套。
  旧镜像的 `Boot Linux` 读的是 `/boot/{Image,initrd.img,liuqin.dtb}`，旧
  NixOS 配置写的是那三个文件；过渡期二者不要混用。
- 新镜像先 RAM 引导（`fastboot boot`），`boot_b` 上的现有镜像保持不动作为
  已知可用回退。
- U-Boot 侧的补丁是本仓库自带的（上游 2024.10 没有）；`boot/pxe_utils.c` 的
  改动是通用的（"让 pxe/extlinux 菜单用按键"），值得单独上游化，届时这段
  说明要跟着改。

## 关于独立 `NIXOSboot` 分区

| 布局 | 判断 |
| --- | --- |
| `linux` ext4 根分区内 `/boot` | 采用。沿用已读通的 UFS 分区与现有 root guard；不再触碰 GPT。 |
| 新 `NIXOSboot` ext4 分区挂载 `/boot` | 仅在有明确需求后做。U-Boot 要按新 partlabel 查找；NixOS 与安装器都要在安装/重建前正确挂载并检查容量与身份；`linux` 根分区仍要容纳 `/nix/store`。 |
| 把 kernel 塞进 `boot_b` 或把它格式化成 ESP | 不适合：`boot_b` 是 ABL 加载 U-Boot 的 Android boot 镜像分区，不是文件系统。 |

若将来确需新分区，先读完整 GPT、备份、核对 userdata 缩容与 ABL 校验约定，
再依据实测每代 kernel + initrd + dtbs 大小、保留代数与余量定容量，不写死
分区号、扇区位置或"通用大小"。独立 `/boot` 也不自动回滚 rootfs 里的可变
数据；generation 回滚只回滚 NixOS 系统闭包。

[ubdoc]: https://docs.u-boot.org/en/latest/develop/bootstd/extlinux.html

设备菜单现在是 `bootmenu 5`：5 s 无输入跑第 0 项 `Boot NixOS`（不写任何东西，
失败时打印原因并 `pause`），任何按键都停住倒计时进入交互；倒计时只出现在第一次
显示，菜单项返回后的菜单是无超时的常驻菜单（`cmd/bootmenu.c` 的重绘循环用
`-1` 再问）。`Boot Android` 在第 2 项，倒计时够不到它。
