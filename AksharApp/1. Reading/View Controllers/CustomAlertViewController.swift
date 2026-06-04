import UIKit

class CustomAlertViewController: UIViewController {
    
    // MARK: - Outlets
    @IBOutlet weak var parentView: UIView!
    @IBOutlet weak var rewardImageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var actionButton: UIButton!
    
    // MARK: - Properties
    var alertTitle: String?
    var alertMessage: String?
    var buttonText: String?
    var alertImage: UIImage?

    /// Called when the action button is tapped.
    var onDismiss: (() -> Void)?

    /// Optional: called when the user taps outside the card (background dimmer).
    /// If nil, tapping outside does nothing (default for completion/celebration alerts).
    /// Set this to a closure for dismissal without action (e.g. "stay in guided mode").
    var onBackgroundTap: (() -> Void)?

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        populateData()
        setupBackgroundTap()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .black.withAlphaComponent(0.4)
        
        parentView.backgroundColor = .systemBackground
        parentView.layer.cornerRadius = 25
        parentView.layer.borderWidth = 5
        parentView.layer.borderColor = UIColor.systemYellow.cgColor
        
        parentView.layer.shadowColor = UIColor.black.cgColor
        parentView.layer.shadowOpacity = 0.2
        parentView.layer.shadowOffset = CGSize(width: 0, height: 4)
        parentView.layer.shadowRadius = 10
        
        actionButton.layer.cornerRadius = 15
        actionButton.backgroundColor = .systemYellow
        actionButton.titleLabel?.font = .systemFont(ofSize: 25, weight: .bold)
        
        titleLabel.font = .systemFont(ofSize: 32, weight: .medium).rounded()
        subtitleLabel.font = UIFont(name: "SF Pro Rounded", size: 28)

        // Fix image being clipped at the top — use aspectFit so full teddy shows
        rewardImageView.contentMode = .scaleAspectFit
        rewardImageView.clipsToBounds = false
    }
    
    private func populateData() {
        titleLabel.text = alertTitle
        subtitleLabel.text = alertMessage
        actionButton.setTitle(buttonText, for: .normal)
        
        rewardImageView.image = alertImage
        rewardImageView.isHidden = (alertImage == nil)
    }

    // MARK: - Background tap
    private func setupBackgroundTap() {
        // Only wire up the tap if a background-tap handler is provided
        guard onBackgroundTap != nil else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    @objc private func backgroundTapped(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)
        // Only dismiss if tapped outside the card
        guard !parentView.frame.contains(location) else { return }
        dismiss(animated: true) { [weak self] in
            self?.onBackgroundTap?()
        }
    }

    // MARK: - Actions
    @IBAction func actionButtonTapped(_ sender: UIButton) {
        dismiss(animated: false) { [weak self] in
            self?.onDismiss?()
        }
    }
}

// MARK: - Helpers
private extension UIFont {
    func rounded() -> UIFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
