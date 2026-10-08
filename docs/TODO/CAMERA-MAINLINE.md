# 摄像头（SM8475）现状与操作说明

生产分支的相机总览：**做了什么 / 还没做什么 / 注意事项与关键事实**。
实验过程的原始日志、数据与失败记录在 `camera/mainline` 分支（git 历史）；
内核补丁索引在 `pkgs/kernel/patches/README.md`；移植背景见 `docs/PORTING-NOTES.md`（Camera）。

## 我们做了什么（真机实测）

**内核（补丁 0012、0013、0021）**
- CAMSS SM8475 资源表 + 三颗模组驱动：宽 S5KJN1（csiphy3）、前 IMX596（csiphy2）、
  景深 SC202CS（csiphy1），含板级媒体图、供电/时钟/pinctrl；GDSC 用 vendor wait 值。
- sensor 模块晚加载 + 3 次重试（之间给 reset 脉冲），绕开早期 autoload 的 probe 抽卡。
- 逐项实测钉死的值：前摄链路 678.4 MHz、16 位 stream-on（`0x0100=0x0103`）；
  景深 360 MHz、单 lane；宽 700 MHz 菜单；VCM（GT9764）地址 0x0c；
  模组 EEPROM GT24P128E 在 0x51（8 字节分块读）；宽模组板装 180 度 ⇒ 驱动默认 HFLIP=1 + VFLIP=1（完整的 180° 校正；2026-10-07 修正：此前只置 VFlip，成片左右镜像、预览里不易察觉）；
  前摄 BGGR；景深为单色硬件。
- 对焦供电模型：模组轨由 sensor 的 runtime-PM 控制；对焦轨 pm8350c l7 常开、停 3.0 V 默认，
  **任何代码都不写轨道电压**（早期电压实验已全部删除）。
- VCM（GT9764）的 init/park 挂在 **sensor 的流** 上（0013）：`dw9768` 新增 `s_stream`
  op（stream-on 做 AAC/PD 初始化、stream-off 降 DAC 0 进 PD 停掉线圈），`s5kjn1` 在
  `enable_streams`/`disable_streams` 里按 DT `lens-focus` 引用带它一起；`runtime_resume`
  不再对芯片说话（open 时模块还没电，必然 -110）。2026-10-07 冷启动实测：重启后的
  **第一路流**就直接锁定（DAC 534/Focused；修复前 3/3 失败），dmesg 无 `-110`。
- 唯一标注为 downstream bring-up（`Kept on only for bring-up`）的工作并进 0013：
  titan_top/IFE GDSC 常开 + GCC camera AXI 常开，待最小集 bisect；0013 其余内容
  （s5kjn1 vendor 模式表/vflip、gt9764 VCM 驱动）是常规功能改动。

**用户态**
- libcamera 0.7.2 `simple` pipeline + 软件 ISP：`cam` 出成品帧；
  GNOME 应用经 portal -> pipewire -> libcamera 取景可用（用户实测确认）。
- AF 补丁系列（`pkgs/libcamera-af/`，standalone 构建，只注入 pipewire/wireplumber）：
  软 ISP 在成品帧中央 3/5 区域测一个归一化对焦度量（`SwIspStats.focusFoM` =
  Σ∇L²/ΣL²，CPU/EGL 两条 debayer 路径都算），并以标准 `FocusFoM` 元数据上报；
  对比度 AF 是 simple IPA 里的一个算法（`src/ipa/simple/algorithms/af.cpp`），
  扫描逻辑移植自 RPi IPA 的 `Af`（BSD-2）：粗扫起点离峰太近时反向、对比度掉到峰值
  75% 提前终止、细扫三点 + 抛物线拟合锁到子步长、Settle 只在峰确实被跨越时报
  Focused；连续模式按 RPi 语义触发重扫：**场景变化（对比度或任一通道均值偏离参考 >25%）之后平稳 `retrigger_delay`(10) 个 tick** 就重扫（不是"持续变化"——那会导致一次性场景变化永不重扫，也是 2026-10-07 修的"停在模糊位不动"）；锁在差位置时该规则会周期性成立，自带重试。
  参数是 RPi schema
  （`ranges`/`speeds`/`map`，单位屈光度；`map` = 屈光度→DAC，暂定线性、待 V 曲线标定）；
  统计 tick = 4 帧，armed 后按流帧数 `skip_frames` 起步；
  软 ISP 用 libcamera 的默认（GPU/EGL debayer，无 EGL 时回落 CPU）：EGL 把**整幅**传感器
  画面缩放到流尺寸（保住视野；CPU debayer 没有缩放器、只裁中心——1080p 流从 3840x2160
  传感器模式出发时水平视野只剩一半），FOM 的读回在补丁加上 GPU 同步后可用
  （2026-10-07 实测：离焦 1248 / 合焦 4261）；
  镜头移动经 mojom 事件 `setLensPosition` 交回 pipeline 写 VCM，
  LensPosition/AfMode/AfTrigger/AfState 由 pipeline 暴露；AE 数字增益、AWB
  `max-gain` 限幅、`Adjust.saturation` 默认值、sensor flip 默认同样按数据配置。
