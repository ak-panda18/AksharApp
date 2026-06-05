import UIKit
import Vision
import PDFKit
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AksharApp", category: "OCRManager")

final class OCRManager {

    // MARK: - Properties
    private(set) var documents: [StoredDoc] = []
    private let thumbnailsCache = NSCache<NSString, UIImage>()

    private let fileManager    = FileManager.default
    private let indexFileName  = "index.json"

    private let childManager: ChildManager
    private var lastLoadedChildId: String?
    private var activeDocumentsURL: URL!

    init(childManager: ChildManager) {
        self.childManager = childManager
        thumbnailsCache.countLimit = 100  
        ensureIndexLoaded()
    }

    // MARK: - Dynamic Index Scoping
    private func ensureIndexLoaded() {
        let currentId = childManager.currentChild.id?.uuidString ?? "default"
        if lastLoadedChildId != currentId {
            lastLoadedChildId = currentId
            activeDocumentsURL = getDocumentsURL(for: currentId)
            loadIndex(for: currentId)
        }
    }

    private func getDocumentsURL(for childId: String) -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("ocr_scans_\(childId)")
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    // MARK: - Data Access
    func getAllDocuments() -> [StoredDoc] {
        ensureIndexLoaded()
        return documents
    }

    func getThumbnail(for doc: StoredDoc) -> UIImage? {
        ensureIndexLoaded()
        let key = doc.id as NSString
        if let cached = thumbnailsCache.object(forKey: key) { return cached }
        let url = activeDocumentsURL.appendingPathComponent(doc.thumbnailFileName)
        if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
            thumbnailsCache.setObject(img, forKey: key)
            return img
        }
        return nil
    }

    func getPages(for doc: StoredDoc) -> [String]? {
        ensureIndexLoaded()
        guard let pagesFile = doc.pagesFileName else { return nil }
        guard let data = try? Data(contentsOf: activeDocumentsURL.appendingPathComponent(pagesFile)) else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    // MARK: - Process New Scan
    func processNewDocument(images: [UIImage], completion: @escaping (StoredDoc) -> Void) {
        ensureIndexLoaded()
        let targetDocumentsURL = activeDocumentsURL!
        let targetChildId = lastLoadedChildId ?? "default"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let ocrPages = self.recognizeTextPerPage(in: images)
            let id       = UUID().uuidString

            let fileName  = self.saveDocumentImages(images, id: id, at: targetDocumentsURL)
            let thumbName = self.saveThumbnail(from: images.first, id: id, at: targetDocumentsURL)
            let pagesName = self.savePagesJSON(ocrPages, id: id, at: targetDocumentsURL)
            let textName  = self.saveFullText(ocrPages, id: id, at: targetDocumentsURL)

            let newDoc = StoredDoc(
                id: id, title: "Untitled", createdDate: Date(),
                fileName: fileName, thumbnailFileName: thumbName,
                ocrTextFileName: textName, pagesFileName: pagesName
            )

            DispatchQueue.main.async {
                self.ensureIndexLoaded()
                if self.lastLoadedChildId == targetChildId {
                    self.documents.insert(newDoc, at: 0)
                    if let first = images.first {
                        if let thumb = self.makeThumbnail(from: first, maxSide: 140) {
                            self.thumbnailsCache.setObject(thumb, forKey: id as NSString)
                        }
                    }
                    self.saveIndex()
                    completion(newDoc)
                } else {
                    self.insertDocAndSaveIndex(newDoc, for: targetChildId, targetURL: targetDocumentsURL)
                }
            }
        }
    }

    private func insertDocAndSaveIndex(_ doc: StoredDoc, for childId: String, targetURL: URL) {
        let indexURL = targetURL.appendingPathComponent(indexFileName)
        var childDocs: [StoredDoc] = []
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([StoredDoc].self, from: data) {
            childDocs = decoded
        }
        childDocs.insert(doc, at: 0)
        if let data = try? JSONEncoder().encode(childDocs) {
            try? data.write(to: indexURL)
        }
    }

    // MARK: - Document Actions
    func renameDocument(docId: String, newTitle: String) {
        ensureIndexLoaded()
        guard let i = documents.firstIndex(where: { $0.id == docId }) else { return }
        documents[i].title = newTitle
        saveIndex()
    }

    func deleteDocument(docId: String) {
        ensureIndexLoaded()
        guard let i = documents.firstIndex(where: { $0.id == docId }) else { return }
        let doc = documents.remove(at: i)
        thumbnailsCache.removeObject(forKey: doc.id as NSString)
        [doc.fileName, doc.thumbnailFileName, doc.pagesFileName, doc.ocrTextFileName]
            .compactMap { $0 }
            .forEach { try? fileManager.removeItem(at: activeDocumentsURL.appendingPathComponent($0)) }
        saveIndex()
    }

    func duplicateDocument(docId: String) {
        ensureIndexLoaded()
        guard let i = documents.firstIndex(where: { $0.id == docId }) else { return }
        var copy  = documents[i]
        let newId = UUID().uuidString
        copy.id    = newId
        copy.title += " Copy"

        let ext = copy.fileName.hasSuffix(".pdf") ? ".pdf" : ".png"
        let newFile = newId + ext
        try? fileManager.copyItem(at: activeDocumentsURL.appendingPathComponent(copy.fileName),
                                  to: activeDocumentsURL.appendingPathComponent(newFile))
        copy.fileName = newFile

        let newThumb = "\(newId)_thumb.png"
        try? fileManager.copyItem(at: activeDocumentsURL.appendingPathComponent(copy.thumbnailFileName),
                                  to: activeDocumentsURL.appendingPathComponent(newThumb))
        copy.thumbnailFileName = newThumb

        if let pages = copy.pagesFileName {
            let newPages = "pages_\(newId).json"
            try? fileManager.copyItem(at: activeDocumentsURL.appendingPathComponent(pages),
                                      to: activeDocumentsURL.appendingPathComponent(newPages))
            copy.pagesFileName = newPages
        }
        if let txt = copy.ocrTextFileName {
            let newTxt = "\(newId).txt"
            try? fileManager.copyItem(at: activeDocumentsURL.appendingPathComponent(txt),
                                      to: activeDocumentsURL.appendingPathComponent(newTxt))
            copy.ocrTextFileName = newTxt
        }

        documents.insert(copy, at: 0)
        if let img = thumbnailsCache.object(forKey: docId as NSString) {
            thumbnailsCache.setObject(img, forKey: newId as NSString)
        }
        saveIndex()
    }

    func reset() {
        documents.removeAll()
        thumbnailsCache.removeAllObjects()
        lastLoadedChildId = nil
        activeDocumentsURL = nil
    }

    // MARK: - Index Persistence
    private func saveIndex() {
        if let data = try? JSONEncoder().encode(documents) {
            try? data.write(to: activeDocumentsURL.appendingPathComponent(indexFileName))
        }
    }

    private func loadIndex(for childId: String) {
        documents.removeAll()
        thumbnailsCache.removeAllObjects()

        let url = activeDocumentsURL.appendingPathComponent(indexFileName)
        guard let data = try? Data(contentsOf: url),
              let docs = try? JSONDecoder().decode([StoredDoc].self, from: data) else { return }
        documents = docs
        // Warm the cache on load (lightweight pass — only loads thumbnails that are already on disk)
        docs.forEach { doc in
            if let data = try? Data(contentsOf: activeDocumentsURL.appendingPathComponent(doc.thumbnailFileName)),
               let img = UIImage(data: data) {
                thumbnailsCache.setObject(img, forKey: doc.id as NSString)
            }
        }
    }

    // MARK: - OCR
    private func recognizeTextPerPage(in images: [UIImage]) -> [String] {
        images.map { image in
            guard let cg = image.cgImage else { return "" }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel       = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages   = ["en-AU"]

            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            guard (try? handler.perform([request])) != nil,
                  let observations = request.results, !observations.isEmpty else { return "" }

            let xMins = observations.map { $0.boundingBox.minX }.sorted()
            let xMaxs = observations.map { $0.boundingBox.maxX }.sorted()
            let medianMinX = xMins[xMins.count / 2]
            let medianMaxX = xMaxs[xMaxs.count / 2]
            let pageWidth  = medianMaxX - medianMinX
            let blockCenter = medianMinX + (pageWidth / 2)

            var fullText = ""
            var prev: VNRecognizedTextObservation?

            for obs in observations {
                guard let candidate = obs.topCandidates(1).first else { continue }
                var text = candidate.string

                let isCentered = obs.boundingBox.width < (pageWidth * 0.85)
                    && abs(obs.boundingBox.midX - blockCenter) < (pageWidth * 0.15)
                if isCentered { text = "<CENTER>" + text }

                if let p = prev {
                    let gap         = p.boundingBox.minY - obs.boundingBox.maxY
                    let isPrevShort = p.boundingBox.maxX < (medianMaxX - (pageWidth * 0.15))
                    let isBigGap    = gap > (p.boundingBox.height * 1.3)
                    let isIndented  = !isCentered && (obs.boundingBox.minX > (medianMinX + (pageWidth * 0.05)))

                    var isHyphenated = false
                    if let lastIdx = fullText.lastIndex(where: { !$0.isWhitespace }),
                       fullText[lastIdx] == "-" {
                        isHyphenated = true
                        fullText = String(fullText[..<lastIdx])
                    }

                    if isHyphenated                               { fullText += text }
                    else if isCentered                            { fullText += "\n\n" + text }
                    else if isBigGap || isPrevShort || isIndented { fullText += "\n\n" + text }
                    else                                          { fullText += " " + text }
                } else {
                    fullText = text
                }
                prev = obs
            }
            return fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: - File Saving Helpers
    private func saveDocumentImages(_ images: [UIImage], id: String, at url: URL) -> String {
        if images.count > 1 {
            let name = "\(id).pdf"
            if let first = images.first {
                let rect = CGRect(origin: .zero, size: first.size)
                let data = UIGraphicsPDFRenderer(bounds: rect).pdfData { ctx in
                    images.forEach { ctx.beginPage(); $0.draw(in: rect) }
                }
                try? data.write(to: url.appendingPathComponent(name))
            }
            return name
        } else {
            let name = "\(id).png"
            if let data = images.first?.jpegData(compressionQuality: 0.9) {
                try? data.write(to: url.appendingPathComponent(name))
            }
            return name
        }
    }

    private func saveThumbnail(from image: UIImage?, id: String, at url: URL) -> String {
        let name = "\(id)_thumb.png"
        if let img = image, let thumb = makeThumbnail(from: img, maxSide: 140),
           let data = thumb.pngData() {
            try? data.write(to: url.appendingPathComponent(name))
        }
        return name
    }

    private func makeThumbnail(from image: UIImage?, maxSide: CGFloat) -> UIImage? {
        guard let image else { return nil }
        let aspect = image.size.width / image.size.height
        let size: CGSize = aspect >= 1
            ? CGSize(width: maxSide, height: maxSide / aspect)
            : CGSize(width: maxSide * aspect, height: maxSide)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func savePagesJSON(_ pages: [String], id: String, at url: URL) -> String {
        let name = "pages_\(id).json"
        if let data = try? JSONEncoder().encode(pages) {
            try? data.write(to: url.appendingPathComponent(name))
        }
        return name
    }

    private func saveFullText(_ pages: [String], id: String, at url: URL) -> String? {
        let text = pages.joined(separator: "\n\n")
        guard !text.isEmpty else { return nil }
        let name = "\(id).txt"
        try? text.data(using: .utf8)?.write(to: url.appendingPathComponent(name))
        return name
    }
}
