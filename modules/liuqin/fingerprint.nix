# SPDX-License-Identifier: MIT
#
# OEM FPC1264 fingerprint support (hardware.liuqin.fingerprint.enable).
#
# The full stack, from the sensor up:
#
#   kernel      qseecomtee.ko (CONFIG_TEE_QSEECOM, 0017-liuqin-tee-qseecom-legacy-transport.patch) speaks the
#               legacy QSEE transport and exposes /dev/tee0 and /dev/teepriv0;
#               fpc1020.ko (CONFIG_SENSORS_FPC1020, 0018-liuqin-misc-fpc1020.patch) powers the
#               sensor and reports its interrupt through /dev/fpc1020, and
#               deliberately performs no SPI (the fpcliu trustlet owns the
#               bus); 0019-liuqin-dts-fpc1264.patch adds the DT node.  QCOM_QSEECOM and the TEE
#               core (TEE=module) are pulled in by modprobe as dependencies,
#               so only the two leaf modules are named below.
#   TOD driver  pkgs.liuqinFpcOemTodDriver: the out-of-tree libfprint TOD
#               module ("fpc1264_oem") loaded from FP_TOD_DRIVERS_DIR.  It has
#               no matcher of its own: verify() stages the single stored
#               FpPrint and runs the OEM runtime with the trustlet's match
#               result, then commits an adapted template through fprintd;
#               enroll() (patched in) consumes the prepared credential input,
#               drives the trustlet's enrolment and returns the opaque
#               single-finger database as the FpPrint for fprintd to store.
#   fprintd     pkgs.liuqinFprintdOem: 1.94.5 with the reviewed adaptive-template
#               persistence change (commit before VerifyStatus success).
#   PAM         pkgs.liuqinPamFpc: while the account password is being
#               authenticated (login, which carries gdm-password, and sudo),
#               derives the 32-byte credential input the trustlet requires for
#               enrolment and caches it in the root keyring - 18 h, one use,
#               boot-local, nothing on disk - exactly like the bundle's
#               acceptance_input.  That is what lets GNOME's stock
#               "Add fingerprint" flow work without a second prompt.
#   runtime     pkgs.liuqinFpcOem: the static FPC/Keymaster clients, the
#               QSEE/TEE supplicant + authenticated UFS RPMB provider, the PAM
#               credential input helper and the Python entry points, all under
#               one prefix (LIUQIN_FPC_OEM_RUNTIME).
#
# Off by default, and deliberately so: enabling it is not enough for a working
# sensor.  The OEM firmware images, the FPC trusted applications, RPMB state and
# the Gatekeeper handles are per-device data that cannot be packaged, and the
# first credential creation (liuqin-fpc-credential --create <user>) is a
# physical procedure documented in docs/INSTALL.md (Fingerprint); until it has
# been performed on the unit, the option only makes the stack reachable -
# password login is untouched either way.
{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.liuqin.fingerprint;

  # One flat runtime prefix; see pkgs/fingerprint/liuqin-fpc-oem.nix for why the
  # entry points require their helpers to be siblings.
  runtimeDir = "${pkgs.liuqinFpcOem}/libexec/liuqin-fpc-oem";

  # Private OEM state, hard-coded by the component's entry points: native/ holds the
  # per-uid Gatekeeper handles and their operation locks, pending/ holds an
  # accepted export whose publication failed, acceptance.json is the marker the
  # acceptance flow writes.  /var/lib/fprint (fprintd's own store) is created by
  # the unit's StateDirectory.
  stateDir = "/var/lib/liuqin-fingerprint";

  # A CLI entry is a thin exec of one Python entry point of the bundle: the
  # firmware directory and the bytecode-cache decision are the only environment
  # the NixOS deployment adds.  Arguments are forwarded unchanged, so the
  # scripts stay the single source of truth for their own interface.
  mkCli = name: script: description: pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = [ pkgs.python3 pkgs.coreutils ];
    text = ''
      # ${description}
      export LIUQIN_FPC_OEM_FIRMWARE=${cfg.firmwareDir}
      export PYTHONDONTWRITEBYTECODE=1
      exec python3 ${runtimeDir}/${script} "$@"
    '';
  };
