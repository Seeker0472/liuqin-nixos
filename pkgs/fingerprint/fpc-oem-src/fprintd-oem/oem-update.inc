/* SPDX-License-Identifier: GPL-2.0-or-later
 * Included by fprintd file_storage.c after its private path helpers.
 * Commit OEM adaptation before VerifyStatus can authorize a caller, and
 * durably confirm a new enrolment before reporting EnrollStatus success.
 */
#include <fcntl.h>
#include <sys/file.h>
#include <sys/wait.h>

static const gchar *const oem_finger_names[] = { NULL, "left-thumb",
  "left-index-finger", "left-middle-finger", "left-ring-finger",
  "left-little-finger", "right-thumb", "right-index-finger",
  "right-middle-finger", "right-ring-finger", "right-little-finger" };

/* The canonical file is authoritative even when invalid or empty.  Never
 * recover from a stale per-finger file once .gallery has been published. */
#define OEM_GALLERY ".gallery"
#define OEM_MAX_PRINT  (17u * 1024u * 1024u)
#define OEM_MAX_DB     (16u * 1024u * 1024u)

static gboolean
oem_gallery_data (FpPrint *print, GVariant **db, GVariant **ids,
                  gboolean tombstone)
{
  g_autoptr(GVariant) data = NULL;
  guint version, finger, id, seen = 0;
  guint32 used[5] = {};

  g_object_get (print, "fpi-data", &data, NULL);
  if (!data || !g_variant_is_of_type (data, G_VARIANT_TYPE ("(uaya(uu))")))
    return FALSE;
  g_variant_get (data, "(u@ay@a(uu))", &version, db, ids);
  if (version != 2 || g_variant_n_children (*ids) > 5 ||
      (g_variant_n_children (*ids) == 0 && !tombstone) ||
      g_variant_get_size (*db) > OEM_MAX_DB ||
      (g_variant_n_children (*ids) && !g_variant_get_size (*db)))
    return FALSE;
  for (gsize n = 0; n < g_variant_n_children (*ids); n++)
    {
      g_variant_get_child (*ids, n, "(uu)", &finger, &id);
      if (!FP_FINGER_IS_VALID (finger) || finger >= G_N_ELEMENTS (oem_finger_names) ||
          (seen & (1u << finger)) || id == 0)
        return FALSE;
      for (gsize j = 0; j < n; j++)
        if (used[j] == id)
          return FALSE;
      seen |= 1u << finger;
      used[n] = id;
    }
  return TRUE;
}

static gboolean
oem_gallery_has_finger (GVariant *ids, FpFinger finger, guint32 *id_out)
{
  guint32 item_finger, id;
  for (gsize n = 0; n < g_variant_n_children (ids); n++)
    {
      g_variant_get_child (ids, n, "(uu)", &item_finger, &id);
      if (item_finger == (guint32) finger)
        {
          if (id_out)
            *id_out = id;
          return TRUE;
        }
    }
  return FALSE;
}

