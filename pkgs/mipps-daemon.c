/* SPDX-License-Identifier: MIT */
/*
 * liuqin-mippsd - the AP-side Xiaomi charger authentication coordinator.
 *
 * The ADSP owns USB-PD and UVDM.  This process only drives the deliberately
 * narrow qcom-battery ABI; it never writes a PDO or a voltage.  The key files
 * are provisioned outside the Nix store and are required to be root-owned
 * mode 0600.  Missing keys disable authentication and clear any stale verdict.
 *
 * LIUQIN_SYSFS_ROOT is intentionally supported for an offline fake-sysfs test
 * harness.  Production uses /sys.  No board access is performed by this
 * program; all hardware validation remains a later on-device step.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/netlink.h>
#include <openssl/crypto.h>
#include <openssl/hmac.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/random.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define MAX_VALUE 128
#define FG_CHALLENGE 32
#define PD_CHALLENGE 16
#define HMAC_SIZE 32

static volatile sig_atomic_t stopping;
static int no_data_role_swap;
static int reverse_auth;

static void stop_requested(int signal_number)
{
    (void)signal_number;
    stopping = 1;
}

static const char *root_dir(void)
{
    const char *root = getenv("LIUQIN_SYSFS_ROOT");
    return root && root[0] ? root : "/sys";
}

static int path_for(char *out, size_t out_len, const char *path)
{
    int n = snprintf(out, out_len, "%s%s", root_dir(), path);
    return n < 0 || (size_t)n >= out_len ? -ENAMETOOLONG : 0;
}

static int read_text(const char *path, char *buf, size_t len)
{
    char full[512];
    int fd, ret;
    ssize_t n;
    ret = path_for(full, sizeof(full), path);
    if (ret) return ret;
    fd = open(full, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return -errno;
    n = read(fd, buf, len - 1);
    ret = n < 0 ? -errno : 0;
    if (!ret) buf[n] = '\0';
    close(fd);
    return ret;
}

static int write_bytes(const char *path, const void *data, size_t len)
{
    char full[512];
    int fd, ret = 0;
    ssize_t n;
    ret = path_for(full, sizeof(full), path);
    if (ret) return ret;
    fd = open(full, O_WRONLY | O_CLOEXEC);
    if (fd < 0) return -errno;
    n = write(fd, data, len);
    if (n != (ssize_t)len) ret = n < 0 ? -errno : -EIO;
    close(fd);
    return ret;
}

static int write_text(const char *path, const char *text)
{
    return write_bytes(path, text, strlen(text));
}

static int read_u32_hex(const char *path, uint32_t *value)
{
    char text[MAX_VALUE], *end;
    unsigned long v;
    int ret = read_text(path, text, sizeof(text));
    if (ret) return ret;
    errno = 0;
    v = strtoul(text, &end, 16);
    if (errno || end == text || v > UINT32_MAX) return -EINVAL;
    *value = (uint32_t)v;
    return 0;
}

static int secret_file(const char *name, unsigned char *secret, size_t secret_len)
{
    const char *dir = getenv("LIUQIN_MIPPS_KEY_DIR");
    char path[512];
    int fd, ret = 0;
    struct stat st;
    ssize_t n;
    if (!dir || !dir[0]) dir = "/var/lib/liuqin/mipps";
    if (snprintf(path, sizeof(path), "%s/%s", dir, name) >= (int)sizeof(path))
        return -ENAMETOOLONG;
    if (stat(path, &st)) return -errno;
    if (st.st_uid != 0 || (st.st_mode & 0777) != 0600 || !S_ISREG(st.st_mode))
        return -EACCES;
    fd = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) return -errno;
    n = read(fd, secret, secret_len);
    if (n != (ssize_t)secret_len) ret = n < 0 ? -errno : -EINVAL;
    if (!ret) {
        unsigned char extra;
        if (read(fd, &extra, 1) != 0) ret = -EINVAL;
    }
    close(fd);
    return ret;
}

static int key_file(const char *name, unsigned char key[HMAC_SIZE])
{
    return secret_file(name, key, HMAC_SIZE);
}

static int hex_decode(const char *text, unsigned char *out, size_t out_len)
{
    size_t i;
    if (strlen(text) < out_len * 2) return -EINVAL;
    for (i = 0; i < out_len; i++) {
        unsigned int nibbles[2];
        for (size_t j = 0; j < 2; j++) {
            unsigned char c = (unsigned char)text[i * 2 + j];
            if (c >= '0' && c <= '9') nibbles[j] = c - '0';
            else if (c >= 'a' && c <= 'f') nibbles[j] = c - 'a' + 10;
            else if (c >= 'A' && c <= 'F') nibbles[j] = c - 'A' + 10;
            else return -EINVAL;
        }
        out[i] = (unsigned char)((nibbles[0] << 4) | nibbles[1]);
    }
    return 0;
}

static void hex_encode(const unsigned char *in, size_t len, char *out)
{
    static const char hex[] = "0123456789abcdef";
    size_t i;
    for (i = 0; i < len; i++) {
        out[i * 2] = hex[in[i] >> 4];
        out[i * 2 + 1] = hex[in[i] & 15];
    }
    out[len * 2] = '\0';
}

static int hmac_sha256(const unsigned char *key, const void *msg, size_t len,
                       unsigned char digest[HMAC_SIZE])
{
    unsigned int out_len = 0;
    if (!HMAC(EVP_sha256(), key, HMAC_SIZE, msg, len, digest, &out_len) ||
        out_len != HMAC_SIZE)
        return -EIO;
    return 0;
}

static int clear_verdict(void)
{
    int ret = write_text("/class/qcom-battery/qcom-battery/verify_process", "0");
    int verdict_ret = write_text("/class/qcom-battery/qcom-battery/pd_verifed", "0");
    return ret ? ret : verdict_ret;
}

static int authenticate_fg(unsigned int slave)
{
    unsigned char challenge[FG_CHALLENGE], expected[HMAC_SIZE], received[HMAC_SIZE];
    char encoded[FG_CHALLENGE * 2 + 1], response[MAX_VALUE];
    unsigned char key[HMAC_SIZE];
    const char *key_name = slave ? "slave-fg.key" : "fg.key";
    const char *digest = "/class/qcom-battery/qcom-battery/verify_digest";
    const char *auth = slave ? "/class/qcom-battery/qcom-battery/slave_authentic" :
                               "/class/qcom-battery/qcom-battery/authentic";
    char slave_flag[2];
    int ret = -EIO;
    int tries;
    ret = key_file(key_name, key);
    if (ret) goto fail;
    slave_flag[0] = slave ? '1' : '0';
    slave_flag[1] = '\0';
    ret = write_text("/class/qcom-battery/qcom-battery/verify_slave_flag", slave_flag);
    if (ret) goto fail;
    if (getrandom(challenge, sizeof(challenge), 0) != (ssize_t)sizeof(challenge))
        goto fail;
    hex_encode(challenge, sizeof(challenge), encoded);
    ret = write_bytes(digest, encoded, sizeof(encoded));
    if (ret) goto fail;
    ret = hmac_sha256(key, challenge, sizeof(challenge), expected);
    OPENSSL_cleanse(key, sizeof(key));
    if (ret) goto fail;
    /*
     * Poll for the ADSP reply instead of sleeping a fixed 89280 us like the
     * stock batterysecret: the mainline pmic-glink round trip can take a few
     * hundred milliseconds, and reading too early returns a stale value (the
     * written challenge, or a partially updated digest) which then fails the
     * comparison with -EACCES even though the key and protocol are correct.
     * Measured on hardware: stale at 90 ms, correct by 500 ms.
     */
    for (tries = 0; tries < 40; tries++) {
        usleep(50000);
        if (!read_text(digest, response, sizeof(response)) &&
            !hex_decode(response, received, HMAC_SIZE) &&
            !CRYPTO_memcmp(expected, received, HMAC_SIZE))
            return write_text(auth, "1\n");
    }
    ret = -EACCES;
    goto fail;
