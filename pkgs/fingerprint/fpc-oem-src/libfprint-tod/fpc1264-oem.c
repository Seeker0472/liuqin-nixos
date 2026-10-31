/* SPDX-License-Identifier: LGPL-2.1-or-later
 * V1 prints carry a single opaque OEM database; V2 prints carry an opaque
 * gallery and a bounded finger-to-TA-template inventory. fprintd publishes
 * the canonical gallery; the adapter only stages private worker inputs.
 */
#include <gio/gio.h>
#include <gmodule.h>
#include <glib/gstdio.h>
#include <fpi-device.h>
#include <fpi-print.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

typedef struct {
  FpDevice parent;
  GSubprocess *child;
  guint8 enroll_read_buffer[4096];
  gchar enroll_line[1025];
  gsize enroll_line_length;
  gsize enroll_output_bytes;
  guint enroll_stages;
  gboolean enroll_active;
  gboolean enroll_stream_done;
  gboolean enroll_wait_done;
  gboolean enroll_ready;
  gboolean enroll_final_sample;
  gboolean enroll_finalizing;
  gboolean enroll_recovered;
  gboolean enroll_committed;
  gint enroll_exit_status;
  GError *enroll_error;
  gchar *enroll_error_code;
  const gchar *enroll_failure_phase;
  gint enroll_ta_status;
  gchar *directory;
  gchar *database;
  gchar *updated_database;
  gchar *inventory_path;
  gchar *match_id_path;
  guint32 fingers[5];
  guint32 ids[5];
  guint gallery_count;
  gboolean gallery_v2;
  gboolean identifying;
  GPtrArray *candidates;
  FpPrint *enrolled_print;
  gboolean cancelled;
} FpiDeviceFpc1264Oem;

typedef struct { FpDeviceClass parent; } FpiDeviceFpc1264OemClass;
G_DEFINE_TYPE (FpiDeviceFpc1264Oem, fpi_device_fpc1264_oem, FP_TYPE_DEVICE)

static void
clear_operation (FpiDeviceFpc1264Oem *self)
{
  g_clear_error (&self->enroll_error);
  g_clear_pointer (&self->enroll_error_code, g_free);
  self->enroll_failure_phase = NULL;
  self->enroll_ta_status = 0;
  self->enroll_line_length = 0;
  self->enroll_output_bytes = 0;
  self->enroll_stages = 0;
  self->enroll_active = FALSE;
  self->enroll_stream_done = FALSE;
  self->enroll_wait_done = FALSE;
  self->enroll_ready = FALSE;
  self->enroll_final_sample = FALSE;
  self->enroll_finalizing = FALSE;
  self->enroll_recovered = FALSE;
  self->enroll_committed = FALSE;
  self->enroll_exit_status = -1;
  g_clear_object (&self->child);
  if (self->database)
    g_unlink (self->database);
  if (self->updated_database)
    g_unlink (self->updated_database);
  if (self->inventory_path)
    g_unlink (self->inventory_path);
  if (self->match_id_path)
    g_unlink (self->match_id_path);
  if (self->directory)
    g_rmdir (self->directory);
  g_clear_pointer (&self->database, g_free);
  g_clear_pointer (&self->updated_database, g_free);
  g_clear_pointer (&self->inventory_path, g_free);
  g_clear_pointer (&self->match_id_path, g_free);
  g_clear_pointer (&self->candidates, g_ptr_array_unref);
  self->gallery_count = 0;
  self->gallery_v2 = FALSE;
  self->identifying = FALSE;
  g_clear_object (&self->enrolled_print);
  g_clear_pointer (&self->directory, g_free);
}

static void
probe (FpDevice *device)
{
  struct stat info;
  if (lstat ("/dev/fpc1020", &info) || !S_ISCHR (info.st_mode))
    fpi_device_probe_complete (device, NULL, NULL,
                              fpi_device_error_new_msg (FP_DEVICE_ERROR_NOT_SUPPORTED,
                                                        "FPC1264 stable-base device is unavailable"));
  else
    fpi_device_probe_complete (device, "liuqin-fpc1264-oem", "FPC1264 OEM on liuqin", NULL);
}

static void
open_device (FpDevice *device)
{
  fpi_device_open_complete (device, geteuid () == 0 ? NULL :
                           fpi_device_error_new_msg (FP_DEVICE_ERROR_GENERAL,
                                                     "The OEM runtime requires a privileged caller"));
}

static void
close_device (FpDevice *device)
{
  if (((FpiDeviceFpc1264Oem *) device)->enroll_active) {
    fpi_device_close_complete (device,
                               fpi_device_error_new_msg (FP_DEVICE_ERROR_GENERAL,
                                                         "OEM enrolment is still finishing"));
    return;
  }
  clear_operation ((FpiDeviceFpc1264Oem *) device);
  fpi_device_close_complete (device, NULL);
}

/* The OEM trustlet requires 20 accepted captures. Never report the final
 * stage until END, inventory, export and the private output are complete. */
#define LIUQIN_ENROL_MAX_STAGES 20
#define LIUQIN_ENROL_LINE_LIMIT 1024
#define LIUQIN_ENROL_OUTPUT_LIMIT (64u * 1024u)

static const gchar *const finger_names[] = {
  NULL, "left-thumb", "left-index-finger", "left-middle-finger",
  "left-ring-finger", "left-little-finger", "right-thumb",
  "right-index-finger", "right-middle-finger", "right-ring-finger",
  "right-little-finger"
};