- 三颗相机在 DT 里声明了 `orientation`（宽/景深 back、前摄 front，补丁 0021）：libcamera 由此得到
  `Location`，pipewire 设备属性露出 `api.libcamera.location`。缺这个属性时 GNOME 侧按"未知朝向"
  处理——**表现为预览左右镜像而成片正常**（2026-10-07 实测：补上后预览恢复正常）。前摄/景深两颗的
  驱动还没接 `v4l2_fwnode_device_parse`，它们的 location 仍缺（见 open items）。
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
| 前摄/景深的 location | 这两颗驱动没有 `v4l2_fwnode_device_parse`/`v4l2_ctrl_new_fwnode_properties`，DT 的 `orientation` 不生效（libcamera 仍报 `Failed to retrieve the camera location`）⇒ 前摄的自拍预览不会按前摄约定镜像；按其驱动加同样两行即可 |
| AF 画质上限 | 已换成 RPi `Af` 移植（bracketing/抛物线/Settle 验证/场景变化触发）；仍无 PDAF、无 ROI；锁点精度取决于 V 曲线标定 |
| 应用拍照/录像 | GNOME Snapshot：保存的 JPEG 为 0 字节；录像文件 moov 未 finalize |
| suspend/resume | "睡醒后再抓帧"未测 |
| probe 稳定性 | 重试后的跨重启统计未做 |
| 色彩标定 | CCM 仍是 identity，需色卡实测 |
| 闪光灯联动 | LED 可用（/sys/class/leds），strobe 与 sensor 的 V4L2 flash 联动未接 |
| JPEG/录像编码 | 无 ISP/编码路径 |
| UVC gadget | 暂缓 |
| 0013 最小集 | titan_top/IFE GDSC + GCC AXI 哪些真的必要，待 bisect |
| EGL debayer FOM 绝对值 | 2026-10-07 复测：加了读回同步后 EGL 的 `focusFoM` 能跟踪对焦（离焦 1248 → 合焦 4261，同一场景 3.4×），AF 可用、CPU pin 已删除；但它的绝对值比同帧离线度量（0.00186）高约 2.3 倍，读回是否严格对应当前帧仍未查清（AF 只用比值，不受影响） |
| FOM 的早期帧 | 流的前 ~2 秒 FOM 会随 ISP 收敛整体漂移（暗场景下 AGC 数字增益爬升，gamma 编码下最多 4×；曝光本身不变）⇒ `skip_frames` 必须盖过它（现 240 帧 ≈4 s@60fps，见 tuning 注释）；流的**第一帧**还会读到 3–10× 的尖峰（疑似读到未渲染完的缓冲），目前靠 skip 绕开、未修 |
| V 曲线标定 | `map`（屈光度↔DAC）与 `ranges/speeds` 目前是暂定值：capture script（`--script` 逐 DAC 设 `LensPosition` + 读 `FocusFoM`）已备好，待合适的场景/环境下再跑；或从 stock `actuatorDriver`/EEPROM 提取。此前唯一实测点是 30 cm @ DAC 536 |

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

**应用侧（pipewire / GStreamer）**
- GNOME 应用取景走 portal -> pipewire -> libcamera，而 libcamera 就活在
  pipewire/wireplumber 进程里：**libcamera 崩溃 = "相机打不开"**，应用侧只看到
  GStreamer `Format negotiation failed`（`gst_base_src_loop ... reason not-negotiated`）。
  排查顺序：`coredumpctl list`（wireplumber 有没有 SIGSEGV）、`coredumpctl info <PID>`
  与 `journalctl --user -b | grep -i wireplumber`（回溯就在日志里）。
