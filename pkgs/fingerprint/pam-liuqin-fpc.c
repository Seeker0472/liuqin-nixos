/* SPDX-License-Identifier: MIT
 *
 * pam_liuqin_fpc.so - credential input preparation for the OEM FPC1264 stack.
 *
 * The fpcliu trustlet accepts a template only when the enrolment is authorised
 * with the account's credential input: PBKDF2-HMAC-SHA256 (schema 1, 32-byte
 * salt, 32-byte output) over the Linux account password.  fprintd's Enroll API
 * cannot carry a secret, so the input is derived here, when the account
 * authenticates with its password, and stored exactly like the OEM bundle's
 * acceptance_input.prepare() does: one key in the ROOT UID keyring, 18 h
 * expiry, consumed (revoked) by the first enrolment that uses it.  Neither the
 * password nor the derived input is written to disk, and no userspace daemon
 * holds them; the TOD driver's enroll() then runs the trustlet without a
 * second prompt.
 *
 * The module never fails an authentication: every error path returns
 * PAM_IGNORE and leaves the password login untouched.
 *
 * Private state it reads:
 *   /var/lib/liuqin-fingerprint/native/<native_uid>/input-parameters.json
 *   /var/lib/liuqin-fingerprint/native/<native_uid>/gatekeeper.handle
 * Custody it writes:
 *   keyring key "liuqin-fpc-acceptance:<boot_id>:<user>" (root UID keyring)
 *   /run/liuqin-fpc-oem-runtime/acceptance-<user>.json
 */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pwd.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <syslog.h>
#include <time.h>
#include <unistd.h>

#include <linux/keyctl.h>
#include <openssl/evp.h>
#include <security/pam_ext.h>
#include <security/pam_modules.h>

#define NATIVE_STATE_DIR "/var/lib/liuqin-fingerprint/native"
#define RUNTIME_DIR "/run/liuqin-fpc-oem-runtime"
#define BOOT_ID_FILE "/proc/sys/kernel/random/boot_id"
#define LIFETIME_SECONDS (18 * 3600)
#define INPUT_BYTES 32
#define SALT_BYTES 32
/* Possessor and owning user may view/read/write/search/link/setattr; group and
 * other get nothing.  Same value acceptance_input.prepare() sets. */
#define KEY_PERM 0x3F3F0000u
#define MAX_PARAMETER_BYTES 4096
#define NATIVE_UID_SCHEME 0x50000000u
#define LEGACY_NATIVE_UID_SCHEME 0x40000000u

/* Strict private-file read: root-owned regular file, mode 0600, bounded size.
 * Returns the content NUL-terminated in buffer. */
static bool
read_private_file (const char *path, char *buffer, size_t capacity)
{
  struct stat info;
  size_t offset = 0;
  int fd = open (path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);

  if (fd < 0)
    return false;
  if (fstat (fd, &info) || !S_ISREG (info.st_mode) || info.st_uid != 0 ||
      (info.st_mode & 0777) != 0600 || info.st_size <= 0 ||
      (size_t) info.st_size >= capacity)
    {
      close (fd);
      return false;
    }
  while (offset < (size_t) info.st_size)
    {
      ssize_t count = read (fd, buffer + offset, (size_t) info.st_size - offset);
      if (count < 0 && errno == EINTR)
        continue;
      if (count <= 0)
        {
          close (fd);
          return false;
        }
      offset += (size_t) count;
    }
  close (fd);
  buffer[offset] = '\0';
  return true;
}

/* Bounded read for world-readable kernel files. */
static bool
read_world_file (const char *path, char *buffer, size_t capacity)
{
  size_t offset = 0;
  int fd = open (path, O_RDONLY | O_CLOEXEC);

  if (fd < 0)
    return false;
  while (offset + 1 < capacity)
    {
      ssize_t count = read (fd, buffer + offset, capacity - 1 - offset);
      if (count < 0 && errno == EINTR)
        continue;
      if (count <= 0)
        break;
      offset += (size_t) count;
    }
  close (fd);
  if (offset == 0)
    return false;
  buffer[offset] = '\0';
  return true;
}

