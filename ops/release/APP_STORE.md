# Ataste: App Store Connect checklist

## Before release
- [x] Public TestFlight link https://testflight.apple.com/join/U65TErQM (group "Public"; build 3 approved 2026-10-01; build 7 approved 2026-10-02; build 8 live 2026-10-02; build 9 live 2026-10-02; build 13 live 2026-10-08) in `Links.getTheApp` and `web/index.html`.
- Atas Artisan permission: not needed (user's decision, 2026-10-01). Ataste only links customers to Atas's own
  WhatsApp ordering; the "not affiliated" disclaimer stays in the app, listing and terms. If App Review raises
  guideline 5.2, answer with that.

## App information
- Name: Ataste · Subtitle: Group orders from Atas Artisan
- Category: Food & Drink (secondary: Social Networking)
- Age rating: 4+ (no objectionable content; user photos limited to private groups, reportable)
- Privacy Policy URL: https://scgyssmzfurqjkgfomtq.supabase.co/functions/v1/legal/privacy
- Support URL: https://scgyssmzfurqjkgfomtq.supabase.co/functions/v1/legal/support
  (plain text served by the `legal` function. App Review could not open the sslip.io host, either through the old
  redirect (2026-10-29) or directly (2026-11-10), both times under 1.5. The app keeps the styled sslip.io pages.)
- Copyright: 2026 Johar Kurniawan

## Description (as submitted for 1.0)
Promotional text: One link for the whole office order. Everyone adds their own pastries, Ataste writes the WhatsApp
order for Atas, and the bill splits itself to the rupiah.

Ordering from Atas Artisan with friends? Ataste does the busywork.

Start a group order, share the link, and everyone adds their own items from the Atas menu: sourdough sliced or whole,
the right size, a note for the bakery. Ataste shows how close the group is to Rp 200.000, where ongkir is free, and
lets friends split a whole cake piece by piece.

When the order is ready, Ataste writes the WhatsApp message in the format Atas expects, so the host only has to press
send. Everyone's bill is worked out to the rupiah, with the host's bank or e-wallet one tap away. Snap a photo when it
arrives, and done.

Ataste is an independent app and is not affiliated with Atas Artisan. Payments happen directly between friends;
Ataste never handles money.

Keywords: atas,artisan,bakery,bali,group order,split bill,sourdough,ongkir,patungan,pesan bareng,roti,kue

## App Privacy (must match PrivacyInfo.xcprivacy)
Data linked to the user, used for App Functionality only, no tracking:
- Contact Info: Phone Number, Name, Physical Address
- Financial Info: Payment Info (host's bank or e-wallet account number, shown to their group)
- User Content: Photos (receipts, delivery photos), Other User Content (orders, notes)
- Identifiers: User ID
Not collected: location, contacts, browsing, purchases, usage data, diagnostics, device ID for ads.

## App Review information
- Sign-in required: yes. Demo account: there is no password; see notes.
- Notes (paste, replacing CODE with the Keychain value `ataste.review-code`):

  Sign in with Apple is the only sign-in. A new account can join groups and order right away. Hosting a group
  needs a verified phone number, because members pay the host and the bakery needs the host's number: the user
  sends a one-time code from their own WhatsApp to our number, and gets a "Verified" badge.
  To see sample data without WhatsApp, use the demo account: on the Welcome screen, press and hold the "ataste"
  logo for 2 seconds; a "Review code" field appears. Enter CODE and tap Sign in. You are signed in as "Rani"
  (already verified), the host of a sample group ("Academy Bali Friday Treats", open) and a member of a second
  group whose bill is final ("Academy Bali Snacks"). It may offer once to link an Apple ID; tap Later.
  Ataste does not process payments: members transfer money to the host outside the app (physical goods,
  guideline 3.1.3(e)). Ataste is not affiliated with Atas Artisan; the "Send to Atas" button opens WhatsApp
  with the order text for the host to send themselves.
  Account deletion: Profile → Delete account (it also revokes the Sign in with Apple token).

## Export compliance
`ITSAppUsesNonExemptEncryption = NO` in Info.plist (HTTPS only), so no questions per build.

## Screenshots
Claude Design board "App Store Screenshots.dc.html" (AS-01 to AS-07, 1320 × 2868, with Atas's menu photos), exported
to the project's `export/` folder. App Store Connect asks for the 6.5" slot, so they were scaled to 1284 × 2778 JPEG
(no alpha) and uploaded one at a time: a multi-file upload lands in completion order and breaks the seams.

iPhone Duo: "App Store Screenshots Duo.dc.html" is a copy of the board plus a script; `?duo=inner|outer&as=1..7`
widens the 440 × 956 design stage to the Duo ratio and renders one panel (inner 2007 × 2853, outer 1398 × 2034,
JPEG, `export/duo/`). All 14 uploaded to Asset Library 2026-10-07, one at a time.

## Creative assets (iOS 27 header and search results)
OpenDesign board "App Store Creative Assets.html" (project "Ataste iOS app design"), rendered with headless Chrome
(`?a=header` / `?a=search` shows one artboard at 0,0) into `export/creative/`. Uploaded to Asset Library 2026-10-07:
header 3840 × 1646 as **PNG** (the same size as JPEG was rejected, "File dimensions are invalid"), search results
3840 × 2560 JPEG. Apple's specs: https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications

## Submissions
- 1.0 (build 12) submitted for review 2026-10-03, manual release. Content Rights: yes, with rights. Age rating 4+.
  Price free.
  - Rejected 2026-10-12, guideline 4.8 (Login Services): "Continue with WhatsApp" read as a third-party login.
  - Resubmitted 2026-10-14 with build 24 (Sign in with Apple as the only sign-in; WhatsApp only verifies a
    number) and a reply in the submission's messages.
  - Rejected 2026-10-29 (iPad Air, iPadOS 27.2): 2.1(a) the reviewer got "Update Ataste" (App Review installs read
    as TestFlight; `testflight.py` had raised that minimum to 25 over build 24 in review), so the logo was out of
    reach; 1.5 Support URL "not functional"; 3.2 asked whether the app is for one organisation.
  - Resubmitted 2026-10-29 with build 25, notes "hold for 2 seconds" (the gesture needs 1.2 s), direct legal URLs,
    and a reply answering the 3.2 questions. `testflight.py` now stops the TestFlight minimum at the build in review.
    Review demo cutoff is 2026-11-05 (reseeded 2026-10-29); rerun `supabase/seed/review_demo.sql` if review runs
    past it.
  - Rejected 2026-11-10 (iPad Air 11-inch M3), 1.5 only: the sslip.io Support URL "not functional" (it answered 200
    from here). Moved the Support and Privacy Policy URLs to the Supabase `legal` function (plain text), reseeded the
    review demo (cutoff 2026-11-17 13:00 WITA), replied in the submission's messages, and resubmitted build 25 the
    same day through the API.
  - The resubmit button stays disabled until the rejected item is marked resolved: API `PATCH
    reviewSubmissionItems/{id}` `resolved: true`, then `PATCH reviewSubmissions/{id}` `submitted: true`.
- Asset Library draft iOS submission (started 2026-10-07): header, search results and the 14 Duo screenshots,
  "Ready for Review". Submit for Review is disabled ("add an app version for the selected platform") until 1.0 is
  approved; then open Asset Library → Draft Submissions → Submit for Review.