- `cam` 不经过 pipewire：CLI 能出帧而应用打不开 ⇒ 问题在 pipewire 侧（或反之）。
- 相机节点与其对外格式：`pw-cli ls Node`（`libcamera_input.*`）→
  `pw-cli enum-params <id> EnumFormat`。
- **GNOME Snapshot 只在窗口获得焦点后才启动相机**（`src/widgets/window.rs`：
  "We start the camera only after the window is active"）⇒ 从 SSH 无头启动的实例
  **永远不会碰相机**，只会停在取景器占位（看起来就是"转圈"）；验证相机必须让窗口真正激活
  （人工点一下），否则你只是在看一个僵死的旧实例。同理：`pkill` 掉旧实例要按
  `pkill -f "^snapshot$"`（进程 `comm` 是 `.snapshot-wrapp`，`cmdline` 只有 `snapshot`，
  `pkill -x snapshot` 与 `pkill -f "[.]snapshot-wrapp"` 都匹配不到），否则新启动只是
  "交接给旧实例后退出"（log 停在 `handle_local_options`，退出码 0）。
- 相机权限在 portal 权限库：`~/.local/share/flatpak/db/devices`（表 `devices`、id
  `camera`、值 `yes`；`org.gnome.Snapshot → yes` 即已授权）。`Camera.OpenPipeWireRemote`
  返回 `org.freedesktop.portal.Error.NotAllowed` 时应用走 `on_portal_not_allowed()`，
  UI 停在转圈。手工 `gdbus` 调它**永远** NotAllowed（调用者没有 app-id，除非先
  `host.portal.Registry.Register`）。`Camera` 接口的 `IsCameraPresent` 是**属性**不是方法。

**闪光灯（white:flash）**
- LED 类设备，火把亮度 0..255（`flash_*` 是 V4L2 闪光的 strobing 接口，未用）；相机闪光与手电筒共用这颗灯。
- GNOME Quick Settings 的 Flashlight 扩展（`pkgs/gnome-flashlight/`，**Wi-Fi 式两级**：磁贴点按开关灯、
  副标题显示亮度百分比、箭头展开二级菜单里的亮度滑条；图标取自 MDI `flashlight`/`flashlight-off`）
  由 demo 配置经 dconf 启用。udev 用 `RUN+=chgrp video/chmod 0664` 授权 —— **LED 没有 /dev 节点，
  `GROUP`/`MODE`/`uaccess` 对它全是空操作**（实测）。写 sysfs 不能用 `GLib.file_set_contents`
  （原子写要先在同目录建临时文件，sysfs 建不了），要直接 append；GNOME 50 没有 `St.Slider`
  （用 `ui/slider.js` 的 `Slider`）；改扩展 JS 后 GJS 模块缓存不失效，必须重启 Shell/重登。

**对焦（VCM）**
- V 曲线实测（2026-10-07，30 cm 说明书场景，1080p/CPU）：峰在 **DAC 512**（与历史
  "536=30cm" 吻合），信号半高宽约 **140 DAC**；tuning 的 `map` 锚定为 3.33 D↔512，
  `step_coarse` 0.5 D（≈51 DAC，约宽度的 1/3）。
- 镜头只在**模组上电（推流）时**可动；空闲写 focus 得到 `-110`/`-ETIMEDOUT` 是**预期**行为
  （init/park 跟流走：stream-on 初始化、stream-off park 到 DAC 0 并进 PD；
  桌面对话期驱动不 suspend 也不再影响线圈）。
- 对焦是流中动作：`v4l2-ctl -d <dw9768-subdev> --set-ctrl focus_absolute=<dac>`；
  536 是 30 cm 标定点。找节点：`media-ctl -p -d /dev/media0 | grep -A3 dw9768`。
- 自动对焦的形状：默认 `AfModeContinuous`，以统计 tick（4 帧）为单位推进；一次扫描 =
  起点 → 粗扫（对比度掉到峰值 75% 即止；若起点离峰太近则反向重扫）→ 细扫三点 +
  抛物线拟合 → Settle 验证（峰未被跨越时报 Failed）；失败就停在拟合峰，不自动重试
  （等场景变化）。每个采样点都打日志。
  手动标定：capture script 逐 DAC 设 `LensPosition`（AfMode=Manual）并读 `FocusFoM`
  元数据。AF 日志：`LIBCAMERA_LOG_LEVELS=IPASoftAf:0`。

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
- vendor 派生数据（0012/0013 内嵌寄存器/模式表）来自 MIUI blob；
  再分发限制见 `NOTICE`。
