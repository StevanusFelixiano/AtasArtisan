// Logic checks. Run: rm -f /tmp/atcheck && swiftc -parse-as-library AtasArtisan/Logic/*.swift check.swift -o /tmp/atcheck && /tmp/atcheck
import Foundation

func expect(_ ok: Bool, _ what: String, file: StaticString = #file, line: UInt = #line) {
    if !ok { print("FAIL \(what) (line \(line))"); exit(1) }
}

@main struct Check {
    static func main() {
        // Rupiah
        expect(Rupiah.format(481_000) == "Rp 481.000", "format")
        expect(Rupiah.format(5_500) == "Rp 5.500", "format small")
        expect(Rupiah.short(37_000) == "37k" && Rupiah.short(5_500) == "5.5k", "short")

        // WITA cutoff: 14:59 WITA -> tomorrow 10:00; 15:00 -> day after.
        let c = Wita.calendar
        let before = c.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 14, minute: 59))!
        let after = c.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 15, minute: 0))!
        expect(c.component(.day, from: Wita.defaultDelivery(now: before)) == 3, "delivery tomorrow")
        expect(c.component(.day, from: Wita.defaultDelivery(now: after)) == 4, "delivery after cutoff")
        let fri10 = c.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 10))!
        expect(!Wita.cutoffTooLate(cutoff: c.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 13)), delivery: fri10), "13:00 ok")
        expect(Wita.cutoffTooLate(cutoff: c.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 17)), delivery: fri10), "17:00 late")

        // Options: Classic Sourdough
        let v = [VariantChoice(options: ["Berat": "600gr", "Slice": "Whole Sourdough"], price: 21_000, available: true),
                 VariantChoice(options: ["Berat": "600gr", "Slice": "Sliced 15mm"], price: 21_000, available: true),
                 VariantChoice(options: ["Berat": "1000gr", "Slice": "Whole Sourdough"], price: 33_000, available: true),
                 VariantChoice(options: ["Berat": "1000gr", "Slice": "Sliced 15mm"], price: 33_000, available: false)]
        expect(OptionMatch.variant(["Berat": "1000gr", "Slice": "Whole Sourdough"], groups: ["Berat", "Slice"], variants: v)?.price == 33_000, "price follows pick")
        expect(OptionMatch.choices("Slice", all: ["Whole Sourdough", "Sliced 15mm"], picked: ["Berat": "1000gr"], variants: v) == ["Whole Sourdough"], "sold-out combo hidden")
        expect(OptionMatch.variant(["Berat": "1000gr"], groups: ["Berat", "Slice"], variants: v) == nil, "incomplete pick")

        // Shared items: Burnt Cheesecake 260.000 in 12 pieces, Kevin 3 and Putri 2 (the server's example)
        expect(Pieces.amount(price: 260_000, pieces: 12, n: 3) == 65_000, "joiner pays 3 of 12")
        expect(Pieces.amount(price: 260_000, pieces: 12, n: 2) == 43_333, "joiner rounds down")
        expect(Pieces.ownerAmount(price: 260_000, pieces: 12, claims: [3, 2]) == 151_667, "owner pays the rest")
        expect(Pieces.ownerAmount(price: 260_000, pieces: 12, claims: [3, 2]) + 65_000 + 43_333 == 260_000, "shares add up")
        expect(Pieces.each(price: 260_000, pieces: 12) == 21_667, "price a piece")
        expect(Pieces.defaultCount("Burnt Cheesecake 20 cm") == 12 && Pieces.defaultCount("New York Cheesecakes 20 x 20 cm") == 16
               && Pieces.defaultCount("Classic Sourdough") == 8, "default pieces")
        expect(Pieces.ordinal(3) == "3rd" && Pieces.ordinal(11) == "11th" && Pieces.ordinal(22) == "22nd", "ordinal")

        // The Atas message, golden text in the host's own format.
        let order = AtasOrder(hostName: "Rani", hostPhone: "6281277882210", place: "Apple Developer Academy Bali",
                              mapsURL: "https://maps.app.goo.gl/x", delivery: fri10,
                              people: [("Rani", [AtasLine(name: "Classic Sourdough", options: ["1000gr", "Sliced 15mm"], qty: 1, unitPrice: 33_000, note: ""),
                                                 AtasLine(name: "Butter Croissant", options: [], qty: 2, unitPrice: 12_000, note: "")]),
                                       ("Dimas", [AtasLine(name: "Pain Au Chocolate", options: ["80gr"], qty: 1, unitPrice: 16_000, note: "dihangatkan")]),
                                       ("Nadia", [])])
        let id = AtasMessage.text(order, indonesian: true)
        let want = """
        Nama PIC : Rani
        Nama Cafe : Apple Developer Academy Bali
        No. HP: 081277882210
        Link alamat Cafe: https://maps.app.goo.gl/x
        Tanggal & Jam Pengiriman: 3 Oktober 2026. Jam pengiriman 10.00 WITA
        Item yang dipesan :

        Rani
        1. Classic Sourdough (1kg, slice 1.5cm) @1 - 33k
        2. Butter Croissant @2 - 12k
        Total: 57k

        Dimas
        1. Pain Au Chocolate (80g) @1 - 16k (catatan: dihangatkan)
        Total: 16k

        Total semua: 73k (belum ongkir). Terima kasih!
        """
        if id != want { print(id); print("---want---"); print(want) }
        expect(id == want, "Indonesian message")
        let en = AtasMessage.text(order, indonesian: false)
        expect(en.contains("1. Classic Sourdough (1000gr, Sliced 15mm) @1 - 33k"), "English keeps site labels")
        expect(en.hasPrefix("PIC name: Rani"), "English header")

        print("check.swift: all passed")
    }
}
