# FPC1264 OEM TOD driver

The NixOS package builds `fpc1264-oem.c` against the system's libfprint-tod.
The adapter operates the sensor and stages opaque OEM data, but never writes
fprintd's print store. fprintd publishes each account's canonical `.gallery`
print, with `(uaya(uu))` version 2 data: an opaque database and up to five
unique finger/template-ID pairs. Existing `(uay)` version 1 prints remain
readable and verifiable without rewriting them.

Enrolment uses `user_credentials.py --enrol-prepared`: the password-derived
input must first have been prepared through a configured PAM service or
`liuqin-fpc-credential --prepare-acceptance`. The worker writes an uncertainty
marker before calling the FPC trustlet, then a private accepted export and
finger-bound marker after successful END_ENROL. The driver reports only
allowlisted versioned sample/retry/lift/finalization events to libfprint.
Child exit, stdout EOF and the committed event must all agree before it
returns an opaque print. A cancellation cannot publish an incomplete result.

Intermediate `remaining` values are vendor feedback, not a promised exact
19-to-0 sequence. Only the native final-sample event followed by the accepted
export may complete an enrolment; bounded progress and the driver's own
protocol errors remain visible without forwarding raw child output.

If fprintd crashes after the trustlet accepts a template, the next enrolment
can recover the accepted export and private ID inventory without calling the
trustlet again. fprintd publishes and syncs the gallery, then acknowledges
both committed outputs. An incomplete or uncertain export is not automatically
retried or deleted.

To append a finger, the adapter reads the canonical print (or the single
legacy print when no canonical gallery exists) without modifying it, stages
the private input database and requests a private 28-byte inventory from the
credential worker. It rejects conflicting fingers, a sixth template, duplicate
or missing template IDs and any change to the previous finger/ID mapping.
Only fprintd publishes the returned replacement gallery. Canonical presence
is authoritative; a corrupt or empty canonical file never triggers legacy
fallback.

Verification of version 2 prints consumes the authenticated template ID and
accepts only the claimed finger's ID. Identification makes one sensor scan
against a claimed user's gallery, then selects the corresponding FpPrint by
the returned ID. Both paths can attach an adapted database to the matching
print for fprintd's durable compare-and-replace update; a failed or cancelled
match never updates the stored gallery. Version 1 verification continues to
use its existing single-finger match path. Galleries belonging to separate
users are not combined for identification.

The OS2 lab established distinct old/new template IDs, selective deletion,
and isolated-database match/mismatch before enabling the multi-finger path.
