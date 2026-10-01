# Ataste: App Store Connect checklist

## Before release
- [x] Public TestFlight link https://testflight.apple.com/join/U65TErQM (group "Public"; build 3 submitted for beta review 2026-10-01) in `Links.getTheApp` and `web/index.html`.
- Atas Artisan permission: not needed (user's decision, 2026-10-01). Ataste only links customers to Atas's own
  WhatsApp ordering; the "not affiliated" disclaimer stays in the app, listing and terms. If App Review raises
  guideline 5.2, answer with that.

## App information
- Name: Ataste · Subtitle: Group orders from Atas Artisan
- Category: Food & Drink (secondary: Social Networking)
- Age rating: 4+ (no objectionable content; user photos limited to private groups, reportable)
- Privacy Policy URL: https://scgyssmzfurqjkgfomtq.supabase.co/functions/v1/legal/privacy
- Support URL: https://scgyssmzfurqjkgfomtq.supabase.co/functions/v1/legal/support
- Copyright: 2026 Johar Kurniawan

## Description (draft)
Ordering from Atas Artisan with friends? Ataste does the busywork. Start a group order, share the link, and
everyone adds their own items from the Atas menu: sourdough sliced or whole, the right size, a note for the
bakery. Ataste shows how close you are to the Rp 200.000 ongkir discount, lets friends split a whole cake,
and writes the WhatsApp order in the format Atas expects. When Atas confirms the ongkir, everyone's bill is
worked out to the rupiah, with the host's bank or e-wallet one tap away. Snap a photo when it arrives, and done.

Ataste is an independent app and is not affiliated with Atas Artisan. Payments happen directly between friends;
Ataste never handles money.

Keywords: atas, artisan, bakery, bali, group order, split bill, sourdough, ongkir, patungan, pesan bareng

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

  Ataste verifies a user's phone number by having them send a one-time code from their own WhatsApp to our
  number; the reviewer may not have WhatsApp, so there is a review sign-in. On the Welcome screen, press and
  hold the "ataste" logo for 1 second; a "Review code" field appears. Enter CODE and tap Sign in. You are
  signed in as "Rani", the host of a sample group ("Academy Bali Friday Treats", open) and a member of a
  second group whose bill is final ("Academy Bali Snacks"). Ataste does not process payments: members transfer
  money to the host outside the app (physical goods, guideline 3.1.3(e)). Ataste is not affiliated with Atas
  Artisan; the "Send to Atas" button opens WhatsApp with the order text for the host to send themselves.
  Account deletion: Profile → Delete account.

## Export compliance
`ITSAppUsesNonExemptEncryption = NO` in Info.plist (HTTPS only), so no questions per build.

## Screenshots (6.9", 1320 × 2868)
From the simulator with the DEBUG hooks (see CLAUDE.md): Home, group screen, menu, product with options,
Send to Atas message, bill.
