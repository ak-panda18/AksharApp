import UIKit
import VisionKit
import PhotosUI

class UploadsViewController: UIViewController {

    @IBOutlet weak var selectButton: UIButton!
    @IBOutlet weak var searchButton: UIButton!
    @IBOutlet weak var collectionView: UICollectionView!
    
    // MARK: - Injected
    var ocrManager: OCRManager!
    var storyManager: StoryManager!
    var childManager: ChildManager!
    var checkpointHistoryManager: CheckpointHistoryManager!
    var skipManager: SkipManager!
    
    private var isSelectionMode = false
    private var selectedDocIds: Set<String> = []

    private var isSearching: Bool = false
    private var filteredDocs: [StoredDoc] = []
    private var searchBar: UISearchBar?
    private var dismissTapGesture: UITapGestureRecognizer?
    
    private lazy var fallbackPlusImage: UIImage? = placeholderPlusImage()
    
    private var currentDocs: [StoredDoc] {
        if isSearching {
            return filteredDocs
        }
        return ocrManager.getAllDocuments()
    }
    
    // MARK: - Lifecycle
    private func verifyDependencies() {
        assert(ocrManager != nil, "ocrManager was not injected into \(type(of: self))")
        assert(storyManager != nil, "storyManager was not injected into \(type(of: self))")
        assert(childManager != nil, "childManager was not injected into \(type(of: self))")
        assert(checkpointHistoryManager != nil, "checkpointHistoryManager was not injected into \(type(of: self))")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        verifyDependencies()
        
        collectionView.allowsMultipleSelection = true
        
        collectionView.dataSource = self
        collectionView.delegate = self
        
        configureCollectionLayout()
        setupSearch()
        
        updateSelectButtonTitle("Select")
        updateSelectButtonState()
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(hideSearchIfNeeded))
        tap.cancelsTouchesInView = false
        tap.delegate = self

