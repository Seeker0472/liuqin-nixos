# 摄像头（SM8475）现状与操作说明

生产分支的相机总览：**做了什么 / 还没做什么 / 注意事项与关键事实**。
实验过程的原始日志、数据与失败记录在 `camera/mainline` 分支（git 历史）；
内核补丁索引在 `pkgs/kernel/patches/README.md`；移植背景见 `docs/PORTING-NOTES.md`（Camera）。

## 我们做了什么（真机实测）

**内核（补丁 0018-0025）**
- CAMSS SM8475 资源表 + 三颗模组驱动：宽 S5KJN1（csiphy3）、前 IMX596（csiphy2）、
  景深 SC202CS（csiphy1），含板级媒体图、供电/时钟/pinctrl；GDSC 用 vendor wait 值。
- sensor 模块晚加载 + 3 次重试（之间给 reset 脉冲），绕开早期 autoload 的 probe 抽卡。
- 逐项实测钉死的值：前摄链路 678.4 MHz、16 位 stream-on（`0x0100=0x0103`）；
  景深 360 MHz、单 lane；宽 700 MHz 菜单；VCM（GT9764）地址 0x0c；
  模组 EEPROM GT24P128E 在 0x51（8 字节分块读）；宽模组板装 180 度 ⇒ 驱动默认 VFLIP=1；
  前摄 BGGR；景深为单色硬件。
- 对焦供电模型：模组轨由 sensor 的 runtime-PM 控制；对焦轨 pm8350c l7 常开、停 3.0 V 默认，
  **任何代码都不写轨道电压**（早期电压实验已全部删除）。
- 唯一标注为 downstream bring-up 的是 0024（titan_top/IFE GDSC 常开 + GCC camera AXI 常开），
  待最小集 bisect；其余补丁都是修 bug。

**用户态**
- libcamera 0.7.2 `simple` pipeline + 软件 ISP：`cam` 出成品帧；
  GNOME 应用经 portal -> pipewire -> libcamera 取景可用（用户实测确认）。
- AF 补丁系列（`pkgs/libcamera-af/`，standalone 构建，只注入 pipewire/wireplumber）：
  LensPosition、AfMode/AfTrigger 契约、对比度 AF（settle 90 帧、每位置驻留 11 帧、
  tracking 3 倍掉分 + 冷却）、AE 数字增益、AWB 增益限幅、flip 默认、默认饱和度。
- NixOS：sensor 模块黑名单 + 晚加载、dma-buf heap 的 video 组权限、AF 可选注入、
  journald `SyncIntervalSec=5s`（无 UART 时的取证通道）。
- 手动/脚本路径全部用上游工具，**没有自研 CLI**（以下命令已在本机 system-129 上实测）：
  `cam --stream role=raw --capture=1 --file=/tmp/f.raw`（宽 10,368,000 B/帧）、
  `cam --stream role=viewfinder --capture=2`（软 ISP，8160x6144）、
  `media-ctl -r -d /dev/media0`、`v4l2-ctl --set-ctrl focus_absolute=...`（详见 README/INSTALL）。

## 还没做（open items）

| 项 | 说明 |
| --- | --- |
| SC202CS 增益寄存器语义 | 厂律 Q10 的落点未知；当前把**模拟增益钉死 1x**（最小步进 3.4 倍会造成 AE 每帧 bang-bang），AE 只用曝光 + 数字增益 |
| 景深翻转 | `0x3221 = 0x06` vs `0x60` 待上机确认（寄存器不可在线访问，需部署迭代） |
| AF 画质上限 | 见补丁 0002 的 FIXME：对亮度敏感（AE 全程在动）、固定驻留、9+6 固定步进无插值、无 ROI |
| VCM 不 park | 桌面对话期 libcamera 常驻持有 lens subdev ⇒ 驱动永不 suspend ⇒ 关相机后镜头停在最后 DAC（实测 639），`dw9768_release()` 从不执行（rail 常开是 DTS 设计，这条是额外的线圈保持电流）；应改为停流时 park；FIXME 见 `0021` |
| VCM init 重试不到 | 模块未上电时 resume 的 `dw9768_init()` 超时（-110），"下次 resume 再试"在节点常开时永不发生 ⇒ 芯片整 boot 跑在 POR 默认（无 AAC/PD 复位）；修法：init/park 都挂到 sensor 的 `s_stream`；FIXME 见 `0021` |
| 应用拍照/录像 | GNOME Snapshot：保存的 JPEG 为 0 字节；录像文件 moov 未 finalize |
| suspend/resume | "睡醒后再抓帧"未测 |
| probe 稳定性 | 重试后的跨重启统计未做 |
| 色彩标定 | CCM 仍是 identity，需色卡实测 |
| 闪光灯联动 | LED 可用（/sys/class/leds），strobe 与 sensor 的 V4L2 flash 联动未接 |
| JPEG/录像编码 | 无 ISP/编码路径 |
| UVC gadget | 暂缓 |
| 0024 最小集 | titan_top/IFE GDSC + GCC AXI 哪些真的必要，待 bisect |
| 远距对焦标定 | DAC 536 只在 30 cm 标定过 |

