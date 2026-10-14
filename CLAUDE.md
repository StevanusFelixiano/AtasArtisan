# Ataste (repo: StevanusFelixiano/AtasArtisan)

Group ordering from the Atas Artisan bakery (Bali) for Apple Developer Academy people. The host collects
orders, Ataste splits the bill and writes the WhatsApp order; members pay the host directly.
Personal, machine-specific notes go in `CLAUDE.local.md` (gitignored).

## Refs
- **Apple:** bundle `com.bayujo.Ataste`, display name Ataste.
  - iPhone only, iOS 26.0+ (Liquid Glass native; iOS 27 extras go behind `#available`).
- **Supabase:** project ref `scgyssmzfurqjkgfomtq` (ap-northeast-1, Tokyo).
  - The publishable key is in `Shared/Backend.swift`.
- **Design tokens** are in `Shared/Brand.swift`. Every colour is a `Brand` token; a `Color(hex:)` in a view is a bug.
- **Fonts:** Roundo, Manrope (variable, weight set on the `wght` axis in `Brand.uiFont`) and Shrikhand, all OFL. Licences are in `docs/font-licenses`.
- **Secrets:** never commit or print one. Supabase Vault stores only SHA-256 hashes of the bridge/scraper secrets and the review code, plus the APNs key.

## Build
- **Logic checks:** `rm -f /tmp/atcheck && swiftc -parse-as-library AtasArtisan/Logic/*.swift check.swift -o /tmp/atcheck && /tmp/atcheck`
- **Simulator:** must be **ad-hoc signed**. An unsigned build (`CODE_SIGNING_ALLOWED=NO`) can't write the Keychain, so the Supabase session is lost and every screen after sign-in breaks:
  `xcodebuild -project AtasArtisan.xcodeproj -scheme AtasArtisan -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/ataste-dd CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build`
  - Build into `/tmp`, never the project folder.
- **Simulator screenshots (DEBUG hooks in `Shared/DebugScreens.swift`):**
  - `SIMCTL_CHILD_ATASTE_REVIEW_CODE=<code>` signs in as the review account.
  - `ATASTE_TAB` (1 History, 2 Profile) picks a tab.
  - `ATASTE_OPEN=<group name part>` opens a group.
  - `ATASTE_SHEET` = menu | send | confirm | bill | board | delivery | share | split.
- **Device:** `xcrun devicectl device install app` often fails with CoreDeviceError 4000; it is transient, retry.
- **Project:** Xcode 27 folders that auto-sync. Never add files by hand-editing `project.pbxproj`.
  - `AtasArtisan-Info.plist` (URL scheme `ataste`, `whatsapp` query scheme, `ITSAppUsesNonExemptEncryption` false) and `AtasArtisan.entitlements` sit at the repo root, outside the synced folder.
  - Default actor isolation is MainActor: data models and `Logic/` are `nonisolated`.

## How sign-in works (Sign in with Apple; WhatsApp verifies a number)
1. **Sign in with Apple is the only sign-in** (App Review 4.8). The app sends Apple the SHA-256 of a random nonce, then
   posts the identity token, authorization code and raw nonce to `apple`.
