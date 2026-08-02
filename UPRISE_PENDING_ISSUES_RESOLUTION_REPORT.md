# UPRISE — Pending Issues Resolution Report

**Source:** `UPRISE_FINAL_COMPLETE_STATUS.md` (2 pending issues)
**Status:** Both resolved
**Scope:** Student mobile screens (image rendering) + org web screen (announcements)

---

## Issue #1: Image Provider Duplication — RESOLVED

**Before:** 9 separately-maintained copies of base64/network image-decoding logic across 6 files, each with different edge-case handling.

**Fix:** Created one shared widget, `lib/widgets/student/app_image.dart`:
- `AppImage` — a widget that replaces `Image`/`Image.memory`/`Image.network` call sites
- `AppImage.provider(source)` — a synchronous `ImageProvider?` helper for `CircleAvatar.backgroundImage` / `DecorationImage.image` call sites
- `decodeAppImageBytes(source)` — the single shared decode routine

It recognizes every format the 9 originals handled between them: `data:image;base64,...` URIs, the malformed `dataimage` (no colon) variant, raw base64 with no prefix, and `http(s)` network URLs — including authenticated Firebase Storage fetches (a capability only one of the 9 originals had).

### Files migrated

| File | What changed |
|---|---|
| `student_announcements_screen.dart` | Deleted `_studentImageProvider`; 4 call sites now use `AppImage.provider(...)` |
| `student_certificates_screen.dart` | Deleted `isBase64Image` + 6 duplicated render blocks (`_buildImage`, 2× `_buildFullImage`, 3× inline template-image blocks); all now call `AppImage` |
| `student_home_screen.dart` | `Base64Image` widget kept (for call-site compatibility) but its body now delegates to `AppImage` |
| `student_organizations_screen.dart` | Deleted 3 duplicated `_buildLogoImage` methods (one was already dead code, zero call sites); call sites now use `AppImage.provider(...)` |
| `student_organization_details_screen.dart` | Simplified `_buildLogoImage`/`_buildCoverImage` to delegate to `AppImage.provider`; replaced an inline adviser-photo decoder with the same call |
| `student_profile_screen.dart` | `_ProfileImage` widget's body now delegates to `AppImage`; deleted the dead, unused `_profileImageProvider` function |

### Effects
- **One place to fix bugs** — a rendering fix or new format now only needs to change in `app_image.dart`, not 9 places.
- **Real bug fixed, not just cleanup:** in `student_certificates_screen.dart`, three of the old duplicates called `base64Decode(...)` directly inline as a widget-constructor argument, outside any `try/catch` — a malformed value there would have crashed instead of showing a placeholder. `AppImage` decodes defensively everywhere.
- **New capability, no regression:** avatars/logos/certificates that are stored as Firebase Storage URLs now get authenticated fetches (previously only event banners had this); every screen's existing placeholder/fallback behavior (letter avatars, custom icons, the reactive cover-image gradient in org details) was preserved exactly.
- Removed one latent bug: the announcements screen's old fallback, `AssetImage('assets/placeholder.png')`, pointed at an asset that was never registered in `pubspec.yaml` and would have silently failed every time it was hit.

---

## Issue #2: Announcements Firestore Document Size Guard — RESOLVED

**Before:** `org_announcements.dart` let an org attach a 5MB image (→ ~6.7MB once base64-encoded — 6× over Firestore's ~1MiB per-document cap) and an unlimited number of individually-compliant attachments, with no check of the combined document size before writing. A too-large announcement would fail at `.add()`/`.update()` with a raw Firestore exception shown to the org.

**Fix (all in `lib/screens/web/org/org_announcements.dart`):**
1. Image picker reject threshold lowered from 5MB → **700KB**, matching the safety-margin convention already used elsewhere in this codebase for inline-base64 Firestore fields (`org_broadcast.dart`, `org_event_proposals.dart`).
2. Attachment picker now caps **total attachment count at 5** and **cumulative attachment size at 600KB**, checked as each file is picked — so the org gets feedback immediately instead of only at submit time.
3. Added an **aggregate check before the Firestore write**: `imageBase64.length + all attachments' base64.length` must stay under 900KB, or the save is blocked with a friendly message ("This announcement is too large to save. Remove the image or an attachment and try again.") instead of attempting the write.

### Effects
- An org can no longer compose an announcement that silently fails at Post — the limits are enforced while composing, with a second guard right before the write as a backstop.
- Student-side display (`student_announcements_screen.dart`) needed no changes — it was already defensively coded (null-safe field parsing, decode wrapped in try/catch, error builders on every image) and confirmed to have no equivalent unguarded write path.
- No new dependency introduced — kept the existing `file_picker`-based flow rather than switching to `image_picker`/`flutter_image_compress` (the latter is declared in `pubspec.yaml` but has zero usages anywhere in the app; introducing its first real usage here would have been a separate, larger decision).

---

## Verification

- `dart format` + `flutter analyze` run after every file edit — every new warning/info traced back to confirm it was pre-existing (via `git stash` A/B comparison), never introduced by these changes.
- Full-project `flutter analyze`: **0 errors**, 684 issues (685 before — one fewer, from removing dead code along the way).

## Suggested manual test pass (not yet done — recommend before shipping)
- [ ] View an announcement with a base64 image, a Firebase Storage image URL, and a broken/empty URL on the student app — confirm all three render correctly.
- [ ] Certificates screen: view a certificate list, a certificate detail, and a live-preview template — confirm banners/templates still render.
- [ ] Organizations list/grid and org details: logo, cover photo, and adviser photo all still render with correct letter-avatar/gradient fallbacks when missing.
- [ ] Profile screen: avatar renders in all 4 places it's used (header, ID card, and the two smaller instances).
- [ ] Org side: try uploading an 800KB image (should reject), 6 attachments (6th should reject), and attachments totaling >600KB (should reject) — confirm friendly messages, not raw Firestore errors.
