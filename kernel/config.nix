# SPDX-License-Identifier: MIT
#
# liuqin kernel configuration, expressed as nixpkgs structuredExtraConfig.
#
# Base: the kernel's own arm64 defconfig (the generate-config.pl flow in
# nixpkgs builds the .config by answering `make defconfig` first, then
# applies these answers on top).  nixpkgs common-config is NOT part of the
# base - see the enableCommonConfig comment in default.nix for what that
# deliberately leaves out.  PREFER_BUILTIN is on for aarch64 by nixpkgs'
# default, but it only affects questions no answer covers; an explicit
# `=module` here stays a module, so the symbols that must be built in for the
# current bring-up are lifted by kernel/liuqin-firstboot.config instead.
#
# Sources: merged and deduplicated from xiaomipad-6pro-mainline
# device/configs/{liuqin-desktop,liuqin-keyboard,liuqin-sensors,liuqin-firstboot}.config,
# minus the snapd-only entries; the dedup against nixpkgs common-config was
# done while it was still enabled, so an option only it used to answer is
# absent unless it is answered here or in kernel/liuqin-firstboot.config.
# Options introduced by the patches in ../patches/kernel
# (HID_NANOSIC, TOUCHSCREEN_NT36523_SPI, DRM_PANEL_NOVATEK_NT36532,
# SERIAL_EARLYCON_SIMPLEFB) are answered here explicitly.
{ lib, kernelLib ? lib.kernel }:

let
  inherit (lib) mkForce;
in

with kernelLib;