        dismissTapGesture = tap

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudDocumentsDidSync),
            name: .coreDataDidSyncFromCloud,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func iCloudDocumentsDidSync() {
        updateSelectButtonState()
        collectionView.reloadData()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
        searchBar?.resignFirstResponder()
        searchBar?.text = ""
        searchBar?.isHidden = true
        isSearching = false
        filteredDocs.removeAll()
        updateSelectButtonState()
        collectionView.reloadData()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView.collectionViewLayout.invalidateLayout()
        selectButton.layer.cornerRadius = 30
    }

    // MARK: - Layout Configuration (Restored)
    private func configureCollectionLayout() {
        guard let flow = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        flow.sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        flow.minimumInteritemSpacing = 16
        flow.minimumLineSpacing = 8
        flow.estimatedItemSize = .zero
    }
    
    private func exitSelectionMode() {

        isSelectionMode = false
        selectedDocIds.removeAll()

        updateSelectButtonTitle("Select")
        searchButton.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)

        collectionView.reloadData()
    }
    
    private func updateSelectButtonState() {

        let hasDocuments = !ocrManager.getAllDocuments().isEmpty

        selectButton.isEnabled = hasDocuments
        selectButton.alpha = hasDocuments ? 1.0 : 0.5
    }
    // MARK: - Actions
    @IBAction func homeTapped(_ sender: UIButton) {
        navigationController?.popToRootViewController(animated: true)
    }

    @IBAction func searchTapped(_ sender: UIButton) {

        if isSelectionMode {
            exitSelectionMode()
            return
        }

        searchBar?.isHidden = false
        searchBar?.becomeFirstResponder()

        if let tap = dismissTapGesture {
            view.addGestureRecognizer(tap)
        }
    }
    
    @IBAction func selectTapped(_ sender: UIButton) {

        if isSelectionMode && !selectedDocIds.isEmpty {

            let alert = UIAlertController(
                title: "Delete Documents?",
                message: "Are you sure you want to delete \(selectedDocIds.count) documents?",
                preferredStyle: .alert
            )

            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

            alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in

                for id in self.selectedDocIds {
                    self.ocrManager.deleteDocument(docId: id)
                }

                self.exitSelectionMode()
                self.updateSelectButtonState()
            })

            present(alert, animated: true)
            return
        }

        isSelectionMode = true
        selectedDocIds.removeAll()

        updateSelectButtonTitle("Delete")
        searchButton.setImage(UIImage(systemName: "checkmark"), for: .normal)

        collectionView.reloadData()
    }
    
    // MARK: - Add Document Logic
    private func presentAddOptions() {
        let alert = UIAlertController(title: "Add Document", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Scan with Camera", style: .default) { _ in self.presentScanner() })
        alert.addAction(UIAlertAction(title: "Choose from Photos", style: .default) { _ in self.presentPhotoPicker() })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    // MARK: - Handlers
    
    private func showNoTextDetectedAlert() {
        let alert = UIAlertController(
            title: "No Text Detected",
            message: "We couldn't detect any readable text in the selected images. Please try scanning a clearer document.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        present(alert, animated: true)
    }
    
    private func handleNewImages(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        
        ocrManager.processNewDocument(images: images) { [weak self] newDoc in
            
            guard let self = self else { return }
            
            guard let pages = ocrManager.getPages(for: newDoc),
                  pages.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                
                ocrManager.deleteDocument(docId: newDoc.id)
                
                self.showNoTextDetectedAlert()
                return
            }
            
            let uniqueTitle = self.generateUniqueTitle(base: "Untitled")
            ocrManager.renameDocument(docId: newDoc.id, newTitle: uniqueTitle)

            self.collectionView.reloadData()
            self.updateSelectButtonState()
            self.promptForTitle(docId: newDoc.id, currentTitle: uniqueTitle)
        }
    }
    
    private func promptForTitle(docId: String, currentTitle: String) {

        let alert = UIAlertController(
            title: "Document Saved",
            message: "Give it a title",
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.text = currentTitle
            textField.clearButtonMode = .whileEditing
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            
            guard let text = alert.textFields?.first?.text?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return }

            let existingTitles = self.ocrManager
                .getAllDocuments()
                .filter { $0.id != docId }
                .map { $0.title.lowercased() }

            if existingTitles.contains(text.lowercased()) {
                self.showDuplicateTitleAlert {
                    self.promptForTitle(docId: docId, currentTitle: text)
                }
                return
            }

            self.ocrManager.renameDocument(docId: docId, newTitle: text)
            self.collectionView.reloadData()
        })

        present(alert, animated: true)
    }
    
    private func showDuplicateTitleAlert(onDismiss: @escaping () -> Void) {
        let alert = UIAlertController(
            title: "Name Already Exists",
            message: "Please choose a different name.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            onDismiss()
        })
        
        present(alert, animated: true)
    }
    
    private func openDocument(at index: Int) {
        let doc = currentDocs[index]
        
        if let pages = ocrManager.getPages(for: doc), !pages.isEmpty {
            if let vc = storyboard?.instantiateViewController(withIdentifier: "LabelReadingVC") as? LabelReadingViewController {
                vc.scannedPages             = pages
                vc.scannedTitle             = doc.title
                vc.currentIndex             = 0
                vc.storyTextString          = pages[0]
                vc.storyManager             = storyManager
                vc.childManager             = childManager
                vc.checkpointHistoryManager = checkpointHistoryManager
                vc.skipManager              = skipManager
                navigationController?.pushViewController(vc, animated: true)
            }
        }
    }
    
    private func generateUniqueTitle(base: String) -> String {

        let existingTitles = ocrManager
            .getAllDocuments()
            .map { $0.title.lowercased() }
        
        if !existingTitles.contains(base.lowercased()) {
            return base
        }

        var counter = 1
        var newTitle = "\(base) \(counter)"

        while existingTitles.contains(newTitle.lowercased()) {
            counter += 1
            newTitle = "\(base) \(counter)"
        }

        return newTitle
    }

}