in
{
  options.hardware.liuqin.fingerprint = {
    enable = lib.mkEnableOption ''
      OEM FPC1264 fingerprint support: the qseecomtee/fpc1020 modules,
      the libfprint TOD driver, fprintd with OEM template persistence and the
      OEM userspace runtime.  Requires operator-supplied firmware and the
      documented device-side credential/enrolment procedure'';

    firmwareDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/liuqin-fpc-oem/firmware";
      description = ''
        Root-owned directory holding the OEM firmware images for the FPC1264
        (fpcliu.mdt plus its segment files) and the SHA256.json that lists them.
        The OEM runtime points the kernel's firmware_class.path at this
        directory for the duration of one operation and verifies every file
        against that manifest, so the files must be placed there by the
        operator: they are per-device vendor data and cannot be packaged.
      '';
    };

    pamServices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "login" "sudo" "polkit-1" ];
      description = ''
        PAM services whose password authentication prepares the credential
        input the trustlet requires for enrolment.  `login` carries
        gdm-password as a substack, so a password typed at the login screen or
        at the lock screen is enough; `sudo` covers sessions that were started
        without a password (autologin); `polkit-1` is the prompt GNOME shows
        anyway when "Add fingerprint" is confirmed, which makes the flow
        self-sufficient.  Each listed service gets an earlier pam_unix instance
        (try_first_pass, so an existing token is reused) and must therefore be
        a service that may prompt for the account password.  Services are
        expected to use the default PAM rules.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.fprintd = {
      enable = true;
      # fprintd 1.94.5 + the OEM commit-before-VerifyStatus change, linked
      # against the same libfprint-tod the TOD driver was built for.
      package = pkgs.liuqinFprintdOem;
      tod.enable = true;
      tod.driver = pkgs.liuqinFpcOemTodDriver;
    };

    # The trustlet authorises a template with the account credential input
    # (PBKDF2-HMAC-SHA256 over the Linux password) and fprintd's Enroll API
    # cannot carry a secret.  pam_liuqin_fpc derives that 32-byte input while a
    # password is being authenticated and caches it exactly like the bundle's
    # acceptance_input.prepare(): root UID keyring, 18 h, one use, boot-local,
    # nothing on disk.  The TOD driver's enroll() consumes it, so GNOME's
    # stock "Add fingerprint" flow needs no second prompt.
    #
    # Placement: immediately before the sufficient pam_unix, i.e. after the
    # stack has prompted for the password (PAM_AUTHTOK exists) and before
    # pam_unix short-circuits the rest of the stack.  When a service has no
    # earlier pam_unix instance (nothing else needs the token), one is added so
    # that the password is available here.
    security.pam.services = lib.listToAttrs (map (name: lib.nameValuePair name {
      rules.auth = let
        unix = lib.attrByPath [ "unix" ]
          (throw "hardware.liuqin.fingerprint.pamServices: ${name} does not use the default PAM rules")
          config.security.pam.services.${name}.rules.auth;
      in
      {
        # Prompts only when no earlier instance has a token yet
        # (try_first_pass), so stacks that already prompt are unchanged.
        liuqin_fpc_unix_early = {
          order = unix.order - 20;
          control = "optional";
          modulePath = config.security.pam.pam_unixModulePath;
          settings.try_first_pass = true;
        };
        liuqin_fpc_prepare = {
          order = unix.order - 10;
          control = "optional";
          modulePath = "${pkgs.liuqinPamFpc}/lib/security/pam_liuqin_fpc.so";
        };
      };
    }) cfg.pamServices);

    boot.kernelModules = [ "qseecomtee" "fpc1020" ];

    systemd.tmpfiles.rules = [
      "d ${stateDir} 0700 root root -"
      "d /var/lib/liuqin-fpc-oem 0700 root root -"
      "d ${cfg.firmwareDir} 0700 root root -"
      "d /var/lib/liuqin-fpc-oem/candidate 0700 root root -"
    ];

    systemd.services.fprintd = {
      environment = {
        # Selects the virtual OEM device in the TOD driver.
        FP_LIUQIN_FPC1264_OEM_ENABLE = "1";
        # The stock libfprint also contains a built-in fpc1020 driver; restrict
        # this daemon to the TOD adapter so it cannot probe the sensor through
        # the unrelated legacy driver.
        FP_DRIVERS_ALLOWLIST = "fpc1264_oem";
        LIUQIN_FPC_OEM_RUNTIME = runtimeDir;
        LIUQIN_FPC_OEM_FIRMWARE = cfg.firmwareDir;
        # The bundle lives in the read-only store; do not attempt __pycache__
        # writes next to it.
        PYTHONDONTWRITEBYTECODE = "1";
      };
      serviceConfig = {
        # The CLI and fprintd share one operation lock and one TA listener set;
        # preserving the directory keeps a live lock inode across the daemon's
        # idle exits (the unit is D-Bus activated).
        RuntimeDirectory = "liuqin-fpc-oem-runtime";
        RuntimeDirectoryMode = "0700";
        RuntimeDirectoryPreserve = "yes";
        # A drop-in replaces a list setting rather than extending it, so the
        # upstream StateDirectory=fprint is restated here next to the OEM state
        # directory that the entry points write to under ProtectSystem=strict.
        StateDirectory = "fprint liuqin-fingerprint";
        StateDirectoryMode = "0700";
        # The OEM adaptive-template commit (oem-update.inc, pulled in by the
        # adaptive-template patch) refuses a stored template that is not 0600, while
        # fprintd's own file storage writes new prints with the daemon umask
        # (0644 under the default 0022). A print enrolled from the desktop then
        # matches but cannot be committed: fprintd reports verify-unknown-error
        # and the lock screen stays locked.  The CLI path chmods its output to
        # 0600 itself, which is why only the desktop flow exposed this.
        UMask = "0077";
        # Likewise: /sys/devices is the upstream exception (USB wakeup tuning);
        # the firmware class parameter is the one the OEM runtime rewrites to
        # point the sensor firmware loader at firmwareDir.  Same list, so both
        # survive the upstream unit's ProtectSystem=strict/ProtectKernelTunables.
        ReadWritePaths = [
          "/sys/devices"
          "/sys/module/firmware_class/parameters/path"
        ];
        # Upstream device rules are restated for the same reason (a drop-in
        # replaces the list); the last four are the nodes the OEM stack uses:
        # the sensor control interface, the TEE client and supplicant devices,
        # and the UFS RPMB bsg node.  No char-spi: the normal world never
        # touches the sensor bus, the trustlet does.
        DeviceAllow = [
          "char-usb_device rw"
          "char-hidraw rw"
          "/dev/cros_fp rw"
          "/dev/fpc1020 rw"
          "/dev/tee0 rw"
          "/dev/teepriv0 rw"
          "/dev/bsg/0:0:0:49476 rw"
        ];
      };
    };

    # gnome-control-center reads org.gnome.login-screen to decide whether the
    # Users panel offers "Fingerprint Login"; that schema is GDM's, and glib
    # only looks in <datadir>/glib-2.0/schemas (it does not descend into
    # <datadir>/gsettings-schemas/*), so the schema is invisible unless its
    # datadir is listed.  GDM's greeter runs with GDM's environment and sees it,
    # session applications do not: settings_or_null() then returns NULL and the
    # row is hidden without a message anywhere.
    environment.sessionVariables.XDG_DATA_DIRS = [
      "${pkgs.gdm}/share/gsettings-schemas/${pkgs.gdm.name}"
    ];

    # The PAM service pam-input authenticates the Linux account before it
    # derives the FPC credential input (pam_unix only: no include, no nullok,
    # no fingerprint recursion - see the file itself).
    environment.etc."pam.d/liuqin-fpc-enrol".source =
      "${pkgs.liuqinFpcOem}/etc/pam.d/liuqin-fpc-enrol";

    environment.systemPackages = [
      (mkCli "liuqin-fpc-oem-runtime" "oem_runtime.py"
        "Root-only OEM operation: probes, template inventory, match, or a credential/authorisation operation over the authenticated UFS RPMB listener.")
      (mkCli "liuqin-fpc-enrol" "enrol_publish.py"
        "Root-only authenticated enrolment: capture and export one OEM template and publish it into fprintd's file store (interactive terminal).")
      (mkCli "liuqin-fpc-credential" "user_credentials.py"
        "Root-only Gatekeeper credential creation and password re-synchronisation (interactive terminal).")
    ];
  };
}