{
  # --- Core platform: SM8475 / Qualcomm bring-up ---
  ARCH_QCOM = lib.mkForce yes;
  # TLMM for qcom,sm8475-tlmm (patch 0010); without it every GPIO-backed
  # peripheral on liuqin defers probe forever.
  PINCTRL_SM8475 = lib.mkForce yes;
  SCSI_UFS_QCOM = lib.mkForce yes;
  PHY_QCOM_QMP = lib.mkForce yes;
  PHY_QCOM_QMP_UFS = lib.mkForce yes;
  PHY_QCOM_QMP_PCIE = lib.mkForce yes;
  PHY_SNPS_EUSB2 = lib.mkForce yes;
  # The eusb2-repeater node instantiated by DTS patch 0001 binds to
  # PHY_QCOM_I2C_EUSB2_REPEATER ("nxp,eusb2-repeater"), backported as
  # patches/kernel/0009. The mainline SPMI variant is kept too.
  PHY_QCOM_I2C_EUSB2_REPEATER = lib.mkForce yes;
  PHY_QCOM_EUSB2_REPEATER = lib.mkForce yes;
  I2C_QCOM_GENI = lib.mkForce yes;
  SPI = lib.mkForce yes;
  SPI_QCOM_GENI = lib.mkForce yes;
  QCOM_GPI_DMA = lib.mkForce yes;
  QCOM_LLCC = lib.mkForce yes;
  QCOM_OCMEM = lib.mkForce yes;
  QCOM_SOCINFO = lib.mkForce yes;
  QCOM_STATS = lib.mkForce module;
  RTC_DRV_PM8XXX = lib.mkForce module;
  NVMEM_SPMI_SDAM = lib.mkForce module;
  NVMEM_REBOOT_MODE = lib.mkForce module;

  # Remote processors / DSP / RPMsg (ADSP, CDSP, SLPI for sensors).
  QCOM_Q6V5_PAS = lib.mkForce module;
  QCOM_MDT_LOADER = lib.mkForce module;
  QCOM_PDR_HELPERS = lib.mkForce module;
  QCOM_PD_MAPPER = lib.mkForce yes;
  QCOM_APR = lib.mkForce module;
  QCOM_FASTRPC = lib.mkForce module;
  QCOM_PMIC_GLINK = lib.mkForce module;
  QCOM_SYSMON = lib.mkForce module;
  QRTR = lib.mkForce yes;
  QRTR_SMD = lib.mkForce yes;
  QRTR_MHI = lib.mkForce module;
  MHI_BUS = lib.mkForce module;
  RPMSG_QCOM_GLINK_SMEM = lib.mkForce module;

  # Power, charging, Type-C.
  POWER_RESET_QCOM_PON = lib.mkForce module;
  INPUT_PM8941_PWRKEY = lib.mkForce module;
  BATTERY_QCOM_BATTMGR = lib.mkForce module;
  TYPEC = lib.mkForce module;
  TYPEC_UCSI = lib.mkForce module;
  UCSI_PMIC_GLINK = lib.mkForce module;
  POWER_SEQUENCING = lib.mkForce yes;
  POWER_SEQUENCING_QCOM_WCN = lib.mkForce module;

  # CPU frequency/idle governors used by the downstream desktop config.
  CPU_FREQ_GOV_POWERSAVE = lib.mkForce module;
  CPU_FREQ_GOV_CONSERVATIVE = lib.mkForce module;
  CPU_IDLE_GOV_TEO = lib.mkForce yes;
  PSI = lib.mkForce yes;

  # Display: MSM DRM + Novatek DSI panel + KTZ8866 backlight.
  DRM = lib.mkForce module;
  DRM_KMS_HELPER = lib.mkForce module;
  DRM_DISPLAY_HELPER = lib.mkForce module;
  DRM_DISPLAY_DSC_HELPER = lib.mkForce yes;
  DRM_MSM = lib.mkForce module;
  DRM_MSM_KMS = lib.mkForce yes;
  DRM_MSM_MDSS = lib.mkForce yes;
  DRM_MSM_DPU = lib.mkForce yes;
  DRM_MSM_DSI = lib.mkForce yes;
  DRM_MSM_DSI_7NM_PHY = lib.mkForce yes;
  DRM_MIPI_DSI = lib.mkForce yes;
  DRM_PANEL = lib.mkForce yes;
  DRM_PANEL_NOVATEK_NT36532 = lib.mkForce module; # from patch 0004
  DRM_FBDEV_EMULATION = lib.mkForce yes;
  DRM_CLIENT_LOG = lib.mkForce yes; # drm_client_lib.active=log still selectable
  DRM_CLIENT_DEFAULT_FBDEV = lib.mkForce yes; # fbcon on the DSI panel; the log
  # client implements no terminal and leaves the panel black at loglevel=4
  DRM_CLIENT_DEFAULT_LOG = lib.mkForce no;
  BACKLIGHT_CLASS_DEVICE = lib.mkForce module;
  BACKLIGHT_KTZ8866 = lib.mkForce module;
  FB_SIMPLE = lib.mkForce module;
  FONTS = lib.mkForce yes;
  FONT_8x16 = yes;
  FONT_TER16x32 = yes;
  SM_DISPCC_8450 = lib.mkForce module;
  # The SM8450 CAMCC driver also covers SM8475 and provides the MCLK,
  # CSIPHY/IFE clocks and camera GDSCs consumed by the CAMSS DT node.
  SM_CAMCC_8450 = lib.mkForce module;
  SM_GPUCC_8450 = lib.mkForce module;

  # Input: touchscreen (SPI Novatek, patch 0003), keyboard cover HID
  # (patch 0002), uinput/uhid for desktop tooling.
  INPUT_EVDEV = lib.mkForce module;
  INPUT_UINPUT = lib.mkForce module;
  UHID = lib.mkForce module;
  HID_MULTITOUCH = lib.mkForce module;
  HID_NANOSIC = lib.mkForce module; # from patch 0002
  TOUCHSCREEN_NT36523_SPI = lib.mkForce module; # from patch 0003

  # BT's optional deps/selects must be built in so BT=y sticks
  # (RFKILL=m caps BT at m and generate-config.pl dies on the re-ask).
  INPUT = lib.mkForce yes;
  LEDS_CLASS = lib.mkForce yes;
  LEDS_TRIGGERS = lib.mkForce yes;

  HID = lib.mkForce yes;
  HIDRAW = lib.mkForce yes;
  HID_GENERIC = lib.mkForce yes;

  USB = lib.mkForce yes;
  # The tablet's DWC3 controller is dual-role; the live installer needs its
  # peripheral gadget engine selected in the kernel because there is no module
  # loader before the control channel comes up.
  USB_DWC3_GADGET = lib.mkForce yes;

  # BT_RFCOMM_TTY is asked as a bool under BT_RFCOMM=m; answering y makes
  # kconfig re-ask the parent tree and generate-config.pl dies. Keep it off.
  BT_RFCOMM_TTY = lib.mkForce no;

  # RPMSG drivers menu only shows when the bus core selects it.
  QCOM_RPROC_COMMON = lib.mkForce module;

  MAILBOX = lib.mkForce yes;
  RPMSG = lib.mkForce yes;
  QCOM_SMEM = lib.mkForce yes;
  RPMSG_QCOM_SMD = lib.mkForce yes;

  # BT=y select chain must be built in too (otherwise Kconfig rejects the
  # upgrade of BT from m to y and generate-config.pl loops).
  CRC16 = lib.mkForce yes;
  CRYPTO = lib.mkForce yes;
  CRYPTO_LIB_AES = lib.mkForce yes;
  CRYPTO_ECDH = lib.mkForce yes;

  # Early console over the ABL simple-framebuffer (patch 0008).
  SERIAL_EARLYCON_SIMPLEFB = lib.mkForce yes;

  # Pstore remains available for stock ramoops hand-off. The ABL overlay
  # disables the duplicate reserved-memory node used by the mainline DTS.
  PSTORE = lib.mkForce yes;
  PSTORE_CONSOLE = lib.mkForce yes;
  PSTORE_PMSG = lib.mkForce yes;
  PSTORE_RAM = lib.mkForce yes;

  # Wireless: ath11k (QCA6490 WLAN) + Qualcomm Bluetooth over UART.
  CFG80211 = lib.mkForce module;
  MAC80211 = lib.mkForce module;
  ATH11K = lib.mkForce module;
  ATH11K_PCI = lib.mkForce module;
  ATH11K_DEBUG = lib.mkForce yes;
  PCI_PWRCTRL = lib.mkForce yes;
  PCI_PWRCTRL_PWRSEQ = lib.mkForce module;
  BT = lib.mkForce module;
  BT_LE = lib.mkForce yes;
  BT_RFCOMM = lib.mkForce module;
  BT_BNEP = lib.mkForce module;
  BT_HIDP = lib.mkForce module;
  BT_HCIUART = lib.mkForce module;
  BT_HCIUART_QCA = lib.mkForce yes;
  BT_QCA = lib.mkForce module;
  RFKILL = lib.mkForce module;

  # Audio: audioreach over SoundWire + CS35L41 speaker amps (patch 0005).
  SOUND = lib.mkForce module;
  SND = lib.mkForce module;
  SND_SOC = lib.mkForce module;
  SOUNDWIRE = lib.mkForce module;
  SND_SOC_QCOM = lib.mkForce module;
  SND_SOC_SC8280XP = lib.mkForce module;
  SND_SOC_CS35L41_I2C = lib.mkForce module;

  # Media: CAMSS raw capture plus the Iris V4L2 decoder (patch 0007).
  # Keep these explicit so a future defconfig change cannot silently leave a
  # camera DT node without its media-controller/subdev stack.
  MEDIA_SUPPORT = lib.mkForce module;
  MEDIA_CONTROLLER = lib.mkForce yes;
  VIDEO_V4L2_SUBDEV_API = lib.mkForce yes;
  VIDEOBUF2_DMA_SG = lib.mkForce module;
  I2C_QCOM_CCI = lib.mkForce module;
  VIDEO_QCOM_CAMSS = lib.mkForce module;
  VIDEO_S5KJN1 = lib.mkForce module;
  VIDEO_QCOM_LIUQIN_SENSORS = lib.mkForce module;
  VIDEO_QCOM_IRIS = lib.mkForce module;
  # The rear module's GT9764 autofocus (patch 0024).
  VIDEO_DW9768 = lib.mkForce module;

  # Camera flash (PM8350C) and the module EEPROMs on the CCI buses.  Both are
  # answered explicitly because the flash class and the EEPROM driver are the
  # consumers of the camera DT nodes; a defconfig change must not be able to
  # drop them silently.
  LEDS_CLASS_FLASH = lib.mkForce module;
  LEDS_QCOM_FLASH = lib.mkForce module;
  EEPROM_AT24 = lib.mkForce module;

  # Boot-image/initrd plumbing NixOS needs on this board.
  FW_LOADER = lib.mkForce yes;
  FW_LOADER_COMPRESS = lib.mkForce yes;
  FW_LOADER_COMPRESS_ZSTD = lib.mkForce yes;
  BLK_DEV_INITRD = lib.mkForce yes;
  DEVTMPFS = lib.mkForce yes;
  DEVTMPFS_MOUNT = lib.mkForce yes;
  OVERLAY_FS = lib.mkForce module;
  SQUASHFS = lib.mkForce module;
  SQUASHFS_XZ = lib.mkForce yes;
  SQUASHFS_ZSTD = lib.mkForce yes;
  SQUASHFS_LZO = lib.mkForce yes;
  # This selects libcomposite and the gadget functions. The platform's DWC3
  # peripheral controller is already built in by arm64 defconfig/downstream
  # firstboot config; answering its dependency tree again makes nixpkgs'
  # generate-config dialogue diverge.
  USB_CONFIGFS = lib.mkForce yes;
  USB_CONFIGFS_NCM = lib.mkForce yes;
  USB_CONFIGFS_ECM = lib.mkForce yes;

  # serial-flash for the persist partition and friends.
  MTD_SPI_NOR = lib.mkForce module;

  # GNOME portals (xdg-document-portal) mount via FUSE.
  FUSE_FS = lib.mkForce yes;

  # Post-mortem capture on a unit with no reachable debug UART.  A stuck CPU
  # or task should panic into the vendor-aligned ramoops console zone (readable
  # from the stock kernel's /sys/fs/pstore on Android afterwards) rather than
  # parking the unit silently; the persistent journal is the second channel.
  # A deliberate sysrq crash was measured to leave no dump on this overlay, so
  # the detectors are the panic path that actually produces a backtrace.
  SOFTLOCKUP_DETECTOR = yes;
  HARDLOCKUP_DETECTOR = yes;
  HARDLOCKUP_DETECTOR_BUDDY = yes;
  BOOTPARAM_HARDLOCKUP_PANIC = yes;
  DETECT_HUNG_TASK = yes;
}
