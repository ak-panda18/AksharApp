import UIKit
import FirebaseAuth
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AksharApp", category: "SignUpViewController")

class SignUpViewController: UIViewController, UITextFieldDelegate {
    @IBOutlet var scrollView: UIScrollView!
    @IBOutlet var contentView: UIView!
    @IBOutlet var centreContainerView: UIView!
    @IBOutlet var boardingImageView: UIImageView!
    @IBOutlet var boardingTextView: UITextView!
    @IBOutlet var textFieldStackView: UIStackView!
    @IBOutlet var signUpButton: UIButton!
    @IBOutlet var signInStackView: UIStackView!
    @IBOutlet var signInButton: UIButton!
    @IBOutlet var textFields: [UITextField]!

    var childManager: ChildManager!
    
    private let nameErrorLabel = UILabel()
    private var errorTimer: DispatchWorkItem?
    
    private func verifyDependencies() {
        assert(childManager != nil, "childManager was not injected into \(type(of: self))")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        verifyDependencies()
        setupKeyboardObservers()
        
        textFields[2].delegate = self
        
        let ageButton = UIButton(type: .custom)
        ageButton.translatesAutoresizingMaskIntoConstraints = false
        ageButton.addTarget(self, action: #selector(showAgeDropDown(_:)), for: .touchUpInside)
        view.addSubview(ageButton)
        NSLayoutConstraint.activate([
            ageButton.topAnchor.constraint(equalTo: textFields[0].topAnchor),
            ageButton.bottomAnchor.constraint(equalTo: textFields[0].bottomAnchor),
            ageButton.leadingAnchor.constraint(equalTo: textFields[0].leadingAnchor),
            ageButton.trailingAnchor.constraint(equalTo: textFields[0].trailingAnchor)
        ])
        
        setupNameErrorLabel()
    }
    
    @objc private func showAgeDropDown(_ sender: UIButton) {
        let vc = AgeDropDownViewController()
        vc.popoverPresentationController?.sourceView = sender
        vc.popoverPresentationController?.sourceRect = sender.bounds
        vc.onSelect = { [weak self] age in
            self?.textFields[0].text = "\(age)"
        }
        present(vc, animated: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        styleTextFieldsAndButton()
    }

    // MARK: - Sign Up
    @IBAction func signUpTapped(_ sender: UIButton) {
        guard let email    = textFields[1].text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let name     = textFields[2].text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let ageText  = textFields[0].text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let password = textFields[3].text,
              let confirm  = textFields[4].text,
              !email.isEmpty, !name.isEmpty, !password.isEmpty
        else { showAlert("Please fill in all fields."); return }

        guard password.count >= 6 else { showAlert("Password must be at least 6 characters."); return }
        guard password == confirm  else { showAlert("Passwords do not match."); return }

        sender.isEnabled = false

        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            guard let self else { return }
            DispatchQueue.main.async {
                sender.isEnabled = true
                if let error { self.showAlert(self.friendlyError(error)); return }
                guard let uid = result?.user.uid else { return }

                let req = result?.user.createProfileChangeRequest()
                req?.displayName = name
                req?.commitChanges(completion: nil)

                result?.user.sendEmailVerification { error in
                    if let error {
                        logger.warning("SignUpVC: verification email failed – \(error)")
                    }
                }

                let nameParts  = name.split(separator: " ", maxSplits: 1).map(String.init)
                let firstName  = nameParts.first ?? name
                let lastName   = nameParts.count > 1 ? nameParts[1] : ""
                let age        = Int16(ageText) ?? 0

                self.childManager.currentChild.name      = name
                self.childManager.currentChild.firstName = firstName
                self.childManager.currentChild.lastName  = lastName
                self.childManager.currentChild.age       = age
                self.childManager.linkFirebaseUID(uid)
                self.childManager.saveProfileData()

                self.showVerificationAlert()
            }
        }
    }

    @IBAction func goToSignInTapped(_ sender: UIButton) {
        navigationController?.popViewController(animated: true)
    }

    private func friendlyError(_ error: Error) -> String {
        let code = AuthErrorCode(rawValue: (error as NSError).code)
        switch code {
        case .emailAlreadyInUse: return "An account with this email already exists."
        case .invalidEmail:      return "Please enter a valid email address."
        case .weakPassword:      return "Password must be at least 6 characters."
        case .networkError:      return "No internet connection."
        default:                 return "Sign up failed. Please try again."
        }
    }

    private func showAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func showVerificationAlert() {
        let alert = UIAlertController(
            title: "Verify your email",
            message: "A verification link has been sent to your email address. Please verify before signing in.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }
}



// MARK: - Name Validation
extension SignUpViewController {
    func textField(_ textField: UITextField,
                   shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {
        
        if textField == textFields[2] {
            clearNameError()
            
            if string.isEmpty { return true }
            
            let allowedCharacterSet = CharacterSet.letters.union(CharacterSet.whitespaces)
            if string.rangeOfCharacter(from: allowedCharacterSet.inverted) != nil {
                showNameError("Only letters and spaces are allowed.")
                return false
            }
        }
        
        return true
    }
    
    private func setupNameErrorLabel() {
        nameErrorLabel.textColor = .systemRed
        nameErrorLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        nameErrorLabel.numberOfLines = 0
        nameErrorLabel.isHidden = true
        nameErrorLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nameErrorLabel)
        
        NSLayoutConstraint.activate([
            nameErrorLabel.topAnchor.constraint(equalTo: textFields[2].bottomAnchor, constant: 4),
            nameErrorLabel.leadingAnchor.constraint(equalTo: textFields[2].leadingAnchor, constant: 4),
            nameErrorLabel.trailingAnchor.constraint(equalTo: textFields[2].trailingAnchor)
        ])
    }

    private func showNameError(_ message: String) {
        nameErrorLabel.text = message
        nameErrorLabel.isHidden = false
        textFields[2].layer.borderWidth = 1.5
        textFields[2].layer.borderColor = UIColor.systemRed.cgColor
        textFields[2].layer.cornerRadius = textFields[2].bounds.height / 2
        shake(view: textFields[2])
        
        errorTimer?.cancel()
        let timer = DispatchWorkItem { [weak self] in
            self?.clearNameError()
        }
        errorTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: timer)
    }

    private func clearNameError() {
        errorTimer?.cancel()
        nameErrorLabel.isHidden = true
        textFields[2].layer.borderWidth = 1
        textFields[2].layer.borderColor = UIColor.lightGray.cgColor
    }
    
    private func shake(view: UIView) {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [-10, 10, -8, 8, -5, 5, 0]
        animation.duration = 0.35
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        view.layer.add(animation, forKey: "shake")
    }
}

// MARK: - Keyboard & Styling
extension SignUpViewController {
    func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    @objc func keyboardWillShow(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        scrollView.contentInset.bottom = frame.height + 20
    }
    @objc func keyboardWillHide(_ notification: Notification) {
        scrollView.contentInset.bottom = 0
    }
    private func styleTextFieldsAndButton() {
        for (index, textField) in textFields.enumerated() {
            textField.backgroundColor     = .white
            if index == 2 && !nameErrorLabel.isHidden {
                textField.layer.borderWidth   = 1.5
                textField.layer.borderColor   = UIColor.systemRed.cgColor
            } else {
                textField.layer.borderWidth   = 1
                textField.layer.borderColor   = UIColor.lightGray.cgColor
            }
            textField.layer.cornerRadius  = textField.bounds.height / 2
            textField.layer.masksToBounds = true
            
            let padding = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: textField.bounds.height))
            textField.leftView  = padding
            textField.leftViewMode  = .always
            textField.rightView = UIView(frame: padding.frame)
            textField.rightViewMode = .always
        }
        signUpButton.layer.cornerRadius = signUpButton.bounds.height / 2
    }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if let index = textFields.firstIndex(of: textField), index < textFields.count - 1 {
            textFields[index + 1].becomeFirstResponder()
        } else { textField.resignFirstResponder() }
        return true
    }
}

class AgeDropDownViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UIPopoverPresentationControllerDelegate {
    let tableView = UITableView()
    var onSelect: ((Int) -> Void)?
    
    init() {
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .popover
        self.popoverPresentationController?.delegate = self
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        preferredContentSize = CGSize(width: 150, height: 250)
    }
    
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return .none
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 21 }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = "\(indexPath.row)"
        cell.textLabel?.textAlignment = .center
        cell.textLabel?.font = UIFont.systemFont(ofSize: 16)
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        onSelect?(indexPath.row)
        dismiss(animated: true)
    }
}