static bool
boot_id (char *out, size_t out_size)
{
  char buffer[128];
  size_t end;

  if (!read_world_file (BOOT_ID_FILE, buffer, sizeof (buffer)))
    return false;
  end = strlen (buffer);
  while (end > 0 && (buffer[end - 1] == '\n' || buffer[end - 1] == '\r' ||
                     buffer[end - 1] == ' ' || buffer[end - 1] == '\t'))
    end--;
  if (end == 0 || end >= out_size)
    return false;
  memcpy (out, buffer, end);
  out[end] = '\0';
  return true;
}

/* The parameter file is machine-written by user_credentials.py with
 * json.dumps(sort_keys=True); a strict scanner for the few fields we trust is
 * enough and avoids a JSON dependency in the authentication path. */
static bool
json_string (const char *json, const char *key, char *out, size_t out_size)
{
  char pattern[64];
  const char *cursor;
  size_t length = 0;

  if (snprintf (pattern, sizeof (pattern), "\"%s\"", key) >= (int) sizeof (pattern))
    return false;
  cursor = strstr (json, pattern);
  if (!cursor)
    return false;
  cursor += strlen (pattern);
  while (*cursor == ' ' || *cursor == '\t' || *cursor == '\n' || *cursor == '\r')
    cursor++;
  if (*cursor++ != ':')
    return false;
  while (*cursor == ' ' || *cursor == '\t' || *cursor == '\n' || *cursor == '\r')
    cursor++;
  if (*cursor++ != '"')
    return false;
  while (*cursor && *cursor != '"' && *cursor != '\\')
    {
      if (length + 1 >= out_size)
        return false;
      out[length++] = *cursor++;
    }
  if (*cursor != '"')
    return false;
  out[length] = '\0';
  return true;
}

static bool
json_unsigned (const char *json, const char *key, unsigned long long *value)
{
  char pattern[64];
  const char *cursor;
  char *end = NULL;
  unsigned long long parsed;

  if (snprintf (pattern, sizeof (pattern), "\"%s\"", key) >= (int) sizeof (pattern))
    return false;
  cursor = strstr (json, pattern);
  if (!cursor)
    return false;
  cursor += strlen (pattern);
  while (*cursor == ' ' || *cursor == '\t' || *cursor == '\n' || *cursor == '\r')
    cursor++;
  if (*cursor++ != ':')
    return false;
  while (*cursor == ' ' || *cursor == '\t')
    cursor++;
  errno = 0;
  parsed = strtoull (cursor, &end, 10);
  if (errno || end == cursor)
    return false;
  *value = parsed;
  return true;
}

static int
hex_nibble (char c)
{
  if (c >= '0' && c <= '9')
    return c - '0';
  if (c >= 'a' && c <= 'f')
    return c - 'a' + 10;
  if (c >= 'A' && c <= 'F')
    return c - 'A' + 10;
  return -1;
}

static bool
hex_to_bytes (const char *text, uint8_t *out, size_t out_size)
{
  if (strlen (text) != out_size * 2)
    return false;
  for (size_t i = 0; i < out_size; i++)
    {
      int high = hex_nibble (text[i * 2]);
      int low = hex_nibble (text[i * 2 + 1]);
      if (high < 0 || low < 0)
        return false;
      out[i] = (uint8_t) ((high << 4) | low);
    }
  return true;
}

/* Existence check with the *effective* credentials: a setuid helper (sudo's
 * PAM stack) runs with ruid = the invoking user, and access(2) would test the
 * real uid and refuse to look inside the 0700 root state directory. */
static bool
file_exists (const char *path)
{
  int fd = open (path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);

  if (fd < 0)
    return false;
  close (fd);
  return true;
}