## 注意事项与关键事实

**媒体图 / 单消费者**
- 三颗模组共享 `csid0 -> vfe0_rdi0`：任何时刻**只能有一个流**；多余的 phy->csid link 会让
  CSID 解析出多个输入，三颗**都不出帧**。
- 复位媒体图：`media-ctl -r -d /dev/media0`（把所有 link 置 inactive）。
- 不要在开机阶段路由/推流；应用由 libcamera 自行路由。已路由的图被 probe/打开可能**楔死相机路径**
  （只能重启）。
- 判据：`media-ctl -p` 里缺 wide/front/depth 任一 sensor，或有多条 enabled 的 csiphy->csid -
  重启设备，别硬修。
- 会话启动后 wireplumber 的探测可能**留下一条 enabled 的 csiphy->csid 链路**（实测：开机后
  csiphy1/景深残留开启）；App 报 EBUSY 或黑屏时先 `sudo media-ctl -r -d /dev/media0` 再重试。
- wireplumber 的 v4l2 监控算一个消费者：raw 抓帧前 `systemctl --user mask --now wireplumber`，
  之后 unmask。

**对焦（VCM）**
- 镜头只在**模组上电（推流）时**可动；空闲写 focus 得到 `-110`/`-ETIMEDOUT` 是**预期**行为
  （注意：驱动在桌面对话期不 suspend，所以也不会自动 park / 重新 init —— 见 open items 两行）。
- 对焦是流中动作：`v4l2-ctl -d <dw9768-subdev> --set-ctrl focus_absolute=<dac>`；
  536 是 30 cm 标定点。找节点：`media-ctl -p -d /dev/media0 | grep -A3 dw9768`。

**探测与恢复**
- sensor 模块被 blacklist，由 `liuqin-camera-probe`（3 次、间隔 5 s）晚加载；失败时**每颗相机都消失**，
  此时不要碰相机栈，重启恢复（驱动自身的重试已把概率压到很低）。
- 无 UART：取证只有屏幕、pstore/ramoops 与 journald（所以模块把落盘间隔调到 5 s）。

**硬件速查**

| 模组 | 位置 | I2C | 链路 | 时钟/复位 |
| --- | --- | --- | --- | --- |
| 宽 S5KJN1 | csiphy3，4080x3060 | 0x10 | 4 lane，700 MHz 菜单 | MCLK2/gpio102，RST gpio126 |
| 前 IMX596 | csiphy2，2592x1952 | 0x10 | 4 lane，678.4 MHz（实测） | MCLK5/gpio105，RST gpio127 |
| 深 SC202CS | csiphy1，1600x1200（单色） | 0x36 | 1 lane，360 MHz（实测） | MCLK1/gpio101，RST gpio24 |

- 相机 I2C 总线号逐启动漂移：按"驱动名 + 地址后缀"匹配（别写死 `5-0010`）。
- CCI/EEPROM 单次读不超过 8 字节。
- 两份 libcamera：`cam` 是 stock；AF 补丁版只进 pipewire/wireplumber，命令行用 `cam-af`。
- 不要读 camss 的 debugfs `regs`：历史补丁的 CAMNOC/VFE 窗口读取会硬挂（补丁已删除，别再加载）。
- vendor 派生数据（0018/0019/0020 内嵌寄存器/模式表）来自 MIUI blob；
  再分发限制见 `NOTICE`。