/* Canonical presence is authoritative, even if the file is corrupt. */
static gboolean
load_enrol_gallery (FpDevice *device, const gchar *username, FpFinger finger,
                    guint8 **input, gsize *input_length, guint32 fingers[5],
                    guint32 ids[5], guint *count, gboolean *legacy, GError **error)
{
  g_autofree gchar *directory = NULL;
  g_autofree gchar *path = NULL;
  g_autofree guint8 *serialized = NULL;
  g_autoptr(FpPrint) stored = NULL;
  g_autoptr(GVariant) data = NULL;
  g_autoptr(GVariant) bytes = NULL;
  g_autoptr(GVariant) entries = NULL;
  struct stat info;
  int fd = -1;
  gsize size;
  guint32 version;
  const guint8 *contents;

  if (!*username || strchr (username, '/') || g_str_equal (username, ".") ||
      g_str_equal (username, ".."))
    goto invalid;
  directory = g_build_filename ("/var/lib/fprint", username, "fpc1264_oem",
                                "liuqin-fpc1264-oem", NULL);
  path = g_build_filename (directory, ".gallery", NULL);
  fd = g_open (path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW, 0);
  if (fd < 0 && errno == ENOENT) {
    g_clear_pointer (&path, g_free);
    for (guint i = 1; i <= 10; i++) {
      gchar name[2] = { i == 10 ? 'a' : '0' + i, 0 };
      g_autofree gchar *candidate = g_build_filename (directory, name, NULL);
      if (!lstat (candidate, &info)) {
        if (path)
          goto invalid;
        path = g_steal_pointer (&candidate);
        fingers[0] = i;
      }
      else if (errno != ENOENT)
        goto invalid;
    }
    if (!path)
      return TRUE;
    fd = g_open (path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW, 0);
    *legacy = TRUE;
  }
  if (fd < 0 || fstat (fd, &info) || !S_ISREG (info.st_mode) ||
      info.st_uid != 0 || (info.st_mode & 0777) != 0600 ||
      info.st_size <= 0 || info.st_size > 17u * 1024u * 1024u)
    goto invalid;
  serialized = g_malloc (info.st_size);
  for (gsize offset = 0; offset < (gsize) info.st_size;) {
    ssize_t n = read (fd, serialized + offset, info.st_size - offset);
    if (n < 0 && errno == EINTR)
      continue;
    if (n <= 0)
      goto invalid;
    offset += n;
  }
  if (close (fd)) {
    fd = -1;
    goto invalid;
  }
  fd = -1;
  stored = fp_print_deserialize (serialized, info.st_size, NULL);
  if (!stored || !fp_print_compatible (stored, device) ||
      g_strcmp0 (fp_print_get_username (stored), username))
    goto invalid;
  g_object_get (stored, "fpi-data", &data, NULL);
  if (!data)
    goto invalid;
  if (*legacy) {
    if (fp_print_get_finger (stored) != fingers[0] ||
        !g_variant_is_of_type (data, G_VARIANT_TYPE ("(uay)")))
      goto invalid;
    g_variant_get (data, "(u@ay)", &version, &bytes);
    if (version != 1 || fingers[0] == finger)
      goto invalid;
    *count = 1;
  }
  else {
    if (!g_variant_is_of_type (data, G_VARIANT_TYPE ("(uaya(uu))")))
      goto invalid;
    g_variant_get (data, "(u@ay@a(uu))", &version, &bytes, &entries);
    *count = g_variant_n_children (entries);
    if (version != 2 || *count > 5)
      goto invalid;
    for (guint i = 0; i < *count; i++) {
      g_variant_get_child (entries, i, "(uu)", &fingers[i], &ids[i]);
      if (!FP_FINGER_IS_VALID (fingers[i]) || !ids[i] || fingers[i] == finger)
        goto invalid;
      for (guint j = 0; j < i; j++)
        if (ids[j] == ids[i] || fingers[j] == fingers[i])
          goto invalid;
    }
  }
  contents = g_variant_get_fixed_array (bytes, &size, 1);
  if ((size == 0 && *count != 0) || size > 16u * 1024u * 1024u)
    goto invalid;
  if (size) {
    *input = g_memdup2 (contents, size);
    *input_length = size;
  }
  return TRUE;

invalid:
  if (fd >= 0)
    close (fd);
  g_set_error_literal (error, FP_DEVICE_ERROR, FP_DEVICE_ERROR_DATA_INVALID,
                       "Stored OEM gallery is invalid or inaccessible");
  return FALSE;
}


static gboolean
read_private_database (const gchar *path, guint8 **database, gsize *length, GError **error)
{
  struct stat info;
  guint8 *data;
  int fd = g_open (path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW, 0);

  if (fd < 0 || fstat (fd, &info) || !S_ISREG (info.st_mode) || info.st_uid != 0 ||
      (info.st_mode & 0777) != 0600 || info.st_size <= 0 ||
      info.st_size > 16u * 1024u * 1024u)
    goto failed;
  data = g_malloc (info.st_size);
  for (gsize offset = 0; offset < (gsize) info.st_size;) {
    ssize_t count = read (fd, data + offset, info.st_size - offset);
    if (count < 0 && errno == EINTR)
      continue;
    if (count <= 0) {
      g_free (data);
      goto failed;
    }
    offset += count;
  }
  close (fd);
  *database = data;
  *length = info.st_size;
  return TRUE;

failed:
  if (fd >= 0)
    close (fd);
  g_set_error_literal (error, FP_DEVICE_ERROR, FP_DEVICE_ERROR_GENERAL,
                       "OEM enrolment failed (storage_failure)");
  return FALSE;
}

static void
enrol_fail (FpiDeviceFpc1264Oem *self, const gchar *message)
{
  if (!self->enroll_error)
    self->enroll_error = fpi_device_error_new_msg (FP_DEVICE_ERROR_GENERAL, "%s", message);
  if (self->child)
    g_subprocess_send_signal (self->child, SIGTERM);
}

static gboolean
enrol_error_code_valid (const gchar *code)
{
  static const gchar *const codes[] = {
    "account_mismatch", "parameters_invalid", "missing_handle",
    "prepared_input_missing", "prepared_input_expired", "busy",
    "export_uncertain", "runtime_failure", "storage_failure", NULL
  };
  for (guint i = 0; codes[i]; i++)
    if (g_str_equal (code, codes[i]))
      return TRUE;
  return FALSE;
}

/* Only these fixed, versioned lines are trusted; unstructured OEM output is
 * ignored and is never written to the journal or interpolated into errors. */
