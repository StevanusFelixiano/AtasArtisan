# Ataste

Group orders from Atas Artisan (Bali) for friends: everyone adds their own items, Ataste splits the bill
(including shared cakes), writes the WhatsApp order in the format Atas expects, and tracks payments to the host.

- `AtasArtisan/` the SwiftUI app (iOS 26+). `Logic/` is pure Swift, checked by `check.swift`.
- `supabase/` migrations, edge functions, SQL tests and the App Review seed.
- `bridge/` the WhatsApp bridge that verifies phone numbers (reverse OTP), run on a VPS.
- `ops/` the menu scraper, the WhatsApp QR helper and release files. `legal/` privacy policy, terms, support.

Ataste is an independent app and is not affiliated with Atas Artisan.
