import Foundation

// Pure logic: no SwiftUI, no Supabase, so `check.swift` compiles it on its own with swiftc.

// MARK: - Rupiah

nonisolated enum Rupiah {
    /// "Rp 45.000"
    static func format(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "."
        f.usesGroupingSeparator = true
        return "Rp " + (f.string(from: NSNumber(value: n)) ?? "\(n)")
    }

    /// "37k", "5.5k": how hosts write prices to Atas.
    static func short(_ n: Int) -> String {
        if n % 1000 == 0 { return "\(n / 1000)k" }
        let k = Double(n) / 1000
        return String(format: "%g", k) + "k"
    }
}

// MARK: - Bali time and Atas's cutoff

nonisolated enum Wita {
    static let zone = TimeZone(identifier: "Asia/Makassar")!
    /// Atas: orders sent before 15:00 WITA arrive the next morning; after that, up to 2 days.
    static let atasCutoffHour = 15

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c
    }

    /// Tomorrow at 10:00 WITA, or the day after once today's cutoff has passed.
    static func defaultDelivery(now: Date = Date()) -> Date {
        let c = calendar
        let afterCutoff = c.component(.hour, from: now) >= atasCutoffHour
        let day = c.date(byAdding: .day, value: afterCutoff ? 2 : 1, to: c.startOfDay(for: now))!
        return c.date(bySettingHour: 10, minute: 0, second: 0, of: day)!
    }

    /// The moment the order must reach Atas for a delivery at `delivery`: 15:00 WITA the day before.
    static func atasDeadline(for delivery: Date) -> Date {
        let c = calendar
        let dayBefore = c.date(byAdding: .day, value: -1, to: c.startOfDay(for: delivery))!
        return c.date(bySettingHour: atasCutoffHour, minute: 0, second: 0, of: dayBefore)!
    }

    /// The group's own cutoff is later than Atas's: delivery may slip.
    static func cutoffTooLate(cutoff: Date?, delivery: Date) -> Bool {
        guard let cutoff else { return false }
        return cutoff > atasDeadline(for: delivery)
    }

    static func isPastTodaysCutoff(_ now: Date = Date()) -> Bool {
        calendar.component(.hour, from: now) >= atasCutoffHour
    }

    static func string(_ d: Date, _ format: String, id: Bool = false) -> String {
        let f = DateFormatter()
        f.timeZone = zone
        f.locale = Locale(identifier: id ? "id_ID" : "en_GB")
        f.dateFormat = format
        return f.string(from: d)
    }
}

// MARK: - Atas delivery areas

nonisolated enum Areas {
    static let all = ["Denpasar", "Canggu", "Tabanan", "Kerobokan", "Pererenan", "Seminyak", "Kuta", "Uluwatu",
                      "Jimbaran", "Nusa Dua", "Ubud", "Sanur", "Nusa Penida", "Nusa Lembongan"]
}

// MARK: - Product options

nonisolated struct VariantChoice: Hashable {
    var options: [String: String]
    var price: Int
    var available: Bool
}

nonisolated enum OptionMatch {
    /// Choices in `group` that still lead to an available variant, given the other picks.
    static func choices(_ group: String, all: [String], picked: [String: String], variants: [VariantChoice]) -> [String] {
        all.filter { choice in
            var trial = picked
            trial[group] = choice
            return variants.contains { v in
                v.available && trial.allSatisfy { k, val in v.options[k] == nil || v.options[k] == val }
            }
        }
    }

    /// The variant for a complete pick, or nil while a group is still unpicked.
    static func variant(_ picked: [String: String], groups: [String], variants: [VariantChoice]) -> VariantChoice? {
        guard groups.allSatisfy({ picked[$0] != nil }) else { return nil }
        return variants.first { $0.options == picked }
    }

    /// First available variant: a sensible starting pick.
    static func defaultPick(variants: [VariantChoice]) -> [String: String] {
        (variants.first { $0.available } ?? variants.first)?.options ?? [:]
    }
}