fail:
    OPENSSL_cleanse(key, sizeof(key));
    write_text(auth, "0\n");
    return ret ? ret : -EIO;
}

static int read_state(char *state, size_t len)
{
    int ret = read_text("/class/qcom-battery/qcom-battery/current_state", state, len);
    if (!ret) state[strcspn(state, "\n")] = '\0';
    return ret;
}

static int set_data_role_host(void)
{
    char role[MAX_VALUE], state[MAX_VALUE];
    int ret;
    if (!read_state(state, sizeof(state))) {
        if (!strcmp(state, "SRC_Ready") || !strcmp(state, "UNKNOWN"))
            return -EINVAL;
        if (strcmp(state, "SNK_Ready"))
            return -EAGAIN;
    }
    ret = write_text("/class/typec/port0/data_role", "host");
    if (ret) return ret;
    for (int i = 0; i < 4; i++) {
        usleep(70000);
        if (!read_text("/class/typec/port0/data_role", role, sizeof(role)) &&
            strstr(role, "[host]")) return 0;
    }
    return -EAGAIN;
}

/* The ADSP publishes the adapter SVID asynchronously after the data role
 * change: the stock daemon sees it within ~90 ms on the vendor kernel, but
 * the mainline pmic-glink round trip can take longer (the FG digest needed
 * ~500 ms), so poll for it before the per-command SVID gate rejects us. */