static void
enrol_parse_line (FpDevice *device, const gchar *line)
{
  FpiDeviceFpc1264Oem *self = (FpiDeviceFpc1264Oem *) device;
  const gchar *remaining_prefix = "fpc_event=1 kind=sample remaining=";

  if (g_str_has_prefix (line, "fpc_error=")) {
    const gchar *code = line + strlen ("fpc_error=");
    if (!enrol_error_code_valid (code) || self->enroll_error_code) {
      enrol_fail (self, "Invalid OEM enrolment error protocol");
      return;
    }
    self->enroll_error_code = g_strdup (code);
    return;
  }
  if (self->enroll_error_code)
    return;
  if (g_str_has_prefix (line, "fpc_event=1 kind=phase code=")) {
    static const gchar *const phases[] = {
      "listener", "bio_init", "set_gid", "load_database", "set_group",
      "challenge", "begin_enrol", "capture", "sample", "end_enrol",
      "sensor_wait", "authorization", "export", "timeout", NULL
    };
    const gchar *code = line + strlen ("fpc_event=1 kind=phase code=");
    if (self->enroll_committed)
      goto invalid;
    for (guint i = 0; phases[i]; i++)
      if (g_str_equal (code, phases[i])) {
        self->enroll_failure_phase = phases[i];
        return;
      }
    goto invalid;
  }
  else if (g_str_has_prefix (line, "fpc_event=1 kind=ta_reject status=")) {
    const gchar *value = line + strlen ("fpc_event=1 kind=ta_reject status=");
    gchar *end = NULL;
    gint64 status;
    if (self->enroll_committed || *value != '-' || !g_ascii_isdigit (value[1]))
      goto invalid;
    status = g_ascii_strtoll (value, &end, 10);
    if (*end || status >= 0 || status < -4096)
      goto invalid;
    self->enroll_ta_status = (gint) status;
  }
  else if (g_str_equal (line, "fpc_event=1 kind=ready")) {
    if (self->enroll_ready || self->enroll_recovered ||
        self->enroll_finalizing || self->enroll_committed)
      goto invalid;
    self->enroll_ready = TRUE;
    fpi_device_report_finger_status (device, FP_FINGER_STATUS_NEEDED);
  }
  else if (g_str_has_prefix (line, remaining_prefix)) {
    const gchar *value = line + strlen (remaining_prefix);
    gchar *end = NULL;
    guint64 remaining;
    if (!self->enroll_ready || self->enroll_recovered ||
        self->enroll_finalizing || self->enroll_committed ||
        self->enroll_final_sample || !g_ascii_isdigit (*value))
      goto invalid;
    remaining = g_ascii_strtoull (value, &end, 10);
    /* The vendor defines remaining, not a host-side exact 19..0 sequence.
     * The old working pipeline accepted any positive intermediate result and
     * finalized only on status 0. Do not abort a valid TA enrolment because
     * firmware uses a different intermediate count. */
    if (*end || remaining > 40)
      goto invalid;
    fpi_device_report_finger_status (device, FP_FINGER_STATUS_PRESENT);
    if (remaining == 0)
      self->enroll_final_sample = TRUE;
    else if (self->enroll_stages < LIUQIN_ENROL_MAX_STAGES - 1) {
      self->enroll_stages++;
      fpi_device_enroll_progress (device, (gint) self->enroll_stages, NULL, NULL);
    }
  }
  else if (g_str_equal (line, "fpc_event=1 kind=lift")) {
    if (!self->enroll_ready || self->enroll_recovered ||
        self->enroll_finalizing || self->enroll_committed ||
        self->enroll_final_sample)
      goto invalid;
    fpi_device_report_finger_status (device, FP_FINGER_STATUS_NEEDED);
    fpi_device_enroll_progress (device, (gint) MIN (self->enroll_stages,
                                                   LIUQIN_ENROL_MAX_STAGES - 1),
                                NULL, fpi_device_retry_new_msg (FP_DEVICE_RETRY_REMOVE_FINGER,
                                                                  "Lift the finger, then press it again"));
  }
  else if (g_str_equal (line, "fpc_event=1 kind=retry code=capture_rejected")) {
    if (!self->enroll_ready || self->enroll_recovered ||
        self->enroll_finalizing || self->enroll_committed ||
        self->enroll_final_sample)
      goto invalid;
    fpi_device_report_finger_status (device, FP_FINGER_STATUS_NEEDED);
    fpi_device_enroll_progress (device, (gint) MIN (self->enroll_stages,
                                                   LIUQIN_ENROL_MAX_STAGES - 1),
                                NULL, fpi_device_retry_new (FP_DEVICE_RETRY_GENERAL));
  }
  else if (g_str_equal (line, "fpc_event=1 kind=finalizing")) {
    if (!self->enroll_ready || self->enroll_recovered ||
        self->enroll_finalizing || self->enroll_committed ||
        !self->enroll_final_sample)
      goto invalid;
    self->enroll_finalizing = TRUE;
  }
  else if (g_str_equal (line, "fpc_event=1 kind=recovered")) {
    if (self->enroll_recovered || self->enroll_ready || self->enroll_stages ||
        self->enroll_final_sample || self->enroll_finalizing || self->enroll_committed)
      goto invalid;
    self->enroll_recovered = TRUE;
  }
  else if (g_str_equal (line, "fpc_event=1 kind=committed")) {
    if ((!self->enroll_finalizing && !self->enroll_recovered) ||
        self->enroll_committed)
      goto invalid;
    self->enroll_committed = TRUE;
  }
  else if (g_str_has_prefix (line, "fpc_event="))
    goto invalid;
  return;

invalid:
  enrol_fail (self, "Invalid OEM enrolment event protocol");
}

static gboolean
read_enrol_inventory (FpiDeviceFpc1264Oem *self, FpFinger finger,
                      GVariant **replacement, const guint8 *database,
                      gsize length, GError **error)
{
  struct stat info;
  guint32 words[7], found[5], total, new_id;
  GVariantBuilder builder;
  int fd = g_open (self->inventory_path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW, 0);
  if (fd < 0 || fstat (fd, &info) || !S_ISREG (info.st_mode) ||
      info.st_uid != 0 || (info.st_mode & 0777) != 0600 ||
      info.st_size != sizeof words)
    goto invalid;
  for (gsize offset = 0; offset < sizeof words;) {
    ssize_t n = read (fd, (guint8 *) words + offset, sizeof words - offset);
    if (n < 0 && errno == EINTR)
      continue;
    if (n <= 0)
      goto invalid;
    offset += n;
  }
  if (close (fd)) {
    fd = -1;
    goto invalid;
  }
  fd = -1;
  total = GUINT32_FROM_LE (words[0]);
  new_id = GUINT32_FROM_LE (words[1]);
  if (total != self->gallery_count + 1 || total > 5 || !new_id)
    goto invalid;
  for (guint i = 0; i < 5; i++) {
    found[i] = GUINT32_FROM_LE (words[2 + i]);
    if ((i < total) != (found[i] != 0))
      goto invalid;
    for (guint j = 0; j < i; j++)
      if (found[i] && found[i] == found[j])
        goto invalid;
  }
  guint new_seen = 0;
  for (guint i = 0; i < total; i++)
    new_seen += found[i] == new_id;
  if (new_seen != 1)
    goto invalid;
  if (self->gallery_v2) {
    for (guint i = 0; i < self->gallery_count; i++) {
      guint seen = 0;
      for (guint j = 0; j < total; j++)
        seen += found[j] == self->ids[i];
      if (seen != 1 || self->ids[i] == new_id)
        goto invalid;
    }
  }
  else if (self->gallery_count == 1) {
    for (guint i = 0; i < total; i++)
      if (found[i] != new_id)
        self->ids[0] = found[i];
    if (!self->ids[0])
      goto invalid;
  }
  g_variant_builder_init (&builder, G_VARIANT_TYPE ("a(uu)"));
  for (guint i = 0; i < self->gallery_count; i++)
    g_variant_builder_add (&builder, "(uu)", self->fingers[i], self->ids[i]);
  g_variant_builder_add (&builder, "(uu)", (guint32) finger, new_id);
  *replacement = g_variant_ref_sink (g_variant_new ("(u@ay@a(uu))", 2u,
                   g_variant_new_fixed_array (G_VARIANT_TYPE_BYTE, database, length, 1),
                   g_variant_builder_end (&builder)));
  return TRUE;

invalid:
  if (fd >= 0)
    close (fd);
  g_set_error_literal (error, FP_DEVICE_ERROR, FP_DEVICE_ERROR_GENERAL,
                       "OEM enrolment inventory does not match the prior gallery");
  return FALSE;
}

