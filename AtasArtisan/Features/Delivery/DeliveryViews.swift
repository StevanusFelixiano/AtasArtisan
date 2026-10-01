import SwiftUI
import PhotosUI
import Supabase

/// 4.14 Confirm delivery: anyone in the group, with a photo as proof.
struct DeliveryView: View {
    var store: GroupStore
    @Environment(\.dismiss) private var dismiss
    @State private var pick: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var camera = false
    @State private var busy = false
    @State private var problem: Problem?

    var body: some View {
        VStack(spacing: Brand.s5) {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: Brand.rCard))
                    .accessibilityLabel("Delivery photo")
            } else {
                Spacer(minLength: 0)
                Mascot(pose: "pose-delivery", size: 180, fill: Brand.choc100)
                Text("Has the order arrived?").brand(.title1)
                Text("Take a photo of it. Everyone sees it on the order with your name.").brand(.body, Brand.ink2).multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
            if image == nil {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take a photo") { camera = true }.buttonStyle(.pill(.primary))
                }
                PhotosPicker("Choose from library", selection: $pick, matching: .images).buttonStyle(.pill(.secondary, .medium))
            } else {
                Button("Confirm delivered") { Task { await confirm() } }.buttonStyle(.pill(.success)).disabled(busy)
                Button("Retake") { image = nil; pick = nil }.brand(.callout, Brand.caramel)
            }
        }
        .padding(Brand.s5)
        .screen()
        .navigationTitle("Confirm delivery")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .fullScreenCover(isPresented: $camera) { CameraPicker(image: $image).ignoresSafeArea() }
        .onChange(of: pick) { _, item in
            Task { if let d = try? await item?.loadTransferable(type: Data.self) { image = UIImage(data: d) } }
        }
        .problemAlert($problem)
    }

    private func confirm() async {
        guard let image, let raw = image.jpegData(compressionQuality: 0.9), let jpeg = JPEG.compress(raw) else { return }
        busy = true
        defer { busy = false }
        await attempt($problem, "Upload failed") {
            let path = "\(store.id.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
            try await supabase.storage.from("delivery").upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg"))
            try await store.rpc("confirm_delivered", ["g": .string(store.id.uuidString), "path": .string(path)])
            dismiss()
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

/// Delivery photos on the order, with a report action (guideline 1.2: user-generated content).
struct DeliveryPhotos: View {
    var store: GroupStore
    @State private var urls: [UUID: URL] = [:]
    @State private var reporting: DeliveryProof?
    @State private var problem: Problem?

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.s3) {
            Text("Delivered").brand(.label)
            ForEach(store.proofs.filter { !$0.hidden }) { p in
                VStack(alignment: .leading, spacing: Brand.s2) {
                    AsyncImage(url: urls[p.id]) { $0.resizable().scaledToFill() } placeholder: { Brand.liquorice100 }
                        .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: Brand.rSmall))
                        .accessibilityLabel("Delivery photo by \(store.name(p.by_user))")
                    HStack {
                        Text("\(store.name(p.by_user)) · \(Wita.string(p.created_at, "EEE d MMM, HH:mm"))").brand(.footnote, Brand.ink3)
                        Spacer()
                        Button("Report") { reporting = p }.brand(.footnote, Brand.destructive)
                    }
                }
                .task {
                    urls[p.id] = try? await supabase.storage.from("delivery").createSignedURL(path: p.path, expiresIn: 3600)
                }
            }
        }
        .card()
        .alert("Report this photo?", isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } })) {
            Button("Report and hide", role: .destructive) {
                if let p = reporting {
                    Task { await attempt($problem, "Couldn't report") { try await store.rpc("report_photo", ["proof": .string(p.id.uuidString)]) } }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("It's hidden for everyone in the group, and we review it.") }
        .problemAlert($problem)
    }
}
