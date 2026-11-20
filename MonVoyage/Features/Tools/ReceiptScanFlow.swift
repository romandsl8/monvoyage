import SwiftUI
import PhotosUI
import Vision
import VisionKit

/// Scan de ticket : appareil photo (VisionKit) ou photothèque, OCR sur l'iPhone,
/// puis l'utilisateur valide ou corrige dans l'éditeur de dépense.
struct ReceiptScanFlow: View {
    @ObservedObject var trip: Trip
    @EnvironmentObject private var nav: TripNavigation
    @Environment(\.dismiss) private var dismiss
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var analyzing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "doc.viewfinder")
                    .font(.system(size: 64))
                    .foregroundStyle(trip.accent)
                    .accessibilityHidden(true)
                Text("Scanner un ticket").font(.title2.bold()).fontDesign(.rounded)
                Text("Le total, la date et le commerçant sont repérés sur l'iPhone, sans connexion. Vous vérifiez avant d'enregistrer.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                if analyzing { ProgressView("Lecture du ticket…") }
                if let error { Text(error).foregroundStyle(.orange).font(.footnote) }
                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        if VNDocumentCameraViewController.isSupported {
                            Button { showCamera = true } label: {
                                Label("Prendre en photo", systemImage: "camera.fill").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glassProminent)
                        }
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Choisir dans Photos", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 500)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } } }
            .fullScreenCover(isPresented: $showCamera) {
                DocumentCamera { image in
                    showCamera = false
                    if let image { Task { await analyze(image) } }
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                    await analyze(image)
                }
            }
        }
    }

    private func analyze(_ image: UIImage) async {
        analyzing = true
        defer { analyzing = false }
        let lines = await ReceiptOCR.recognize(image)
        let parsed = ReceiptParser.parse(lines: lines)
        if lines.isEmpty { error = "Aucun texte reconnu. Vous pouvez saisir la dépense à la main." }
        let jpeg = image.jpegData(compressionQuality: 0.8).map { ImageCompression.jpeg($0) }
        let prefill = ExpensePrefill(title: parsed.merchant ?? "", amount: parsed.total,
                                     currency: parsed.currency ?? (trip.isOngoing() ? trip.currencyCode : "EUR"),
                                     date: parsed.date ?? Date(), merchant: parsed.merchant, receipt: jpeg)
        nav.present(.newExpense(prefill))
    }
}

/// Reconnaissance de texte (français + anglais), entièrement sur l'appareil.
enum ReceiptOCR {
    static func recognize(_ image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["fr-FR", "en-US"]
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: [])
                    return
                }
                let observations = request.results ?? []
                // Tri de haut en bas (coordonnées Vision : origine en bas à gauche).
                let sorted = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                continuation.resume(returning: mergeRows(sorted))
            }
        }
    }

    /// Regroupe les observations sur la même ligne (libellé à gauche, montant à droite).
    private static func mergeRows(_ observations: [VNRecognizedTextObservation]) -> [String] {
        var rows: [(y: CGFloat, parts: [(x: CGFloat, text: String)])] = []
        for obs in observations {
            guard let text = obs.topCandidates(1).first?.string else { continue }
            let y = obs.boundingBox.midY
            if let index = rows.firstIndex(where: { abs($0.y - y) < obs.boundingBox.height * 0.5 }) {
                rows[index].parts.append((x: obs.boundingBox.minX, text: text))
            } else {
                rows.append((y: y, parts: [(x: obs.boundingBox.minX, text: text)]))
            }
        }
        return rows.map { row in row.parts.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ") }
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// Caméra de numérisation de documents (VisionKit).
struct DocumentCamera: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let completion: (UIImage?) -> Void
        init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            completion(scan.pageCount > 0 ? scan.imageOfPage(at: 0) : nil)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            completion(nil)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            completion(nil)
        }
    }
}