static int
oem_read_at (int dirfd, const char *name, FpPrint **print)
{
  g_autofree guint8 *bytes = NULL;
  g_autoptr(GError) error = NULL;
  struct stat info;
  int fd = openat (dirfd, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  if (fd < 0)
    return errno == ENOENT ? -ENOENT : -EIO;
  if (fstat (fd, &info) || !S_ISREG (info.st_mode) || info.st_uid != 0 ||
      (info.st_mode & 0777) != 0600 || info.st_size <= 0 ||
      info.st_size > OEM_MAX_PRINT)
    { close (fd); return -EINVAL; }
  bytes = g_malloc (info.st_size);
  for (gsize offset = 0; offset < (gsize) info.st_size;)
    {
      ssize_t n = read (fd, bytes + offset, info.st_size - offset);
      if (n < 0 && errno == EINTR)
        continue;
      if (n <= 0)
        { close (fd); return -EIO; }
      offset += n;
    }
  close (fd);
  *print = fp_print_deserialize (bytes, info.st_size, &error);
  return *print ? 0 : -EINVAL;
}

/* Keep a hard link to the previous authority before renaming.  An fsync
 * failure after rename is uncertain: retain both the backup and new file
 * for operator recovery, rather than claiming that either version won. */
static gboolean
oem_replace_at (int dirfd, const char *name, const guint8 *bytes, gsize length,
                GCancellable *cancellable)
{
  char temporary[48], previous[48];
  int fd, original;
  gboolean backup = FALSE, renamed = FALSE, saved = FALSE;
  if (!length || length > OEM_MAX_PRINT)
    return FALSE;
  g_snprintf (temporary, sizeof temporary, ".update-%08x-%08x", g_random_int (), g_random_int ());
  g_snprintf (previous, sizeof previous, ".previous-%08x-%08x", g_random_int (), g_random_int ());
  fd = openat (dirfd, temporary, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
  if (fd < 0)
    return FALSE;
  for (gsize offset = 0; offset < length;)
    {
      ssize_t n = write (fd, bytes + offset, length - offset);
      if (n < 0 && errno == EINTR)
        continue;
      if (n <= 0)
        goto out;
      offset += n;
    }
  if (fsync (fd))
    goto out;
  original = openat (dirfd, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  if (original >= 0)
    {
      struct stat info;
      if (fstat (original, &info) || !S_ISREG (info.st_mode) ||
          info.st_uid != 0 || (info.st_mode & 0777) != 0600 ||
          linkat (dirfd, name, dirfd, previous, 0))
        { close (original); goto out; }
      close (original);
      backup = TRUE;
      if (fsync (dirfd))
        goto out;
    }
  else if (errno != ENOENT)
    goto out;
  if (cancellable && g_cancellable_is_cancelled (cancellable))
    goto out;
  if (renameat (dirfd, temporary, dirfd, name))
    goto out;
  renamed = TRUE;
  if (fsync (dirfd))
    goto out;
  saved = TRUE;
  if (backup && !unlinkat (dirfd, previous, 0))
    (void) fsync (dirfd);
out:
  close (fd);
  if (!renamed)
    {
      (void) unlinkat (dirfd, temporary, 0);
      if (backup)
        (void) unlinkat (dirfd, previous, 0);
    }
  return saved;
}

static int
oem_open_dir (FpPrint *print, gboolean create, gchar **directory)
{
  g_autofree gchar *base = file_storage_get_basestore_for_username (fp_print_get_username (print));
  struct stat info;
  int fd;
  *directory = get_path_to_storedir (fp_print_get_driver (print),
                                      fp_print_get_device_id (print), base);
  if (create && g_mkdir_with_parents (*directory, 0700))
    return -1;
  fd = open (*directory, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  if (fd < 0)
    return -1;
  if (fstat (fd, &info) || !S_ISDIR (info.st_mode) || info.st_uid != 0 ||
      (info.st_mode & 0022))
    { close (fd); return -1; }
  return fd;
}

static int
oem_lock (int dirfd)
{
  struct stat info;
  int fd = openat (dirfd, ".operation.lock", O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0600);
  if (fd < 0)
    return -1;
  if (fstat (fd, &info) || !S_ISREG (info.st_mode) || info.st_uid != 0 ||
      (info.st_mode & 0777) != 0600 || flock (fd, LOCK_EX | LOCK_NB))
    { close (fd); return -1; }
  return fd;
}

static gboolean
oem_print_metadata_equal (FpPrint *a, FpPrint *b)
{
  return fp_print_get_finger (a) == fp_print_get_finger (b) &&
         g_strcmp0 (fp_print_get_username (a), fp_print_get_username (b)) == 0 &&
         g_strcmp0 (fp_print_get_driver (a), fp_print_get_driver (b)) == 0 &&
         g_strcmp0 (fp_print_get_device_id (a), fp_print_get_device_id (b)) == 0;
}

gboolean
file_storage_print_data_update (FpPrint *original, FpPrint *updated,
                                GCancellable *cancellable, GError **error)
{
  g_autofree gchar *directory = NULL;
  g_autofree gchar *base = NULL;
  g_autofree gchar *path = NULL;
  g_autofree gchar *name = NULL;
  g_autofree guint8 *bytes = NULL;
  g_autoptr(GVariant) old_db = NULL, old_ids = NULL;
  g_autoptr(GVariant) new_db = NULL, new_ids = NULL;
  g_autoptr(FpPrint) current = NULL;
  g_autoptr(GVariant) old_data = NULL, new_data = NULL, disk_data = NULL;
  gsize length;
  int dirfd = -1, lockfd = -1;
  gboolean saved = FALSE, v2;

  if (geteuid () != 0 || !oem_print_metadata_equal (original, updated) ||
      g_strcmp0 (fp_print_get_driver (updated), "fpc1264_oem") != 0 ||
      !FP_FINGER_IS_VALID (fp_print_get_finger (updated)))
    goto invalid;
  g_object_get (original, "fpi-data", &old_data, NULL);
  g_object_get (updated, "fpi-data", &new_data, NULL);
  v2 = old_data && g_variant_is_of_type (old_data, G_VARIANT_TYPE ("(uaya(uu))"));
  if (v2)
    {
      if (!oem_gallery_data (original, &old_db, &old_ids, FALSE) ||
          !oem_gallery_data (updated, &new_db, &new_ids, FALSE) ||
          !g_variant_equal (old_ids, new_ids) ||
          !oem_gallery_has_finger (old_ids, fp_print_get_finger (original), NULL))
        goto invalid;
      name = g_strdup (OEM_GALLERY);
    }
  else
    {
      if (!old_data || !new_data ||
          !g_variant_is_of_type (old_data, G_VARIANT_TYPE ("(uay)")) ||
          !g_variant_is_of_type (new_data, G_VARIANT_TYPE ("(uay)")))
        goto invalid;
      base = file_storage_get_basestore_for_username (fp_print_get_username (original));
      path = __get_path_to_print (fp_print_get_driver (original),
                                  fp_print_get_device_id (original),
                                  fp_print_get_finger (original), base);
      name = g_path_get_basename (path);
    }
  dirfd = oem_open_dir (original, FALSE, &directory);
  if (dirfd < 0 || (lockfd = oem_lock (dirfd)) < 0)
    goto io_error;
  /* Never publish an adaptation of a legacy print once the gallery exists. */
  if (!v2)
    {
      struct stat info;
      if (!fstatat (dirfd, OEM_GALLERY, &info, AT_SYMLINK_NOFOLLOW) || errno != ENOENT)
        goto invalid;
    }
  if (oem_read_at (dirfd, name, &current))
    goto invalid;
  if (v2)
    fp_print_set_finger (current, fp_print_get_finger (original));
  if (!oem_print_metadata_equal (current, original))
    goto invalid;
  g_object_get (current, "fpi-data", &disk_data, NULL);
  if (!disk_data || !g_variant_equal (disk_data, old_data) ||
      !fp_print_equal (current, original))
    goto invalid;
  if (!fp_print_serialize (updated, &bytes, &length, error))
    goto out;
  if (!oem_replace_at (dirfd, name, bytes, length, cancellable))
    goto io_error;
  saved = TRUE;
  goto out;

invalid:
  g_set_error_literal (error, G_IO_ERROR, G_IO_ERROR_INVALID_DATA,
                       "Stored OEM gallery changed or has invalid private metadata");
  goto out;
io_error:
  g_set_error_literal (error, G_IO_ERROR, G_IO_ERROR_FAILED,
                       "OEM gallery update was not committed durably");
out:
  if (lockfd >= 0)
    close (lockfd);
  if (dirfd >= 0)
    close (dirfd);
  return saved;
}

static gboolean
oem_valid_stored (FpPrint *print, FpDevice *dev, const gchar *username,
                  GVariant **db, GVariant **ids)
{
  return print && g_strcmp0 (fp_print_get_username (print), username) == 0 &&
         fp_print_compatible (print, dev) &&
         oem_gallery_data (print, db, ids, TRUE);
}

/* Return -ENOENT only when the canonical pathname is genuinely absent.
 * Invalid files are never a reason to fall back to the old per-finger store. */
static int
oem_load_gallery (FpDevice *dev, const gchar *username, FpPrint **print)
{
  g_autofree gchar *base = file_storage_get_basestore_for_username (username);
  g_autofree gchar *directory = get_path_to_storedir (fp_device_get_driver (dev),
                                                      fp_device_get_device_id (dev), base);
  g_autoptr(GVariant) db = NULL, ids = NULL;
  struct stat info;
  int dirfd = open (directory, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  int result;
  if (dirfd < 0)
    return errno == ENOENT ? -ENOENT : -EIO;
  if (fstat (dirfd, &info) || !S_ISDIR (info.st_mode) ||
      info.st_uid != 0 || (info.st_mode & 0022))
    { close (dirfd); return -EINVAL; }
  result = oem_read_at (dirfd, OEM_GALLERY, print);
  close (dirfd);
  if (!result && !oem_valid_stored (*print, dev, username, &db, &ids))
    { g_clear_object (print); return -EINVAL; }
  return result;
}

int
file_storage_oem_load (FpDevice *dev, FpFinger finger, const gchar *username,
                       FpPrint **print)
{
  g_autoptr(GVariant) db = NULL, ids = NULL;
  int result;
  if (g_strcmp0 (fp_device_get_driver (dev), "fpc1264_oem") != 0)
    return -ENOENT;
  result = oem_load_gallery (dev, username, print);
  if (result)
    return result == -ENOENT ? -EAGAIN : result;
  if (!oem_gallery_data (*print, &db, &ids, TRUE) ||
      !oem_gallery_has_finger (ids, finger, NULL))
    { g_clear_object (print); return -ENOENT; }
  fp_print_set_finger (*print, finger);
  file_storage_oem_enroll_reconcile (*print);
  return 0;
}

/* Caller must call only for OEM devices.  TRUE means the canonical pathname
 * exists (including a corrupt file or tombstone): never scan legacy names. */
gboolean
file_storage_oem_discover (FpDevice *dev, const gchar *username, GSList **list)
{
  g_autoptr(FpPrint) gallery = NULL;
  g_autoptr(GVariant) db = NULL, ids = NULL;
  int result = oem_load_gallery (dev, username, &gallery);
  if (result == -ENOENT)
    return FALSE;
  if (result)
    { g_warning ("OEM gallery unavailable; refusing legacy fallback"); return TRUE; }
  oem_gallery_data (gallery, &db, &ids, TRUE);
  if (list)
    for (gsize n = 0; n < g_variant_n_children (ids); n++)
      {
        guint32 finger, id;
        g_variant_get_child (ids, n, "(uu)", &finger, &id);
        *list = g_slist_prepend (*list, GUINT_TO_POINTER (finger));
      }
  return TRUE;
}

/* Bind the exact native ID envelope to the variant before publishing.  The
 * worker's post-save acknowledgement separately binds its ready marker to
 * this private file and the database digest. */
static gboolean
oem_pending_ids_equal (FpPrint *print, GVariant *ids)
{
  g_autofree gchar *path = g_build_filename ("/var/lib/liuqin-fingerprint/pending",
                                            fp_print_get_username (print),
                                            oem_finger_names[fp_print_get_finger (print)],
                                            "gallery-ids.bin", NULL);
  struct stat info;
  guint32 raw[7], count, added, selected;
  int fd = open (path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  if (fd < 0)
    return FALSE;
  if (fstat (fd, &info) || !S_ISREG (info.st_mode) ||
      info.st_uid != 0 || (info.st_mode & 0777) != 0600 ||
      info.st_size != sizeof raw)
    { close (fd); return FALSE; }
  gsize offset = 0;
  while (offset < sizeof raw)
    {
      ssize_t n = read (fd, (guint8 *) raw + offset, sizeof raw - offset);
      if (n < 0 && errno == EINTR)
        continue;
      if (n <= 0)
        { close (fd); return FALSE; }
      offset += n;
    }
  close (fd);
  count = GUINT32_FROM_LE (raw[0]);
  added = GUINT32_FROM_LE (raw[1]);
  if (count != g_variant_n_children (ids) ||
      !oem_gallery_has_finger (ids, fp_print_get_finger (print), &selected) ||
      selected != added)
    return FALSE;
  for (guint n = 0; n < 5; n++)
    {
      guint32 id = GUINT32_FROM_LE (raw[n + 2]);
      gboolean seen = FALSE;
      if (n >= count)
        { if (id) return FALSE; continue; }
      for (gsize j = 0; j < g_variant_n_children (ids); j++)
        {
          guint32 finger, stored_id;
          g_variant_get_child (ids, j, "(uu)", &finger, &stored_id);
          if (stored_id == id)
            seen = TRUE;
        }
      if (!seen)
        return FALSE;
      for (guint j = 0; j < n; j++)
        if (GUINT32_FROM_LE (raw[j + 2]) == id)
          return FALSE;
    }
  return TRUE;
}

static gboolean
oem_pending_base_equal (FpPrint *print, GVariant *old_db)
{
  g_autofree gchar *path = g_build_filename ("/var/lib/liuqin-fingerprint/pending",
                                            fp_print_get_username (print),
                                            oem_finger_names[fp_print_get_finger (print)],
                                            "export-ready.json", NULL);
  g_autofree gchar *marker = NULL, *digest = NULL, *field = NULL;
  const guint8 *bytes;
  struct stat info;
  gsize length;
  int fd = open (path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  if (fd < 0)
    return FALSE;
  if (fstat (fd, &info) || !S_ISREG (info.st_mode) ||
      info.st_uid != 0 || (info.st_mode & 0777) != 0600 ||
      info.st_size <= 0 || info.st_size > 4096)
    { close (fd); return FALSE; }
  marker = g_malloc (info.st_size + 1);
  for (gsize offset = 0; offset < (gsize) info.st_size;)
    {
      ssize_t n = read (fd, marker + offset, info.st_size - offset);
      if (n < 0 && errno == EINTR)
        continue;
      if (n <= 0)
        { close (fd); return FALSE; }
      offset += n;
    }
  close (fd);
  marker[info.st_size] = 0;
  bytes = g_variant_get_fixed_array (old_db, &length, 1);
  digest = g_compute_checksum_for_data (G_CHECKSUM_SHA256, bytes, length);
  field = g_strdup_printf ("\"base_sha256\": \"%s\"", digest);
  return g_strstr_len (marker, info.st_size, field) != NULL;
}

int
file_storage_oem_save (FpPrint *print)
{
  g_autofree gchar *directory = NULL;
  g_autofree guint8 *serialized = NULL;
  g_autoptr(GError) error = NULL;
  g_autoptr(FpPrint) current = NULL;
  g_autoptr(GVariant) db = NULL, ids = NULL, old_db = NULL, old_ids = NULL;
  gsize length;
  int dirfd = -1, lockfd = -1, result = -EIO;
  guint old_count = 0;

  if (geteuid () != 0 || !oem_gallery_data (print, &db, &ids, FALSE) ||
      !oem_gallery_has_finger (ids, fp_print_get_finger (print), NULL) ||
      !oem_pending_ids_equal (print, ids))
    return -EINVAL;
  dirfd = oem_open_dir (print, TRUE, &directory);
  if (dirfd < 0 || (lockfd = oem_lock (dirfd)) < 0)
    goto out;
  if (oem_read_at (dirfd, OEM_GALLERY, &current) == 0)
    {
      if (g_strcmp0 (fp_print_get_username (current), fp_print_get_username (print)) ||
          g_strcmp0 (fp_print_get_driver (current), fp_print_get_driver (print)) ||
          g_strcmp0 (fp_print_get_device_id (current), fp_print_get_device_id (print)) ||
          !oem_gallery_data (current, &old_db, &old_ids, TRUE))
        goto out;
      old_count = g_variant_n_children (old_ids);
      for (gsize n = 0; n < old_count; n++)
        {
          guint32 finger, id, retained;
          g_variant_get_child (old_ids, n, "(uu)", &finger, &id);
          if (!oem_gallery_has_finger (ids, finger, &retained) || retained != id)
            goto out;
        }
    }
  else
    {
      struct stat info;
      if (fstatat (dirfd, OEM_GALLERY, &info, AT_SYMLINK_NOFOLLOW) == 0 ||
          errno != ENOENT)
        goto out;
      for (guint finger = 1; finger < G_N_ELEMENTS (oem_finger_names); finger++)
        {
          g_autoptr(FpPrint) previous = NULL;
          g_autoptr(GVariant) previous_data = NULL, previous_bytes = NULL;
          guint32 previous_version;
          gchar digit[2] = { "0123456789abcdef"[finger], 0 };
          int r = oem_read_at (dirfd, digit, &previous);
          if (r == -ENOENT)
            continue;
          if (r || !previous || fp_print_get_finger (previous) != finger ||
              g_strcmp0 (fp_print_get_username (previous), fp_print_get_username (print)))
            goto out;
          g_object_get (previous, "fpi-data", &previous_data, NULL);
          if (!previous_data || !g_variant_is_of_type (previous_data, G_VARIANT_TYPE ("(uay)")) ||
              !oem_gallery_has_finger (ids, finger, NULL))
            goto out;
          g_variant_get (previous_data, "(u@ay)", &previous_version, &previous_bytes);
          if (previous_version != 1 || !g_variant_get_size (previous_bytes) ||
              g_variant_get_size (previous_bytes) > OEM_MAX_DB)
            goto out;
          if (old_count == 0)
            old_db = g_variant_ref (previous_bytes);
          old_count++;
          if (old_count > 1)
            goto out; /* v1 has no IDs: more than one old print is ambiguous. */
        }
    }
  if (old_count && !oem_pending_base_equal (print, old_db))
    goto out;
  if (g_variant_n_children (ids) != old_count + 1 ||
      !fp_print_serialize (print, &serialized, &length, &error) ||
      !oem_replace_at (dirfd, OEM_GALLERY, serialized, length, NULL))
    goto out;
  result = 0;
out:
  if (lockfd >= 0) close (lockfd);
  if (dirfd >= 0) close (dirfd);
  return result;
}
/* Deleting one mapping changes the TA before changing the authoritative
 * gallery. Retain the exported database on an uncertain disk commit. */
int
file_storage_oem_delete (FpDevice *dev, FpFinger finger, const gchar *username)
{
  g_autoptr(FpPrint) current = NULL;
  g_autoptr(GVariant) db = NULL, ids = NULL, next_ids = NULL, next_db = NULL, next = NULL;
  g_autofree gchar *base = NULL, *directory = NULL, *input = NULL, *output = NULL;
  g_autofree gchar *runtime = NULL, *script = NULL, *fd_text = NULL;
  g_autofree guint8 *exported = NULL, *serialized = NULL;
  g_autoptr(GError) error = NULL;
  const guint8 *database;
  gsize length, output_length, serialized_length;
  struct stat info;
  guint32 id, little_endian;
  char input_name[48], output_name[48];
  int dirfd = -1, lockfd = -1, infile = -1, outfile = -1;
  int id_pipe[2] = {-1, -1}, status = 0, result = -EIO;
  gboolean attempted = FALSE;
  GVariantBuilder builder;

  if (geteuid () != 0 || !FP_FINGER_IS_VALID (finger) ||
      g_strcmp0 (fp_device_get_driver (dev), "fpc1264_oem") != 0)
    return -EINVAL;
  base = file_storage_get_basestore_for_username (username);
  directory = get_path_to_storedir (fp_device_get_driver (dev),
                                    fp_device_get_device_id (dev), base);
  dirfd = open (directory, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  if (dirfd < 0 || fstat (dirfd, &info) || !S_ISDIR (info.st_mode) ||
      info.st_uid != 0 || (info.st_mode & 0022) ||
      (lockfd = oem_lock (dirfd)) < 0)
    goto out;
  if (oem_read_at (dirfd, OEM_GALLERY, &current) ||
      !oem_valid_stored (current, dev, username, &db, &ids) ||
      !oem_gallery_has_finger (ids, finger, &id))
    goto out;
  database = g_variant_get_fixed_array (db, &length, 1);
  if (!database || !length || length > OEM_MAX_DB)
    goto out;
  runtime = g_strdup (g_getenv ("LIUQIN_FPC_OEM_RUNTIME"));
  if (!runtime || !g_path_is_absolute (runtime))
    goto out;
  /* The installed runner has the target Python store path in its shebang. */
  script = g_build_filename (runtime, "oem_runtime.py", NULL);
  if (lstat (script, &info) || !S_ISREG (info.st_mode) ||
      info.st_uid != 0 || (info.st_mode & 0022) || access (script, X_OK))
    goto out;
  g_snprintf (input_name, sizeof input_name, ".delete-input-%08x-%08x", g_random_int (), g_random_int ());
  g_snprintf (output_name, sizeof output_name, ".delete-output-%08x-%08x", g_random_int (), g_random_int ());
  input = g_build_filename (directory, input_name, NULL);
  output = g_build_filename (directory, output_name, NULL);
  infile = openat (dirfd, input_name, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
  if (infile < 0)
    goto out;
  for (gsize offset = 0; offset < length;)
    {
      ssize_t n = write (infile, database + offset, length - offset);
      if (n < 0 && errno == EINTR)
        continue;
      if (n <= 0)
        goto out;
      offset += n;
    }
  if (fsync (infile) || fsync (dirfd) || pipe (id_pipe))
    goto out;
  little_endian = GUINT32_TO_LE (id);
  if (write (id_pipe[1], &little_endian, sizeof little_endian) != sizeof little_endian)
    goto out;
  close (id_pipe[1]);
  id_pipe[1] = -1;
  fd_text = g_strdup_printf ("%d", id_pipe[0]);
  gchar *argv[] = { script, (gchar *) "--ufs-rpmb-authenticated",
                    (gchar *) "--delete-template", input, output, fd_text, NULL };
  attempted = TRUE;
  gboolean spawned = g_spawn_sync (NULL, argv, NULL,
                                   G_SPAWN_LEAVE_DESCRIPTORS_OPEN |
                                   G_SPAWN_STDOUT_TO_DEV_NULL | G_SPAWN_STDERR_TO_DEV_NULL,
                                   NULL, NULL, NULL, NULL, &status, &error);
  close (id_pipe[0]);
  id_pipe[0] = -1;
  if (!spawned || !WIFEXITED (status) || WEXITSTATUS (status) != 0)
    {
      g_warning ("OEM delete worker did not confirm deletion; gallery publication was not attempted");
      goto out;
    }
  outfile = openat (dirfd, output_name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  if (outfile < 0 || fstat (outfile, &info) || !S_ISREG (info.st_mode) ||
      info.st_uid != 0 || (info.st_mode & 0777) != 0600 ||
      info.st_size < 0 || info.st_size > OEM_MAX_DB)
    goto out;
  output_length = info.st_size;
  exported = g_malloc (output_length ? output_length : 1);
  for (gsize offset = 0; offset < output_length;)
    {
      ssize_t n = read (outfile, exported + offset, output_length - offset);
      if (n < 0 && errno == EINTR)
        continue;
      if (n <= 0)
        goto out;
      offset += n;
    }
  if (fsync (outfile))
    goto out;
  g_variant_builder_init (&builder, G_VARIANT_TYPE ("a(uu)"));
  for (gsize n = 0; n < g_variant_n_children (ids); n++)
    {
      guint32 existing_finger, existing_id;
      g_variant_get_child (ids, n, "(uu)", &existing_finger, &existing_id);
      if (existing_finger != finger)
        g_variant_builder_add (&builder, "(uu)", existing_finger, existing_id);
    }
  next_ids = g_variant_ref_sink (g_variant_builder_end (&builder));
  if (g_variant_n_children (next_ids) && !output_length)
    goto out;
  next_db = g_variant_ref_sink (g_variant_new_fixed_array (G_VARIANT_TYPE_BYTE,
                                                            exported, output_length, 1));
  next = g_variant_ref_sink (g_variant_new ("(u@ay@a(uu))", 2,
                                            g_variant_ref (next_db), g_variant_ref (next_ids)));
  g_object_set (current, "fpi-data", next, NULL);
  if (!fp_print_serialize (current, &serialized, &serialized_length, &error) ||
      !oem_replace_at (dirfd, OEM_GALLERY, serialized, serialized_length, NULL))
    goto out;
  result = 0;
out:
  if (id_pipe[0] >= 0) close (id_pipe[0]);
  if (id_pipe[1] >= 0) close (id_pipe[1]);
  if (outfile >= 0) close (outfile);
  if (infile >= 0) close (infile);
  if (dirfd >= 0)
    {
      if (input && (!attempted || result == 0))
        (void) unlinkat (dirfd, input_name, 0);
      if (output && result == 0)
        (void) unlinkat (dirfd, output_name, 0);
    }
  if (lockfd >= 0) close (lockfd);
  if (dirfd >= 0) close (dirfd);
  return result;
}

/* The daemon, not the OEM worker, is the sole owner of the fprintd store.
 * The worker retains an accepted export until this durable store operation
 * acknowledges precisely the database returned by the driver. */
gboolean
file_storage_oem_enroll_sync (FpPrint *print)
{
  g_autoptr(GVariant) data = NULL, bytes = NULL, ids = NULL, disk_data = NULL;
  g_autoptr(FpPrint) disk = NULL;
  g_autofree gchar *base = NULL, *path = NULL, *name = NULL;
  g_autofree gchar *directory = NULL, *digest = NULL, *ack = NULL;
  const gchar *runtime = g_getenv ("LIUQIN_FPC_OEM_RUNTIME");
  const guint8 *database;
  gsize length;
  guint32 version;
  struct stat info;
  int fd = -1, dirfd = -1, status = 0;
  gboolean durable = FALSE, v2;

  if (geteuid () != 0 || !FP_FINGER_IS_VALID (fp_print_get_finger (print)) ||
      (guint) fp_print_get_finger (print) >= G_N_ELEMENTS (oem_finger_names) ||
      g_strcmp0 (fp_print_get_driver (print), "fpc1264_oem") != 0 ||
      !runtime || !g_path_is_absolute (runtime))
    return FALSE;
  g_object_get (print, "fpi-data", &data, NULL);
  v2 = data && g_variant_is_of_type (data, G_VARIANT_TYPE ("(uaya(uu))"));
  if (v2)
    {
      if (!oem_gallery_data (print, &bytes, &ids, FALSE) ||
          !oem_gallery_has_finger (ids, fp_print_get_finger (print), NULL))
        return FALSE;
      name = g_strdup (OEM_GALLERY);
    }
  else
    {
      if (!data || !g_variant_is_of_type (data, G_VARIANT_TYPE ("(uay)")))
        return FALSE;
      g_variant_get (data, "(u@ay)", &version, &bytes);
      if (version != 1)
        return FALSE;
      base = file_storage_get_basestore_for_username (fp_print_get_username (print));
      path = __get_path_to_print (fp_print_get_driver (print), fp_print_get_device_id (print),
                                  fp_print_get_finger (print), base);
      name = g_path_get_basename (path);
    }
  database = g_variant_get_fixed_array (bytes, &length, 1);
  if (!database || length == 0 || length > OEM_MAX_DB)
    return FALSE;
  dirfd = oem_open_dir (print, FALSE, &directory);
  if (dirfd < 0)
    goto out;
  fd = openat (dirfd, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  if (fd < 0 || fstat (fd, &info) || !S_ISREG (info.st_mode) ||
      info.st_uid != 0 || (info.st_mode & 0777) != 0600 || info.st_size <= 0 ||
      info.st_size > OEM_MAX_PRINT || oem_read_at (dirfd, name, &disk) ||
      fsync (fd) || fsync (dirfd))
    goto out;
  g_object_get (disk, "fpi-data", &disk_data, NULL);
  if (!disk_data || !g_variant_equal (disk_data, data) ||
      g_strcmp0 (fp_print_get_username (disk), fp_print_get_username (print)) ||
      g_strcmp0 (fp_print_get_device_id (disk), fp_print_get_device_id (print)) ||
      g_strcmp0 (fp_print_get_driver (disk), fp_print_get_driver (print)))
    goto out;
  durable = TRUE;

out:
  if (fd >= 0)
    close (fd);
  if (dirfd >= 0)
    close (dirfd);
  if (!durable)
    return FALSE;

  digest = g_compute_checksum_for_data (G_CHECKSUM_SHA256, database, length);
  ack = g_build_filename (runtime, "enrol_transaction.py", NULL);
  gchar *argv[] = { ack, (gchar *) "--ack", (gchar *) fp_print_get_username (print),
                    (gchar *) oem_finger_names[fp_print_get_finger (print)], digest, NULL };
  if (!g_spawn_sync (NULL, argv, NULL,
                     G_SPAWN_STDOUT_TO_DEV_NULL | G_SPAWN_STDERR_TO_DEV_NULL,
                     NULL, NULL, NULL, NULL, &status, NULL) ||
      !WIFEXITED (status) || WEXITSTATUS (status) != 0)
    {
      g_warning ("OEM enrolment persisted, but pending export acknowledgement failed");
      return !v2; /* Preserve the established v1 transaction semantics. */
    }
  return TRUE;
}

/* An interrupted daemon can save the print and die before acknowledging the
 * worker. Reconcile only when this user's ready marker exists; a mismatched
 * export remains untouched and verification uses the already stored print. */
void
file_storage_oem_enroll_reconcile (FpPrint *print)
{
  g_autofree gchar *marker = NULL;

  if (g_strcmp0 (fp_print_get_driver (print), "fpc1264_oem") != 0 ||
      !FP_FINGER_IS_VALID (fp_print_get_finger (print)) ||
      (guint) fp_print_get_finger (print) >= G_N_ELEMENTS (oem_finger_names))
    return;
  marker = g_build_filename ("/var/lib/liuqin-fingerprint/pending",
                             fp_print_get_username (print),
                             oem_finger_names[fp_print_get_finger (print)],
                             "export-ready.json", NULL);
  if (g_file_test (marker, G_FILE_TEST_EXISTS))
    (void) file_storage_oem_enroll_sync (print);
}
