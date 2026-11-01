# OEM fprintd persistence

`pkgs/fingerprint/fprintd-oem.nix` applies `fprintd-oem-update.patch` to the
pinned fprintd source and installs `oem-update.inc` in its source tree. No
private build-copy script is required. The system fprintd package retains its
upstream D-Bus API and PAM module.

The TOD driver requests an updated opaque database from a genuine successful
match. It clones the original FpPrint and supplies that clone through private
qdata on the enrolled print. fprintd consumes this marker in `match_cb` before
emitting `VerifyStatus`: under the shared enrol/store lock it compares the
disk print with the original, writes a root-private temporary file, saves an
old-file hard link, and commits through rename and fsync. Failure restores the
in-memory original, refuses authentication success, and preserves the original
file or its recovery link. Cancelled, unmatched and inconclusive results never
publish adaptation. Discovery ignores the multi-character recovery filenames.

Enrolment has one publisher: the TOD driver returns an opaque FpPrint, and
fprintd saves it. Before the final authorization and `BIO_END_ENROL`, the
native client waits for a durable root-private uncertainty marker to be
acknowledged by its parent.
Capture failures do not create one; an accepted export is retained until
fprintd syncs the saved print and acknowledges its matching SHA-256 to
`enrol_transaction.py`. A daemon crash after save but before
acknowledgement is reconciled when the saved print is loaded. An interrupted
acknowledgement replays its durable cleanup marker. An uncertain TA/export
outcome never automatically restarts hardware enrolment.

For this driver fprintd does not run its duplicate-identification precheck
before enrollment. That precheck would require an extra, unprompted sensor
touch and would abort the enrollment if it timed out. `EnrollStart` still
deletes an existing print for the requested finger label first, matching the
vendor re-enrolment behavior. A duplicate physical finger enrolled under a
different label is not detected here.

For new enrollments fprintd publishes one root-private `.gallery` per user and
device. Its version-2 `(uaya(uu))` data contains the opaque TA database and up
to five unique finger-to-template-ID mappings. The ready export's private ID
envelope and previous database digest must agree with the gallery under the
shared operation lock before a durable rename and post-save acknowledgement.
The preexisting version-1 finger file remains readable until migration; after
the gallery is committed it is ignored, even for a missing finger or an empty
gallery tombstone. A corrupt gallery never triggers legacy fallback.

Verification of an unspecified finger uses identify when multiple mappings
exist; the same pre-status compare-and-replace persists adaptive databases for
verify and identify. Deleting a mapped finger passes only its binary ID through
an inherited private pipe to the authenticated OEM worker, which confirms
selective TA deletion before fprintd durably replaces the gallery. The last
deletion writes an authoritative empty mapping rather than reviving old files.
An uncertain export or disk commit leaves private recovery material and never
reports success.

Native target compilation and real system-bus discovery/Claim/Release passed.
The recorded desktop-r3 boot has a real OEM print and passed same-finger,
reload and other-finger acceptance; the user also reported GNOME unlock.
Position sensitivity, stutter and unobserved retry/cold-start cases remain
documented in [INSTALL.md](../../../../docs/INSTALL.md).