// MARK: - Collection View DataSource
extension UploadsViewController: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }
    
    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        return currentDocs.count + 1
    }
    
    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "UploadCell", for: indexPath) as? UploadsCollectionViewCell else {
            return UICollectionViewCell()
        }

        cell.containerView.layer.cornerRadius = 16
        cell.containerView.clipsToBounds = true

        if indexPath.item == 0 {

            cell.titleLabel.text = "New File"
            cell.dateLabel.text = ""
            cell.titleLabel.font = UIFont.systemFont(ofSize: 18, weight: .regular)

            cell.containerView.backgroundColor = .clear

            cell.imageView.layer.borderWidth = 1
            cell.imageView.layer.borderColor = UIColor.systemGray4.cgColor
            cell.imageView.layer.cornerRadius = 8
            cell.imageView.clipsToBounds = true

            cell.imageView.image = UIImage(systemName: "plus")
            cell.imageView.preferredSymbolConfiguration =
                UIImage.SymbolConfiguration(pointSize: 35, weight: .regular)

            cell.imageView.contentMode = .center
            cell.imageView.tintColor = .systemYellow

            cell.titleLabel.transform = CGAffineTransform(translationX: 0, y: 8)
        } else {
            
            cell.dateLabel.isHidden = false
            cell.titleLabel.transform = .identity

            let doc = currentDocs[indexPath.item - 1]
            cell.representedDocId = doc.id
            cell.titleLabel.text = doc.title
            cell.dateLabel.text = doc.dateText

            let isSelected = selectedDocIds.contains(doc.id)

            cell.updateSelectionUI(
                isSelecting: isSelectionMode,
                isSelected: isSelected
            )

            cell.titleLabel.font = UIFont.systemFont(ofSize: 18, weight: .regular)
            cell.containerView.backgroundColor = .clear

            cell.imageView.layer.borderWidth = 0
            cell.imageView.layer.borderColor = nil
            cell.imageView.layer.cornerRadius = 0

            if let thumb = ocrManager.getThumbnail(for: doc) {
                cell.imageView.image = thumb
            } else {
                cell.imageView.image = UIImage(systemName: "doc.text")
            }

            cell.imageView.contentMode = .scaleAspectFit
        }

        cell.titleLabel.textAlignment = .center
        cell.dateLabel.textAlignment = .center

        return cell
    }
}

// MARK: - Collection View Delegate & Layout
extension UploadsViewController: UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {

        if isSelectionMode {

            if indexPath.item == 0 { return }

            let doc = currentDocs[indexPath.item - 1]

            if selectedDocIds.contains(doc.id) {

                selectedDocIds.remove(doc.id)
                collectionView.deselectItem(at: indexPath, animated: false)

            } else {

                selectedDocIds.insert(doc.id)

            }

            collectionView.reloadItems(at: [indexPath])
            return
        }

        if indexPath.item == 0 {
            presentAddOptions()
        } else {
            openDocument(at: indexPath.item - 1)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {

        let padding: CGFloat = 16
        let spacing: CGFloat = 16

        let totalSpacing = padding * 2 + spacing * 2
        let width = (collectionView.bounds.width - totalSpacing) / 3

        return CGSize(width: width, height: 210)
    }
    
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard indexPath.item > 0 else { return nil }
        let index = indexPath.item - 1
        let doc = currentDocs[index]
        
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let delete = UIAction(
                title: "Delete",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                
                let confirmAlert = UIAlertController(
                    title: "Delete Document?",
                    message: "Are you sure you want to delete this document? This action cannot be undone.",
                    preferredStyle: .alert
                )
                
                confirmAlert.addAction(UIAlertAction(
                    title: "Cancel",
                    style: .cancel
                ))
                
                confirmAlert.addAction(UIAlertAction(
                    title: "Delete",
                    style: .destructive
                ) { _ in
                    self.ocrManager.deleteDocument(docId: doc.id)
                    self.collectionView.reloadData()
                })
                
                self.present(confirmAlert, animated: true)
            }
            let rename = UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { _ in
                self.promptForTitle(docId: doc.id, currentTitle: doc.title)
            }
            let duplicate = UIAction(title: "Duplicate", image: UIImage(systemName: "doc.on.doc")) { _ in
                self.ocrManager.duplicateDocument(docId: doc.id)
                self.collectionView.reloadData()
            }
            return UIMenu(children: [rename, duplicate, delete])
        }
    }
}

