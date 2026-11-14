# 显示交接调查：证据索引

[综合报告](../DISPLAY-HANDOFF-2026-11-14.md)是本次调查的结论入口。
这里归档分项报告、关键原始指令/源码摘录、输入哈希和历史记录，避免只留下聊天结论。
没有把原始固件镜像、完整 ELF 或整个源码树复制进 BSP。

## 分项报告

- [ABL / UEFI](abl.md)：实际 dump 的 splash 条件分支、DisplayPower 协议、M81 关闭、
  双 DSI TERM、PHY/clock 释放、EBS 和 raw entry，以及 ROM XML 交叉对照。
- [U-Boot](uboot.md)：固定基线与补丁身份、借用 framebuffer、`sysboot`/`booti`、
  DM 退出选择、共享资源、两棵 DT，以及交接阶段的失败处理。
- [Linux / 原厂模块](kernel.md)：从 dump 提取的 5.10.160 模块、continuous splash、
  7.2.5 的实际初始化、PLL probe 写入、双 DSI、TDDI 和命令表对照。
- [历史证据复核](history.md)：材料版本差异、精确历史 Git blob、C2–C9 能支持和
  不能支持的结论，以及原始 GPIO/KMS 快照的离线重读。

分项报告保留独立审查过程，个别“待与另一子项核对”描述属于当时的研究阶段；最终
合并结论和剩余缺口以综合报告为准。各分项使用的原始同名证据已按 `evidence/` 的
子目录归档；完整工作集位于 `/tmp/liuqin-display-systematic-20261114/`。

## 固件和源码身份

- [firmware-inputs.json](firmware-inputs.json)：此次重算并与 dump 清单比对的 12 个
  分区镜像哈希，包括 A/B ABL、UEFI、imagefv、XBL 和 vendor_boot。
- [source-inputs-before.json](source-inputs-before.json)：调查前的 BSP 0001/0003、
  U-Boot/bootimg 定义以及 `/home/seeker/nixos-config/flake.nix` / `flake.lock` 哈希。
  调查结束再次比对，均未改变。
- [ABL 提取清单](evidence/abl/manifest.json)：镜像、实际 PE/XML、工具版本和地址映射。
- [内核材料哈希](evidence/kernel/evidence-sha256.json)：实际/旧显示模块、参考公开代码、
  C5 源码、历史补丁和 dump DTBO。
- [U-Boot 固定源码哈希](evidence/uboot/source-fingerprints.json)及
  [移植文件清单核对](evidence/uboot/port-manifest-check.txt)。
- [历史 Git blob 清单](evidence/history/git-evidence-manifest.json)：原始 commit ID、
  blob 路径和文件内容哈希。旧 Markdown 按原字节存为 `.md.txt`，保留其原始链接文本，
  避免将历史相对路径误当作当前文档导航。
- [归档文件清单](archive-sha256.json)：本目录全部归档文本/脚本的 SHA256；自身不包含
  在清单中。

## 关键证据

- [ABL / DisplayDxe 关键指令](evidence/abl/annotated-excerpts.txt)。地址是对应 PE 的
  RVA，不是压缩分区镜像的偏移。结合提取清单阅读。
- [显示时钟资源表](evidence/abl/clock-resources-8.1.json)和真实 M81
  [42 版 XML](evidence/abl/Panel_M81_42_02_0b_dualdsi_dsc_lcd_video.xml)、
  [36 版 XML](evidence/abl/Panel_M81_36_02_0a_dualdsi_dsc_lcd_video.xml)。
- [PLL probe / CCF 原始源码](evidence/kernel/pll-probe-source-excerpts.txt)和
  [补充注册调用点](evidence/kernel/clk-registration-extra-excerpts.txt)。
- [U-Boot 退出和显示源码](evidence/uboot/source-excerpts.txt)。
- `evidence/kernel/*.annotated.S`：实际 dump 模块的关键函数和重定位调用注释；地址为
  ELF `.text` 偏移。这里没有把同族公开代码当成本机的同版本源码。
- [UEFI / Android 命令差异](evidence/kernel/panel-init-uefi-android-diff.json)及
  [dump 供电 child 顺序](evidence/kernel/stock-supply-order.json)。
- [历史 GPIO 对照](evidence/history/gpio-comparison.json)和
  [C6 KMS 差异](evidence/history/c6-kms-diff.json)。精简日志保留在同目录；完整旧实验
  工作集仍在 `/tmp/liuqin-power-display-review-20261114/`，本次没有重新采集。

## 离线复现

ABL 提取入口为 [reproduce.sh](evidence/abl/reproduce.sh)和
[reproduce.py](evidence/abl/reproduce.py)。使用现有本机 dump / ROM 路径；脚本通过
临时 Nix 环境提供 Python 依赖，不连接设备。将输出指定到独立临时目录：

```sh
LIUQIN_RESEARCH_OUT=/tmp/liuqin-abl-independent \
  bash docs/research/display-handoff-2026-11-14/evidence/abl/reproduce.sh
```

再将导出组件 SHA256 与归档提取清单比对。工具版本已记录；Nix registry 会随时间
变化，未来工具版本改变可能影响反汇编文本格式，原始 PE/XML 哈希仍是内容身份依据。

U-Boot 可按固定 commit 重新取源，核对报告记录的 NAR hash，再应用对应 BSP 的
13 个补丁和新增文件。当前 BSP 基线为 `c2991ed`，U-Boot 输入在此次调查中未改变；
不要用 `old/liuqin-dualboot` 的 checkout 或旧构建配置替换。

原厂模块分析使用 dump `vendor_boot_a.img` 内的 vendor ramdisk。模块哈希、vermagic、
scmversion 和关键函数的重定位注释均已保存；不能拿历史 5.10.81 模块替代它。

## 验证范围

归档内容经过哈希、相对链接、文档格式和关键调用点交叉核对。此轮没有修改 Nix
配置或驱动，没有构建、部署或进行真机验收；这些静态验证不代表首次黑屏已修复。