static int wait_adapter_svid(unsigned int ms)
{
    char svid[MAX_VALUE];
    unsigned int value;

    for (unsigned int i = 0; i * 50 <= ms; i++) {
        if (!read_text("/class/qcom-battery/qcom-battery/adapter_svid",
                       svid, sizeof(svid)) &&
            sscanf(svid, "%x", &value) == 1 && value == 0x2717)
            return 0;
        usleep(50000);
    }
    return -EAGAIN;
}

static int send_vdm(unsigned int command, const char *payload, unsigned int timeout,
                    char *reply_out, size_t reply_len)
{
    char request[MAX_VALUE], reply[MAX_VALUE];
    char svid[MAX_VALUE];
    unsigned int state, svid_value;
    int ret, loops;
    ret = read_text("/class/qcom-battery/qcom-battery/adapter_svid", svid, sizeof(svid));
    if (ret || sscanf(svid, "%x", &svid_value) != 1 || svid_value != 0x2717)
        return -EINVAL;
    /* The vendor's DISCONNECT entry is a bookkeeping step: it does not write
     * command 0, but still performs the readiness and SVID gate. */
    if (command == 0) return 0;
    if (snprintf(request, sizeof(request), "%u,%s", command, payload) >= (int)sizeof(request))
        return -EINVAL;
    for (loops = 0; loops < (command == 1 ? 20 : 4); loops++) {
        ret = read_text("/class/qcom-battery/qcom-battery/request_vdm_cmd", reply, sizeof(reply));
        if (!ret && sscanf(reply, "%u", &state) == 1 && state) break;
        usleep(20000);
    }
    if (loops == (command == 1 ? 20 : 4)) return -EAGAIN;
    ret = write_text("/class/qcom-battery/qcom-battery/request_vdm_cmd", request);
    if (ret) return ret;
    for (loops = 0; loops < (int)(timeout ? timeout : 1); loops++) {
        usleep(10000);
        ret = read_text("/class/qcom-battery/qcom-battery/request_vdm_cmd", reply, sizeof(reply));
        if (!ret && sscanf(reply, "%u", &state) == 1) {
            if (state == command) {
                if (reply_out && reply_len)
                    snprintf(reply_out, reply_len, "%s", reply);
                return 0;
            }
            if (!state) return -EINVAL;
        }
    }
    return -EAGAIN;
}