// MARK: - Gesture Delegate
extension UploadsViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {

        if let touchedView = touch.view {

            if touchedView.isDescendant(of: searchBar ?? UIView()) {
                return false
            }

        }

        return true
    }
}

// MARK: - Helpers & Extensions
extension UploadsViewController: UISearchBarDelegate, VNDocumentCameraViewControllerDelegate, PHPickerViewControllerDelegate {
    
    private func placeholderPlusImage() -> UIImage? {
        let size = CGSize(width: 140, height: 140)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.systemGray5.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 20).fill()
            
            let plusPath = UIBezierPath()
            plusPath.lineWidth = 4
            let center = CGPoint(x: size.width/2, y: size.height/2)
            
            plusPath.move(to: CGPoint(x: center.x - 20, y: center.y))
            plusPath.addLine(to: CGPoint(x: center.x + 20, y: center.y))
            
            plusPath.move(to: CGPoint(x: center.x, y: center.y - 20))
            plusPath.addLine(to: CGPoint(x: center.x, y: center.y + 20))
            
            UIColor.systemGray.setStroke()
            plusPath.stroke()
        }
    }
    
    private func updateSelectButtonTitle(_ title: String) {

        let font = UIFont(name: "ArialRoundedMTBold", size: 21) ?? UIFont.systemFont(ofSize: 21)

        let attr = NSAttributedString(
            string: title,
            attributes: [
                .font: font
            ])

        selectButton.setAttributedTitle(attr, for: .normal)
    }
    
    private func setupSearch() {
        let sb = UISearchBar()
        sb.placeholder = "Search documents"
        sb.delegate = self
        sb.isHidden = true
        sb.translatesAutoresizingMaskIntoConstraints = false
        
        sb.searchBarStyle = .minimal
        sb.backgroundImage = UIImage()
        sb.backgroundColor = .clear
        
        view.addSubview(sb)
        
        NSLayoutConstraint.activate([
            sb.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            sb.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            sb.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
        
        searchBar = sb
    }
    
    @objc private func hideSearchIfNeeded() {
        guard let sb = searchBar else { return }

        view.endEditing(true)
        sb.isHidden = true
        sb.text = ""

        isSearching = false
        filteredDocs.removeAll()

        collectionView.reloadData()

        if let tap = dismissTapGesture {
            view.removeGestureRecognizer(tap)
        }
    }
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.isEmpty {
            isSearching = false
        } else {
            isSearching = true
            filteredDocs = ocrManager.getAllDocuments().filter {
                $0.title.lowercased().contains(searchText.lowercased())
            }
        }
        collectionView.reloadData()
    }
    
    func presentScanner() {
        guard VNDocumentCameraViewController.isSupported else { return }
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = self
        present(scanner, animated: true)
    }
    
    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        var images: [UIImage] = []
        for i in 0..<scan.pageCount { images.append(scan.imageOfPage(at: i)) }
        controller.dismiss(animated: true)
        handleNewImages(images)
    }
    
    func presentPhotoPicker() {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 0
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        let group = DispatchGroup()
        
        var images: [UIImage?] = Array(repeating: nil, count: results.count)
        
        for (index, result) in results.enumerated() {
            group.enter()
            if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                result.itemProvider.loadObject(ofClass: UIImage.self) { image, _ in
                    if let img = image as? UIImage {
                        DispatchQueue.main.async {
                            images[index] = img
                        }
                    }
                    group.leave()
                }
            } else {
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            let validImages = images.compactMap { $0 }
            self.handleNewImages(validImages)
        }
    }
    
    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        if searchBar.text?.isEmpty ?? true {
            searchBar.isHidden = true
            isSearching = false
            collectionView.reloadData()
        }
    }
}
