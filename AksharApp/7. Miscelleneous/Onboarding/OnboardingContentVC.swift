import UIKit

class OnboardingContentVC: UIViewController {
    
    @IBOutlet weak var backgroundImageView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    
    private let getStartedButton: UIButton = {
        let button = UIButton(type: .system)
        
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        let chevronImage = UIImage(systemName: "chevron.right", withConfiguration: config)
        button.setImage(chevronImage, for: .normal)
        
        button.tintColor = .systemYellow
        button.backgroundColor = UIColor(red: 0.38, green: 0.22, blue: 0.09, alpha: 1.0)
        
        button.translatesAutoresizingMaskIntoConstraints = false
        button.alpha = 0
        button.isHidden = true
        return button
    }()
    
    var pageIndex: Int = 0
    var titleText: String = ""
    var subtitleText: String = ""
    var backgroundImage: UIImage?
    var isLastPage: Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.text = titleText
        subtitleLabel.text = subtitleText
        backgroundImageView.image = backgroundImage
        if pageIndex == 0 {
            backgroundImageView.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
        }
        
        setupGetStartedButton()
    }
    
    private func setupGetStartedButton() {
        guard isLastPage else { return }
        
        getStartedButton.isHidden = false
        getStartedButton.addTarget(self, action: #selector(getStartedTapped), for: .touchUpInside)
        
        view.addSubview(getStartedButton)
        
        NSLayoutConstraint.activate([
            getStartedButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -50),
            getStartedButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            getStartedButton.widthAnchor.constraint(equalToConstant: 60),
            getStartedButton.heightAnchor.constraint(equalToConstant: 60)
        ])
        
        getStartedButton.layer.cornerRadius = 30
        
        animateButtonIn()
    }
    
    func animateButtonIn() {
        UIView.animate(withDuration: 0.5, delay: 0.8, options: .curveEaseOut, animations: {
            self.getStartedButton.alpha = 1
        }, completion: nil)
    }
    
    @objc private func getStartedTapped() {
        if let pageVC = parent as? OnboardingPageVC {
            pageVC.navigateToSignUp()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyRelativeScaling()
    }
    
    private func applyRelativeScaling() {
        let referenceDimension = min(view.bounds.width, view.bounds.height)
        let titleSize = referenceDimension * 0.06
        let subtitleSize = referenceDimension * 0.035
        
        if let currentTitleFont = titleLabel.font {
            titleLabel.font = currentTitleFont.withSize(titleSize)
        }
        
        if let currentSubtitleFont = subtitleLabel.font {
            subtitleLabel.font = currentSubtitleFont.withSize(subtitleSize)
        }
    }
}