static int authenticate_pd(void)
{
    unsigned char key[HMAC_SIZE], challenge[PD_CHALLENGE], response[PD_CHALLENGE];
    unsigned char seed[PD_CHALLENGE];
    unsigned char msg[20], mac[HMAC_SIZE];
    char pdo[MAX_VALUE], reply[MAX_VALUE], payload[65], seed_payload[33];
    uint32_t adapter_id;
    unsigned int index;
    char key_name[32], seed_name[32];
    const char *verdict;
    int ret, pd_auth = 0;
    if (getrandom(&index, sizeof(index), 0) != (ssize_t)sizeof(index))
        return -EIO;
    index %= 10;
    snprintf(key_name, sizeof(key_name), "pd-%02u.key", index);
    snprintf(seed_name, sizeof(seed_name), "pd-%02u.seed", index);
    ret = key_file(key_name, key);
    if (ret) goto clear;
    ret = secret_file(seed_name, seed, sizeof(seed));
    if (ret) goto clear;
    ret = write_text("/class/qcom-battery/qcom-battery/verify_process", "1");
    if (ret) goto clear;
    ret = read_text("/class/qcom-battery/qcom-battery/pdo2", pdo, sizeof(pdo));
    if (ret || !strncmp(pdo, "00000000", 8)) goto clear;
    /* The stock batterysecret switches to the Type-C host role before
     * speaking UVDM; --no-data-role-swap (the shipped default) keeps the
     * community service behaviour instead. */
    if (!no_data_role_swap) {
        ret = set_data_role_host();
        if (ret) goto clear;
        /* The ADSP runs the vendor SVID discovery asynchronously after the
         * role change, so give it a bounded window before the SVID gate in
         * send_vdm() rejects the first command. */
        ret = wait_adapter_svid(3000);
        if (ret) goto clear;
    }
    if (getrandom(challenge, sizeof(challenge), 0) != (ssize_t)sizeof(challenge)) goto clear;
    /* Like the stock daemon, a single timed-out command is not fatal: the
     * run continues and the verdict stays 0 unless command 5 verifies. */
    ret = send_vdm(1, "null", 5, NULL, 0); if (ret && ret != -EAGAIN) goto clear;
    ret = send_vdm(2, "null", 5, NULL, 0); if (ret && ret != -EAGAIN) goto clear;
    ret = send_vdm(3, "null", 5, NULL, 0); if (ret && ret != -EAGAIN) goto clear;
    hex_encode(seed, sizeof(seed), seed_payload);
    ret = send_vdm(4, seed_payload, 500, NULL, 0);
    if (ret && ret != -EAGAIN) goto clear;
    hex_encode(challenge, sizeof(challenge), payload);
    /* Capture the command-5 reply in the same state poll that reports
     * completion; a second read could race the ADSP clearing the state. */
    ret = send_vdm(5, payload, 500, reply, sizeof(reply));
    if (ret && ret != -EAGAIN) goto clear;
    if (!ret &&
        !read_u32_hex("/class/qcom-battery/qcom-battery/adapter_id", &adapter_id) &&
        sscanf(reply, "5,%63s", payload) == 1 &&
        !hex_decode(payload, response, PD_CHALLENGE)) {
        memcpy(msg, challenge, sizeof(challenge));
        /* The shipped batterysecret assembles the first 8 hex chars of
         * adapter_id as byte pairs and appends them in text order, i.e. the
         * big-endian byte image of the displayed value. */
        msg[16] = (adapter_id >> 24) & 0xff; msg[17] = (adapter_id >> 16) & 0xff;
        msg[18] = (adapter_id >> 8) & 0xff; msg[19] = adapter_id & 0xff;
        if (!hmac_sha256(key, msg, sizeof(msg), mac))
            pd_auth = !CRYPTO_memcmp(mac, response, 16);
    }
    OPENSSL_cleanse(key, sizeof(key));
    verdict = pd_auth ? "01000000" : "00000000";
    if (reverse_auth) {
        /* Community reverse-auth flow (6 -> 8 -> 7); the stock Android
         * batterysecret never sends command 8. */
        ret = send_vdm(6, verdict, 5, NULL, 0);
        if (ret && ret != -EAGAIN) goto clear;
        if (pd_auth) {
            /* The adapter expects the second half of our MAC for reverse auth. */
            hex_encode(mac + 16, 16, payload);
            ret = send_vdm(8, payload, 500, NULL, 0);
            if (ret && ret != -EAGAIN) goto clear;
        }
        ret = send_vdm(7, verdict, 5, NULL, 0);
        if (ret && ret != -EAGAIN) goto clear;
    } else {
        /* Stock batterysecret order (binary .data table at 0x7710). */
        ret = send_vdm(7, verdict, 5, NULL, 0);
        if (ret && ret != -EAGAIN) goto clear;
        ret = send_vdm(6, verdict, 5, NULL, 0);
        if (ret && ret != -EAGAIN) goto clear;
    }
    ret = send_vdm(0, "null", 0, NULL, 0);
    if (ret && ret != -EAGAIN) goto clear;
    if (!pd_auth) goto clear;
    ret = write_text("/class/qcom-battery/qcom-battery/verify_process", "0");
    if (ret) goto clear;
    ret = write_text("/class/qcom-battery/qcom-battery/pd_verifed", "1");
    if (ret) goto clear;
    OPENSSL_cleanse(seed, sizeof(seed));
    return 0;
clear:
    OPENSSL_cleanse(key, sizeof(key));
    OPENSSL_cleanse(seed, sizeof(seed));
    clear_verdict();
    return ret ? ret : -EACCES;
}