static gboolean
stage_private_database (const gchar *path, const guint8 *database,
                        gsize length, GError **error)
{
  int fd = g_open (path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
  if (fd < 0)
    goto failed;
  for (gsize offset = 0; offset < length;) {
    ssize_t n = write (fd, database + offset, length - offset);
    if (n < 0 && errno == EINTR)
      continue;
    if (n <= 0)
      goto failed;
    offset += n;
  }
  if (close (fd))
    goto failed_closed;
  return TRUE;

failed:
  if (fd >= 0)
    close (fd);
failed_closed:
  g_set_error_literal (error, FP_DEVICE_ERROR, FP_DEVICE_ERROR_GENERAL,
                       "Private OEM database staging failed");
  return FALSE;
}

/* Completion is gated on both child exit and stdout EOF. An exit-status
 * callback can run before buffered final messages have reached the reader. */
static void
enrol_maybe_complete (FpDevice *device)
{
  FpiDeviceFpc1264Oem *self = (FpiDeviceFpc1264Oem *) device;
  g_autoptr(GError) error = NULL;
  g_autoptr(GVariant) replacement = NULL;
  g_autoptr(FpPrint) print = NULL;
  g_autofree guint8 *database = NULL;
  gsize length = 0;
  gboolean cancelled;

  if (!self->enroll_active || !self->enroll_wait_done || !self->enroll_stream_done)
    return;
  cancelled = self->cancelled || fpi_device_action_is_cancelled (device);
  if (!cancelled && !self->enroll_error && !self->enroll_error_code &&
      self->enroll_exit_status == 0 && self->enroll_committed &&
      ((self->enroll_recovered && !self->enroll_ready && !self->enroll_stages &&
        !self->enroll_final_sample && !self->enroll_finalizing) ||
       (!self->enroll_recovered && self->enroll_ready &&
        self->enroll_final_sample && self->enroll_finalizing)) &&
      self->enrolled_print &&
      read_private_database (self->database, &database, &length, &error)) {
    if (read_enrol_inventory (self, fp_print_get_finger (self->enrolled_print),
                              &replacement, database, length, &error))
      print = g_object_ref (self->enrolled_print);
    if (print) {
      fpi_print_set_type (print, FPI_PRINT_RAW);
      g_object_set (print, "fpi-data", replacement, NULL);
      fpi_device_enroll_progress (device, LIUQIN_ENROL_MAX_STAGES, NULL, NULL);
    }
  }
  else if (!cancelled && self->enroll_error)
    error = g_steal_pointer (&self->enroll_error);
  else if (!cancelled && !error) {
    gchar status_detail[32] = "";
    if (self->enroll_ta_status)
      g_snprintf (status_detail, sizeof status_detail, " ta_status=%d",
                  self->enroll_ta_status);
    error = fpi_device_error_new_msg (FP_DEVICE_ERROR_GENERAL,
                                      "OEM enrolment failed (%s%s%s%s)",
                                      self->enroll_error_code ? self->enroll_error_code :
                                      "runtime_failure",
                                      self->enroll_failure_phase ? " phase=" : "",
                                      self->enroll_failure_phase ? self->enroll_failure_phase : "",
                                      status_detail);
  }
  cancelled = cancelled || self->cancelled || fpi_device_action_is_cancelled (device);
  if (cancelled) {
    g_clear_object (&print);
    g_clear_error (&error);
    error = g_error_new_literal (G_IO_ERROR, G_IO_ERROR_CANCELLED,
                                 "Fingerprint enrolment cancelled");
  }
  clear_operation (self);
  fpi_device_report_finger_status (device, FP_FINGER_STATUS_NONE);
  fpi_device_enroll_complete (device, g_steal_pointer (&print), g_steal_pointer (&error));
}

static void
enrol_read (GObject *source, GAsyncResult *result, gpointer user_data)
{
  FpDevice *device = user_data;
  FpiDeviceFpc1264Oem *self = (FpiDeviceFpc1264Oem *) device;
  g_autoptr(GError) error = NULL;
  gssize count = g_input_stream_read_finish (G_INPUT_STREAM (source), result, &error);

  if (count <= 0) {
    if (count < 0 || error)
      enrol_fail (self, "OEM enrolment output read failed");
    else if (self->enroll_line_length)
      enrol_fail (self, "OEM enrolment output ended mid-line");
    self->enroll_stream_done = TRUE;
    enrol_maybe_complete (device);
  }
  else {
    if ((gsize) count > LIUQIN_ENROL_OUTPUT_LIMIT - self->enroll_output_bytes)
      enrol_fail (self, "OEM enrolment output exceeded the protocol limit");
    else
      self->enroll_output_bytes += (gsize) count;
    for (gssize i = 0; i < count; i++) {
      guint8 byte = self->enroll_read_buffer[i];
      if (self->enroll_error)
        continue; /* Keep draining until EOF even after a protocol failure. */
      if (byte == '\n') {
        self->enroll_line[self->enroll_line_length] = '\0';
        if (!g_utf8_validate (self->enroll_line, self->enroll_line_length, NULL))
          enrol_fail (self, "OEM enrolment output is not UTF-8");
        else
          enrol_parse_line (device, self->enroll_line);
        self->enroll_line_length = 0;
      }
      else if (!byte || self->enroll_line_length >= LIUQIN_ENROL_LINE_LIMIT)
        enrol_fail (self, "OEM enrolment output line is invalid or oversized");
      else
        self->enroll_line[self->enroll_line_length++] = byte;
    }
    g_input_stream_read_async (G_INPUT_STREAM (source), self->enroll_read_buffer,
                               sizeof self->enroll_read_buffer, G_PRIORITY_DEFAULT,
                               NULL, enrol_read, g_object_ref (device));
  }
  g_object_unref (device);
}

static void
enrol_wait_finished (GObject *source, GAsyncResult *result, gpointer user_data)
{
  FpDevice *device = user_data;
  FpiDeviceFpc1264Oem *self = (FpiDeviceFpc1264Oem *) device;
  g_autoptr(GError) error = NULL;

  if (!g_subprocess_wait_finish (G_SUBPROCESS (source), result, &error) ||
      !g_subprocess_get_if_exited (G_SUBPROCESS (source)))
    enrol_fail (self, "OEM enrolment process wait failed");
  else
    self->enroll_exit_status = g_subprocess_get_exit_status (G_SUBPROCESS (source));
  self->enroll_wait_done = TRUE;
  enrol_maybe_complete (device);
  g_object_unref (device);
}

static void
enrol (FpDevice *device)
{
  FpiDeviceFpc1264Oem *self = (FpiDeviceFpc1264Oem *) device;
  FpPrint *print = NULL;
  const gchar *username;
  FpFinger finger;
  g_autoptr(GError) error = NULL;
  g_autofree gchar *runtime = NULL;
  const gchar *bundle = g_getenv ("LIUQIN_FPC_OEM_RUNTIME");
  struct stat info;
  g_autofree guint8 *prior = NULL;
  gsize prior_length = 0;
  gboolean legacy = FALSE;

  fpi_device_get_enroll_data (device, &print);
  if (!print || !(username = fp_print_get_username (print)) || !*username ||
      !FP_FINGER_IS_VALID (finger = fp_print_get_finger (print)) ||
      (guint) finger >= G_N_ELEMENTS (finger_names)) {
    error = fpi_device_error_new_msg (FP_DEVICE_ERROR_DATA_INVALID,
                                      "A named finger and account are required for enrolment");
    goto failed;
  }
  if (!bundle || !g_path_is_absolute (bundle) || lstat (bundle, &info) ||
      !S_ISDIR (info.st_mode) || info.st_uid != 0 || (info.st_mode & 0022)) {
    error = fpi_device_error_new_msg (FP_DEVICE_ERROR_GENERAL,
                                      "Supply a trusted private OEM runtime directory");
    goto failed;
  }
  runtime = g_build_filename (bundle, "user_credentials.py", NULL);
  if (lstat (runtime, &info) || !S_ISREG (info.st_mode) || info.st_uid != 0 ||
      (info.st_mode & 0022)) {
    error = fpi_device_error_new_msg (FP_DEVICE_ERROR_GENERAL,
                                      "Trusted OEM credential entry point is missing");
    goto failed;
  }
  if (!load_enrol_gallery (device, username, finger, &prior, &prior_length,
                           self->fingers, self->ids, &self->gallery_count,
                           &legacy, &error))
    goto failed;
  if (self->gallery_count >= 5) {
    error = fpi_device_error_new_msg (FP_DEVICE_ERROR_DATA_DUPLICATE,
                                      "OEM gallery is full");
    goto failed;
  }
  self->gallery_v2 = !legacy;
  self->directory = g_dir_make_tmp ("liuqin-fpc-enrol-XXXXXX", &error);
  if (!self->directory)
    goto failed;
  self->database = g_build_filename (self->directory, "single-finger.db", NULL);
  self->inventory_path = g_build_filename (self->directory, "inventory.bin", NULL);
  if (self->gallery_count && prior_length) {
    g_autofree gchar *input_path = g_build_filename (self->directory, "input.db", NULL);
    if (!stage_private_database (input_path, prior, prior_length, &error))
      goto failed;
    self->updated_database = g_steal_pointer (&input_path);
  }
  self->enrolled_print = g_object_ref (print);
  self->cancelled = FALSE;
  self->enroll_exit_status = -1;
  self->enroll_active = TRUE;
  self->child = g_subprocess_new (G_SUBPROCESS_FLAGS_STDOUT_PIPE | G_SUBPROCESS_FLAGS_STDERR_SILENCE,
                                 &error, "/usr/bin/python3", "-u", runtime, "--enrol-prepared",
                                 username, finger_names[finger], self->database,
                                 self->updated_database ? self->updated_database : self->inventory_path,
                                 self->updated_database ? self->inventory_path : NULL, NULL);
  if (!self->child)
    goto failed;
  fpi_device_report_finger_status (device, FP_FINGER_STATUS_NEEDED);
  g_input_stream_read_async (g_subprocess_get_stdout_pipe (self->child),
                             self->enroll_read_buffer, sizeof self->enroll_read_buffer,
                             G_PRIORITY_DEFAULT, NULL, enrol_read, g_object_ref (device));
  g_subprocess_wait_async (self->child, NULL, enrol_wait_finished, g_object_ref (device));
  return;

failed:
  clear_operation (self);
  fpi_device_enroll_complete (device, NULL, g_steal_pointer (&error));
}

/* Hold the unmodified print for fprintd's compare-and-replace storage update.
 * No database or template bytes are reported outside the owning processes. */
static gboolean
parse_match_print (FpPrint *print, GVariant **contents, GVariant **bytes,
                   guint32 fingers[5], guint32 ids[5], guint *count,
                   gboolean *v2)
{
  guint32 version;
  gsize length;
  g_autoptr(GVariant) entries = NULL;
  g_object_get (print, "fpi-data", contents, NULL);
  if (!*contents)
    return FALSE;
  *v2 = g_variant_is_of_type (*contents, G_VARIANT_TYPE ("(uaya(uu))"));
  if (*v2) {
    g_variant_get (*contents, "(u@ay@a(uu))", &version, bytes, &entries);
    *count = g_variant_n_children (entries);
    if (version != 2 || !*count || *count > 5)
      return FALSE;
    for (guint i = 0; i < *count; i++) {
      g_variant_get_child (entries, i, "(uu)", &fingers[i], &ids[i]);
      if (!FP_FINGER_IS_VALID (fingers[i]) || !ids[i])
        return FALSE;
      for (guint j = 0; j < i; j++)
        if (fingers[i] == fingers[j] || ids[i] == ids[j])
          return FALSE;
    }
    gboolean present = FALSE;
    for (guint i = 0; i < *count; i++)
      present |= fingers[i] == fp_print_get_finger (print);
    if (!present)
      return FALSE;
  }
  else if (g_variant_is_of_type (*contents, G_VARIANT_TYPE ("(uay)"))) {
    g_variant_get (*contents, "(u@ay)", &version, bytes);
    if (version != 1 || !FP_FINGER_IS_VALID (fp_print_get_finger (print)))
      return FALSE;
    fingers[0] = fp_print_get_finger (print);
    *count = 1;
  }
  else
    return FALSE;
  g_variant_get_fixed_array (*bytes, &length, 1);
  return length > 0 && length <= 16u * 1024u * 1024u;
}

static gboolean
read_match_id (FpiDeviceFpc1264Oem *self, guint32 *id)
{
  guint32 value = 0;
  struct stat info;
  int fd = g_open (self->match_id_path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW, 0);
  if (fd < 0 || fstat (fd, &info) || !S_ISREG (info.st_mode) ||
      info.st_uid != 0 || (info.st_mode & 0777) != 0600 ||
      info.st_size != sizeof value) {
    if (fd >= 0)
      close (fd);
    return FALSE;
  }
  gboolean ok = read (fd, &value, sizeof value) == sizeof value;
  if (close (fd))
    ok = FALSE;
  *id = GUINT32_FROM_LE (value);
  return ok && *id != 0;
}

static gboolean
accept_updated_database (FpiDeviceFpc1264Oem *self, gboolean expected, GError **error)
{
  struct stat info;
  int fd = g_open (self->updated_database, O_RDONLY | O_CLOEXEC | O_NOFOLLOW, 0);
  g_autofree guint8 *database = NULL;
  g_autofree guint8 *original_bytes = NULL;
  g_autoptr(FpPrint) original = NULL;
  g_autoptr(GVariant) replacement = NULL;
  g_autoptr(GVariant) data = NULL;
  g_autoptr(GVariant) bytes = NULL;
  g_autoptr(GVariant) entries = NULL;
  guint32 version;
  gsize original_length;

  if (fd < 0 && errno == ENOENT && !expected)
    return TRUE;
  if (fd < 0 || fstat (fd, &info) || !S_ISREG (info.st_mode) ||
      info.st_uid != 0 || (info.st_mode & 0777) != 0600 ||
      info.st_size <= 0 || info.st_size > 16u * 1024u * 1024u)
    goto failed;
  database = g_malloc (info.st_size);
  for (gsize offset = 0; offset < (gsize) info.st_size;) {
    ssize_t count = read (fd, database + offset, info.st_size - offset);
    if (count < 0 && errno == EINTR)
      continue;
    if (count <= 0)
      goto failed;
    offset += count;
  }
  close (fd);
  fd = -1;
  if (!fp_print_serialize (self->enrolled_print, &original_bytes, &original_length, error))
    return FALSE;
  original = fp_print_deserialize (original_bytes, original_length, error);
  if (!original)
    return FALSE;
  g_object_get (self->enrolled_print, "fpi-data", &data, NULL);
  if (!data)
    goto failed;
  if (self->gallery_v2) {
    if (!g_variant_is_of_type (data, G_VARIANT_TYPE ("(uaya(uu))")))
      goto failed;
    g_variant_get (data, "(u@ay@a(uu))", &version, &bytes, &entries);
    if (version != 2)
      goto failed;
    replacement = g_variant_ref_sink (g_variant_new ("(u@ay@a(uu))", 2u,
                    g_variant_new_fixed_array (G_VARIANT_TYPE_BYTE, database, info.st_size, 1),
                    g_variant_ref (entries)));
  }
  else
    replacement = g_variant_ref_sink (g_variant_new ("(u@ay)", 1u,
                    g_variant_new_fixed_array (G_VARIANT_TYPE_BYTE, database, info.st_size, 1)));
  g_object_set_data_full (G_OBJECT (self->enrolled_print), "liuqin-fpc-oem-original",
                          g_steal_pointer (&original), g_object_unref);
  g_object_set (self->enrolled_print, "fpi-data", replacement, NULL);
  return TRUE;

failed:
  if (fd >= 0)
    close (fd);
  g_set_error_literal (error, FP_DEVICE_ERROR, FP_DEVICE_ERROR_GENERAL,
                       "OEM adaptive template export is incomplete");
  return FALSE;
}

/* Keep diagnostics to known status lines. Never forward raw runtime output,
 * template bytes, credentials or authentication tokens to the journal. */
static void
report_runtime_failure (const gchar *output, const gchar *diagnostic,
                        gint status, gboolean cleaned)
{
  const gchar *prefixes[] = {
    "finger_irq_failed=", "match_incomplete=", "match_unavailable=",
    "auth_result_invalid=", "db_import_remaining_mismatch ",
    "template_count_response_invalid=", "oem_runtime_timed_out=",
    "oem_runtime_cancelled=", "oem_runtime=BUSY",
    "capture_result_word4=", "capture_note=", "identify_app_status=",
    "match_result=inconclusive ", "auth_result_available=",
    "loaded_template_count=", "template_enumerate_app_status=",
    "authenticator_id_app_status=", "database_update_required=", NULL
  };
  g_autofree gchar *messages = g_strconcat (output ? output : "", "\n",
                                          diagnostic ? diagnostic : "", NULL);
  g_auto(GStrv) lines = g_strsplit (messages, "\n", -1);

  g_warning ("OEM verify runtime exit=%d cleanup_complete=%d irq_armed=%d irq_received=%d",
             status, cleaned,
             !!(output && strstr (output, "READY finger_irq_armed=down press finger now\n")),
             !!(output && strstr (output, "finger_irq=down\n")));
  for (gsize i = 0; lines[i]; i++)
    for (gsize j = 0; prefixes[j]; j++)
      if (g_str_has_prefix (lines[i], prefixes[j])) {
        g_warning ("OEM verify diagnostic: %s", prefixes[j]);
        break;
      }
}

static void
match_finished (GObject *source, GAsyncResult *result, gpointer user_data)
{
  FpDevice *device = user_data;
  FpiDeviceFpc1264Oem *self = (FpiDeviceFpc1264Oem *) device;
  g_autoptr(GError) error = NULL;
  g_autofree gchar *output = NULL;
  g_autofree gchar *diagnostic = NULL;
  g_autoptr(FpPrint) selected = NULL;
  gboolean identifying = self->identifying;
  gboolean communicated = g_subprocess_communicate_utf8_finish (G_SUBPROCESS (source), result,
                                                               &output, &diagnostic, &error);
  gboolean exited = communicated && g_subprocess_get_if_exited (G_SUBPROCESS (source));
  gint status = exited ? g_subprocess_get_exit_status (G_SUBPROCESS (source)) : -1;
  gboolean cleaned = output && strstr (output, "oem_runtime_cleanup firmware_path_restored=1 sensor_power_off=1 listener_stopped=1\n");
  gboolean matched = output && strstr (output, "match_result=matched desktop_authentication=disabled\n");
  gboolean missed = output && strstr (output, "match_result=not_matched desktop_authentication=disabled\n");
  gboolean cancelled = self->cancelled || fpi_device_action_is_cancelled (device);
  gboolean valid_result = cleaned && ((status == 0 && matched && !missed) ||
                                       (status == 3 && missed && !matched));
  const gchar *capture_prefix = "match_incomplete=capture_rejected app_status=";
  const gchar *capture = diagnostic ? strstr (diagnostic, capture_prefix) : NULL;
  gchar *capture_end = NULL;
  gint64 capture_status = capture ? g_ascii_strtoll (capture + strlen (capture_prefix),
                                                     &capture_end, 10) : 0;
  gboolean retry_capture = capture && capture_end && *capture_end == '\n' &&
    (capture_status == 1 || capture_status == 2 || capture_status == 3 ||
     capture_status == 4 || capture_status == 7);
  gboolean retry_scan = cleaned && status == 1 && !matched && !missed &&
    ((output && (strstr (output, "match_result=inconclusive identify_app_status=4\n") ||
                 strstr (output, "match_result=inconclusive identify_app_status=12\n"))) ||
     retry_capture);

  if (!cancelled && valid_result && self->gallery_v2) {
    guint32 id = 0;
    if (status == 0) {
      if (!read_match_id (self, &id))
        valid_result = FALSE;
      else {
        gboolean known = FALSE;
        for (guint i = 0; i < self->gallery_count; i++)
          known |= self->ids[i] == id;
        if (!known)
          valid_result = FALSE;
      }
      if (valid_result && identifying) {
        for (guint i = 0; i < self->gallery_count; i++)
          if (self->ids[i] == id)
            for (guint j = 0; j < self->candidates->len; j++) {
              FpPrint *candidate = g_ptr_array_index (self->candidates, j);
              if (fp_print_get_finger (candidate) == self->fingers[i]) {
                selected = g_object_ref (candidate);
                break;
              }
            }
      }
      else if (valid_result) {
        for (guint i = 0; i < self->gallery_count; i++)
          if (self->ids[i] == id &&
              self->fingers[i] == fp_print_get_finger (self->enrolled_print))
            selected = g_object_ref (self->enrolled_print);
      }
    }
    else if (!g_access (self->match_id_path, F_OK) || errno != ENOENT)
      valid_result = FALSE;
  }
  else if (!cancelled && valid_result && status == 0) {
    if (identifying)
      selected = g_object_ref (g_ptr_array_index (self->candidates, 0));
    else
      selected = g_object_ref (self->enrolled_print);
  }
  if (!cancelled && valid_result && selected) {
    g_set_object (&self->enrolled_print, selected);
    if (!accept_updated_database (self, output && strstr (output, "database_update_required=1\n"), &error))
      valid_result = FALSE;
  }
  if (!cancelled && communicated && !valid_result && !retry_scan)
    report_runtime_failure (output, diagnostic, status, cleaned);
  clear_operation (self);
  fpi_device_report_finger_status (device, FP_FINGER_STATUS_NONE);
  if (cancelled) {
    error = g_error_new_literal (G_IO_ERROR, G_IO_ERROR_CANCELLED,
                                 "Fingerprint matching cancelled");
    if (identifying)
      fpi_device_identify_complete (device, g_steal_pointer (&error));
    else
      fpi_device_verify_complete (device, g_steal_pointer (&error));
  }
  else if (!communicated || !valid_result) {
    if (!error)
      error = fpi_device_error_new_msg (FP_DEVICE_ERROR_GENERAL,
                                        "OEM matching did not complete");
    if (retry_scan) {
      g_clear_error (&error);
      if (identifying)
        fpi_device_identify_report (device, NULL, NULL,
                                     fpi_device_retry_new (FP_DEVICE_RETRY_GENERAL));
      else
        fpi_device_verify_report (device, FPI_MATCH_ERROR, NULL,
                                   fpi_device_retry_new (FP_DEVICE_RETRY_GENERAL));
    }
    if (identifying)
      fpi_device_identify_complete (device, g_steal_pointer (&error));
    else
      fpi_device_verify_complete (device, g_steal_pointer (&error));
  }
  else {
    g_message ("OEM match result=%s", selected ? "matched" : "not_matched");
    if (identifying) {
      fpi_device_identify_report (device, selected, NULL, NULL);
      fpi_device_identify_complete (device, NULL);
    }
    else {
      fpi_device_verify_report (device, selected ? FPI_MATCH_SUCCESS : FPI_MATCH_FAIL,
                                NULL, NULL);
      fpi_device_verify_complete (device, NULL);
    }
  }
  g_object_unref (device);
}

static void
start_match (FpDevice *device, gboolean identifying)
{
  FpiDeviceFpc1264Oem *self = (FpiDeviceFpc1264Oem *) device;
  FpPrint *print = NULL;
  GPtrArray *prints = NULL;
  g_autoptr(GVariant) data = NULL;
  g_autoptr(GVariant) bytes = NULL;
  g_autoptr(GError) error = NULL;
  g_autofree gchar *runtime = NULL;
  const gchar *bundle = g_getenv ("LIUQIN_FPC_OEM_RUNTIME");
  struct stat info;
  guint count = 0;
  gsize length;
  const guint8 *database;

  if (identifying) {
    fpi_device_get_identify_data (device, &prints);
    if (!prints || !prints->len)
      goto invalid_print;
    print = g_ptr_array_index (prints, 0);
  }
  else
    fpi_device_get_verify_data (device, &print);
  if (!print || !parse_match_print (print, &data, &bytes, self->fingers,
                                     self->ids, &count, &self->gallery_v2))
    goto invalid_print;
  self->gallery_count = count;
  if (identifying) {
    self->candidates = g_ptr_array_new_with_free_func (g_object_unref);
    if (!self->gallery_v2 && prints->len != 1)
      goto invalid_print;
    for (guint i = 0; i < prints->len; i++) {
      FpPrint *candidate = g_ptr_array_index (prints, i);
      gboolean present = FALSE;
      if (g_strcmp0 (fp_print_get_username (candidate), fp_print_get_username (print)))
        goto invalid_print;
      if (self->gallery_v2) {
        g_autoptr(GVariant) candidate_data = NULL;
        g_object_get (candidate, "fpi-data", &candidate_data, NULL);
        if (!candidate_data || !g_variant_equal (data, candidate_data))
          goto invalid_print;
      }
      for (guint j = 0; j < count; j++)
        present |= self->fingers[j] == fp_print_get_finger (candidate);
      if (!present)
        goto invalid_print;
      for (guint j = 0; j < i; j++)
        if (fp_print_get_finger (candidate) ==
            fp_print_get_finger (g_ptr_array_index (self->candidates, j)))
          goto invalid_print;
      g_ptr_array_add (self->candidates, g_object_ref (candidate));
      g_object_set_data (G_OBJECT (candidate), "liuqin-fpc-oem-original", NULL);
    }
  }
  else
    g_object_set_data (G_OBJECT (print), "liuqin-fpc-oem-original", NULL);
  database = g_variant_get_fixed_array (bytes, &length, 1);
  if (!bundle || !g_path_is_absolute (bundle) || lstat (bundle, &info) ||
      !S_ISDIR (info.st_mode) || info.st_uid != 0 || (info.st_mode & 0022)) {
    error = fpi_device_error_new_msg (FP_DEVICE_ERROR_GENERAL,
                                      "Supply a trusted private OEM runtime directory");
    goto failed;
  }
  runtime = g_build_filename (bundle, "oem_runtime.py", NULL);
  if (lstat (runtime, &info) || !S_ISREG (info.st_mode) ||
      info.st_uid != 0 || (info.st_mode & 0022)) {
    error = fpi_device_error_new_msg (FP_DEVICE_ERROR_GENERAL, "Trusted OEM runner is missing");
    goto failed;
  }
  self->directory = g_dir_make_tmp ("liuqin-fpc-match-XXXXXX", &error);
  if (!self->directory)
    goto failed;
  self->database = g_build_filename (self->directory, "gallery.db", NULL);
  self->updated_database = g_build_filename (self->directory, "updated-gallery.db", NULL);
  self->match_id_path = g_build_filename (self->directory, "matched-id.bin", NULL);
  if (!stage_private_database (self->database, database, length, &error))
    goto failed;
  self->cancelled = FALSE;
  self->identifying = identifying;
  self->enrolled_print = g_object_ref (print);
  if (self->gallery_v2)
    self->child = g_subprocess_new (G_SUBPROCESS_FLAGS_STDOUT_PIPE | G_SUBPROCESS_FLAGS_STDERR_PIPE,
                                   &error, "/usr/bin/python3", runtime, "--ufs-rpmb-authenticated",
                                   "--match-gallery", self->database, self->match_id_path,
                                   self->updated_database, NULL);
  else
    self->child = g_subprocess_new (G_SUBPROCESS_FLAGS_STDOUT_PIPE | G_SUBPROCESS_FLAGS_STDERR_PIPE,
                                   &error, "/usr/bin/python3", runtime, "--ufs-rpmb-authenticated",
                                   "--match-single", self->database, self->updated_database, NULL);
  if (!self->child)
    goto failed;
  fpi_device_report_finger_status (device, FP_FINGER_STATUS_NEEDED);
  /* Cancellation must wait for TA cleanup rather than terminating the task. */
  g_subprocess_communicate_utf8_async (self->child, NULL, NULL, match_finished,
                                       g_object_ref (device));
  return;

invalid_print:
  error = fpi_device_error_new_msg (FP_DEVICE_ERROR_DATA_INVALID,
                                    "A valid OEM print gallery is required");
failed:
  clear_operation (self);
  if (identifying)
    fpi_device_identify_complete (device, g_steal_pointer (&error));
  else
    fpi_device_verify_complete (device, g_steal_pointer (&error));
}

static void
verify (FpDevice *device)
{
  start_match (device, FALSE);
}

static void
identify (FpDevice *device)
{
  start_match (device, TRUE);
}

static void
cancel (FpDevice *device)
{
  FpiDeviceFpc1264Oem *self = (FpiDeviceFpc1264Oem *) device;
  self->cancelled = TRUE;
  if (self->child)
    g_subprocess_send_signal (self->child, SIGTERM);
}

static void
fpi_device_fpc1264_oem_init (FpiDeviceFpc1264Oem *self)
{
  (void) self;
}

static void
fpi_device_fpc1264_oem_class_init (FpiDeviceFpc1264OemClass *klass)
{
  static const FpIdEntry devices[] = {
    { .virtual_envvar = "FP_LIUQIN_FPC1264_OEM_ENABLE" }, { .pid = 0 }
  };
  FpDeviceClass *device = FP_DEVICE_CLASS (klass);
  device->id = "fpc1264_oem";
  device->full_name = "FPC1264 OEM on liuqin";
  device->type = FP_DEVICE_TYPE_VIRTUAL;
  device->scan_type = FP_SCAN_TYPE_PRESS;
  device->nr_enroll_stages = LIUQIN_ENROL_MAX_STAGES;
  device->id_table = devices;
  device->temp_hot_seconds = -1;
  device->probe = probe;
  device->open = open_device;
  device->close = close_device;
  device->enroll = enrol;
  device->verify = verify;
  device->identify = identify;
  device->cancel = cancel;
  fpi_device_class_auto_initialize_features (device);
}

G_MODULE_EXPORT GType
fpi_tod_shared_driver_get_type (void)
{
  return fpi_device_fpc1264_oem_get_type ();
}
