// The sizes one sync pass keeps itself to.
//
// Both exist because an unbounded pass is a pass that can never finish: the
// server refuses the oversized request, or the phone spends the whole
// foreground window on one queue. Bounding them turns "never syncs again"
// into "syncs a bit less per pass", which is the trade this app wants — the
// phone is the source of truth and the rest catches up next time.

/// Ops per push request.
///
/// Mirrors the server's cap of 500 (`server/src/validate.ts`) with headroom.
/// Over that the server answers 400, and a 400 is the one failure retrying
/// cannot fix: a guest signing in with 600 entries would re-send the same
/// oversized body on every pass and never back up anything at all.
const int kMaxOpsPerPush = 250;

/// Photo downloads attempted in one pass.
///
/// Downloads are sequential requests with a 30-second timeout each, derived
/// from "every entry missing a file" rather than a queue. A fresh install
/// facing a large archive would otherwise hold one pass open for hours. The
/// remainder is not lost: the missing files still look missing next pass.
const int kMaxPhotoDownloadsPerPass = 25;