/* The vendor battery charger exposes the USB power supply as "usb"; the
 * mainline pmic-glink stack calls it "qcom-battmgr-usb".  Accept either, and
 * bail out silently like before when no source is online. */
static int usb_online(void)
{
    static const char *const paths[] = {
        "/class/power_supply/usb/online",
        "/class/power_supply/qcom-battmgr-usb/online",
    };
    char online[MAX_VALUE];

    for (unsigned int i = 0; i < sizeof(paths) / sizeof(paths[0]); i++)
        if (!read_text(paths[i], online, sizeof(online)) && online[0] == '1')
            return 1;
    return 0;
}

static void process_once(void)
{
    char type[MAX_VALUE], state[MAX_VALUE], verified[MAX_VALUE];
    static int fg_verified[2];
    int ret;
    if (read_text("/class/qcom-battery/qcom-battery/real_type", type, sizeof(type))) {
        clear_verdict();
        return;
    }
    type[strcspn(type, "\n")] = '\0';
    for (unsigned int slave = 0; slave < 2; slave++) {
        const char *auth = slave ? "/class/qcom-battery/qcom-battery/slave_authentic" :
                                   "/class/qcom-battery/qcom-battery/authentic";
        if (fg_verified[slave] &&
            (!read_text(auth, verified, sizeof(verified)) && verified[0] == '1'))
            continue;
        fg_verified[slave] = 0;
        ret = authenticate_fg(slave);
        if (ret) {
            fprintf(stderr, "liuqin-mippsd: %s FG authentication failed: %d\n",
                    slave ? "slave" : "main", ret);
            clear_verdict();
            return;
        }
        fg_verified[slave] = 1;
    }
    if (!usb_online()) {
        clear_verdict();
        return;
    }
    if (strcmp(type, "PD") && strcmp(type, "PD_PPS")) {
        clear_verdict();
        return;
    }
    if (read_state(state, sizeof(state)) || strcmp(state, "SNK_Ready")) {
        clear_verdict();
        return;
    }
    if (!read_text("/class/qcom-battery/qcom-battery/pd_verifed", verified, sizeof(verified)) &&
        verified[0] == '1') return;
    ret = authenticate_pd();
    if (ret)
        fprintf(stderr, "liuqin-mippsd: PD authentication failed: %d\n", ret);
}

static int uevent_socket(void)
{
    struct sockaddr_nl addr = { .nl_family = AF_NETLINK, .nl_pid = getpid(),
                                .nl_groups = UINT32_MAX };
    int fd = socket(AF_NETLINK, SOCK_DGRAM | SOCK_CLOEXEC, NETLINK_KOBJECT_UEVENT);
    if (fd < 0) return -errno;
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr))) { int e = errno; close(fd); return -e; }
    return fd;
}

int main(int argc, char **argv)
{
    char event[65536];
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--no-data-role-swap"))
            no_data_role_swap = 1;
        else if (!strcmp(argv[i], "--reverse-auth"))
            reverse_auth = 1;
        else {
            fprintf(stderr, "liuqin-mippsd: unknown option: %s\n", argv[i]);
            return 2;
        }
    }
    struct sigaction stop_action = { .sa_handler = stop_requested };
    int fd;
    if (geteuid() != 0) { fprintf(stderr, "liuqin-mippsd: must run as root\n"); return 77; }
    sigaction(SIGTERM, &stop_action, NULL);
    sigaction(SIGINT, &stop_action, NULL);
    clear_verdict();
    process_once();
    fd = uevent_socket();
    if (fd < 0) { clear_verdict(); return 1; }
    while (!stopping) {
        struct pollfd p = { .fd = fd, .events = POLLIN };
        ssize_t n;
        int ready = poll(&p, 1, 5000);
        if (ready < 0) { if (errno == EINTR) continue; break; }
        if (ready == 0) { process_once(); continue; }
        n = recv(fd, event, sizeof(event), 0);
        if (n <= 0) continue;
        if (memmem(event, (size_t)n, "POWER_SUPPLY_NAME=usb", 21) ||
            memmem(event, (size_t)n, "DATA_ROLE=ufp", 13)) process_once();
    }
    close(fd);
    clear_verdict();
    return stopping ? 0 : 1;
}
