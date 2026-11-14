# 历史证据复核与材料索引（2026-11-14）

> 归档说明：本子报告原始工作目录为 `/tmp/liuqin-display-systematic-20261114/history/`；
> 已归档的同名证据位于 `evidence/history/`，完整源码/反汇编工作集仍在原目录。


本文件是离线审查。没有访问平板，没有运行新的 DSI、背光、按键、suspend 或部署操作。

## 同核对照与尚缺的原始信息

用户本轮明确确认：ABL 直接启动能出图的对照使用与当前相同的 7.2.5 内核和 DTB。
按用户的直接观测保留这个前提，不擅自改写成“只有旧 Ubuntu 能用”。同时，当前找到的
9 月记录没有保存这组对照的成对 Image/DTB 哈希、封装后的 DT、最终 live FDT、完整
启动参数和 workaround 关闭证据。因此同一输入 DTB 与最终传入树的差异仍应分别分析。
11 月 C5–C9 每个候选的 ABL 直启也未在本轮重新测试。

## 材料来源

- `liuqin-stock-dump/README.md` §4e：dump 为 2026-09-20 的 OS2.0.4 / Android 15，
  系统 ROM 目录为 V14.0.9 / Android 13，不能混用二进制 offset。
- `liuqin-audit/LIUQIN-DMESG-BOOT.txt`：5.10.136 的旧原厂日志，包含 M81_42_02_0b
  panel 选择；不是当前主线黑屏的日志。
- `liuqin-audit/evidence/final-runtime.dts`：旧 Android 的最终树，可以说明面板命令与
  供电描述；不能代替当前 ABL 到主线或 U-Boot 到主线各自的 live FDT。
- `liuqin-mainline-blobs/extracted/EXTRACTION.md`、`gki-mixed-boot/stock/rom/README.md`：
  明确来自 V14；已有 `msm_drm.ko` 也确为旧 5.10.81，不作为 OS2 的实现。
  OS2 模块已从 dump vendor_boot_a 静态提取，见 kernel 子报告。
- `old/liuqin-dualboot/u-boot/source`：历史 port HEAD 918b1f3…；当前 BSP 固定上游
  fork a4f9d7fc…另行取源并验证 NAR，见 U-Boot 子报告。
- `docs/TODO/DISPLAY-CAMERA-REVIEW.md`：2026-10-23 的二次审查，没有该次新真机验证。
- `docs/TODO/DISPLAY-HANDOFF.md`：10 月静态审查与 11 月 C2–C9 真机过程混排，必须
  按分节/boot ID 解释；不能把前面的“待验证”视为后面的已验收。
- `dirtyfb-ab/EVIDENCE.md`：CPU 映射 framebuffer 的 dirtyfb 独立问题，证据也明确
  未获得理想黑白视觉对照；不解释双 DSI 状态读数/触摸 ReK 的首次差异。
- `xiaomipad-6pro-mainline` / `linux-sm8450-liuqin` / `xiaomipad-6pro-nix`：旧直启
  镜像与开发源的参考。不能把上游 README 的“显示 working”作为本 BSP 候选验收。

## 已归档的精确历史版本

`git-evidence-manifest.json` 记录 full commit ID、blob path、内容 SHA256。

- b8cea71：第一次将 splash 改名与 first-modeset retry 放入同一提交。
  它保存了“改名后 ~1.9 秒出图”的书面实验结果，但没有配对原始 trace。
- 2f148f4：提交信息明确承认真正出图依赖 ~1.5 秒 DPMS cycle；controller-stop
  和去除 initial PLL save 单独无效。其因果解释只是当时的解释，不能由提交标题
  “fix(display)”升级为该阶段首次接管已修复。
- 9e40c71：已指出历史结论矛盾，要求核对 live DT、阶段顺序和 reset 的实际执行。

## C2–C9 结果的有效范围

| 现有结果 | 能支持 | 不能支持 |
| --- | --- | --- |
| C2 正常 OFF 阶段 GPIO/usecount 归零，后续 ON 出图 | Linux 关闭路径确实释放了所记录资源，第二次生命周期成功 | 首次启动已修；GPIO 状态直接等于所有实际电源电压 |
| C3 probe 时成对供电 OFF/ON 仍黑 | 该实现/时序不足以修复 | 任意上电/偏压/复位时序都无关；已复现 ABL 的停机 |
| C4 controller quiesce 前移到 PHY reset 前仍黑 | 仅把这一步前移不够 | 所有更早 PHY/PLL probe 操作都无关 |
| C4 禁止本次触摸 probe 后仍黑 | 黑屏无需本轮 NVT 下载参与也能发生 | TDDI 固件、共享供电或历史状态无关 |
| C4 锁定后 PLL mux 等项目相同 | 这些时刻/寄存器未见差异 | probe 之前状态相同、模拟状态机等价 |
| C5 改 burst、恢复上游 host/PLL 仍黑 | 这套改动不足以让首次出图 | 完全排除链路交接或所有 timing 差异 |
| C6 DSI1 首次无 read payload、恢复后 08/9a/9e | 同核两次读返回存在稳定差异 | 直接证明面板物理不通电、双 DSI 都无响应、线端未收到任何 write |
| C7 去四个 regulator-boot-on 仍黑 | 仅这四个 DT 属性不足 | 完全排除实际 rail 启动/软件引用/偏压控制模式 |
| C8 TGEN 首次 setup 前读0、第二次也0 | 到这个 Linux 采点，TGEN_EN 已为0 | U-Boot 出口扫描本来为0；更早接管无故障 |
| C9 194 个0x39入口请求、payload匹配Android DT仍黑 | 原Android短/长包编码差异单独不足 | 匹配UEFI XML；packet已被面板实际接收 |

C6–C9 的状态诊断会主动发送 DCS read，不是无副作用的被动抓取；C5 未加这些读取时
也已失败。DSI0 read 还有 bonded manager trigger 的限制，见 kernel 子报告。DSI1
对照有价值，但不应当作无条件可靠的独立电气测量。

## 此次离线重读原始快照得到的补充

`gpio-comparison.json`：C3/C6/C8 的 GPIO116 在失败首次为 low，恢复后为 high；
旧 Android DT 将它描述为第二 ESD 引脚。GPIO20 没有同样的变化，且本 BSP 未注册
原厂 ESD 状态机。因此这里只记电平相关性，不断言 ESD 来源或中断就是根因。

`c6-kms-diff.json`：失败首次与恢复后，DSI1 的 FIFO_STATUS、LANE_STATUS、readback
字段不同，DSI0 PLL 一个模拟状态值不同。大多数配置相同；状态读数也受采样帧相位和
主动 DCS read 影响，不能从这个 diff 抽出某个数值当作需要写回的“修复寄存器”。

原始 C6/C8/C9 选取日志来自 `/tmp/liuqin-power-display-review-20261114/`，精简副本
保存在本目录。完整日志仍以旧任务目录及已有 tar 为准；当前并未再次采集。