/* Mirror user_credentials.py: a human account keeps its identity in
 * 0x50000000 | UID, unless legacy 0x40000000 | UID state already exists. */
static unsigned int
native_uid_for (const struct passwd *account)
{
  char path[PATH_MAX];
  unsigned int legacy = LEGACY_NATIVE_UID_SCHEME | (unsigned int) account->pw_uid;

  if (snprintf (path, sizeof (path), NATIVE_STATE_DIR "/%u/gatekeeper.handle", legacy)
        < (int) sizeof (path) && file_exists (path))
    return legacy;
  if (snprintf (path, sizeof (path), NATIVE_STATE_DIR "/%u/input-parameters.json", legacy)
        < (int) sizeof (path) && file_exists (path))
    return legacy;
  return NATIVE_UID_SCHEME | (unsigned int) account->pw_uid;
}

static long
keyctl_call (long operation, unsigned long arg2, unsigned long arg3,
             unsigned long arg4, unsigned long arg5)
{
  return syscall (SYS_keyctl, operation, arg2, arg3, arg4, arg5);
}

static void
drop_key (long ring, long serial)
{
  if (serial >= 0)
    {
      keyctl_call (KEYCTL_REVOKE, (unsigned long) serial, 0, 0, 0);
      keyctl_call (KEYCTL_UNLINK, (unsigned long) serial, (unsigned long) ring, 0, 0);
    }
}

/* Same custody as acceptance_input.prepare(): one 32-byte "user" key in the
 * root UID keyring (linked into the process keyring for possession, as the
 * bundle does) plus the private metadata file that names its serial.
 *
 * The root UID keyring is only reachable when the *real* uid is root: sudo's
 * PAM stack still runs with ruid = the invoking user while euid is already 0,
 * and both the possessor link and add_key() are refused there (the bundle's
 * python fails the same way in that state).  The custody work therefore runs
 * in a child that makes itself fully root, leaving the PAM process's
 * credentials untouched. */