2. `apple` checks the token (Apple's JWKS, audience `com.bayujo.Ataste`, nonce), trades the code for a refresh token
   (Vault `siwa_key`, key 3553QXY6KR), and returns a magic-link `token_hash`. A new Apple ID gets a user
   (`<sub>@apple.ataste.invalid`), a `profiles` row with no phone, and an `apple_accounts` row.
3. The app finishes with `auth.verifyOTP(tokenHash:type:.magiclink)`. We mint no JWTs.
4. **Verified** = `profiles.phone` is set: the badge, and needed to host (`host_creates` policy). Verifying is the
   reverse WhatsApp code:
   - The app calls `otp/start` with its session and gets `ATASTE XXXX` plus a nonce, then opens
     `wa.me/6281936100819?text=ATASTE XXXX`. The user presses send in their own WhatsApp.
   - The bridge resolves the sender's number (LID → phone; never verifies a LID-only sender) and POSTs
     `{code, phone, wa_id}` to `wa-inbound` with `x-bridge-secret`. The app polls `otp/status?nonce=` every 2 s.
   - A number on another account answers `taken`; `otp/claim` moves the Apple ID to that older account and deletes the
     new empty one.
5. Builds 23 and older sign in with the code alone (`otp/start` without a session); keep that path until they are gone.
6. Public sign-ups are **off** in Auth settings; admin `createUser` still works.
7. Verification codes are deleted after a day by `tick()`. Account deletion (`account`) revokes the Apple token.

**App Review:** a long-press on the Welcome logo opens a code field (ask the owner for the code). The account is phone `6200000000001`, named "Rani".
- `supabase/seed/review_demo.sql` gives it 5 demo friends and two groups (re-runnable), after it has signed in once.

## UI
- Questions are `.alert`, never `.confirmationDialog`. Exception: Remove-item and Leave-group are custom bottom confirm sheets.
- Anything irreversible (delete, sign out, leave) asks first.
- Every pushed screen has a `navigationTitle`; a screen with its own heading pairs it with `.toolbar(removing: .title)`.
- Never nest a `NavigationStack` inside a pushed flow, or a `ShareLink` inside a `Menu`.

## Backend
- **Migrations** are in `supabase/migrations`; run the security advisors after each DDL change.
- **State changes** go only through security-definer RPCs in `20261001100100_logic.sql`; clients have column grants for the rest.
  - Security-definer functions pin `search_path = ''`, use `coalesce(<cond>, false)` on `auth.uid()` checks, and revoke EXECUTE from both `public` and `anon`.
- **The bill** is `group_bill_v` (equal ongkir − discount among payers; split shares; rounding to the owner and the host). It freezes into `members.bill_total` at `confirm_atas`.
- **Notifications:** every row of `notifications` goes through the trigger, `pg_net`, then the `push` function (APNs). Muted kinds are in `profiles.notify_mute`.
- **Timer:** `pg_cron` `ataste-tick` runs every minute: the 30-minute cutoff reminder, auto-lock, auto-close
  (3 days after delivery, once everyone has paid), and code cleanup.
- **Functions** (`supabase/functions`, `verify_jwt` in `supabase/config.toml`): apple, otp, wa-inbound, push, join (302 → the invite page `/j/CODE`), legal (302 → the legal pages), account (delete), menu-ingest.
  - `apple` and `account` import `_shared/apple.ts`: deploy it with both.
- **Realtime** events mean "refetch"; a 30 s poll stays behind each channel, and each watcher has its own topic.
- **Tests:** `supabase/tests/bill.sql` runs the design's sample order end to end as the real roles and rolls back.
- **Legal:** edit `legal/*.md`, run `python3 legal/build.py` (writes branded HTML to `web/legal/`). Served at `https://ataste.51-79-240-114.sslip.io/legal/{privacy,terms,support}`.
- **Links in the app:** `InAppBrowser.action` is the root `openURL`: web pages open in an in-app Safari view; WhatsApp,
  App Store, TestFlight and mail hand off to their apps; invite links open the join sheet.

## Server side (outside Supabase)
- **WhatsApp bridge** (`bridge/`): Vellum's bridge plus `ataste.go`, whatsmeow kept at `@latest` (older versions get unlinked right after pairing). The linked number needs a re-scan about every 20 days.
- **Menu scraper:** runs at 05:00 and 12:00 WITA, reads the iSeller APIs, and calls `menu-ingest` only when the menu hash changed. Products missing from a scrape are marked unavailable, which sends sold-out notices.

## Release
- Bump `CURRENT_PROJECT_VERSION` in `project.pbxproj` for each upload. The App Store Connect checklist is in `ops/release/APP_STORE.md`.
- `app_release.min_build` makes older builds show "Update Ataste".
