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
    
    private func verifyDependencies() {
        assert(childManager != nil, "childManager was not injected into \(type(of: self))")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        verifyDependencies()
        setupKeyboardObservers()
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

                let actionCodeSettings = ActionCodeSettings()
                actionCodeSettings.url = URL(string: "https://akshar-1405.web.app/index.html")
                actionCodeSettings.handleCodeInApp = true
                actionCodeSettings.setIOSBundleID(Bundle.main.bundleIdentifier!)

                result?.user.sendEmailVerification(with: actionCodeSettings) { error in
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
        textFields.forEach {
            $0.backgroundColor     = .white
            $0.layer.borderWidth   = 1
            $0.layer.borderColor   = UIColor.lightGray.cgColor
            $0.layer.cornerRadius  = $0.bounds.height / 2
            $0.layer.masksToBounds = true
            
            let padding = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: $0.bounds.height))
            $0.leftView  = padding
            $0.leftViewMode  = .always
            $0.rightView = UIView(frame: padding.frame)
            $0.rightViewMode = .always
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