// MARK: - The WhatsApp order to Atas

nonisolated struct AtasLine: Hashable {
    var name: String
    var options: [String]      // in the product's option-group order
    var qty: Int
    var unitPrice: Int
    var note: String
}

nonisolated struct AtasOrder {
    var hostName: String
    var hostPhone: String      // 62812…
    var place: String          // "Apple Developer Academy Bali"
    var address: String = ""   // street detail, its own line when set
    var mapsURL: String
    var delivery: Date
    var people: [(name: String, lines: [AtasLine])]
}

nonisolated enum AtasMessage {
    /// Indonesian by default, in the format hosts already send Atas (user's template, 2026-10-01).
    /// Product names stay as Atas writes them; option labels read the way hosts write them in Indonesian.
    static func text(_ o: AtasOrder, indonesian: Bool) -> String {
        var out: [String] = []
        let phone = o.hostPhone.hasPrefix("62") ? "0" + o.hostPhone.dropFirst(2) : o.hostPhone
        if indonesian {
            out.append("Nama PIC : \(o.hostName)")
            out.append("Nama Cafe : \(o.place)")
            out.append("No. HP: \(phone)")
            if !o.address.isEmpty { out.append("Alamat: \(o.address)") }
            out.append("Link alamat Cafe: \(o.mapsURL.isEmpty ? "-" : o.mapsURL)")
            out.append("Tanggal & Jam Pengiriman: \(Wita.string(o.delivery, "d MMMM yyyy", id: true)). Jam pengiriman \(Wita.string(o.delivery, "HH.mm")) WITA")
            out.append("Item yang dipesan :")
        } else {
            out.append("PIC name: \(o.hostName)")
            out.append("Place: \(o.place)")
            out.append("Phone: \(phone)")
            if !o.address.isEmpty { out.append("Address: \(o.address)") }
            out.append("Address link: \(o.mapsURL.isEmpty ? "-" : o.mapsURL)")
            out.append("Delivery: \(Wita.string(o.delivery, "d MMMM yyyy")), \(Wita.string(o.delivery, "HH:mm")) WITA")
            out.append("Items:")
        }
        var grand = 0
        for person in o.people where !person.lines.isEmpty {
            out.append("")
            out.append(person.name)
            var sum = 0
            for (i, l) in person.lines.enumerated() {
                let opts = l.options.map { indonesian ? idLabel($0) : $0 }
                var line = "\(i + 1). \(l.name)"
                if !opts.isEmpty { line += " (\(opts.joined(separator: ", ")))" }
                line += " @\(l.qty) - \(Rupiah.short(l.unitPrice))"
                if !l.note.isEmpty { line += indonesian ? " (catatan: \(l.note))" : " (note: \(l.note))" }
                out.append(line)
                sum += l.unitPrice * l.qty
            }
            out.append("Total: \(Rupiah.short(sum))")
            grand += sum
        }
        out.append("")
        out.append(indonesian ? "Total semua: \(Rupiah.short(grand)) (belum ongkir). Terima kasih!"
                              : "Grand total: \(Rupiah.short(grand)) (before delivery). Thank you!")
        return out.joined(separator: "\n")
    }

    /// "1000gr" -> "1kg", "Sliced 15mm" -> "slice 1.5cm", "Whole Sourdough"/"Unsliced" -> "utuh".
    static func idLabel(_ s: String) -> String {
        switch s {
        case "Sliced 15mm": return "slice 1.5cm"
        case "Whole Sourdough", "Unsliced": return "utuh"
        default:
            if s.hasSuffix("gr"), let g = Int(s.dropLast(2)), g % 1000 == 0 { return "\(g / 1000)kg" }
            if s.hasSuffix("gr") { return String(s.dropLast(2)) + "g" }
            return s
        }
    }
}
