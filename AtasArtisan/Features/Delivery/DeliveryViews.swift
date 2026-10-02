import SwiftUI
import PhotosUI
import Supabase

/// 4.14 Confirm delivery: anyone in the group, with a photo as proof. 5-11 is the system camera; 5-12 the preview.
struct DeliveryView: View {
    var store: GroupStore
    @Environment(\.dismiss) private var dismiss
    @State private var pick: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var camera = false
    @State private var busy = false
    @State private var problem: Problem?
    /// The JPEG of an upload that failed, kept for "Try again" (6-9's pattern).
    @State private var failed: Data?
    /// The photo's upload, drawn over it as on the receipt (Motion board 18); its button gives the haptics.
    @State private var photoUpload: UploadState?
    @State private var retries = 0

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        Group {
            if let image { preview(image) } else { intro }
        }
        .screen()
        .navigationTitle("Confirm delivery")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } } }
        .fullScreenCover(isPresented: $camera) { CameraPicker(image: $image).ignoresSafeArea().background(Color.black) }
        .onChange(of: pick) { _, item in
            Task { if let d = try? await item?.loadTransferable(type: Data.self) { image = UIImage(data: d) } }
        }
        .onChange(of: image) { _, _ in
            failed = nil
            photoUpload = nil
        }
        .sensoryFeedback(Haptic.tap, trigger: retries)
        .problemAlert($problem)
        #if DEBUG
        .onAppear {
            // Screenshot hook for 5-12: a stand-in photo instead of the camera.
            if DebugScreens.value("ATASTE_DELIVERY_PHOTO") != nil { image = UIImage(named: "pose-cakebox") }
        }
        #endif
    }

    // MARK: Before the photo

    private var intro: some View {
        VStack(spacing: Brand.s4) {
            Spacer(minLength: 0)
            Mascot(pose: "pose-delivery", size: 180, fill: Brand.choc100)
            Text("Has the order arrived?").font(Type5.roundo(28)).foregroundStyle(Brand.cocoa).multilineTextAlignment(.center)
            Text("Take a photo of it. Everyone sees it on the order with your name.")
                .font(Type5.manrope(15)).lineSpacing(1).foregroundStyle(Brand.ink2).multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Brand.s5)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if cameraAvailable { Button("Take a photo", systemImage: "camera") { camera = true }.buttonStyle(.pill(.primary)) }
                PhotosPicker(selection: $pick, matching: .images) { Label("Choose from library", systemImage: "photo") }
                    .buttonStyle(.pill(cameraAvailable ? .secondary : .primary))
            }
            .padding(.horizontal, Brand.s4)
            .padding(.bottom, 10)
        }
    }

    // MARK: 5-12 Preview

    private func preview(_ image: UIImage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Brand.liquorice100
                    .frame(height: 440)
                    .overlay { Image(uiImage: image).resizable().scaledToFill() }
                    .clipShape(RoundedRectangle(cornerRadius: Brand.rHero, style: .continuous))
                    .modifier(UploadOverlay(state: photoUpload, radius: Brand.rHero, badge: false))
                    // A failed upload: tapping the photo tries again.
                    .onTapGesture {
                        guard photoUpload == .failed, !busy else { return }
                        retries += 1
                        Task { await retryUpload() }
                    }
                    .accessibilityLabel("Delivery photo")
                    .accessibilityAddTraits(photoUpload == .failed ? .isButton : [])
                    .accessibilityHint(photoUpload == .failed ? "Uploads the photo again" : "")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Everything arrived?").font(Type5.roundo(22)).foregroundStyle(Brand.cocoa)
                    Text(closing).font(Type5.manrope(14)).lineSpacing(1).foregroundStyle(Brand.ink2)
                }
                .padding(.horizontal, 4)
                if let failed {
                    UploadFailedCard(image: UIImage(data: failed)) { Task { await retryUpload() } }.disabled(busy)
                }
            }
            .padding(.horizontal, Brand.s4)
            .padding(.top, 12)
            .padding(.bottom, Brand.s4)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(alignment: .bottom, spacing: 10) {
                Button("Retake") {
                    self.image = nil
                    pick = nil
                    if cameraAvailable { camera = true }
                }
                .buttonStyle(WidePill(fill: Brand.cream, ink: Brand.cocoa, border: Brand.choc100))
                .disabled(busy)
                // A 1 : 1.6 split: the shared large pill's 32 pt side padding would truncate the label, so it's tight.
                AsyncPill(title: "Confirm delivered", icon: "checkmark", busyTitle: "Confirming…", doneTitle: "Delivered",
                          failTitle: "Couldn’t confirm delivery", tight: true,
                          refresh: store.refresh, reached: { store.group?.state == .delivered }) {
                    try await confirm()
                } then: {
                    dismiss()
                }
                .containerRelativeFrame(.horizontal) { w, _ in (w - 42) * 1.6 / 2.6 }
            }
            .padding(.horizontal, Brand.s4)
            .padding(.bottom, 10)
        }
    }

    private var closing: String {
        guard let host = store.group?.host_id else { return "The photo shows on the order with your name." }
        return host == store.me ? "The photo shows on the order with your name. You then close it."
                                : "The photo shows on the order with your name. \(store.name(host)) then closes it."
    }

    /// Uploads the photo (a fresh path each try: the bucket allows insert only), then marks the order delivered.
    /// A failed upload also shows the failed card with the same JPEG. Errors go to the Confirm delivered button.
    private func confirm() async throws {
        guard let jpeg = failed ?? image?.jpegData(compressionQuality: 0.9).flatMap(JPEG.compress) else { throw UploadError.unreadable }
        let path = "\(store.id.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        photoUpload = .uploading
        do {
            try await supabase.storage.from("delivery").upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg"))
            failed = nil
            photoUpload = .done
        } catch {
            if !isCancellation(error) { failed = jpeg }
            photoUpload = .failed
            throw error
        }
        try await store.rpc("confirm_delivered", ["g": .string(store.id.uuidString), "path": .string(path)])
    }

    /// The failed card's Try again: the whole confirm, with an alert if it fails again.
    private func retryUpload() async {
        busy = true
        defer { busy = false }
        await attempt($problem, "Couldn't confirm delivery") {
            try await confirm()
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
                    CachedPhoto(url: urls[p.id], key: p.path, side: 400, fill: Brand.liquorice100)
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