static bool
store_input_direct (pam_handle_t *pamh, const char *username, unsigned int native_uid,
                    const uint8_t *input)
{
  char identifier[256];
  char metadata_path[PATH_MAX];
  char boot[64];
  char document[512];
  struct stat info;
  uint8_t roundtrip[INPUT_BYTES];
  long ring, process_ring, stale, serial = -1;
  int fd = -1;
  int written;
  bool stored = false;

  if (!boot_id (boot, sizeof (boot)))
    {
      pam_syslog (pamh, LOG_DEBUG, "liuqin-fpc-prepare: boot id unavailable");
      return false;
    }
  if (snprintf (identifier, sizeof (identifier), "liuqin-fpc-acceptance:%s:%s", boot, username)
      >= (int) sizeof (identifier))
    return false;
  if (mkdir (RUNTIME_DIR, 0700) && errno != EEXIST)
    {
      pam_syslog (pamh, LOG_DEBUG, "liuqin-fpc-prepare: runtime directory: %m");
      return false;
    }
  if (lstat (RUNTIME_DIR, &info) || !S_ISDIR (info.st_mode) || info.st_uid != 0 ||
      (info.st_mode & 077) != 0)
    {
      pam_syslog (pamh, LOG_DEBUG, "liuqin-fpc-prepare: runtime directory is not private");
      return false;
    }
  if (snprintf (metadata_path, sizeof (metadata_path), RUNTIME_DIR "/acceptance-%s.json",
                username) >= (int) sizeof (metadata_path))
    return false;

  ring = keyctl_call (KEYCTL_GET_KEYRING_ID, (unsigned long) KEY_SPEC_USER_KEYRING, 1, 0, 0);
  if (ring < 0)
    {
      pam_syslog (pamh, LOG_DEBUG, "liuqin-fpc-prepare: root keyring unavailable: %m");
      return false;
    }
  process_ring = keyctl_call (KEYCTL_GET_KEYRING_ID, (unsigned long) KEY_SPEC_PROCESS_KEYRING,
                              1, 0, 0);
  if (process_ring >= 0)
    keyctl_call (KEYCTL_LINK, (unsigned long) ring, (unsigned long) process_ring, 0, 0);
  stale = keyctl_call (KEYCTL_SEARCH, (unsigned long) ring, (unsigned long) (uintptr_t) "user",
                       (unsigned long) (uintptr_t) identifier, 0);
  if (stale >= 0)
    drop_key (ring, stale);

  serial = syscall (SYS_add_key, "user", identifier, input, (size_t) INPUT_BYTES, ring);
  if (serial < 0)
    {
      pam_syslog (pamh, LOG_DEBUG, "liuqin-fpc-prepare: key creation failed: %m");
      return false;
    }
  if (keyctl_call (KEYCTL_SETPERM, (unsigned long) serial, KEY_PERM, 0, 0) ||
      keyctl_call (KEYCTL_SET_TIMEOUT, (unsigned long) serial, LIFETIME_SECONDS, 0, 0))
    {
      pam_syslog (pamh, LOG_DEBUG, "liuqin-fpc-prepare: key permissions failed: %m");
      goto out;
    }
  memset (roundtrip, 0, sizeof (roundtrip));
  if (keyctl_call (KEYCTL_READ, (unsigned long) serial, (unsigned long) (uintptr_t) roundtrip,
                   INPUT_BYTES, 0) != INPUT_BYTES ||
      memcmp (roundtrip, input, INPUT_BYTES) != 0)
    {
      pam_syslog (pamh, LOG_DEBUG, "liuqin-fpc-prepare: key roundtrip failed");
      memset (roundtrip, 0, sizeof (roundtrip));
      goto out;
    }
  memset (roundtrip, 0, sizeof (roundtrip));

  written = snprintf (document, sizeof (document),
                      "{\"schema\": 1, \"username\": \"%s\", \"native_uid\": %u, "
                      "\"boot_id\": \"%s\", \"key_serial\": %ld, \"expires\": %lld}\n",
                      username, native_uid, boot, serial,
                      (long long) time (NULL) + LIFETIME_SECONDS);
  if (written < 0 || written >= (int) sizeof (document))
    goto out;
  unlink (metadata_path);
  fd = open (metadata_path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
  if (fd < 0)
    {
      pam_syslog (pamh, LOG_DEBUG, "liuqin-fpc-prepare: metadata creation failed: %m");
      goto out;
    }
  if (write (fd, document, (size_t) written) != (ssize_t) written)
    {
      pam_syslog (pamh, LOG_DEBUG, "liuqin-fpc-prepare: metadata write failed: %m");
      goto out;
    }
  stored = true;

out:
  if (fd >= 0)
    close (fd);
  if (!stored)
    {
      unlink (metadata_path);
      drop_key (ring, serial);
    }
  else
    pam_syslog (pamh, LOG_DEBUG,
                "liuqin-fpc-prepare: credential input prepared for %s (serial %ld)",
                username, serial);
  return stored;
}

static bool
store_input (pam_handle_t *pamh, const char *username, unsigned int native_uid,
             const uint8_t *input)
{
  int status = 0;
  pid_t child = fork ();

  if (child < 0)
    {
      pam_syslog (pamh, LOG_DEBUG, "liuqin-fpc-prepare: fork failed: %m");
      return false;
    }
  if (child == 0)
    {
      if (setresuid (0, 0, 0) != 0)
        _exit (EXIT_FAILURE);
      _exit (store_input_direct (pamh, username, native_uid, input)
               ? EXIT_SUCCESS : EXIT_FAILURE);
    }
  while (waitpid (child, &status, 0) < 0)
    if (errno != EINTR)
      return false;
  return WIFEXITED (status) && WEXITSTATUS (status) == EXIT_SUCCESS;
}

/* A skipped preparation is a normal outcome (no credential yet, or no
 * password was prompted); record why so the cases can be told apart. */
#define LIUQIN_SKIP(...) \
  do { \
    pam_syslog (pamh, LOG_DEBUG, "liuqin-fpc-prepare: skipped: " __VA_ARGS__); \
    return PAM_IGNORE; \
  } while (0)

PAM_EXTERN int
pam_sm_authenticate (pam_handle_t *pamh, int flags, int argc, const char **argv)
{
  const char *username = NULL;
  const char *password = NULL;
  struct passwd *account;
  char parameters[MAX_PARAMETER_BYTES];
  char state_path[PATH_MAX];
  char salt_hex[SALT_BYTES * 2 + 1];
  char kdf[64];
  char declared_user[128];
  uint8_t salt[SALT_BYTES];
  uint8_t input[INPUT_BYTES];
  unsigned long long schema, iterations, input_bytes, declared_uid, declared_native;
  unsigned int native_uid;

  (void) flags;
  (void) argc;
  (void) argv;

  if (pam_get_user (pamh, &username, NULL) != PAM_SUCCESS || !username || !*username)
    LIUQIN_SKIP ("no user");
  if (pam_get_item (pamh, PAM_AUTHTOK, (const void **) &password) != PAM_SUCCESS ||
      !password || !*password)
    LIUQIN_SKIP ("no password token");
  account = getpwnam (username);
  if (!account || strcmp (account->pw_name, username) ||
      account->pw_uid == 0 || account->pw_uid >= 0x10000000u)
    LIUQIN_SKIP ("unsupported account");

  native_uid = native_uid_for (account);
  if (snprintf (state_path, sizeof (state_path), NATIVE_STATE_DIR "/%u/input-parameters.json",
                native_uid) >= (int) sizeof (state_path))
    LIUQIN_SKIP ("credential parameter path");
  if (!read_private_file (state_path, parameters, sizeof (parameters)))
    LIUQIN_SKIP ("no credential parameters (%s)", state_path);

  if (!json_unsigned (parameters, "schema", &schema) || schema != 1 ||
      !json_unsigned (parameters, "iterations", &iterations) ||
      iterations < 1 || iterations > 5000000 ||
      !json_unsigned (parameters, "input_bytes", &input_bytes) || input_bytes != INPUT_BYTES ||
      !json_unsigned (parameters, "linux_uid", &declared_uid) ||
      declared_uid != account->pw_uid ||
      !json_unsigned (parameters, "native_uid", &declared_native) ||
      declared_native != native_uid ||
      !json_string (parameters, "kdf", kdf, sizeof (kdf)) ||
      strcmp (kdf, "PBKDF2-HMAC-SHA256") != 0 ||
      !json_string (parameters, "linux_username", declared_user, sizeof (declared_user)) ||
      strcmp (declared_user, username) != 0 ||
      !json_string (parameters, "salt_hex", salt_hex, sizeof (salt_hex)) ||
      !hex_to_bytes (salt_hex, salt, sizeof (salt)))
    LIUQIN_SKIP ("credential parameters are not schema 1");

  if (snprintf (state_path, sizeof (state_path), NATIVE_STATE_DIR "/%u/gatekeeper.handle",
                native_uid) >= (int) sizeof (state_path) ||
      !file_exists (state_path))
    LIUQIN_SKIP ("no credential handle (%s)", state_path);

  memset (input, 0, sizeof (input));
  if (PKCS5_PBKDF2_HMAC (password, (int) strlen (password), salt, sizeof (salt),
                         (int) iterations, EVP_sha256 (), INPUT_BYTES, input) != 1)
    LIUQIN_SKIP ("derivation failed");
  store_input (pamh, username, native_uid, input);
  explicit_bzero (input, sizeof (input));
  return PAM_IGNORE;
}

PAM_EXTERN int
pam_sm_setcred (pam_handle_t *pamh, int flags, int argc, const char **argv)
{
  (void) pamh;
  (void) flags;
  (void) argc;
  (void) argv;
  return PAM_IGNORE;
}
