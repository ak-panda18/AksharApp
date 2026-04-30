import UIKit
import FirebaseAuth
import GoogleSignIn
import FirebaseCore
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AksharApp", category: "SignInViewController")

class SignInViewController: UIViewController, UITextFieldDelegate {

    @IBOutlet var textFields: [UITextField]!
    @IBOutlet var scrollView: UIScrollView!
    @IBOutlet weak var googleButton: UIButton!
    
    var childManager: ChildManager!

    private func verifyDependencies() {
        assert(childManager != nil, "childManager was not injected into \(type(of: self))")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        verifyDependencies()
        setupKeyboardObservers()
        setupTextFields()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        styleTextFields()
        googleButton.layer.borderColor = UIColor(red: 198/255.0,green: 160/255.0,blue: 74/255.0,alpha: 1.0).cgColor
        googleButton.layer.borderWidth = 1
    }

    // MARK: - Email Sign In
    @IBAction func signInTapped(_ sender: UIButton) {
        guard let email    = textFields[0].text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let password = textFields[1].text,
              !email.isEmpty, !password.isEmpty
        else { showAlert("Please enter your email and password."); return }

        sender.isEnabled = false

        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            guard let self else { return }
            DispatchQueue.main.async {
                sender.isEnabled = true
                if let error { self.showAlert(self.friendlyError(error)); return }

                if result?.user.isEmailVerified == false {
                    try? Auth.auth().signOut()
                    self.showAlert("Please verify your email before signing in. Check your inbox for the verification link.")
                    return
                }

                guard let uid = result?.user.uid else { return }
                self.childManager.resolveChild(uid: uid)
                self.goToHome()
            }
        }
    }

    // MARK: - Google Sign In
    @IBAction func googleSignInTapped(_ sender: UIButton) {
        guard let clientID = FirebaseApp.app()?.options.clientID else { return }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        sender.isEnabled = false

        GIDSignIn.sharedInstance.signIn(withPresenting: self) { [weak self] result, error in
            guard let self else { return }
            DispatchQueue.main.async {
                sender.isEnabled = true

                if let error {
                    let nsError = error as NSError
                    if nsError.code == GIDSignInError.canceled.rawValue { return }
                    self.showAlert("Google sign in failed. Please try again.")
                    return
                }

                guard let user    = result?.user,
                      let idToken = user.idToken?.tokenString
                else { return }

                let credential = GoogleAuthProvider.credential(
                    withIDToken: idToken,
                    accessToken: user.accessToken.tokenString
                )

                Auth.auth().signIn(with: credential) { [weak self] authResult, error in
                    guard let self else { return }
                    DispatchQueue.main.async {
                        if let error {
                            logger.error("SignInVC: Google Firebase sign-in failed – \(error)")
                            self.showAlert("Google sign in failed. Please try again.")
                            return
                        }
                        guard let uid = authResult?.user.uid else { return }
                        self.childManager.resolveChild(uid: uid)
                        self.goToHome()
                    }
                }
            }
        }
    }

    // MARK: - Navigation to Sign Up
    @IBAction func goToSignUpTapped(_ sender: UIButton) {
        let sb = UIStoryboard(name: "Main", bundle: nil)
        guard let signUpVC = sb.instantiateViewController(
            withIdentifier: "SignUpViewController") as? SignUpViewController else { return }
        signUpVC.childManager = self.childManager
        navigationController?.pushViewController(signUpVC, animated: true)
    }

    private func goToHome() {
        guard let sceneDelegate = view.window?.windowScene?.delegate as? SceneDelegate else { return }
        sceneDelegate.showHomeAfterAuth()
    }

    // MARK: - Forgot Password
    @IBAction func forgotPasswordButton(_ sender: UIButton) {
        let alert = UIAlertController(
            title: "Reset Password",
            message: "Enter your email to receive a reset link.",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "Email"
            textField.keyboardType = .emailAddress
            textField.autocapitalizationType = .none
        }
        let sendAction = UIAlertAction(title: "Send", style: .default) { [weak self] _ in
            guard let self,
                  let email = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !email.isEmpty else {
                self?.showAlert("Please enter your email.")
                return
            }
            Auth.auth().sendPasswordReset(withEmail: email) { error in
                DispatchQueue.main.async {
                    if let error {
                        self.showAlert(self.friendlyResetError(error))
                    } else {
                        self.showAlert("Password reset link sent to your email.")
                    }
                }
            }
        }
        alert.addAction(sendAction)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - Error Helpers
    private func friendlyResetError(_ error: Error) -> String {
        let code = AuthErrorCode(rawValue: (error as NSError).code)
        switch code {
        case .invalidEmail: return "Please enter a valid email address."
        case .userNotFound:  return "No account found for this email."
        case .networkError:  return "No internet connection."
        default:             return "Failed to send reset email."
        }
    }

    private func friendlyError(_ error: Error) -> String {
        let code = AuthErrorCode(rawValue: (error as NSError).code)
        switch code {
        case .wrongPassword, .invalidEmail: return "Email or password is incorrect."
        case .userNotFound:                 return "No account found for this email."
        case .userDisabled:                 return "This account has been disabled."
        case .networkError:                 return "No internet connection."
        default:                            return "Sign in failed. Please try again."
        }
    }

    private func showAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Setup
private extension SignInViewController {
    func setupTextFields() {
        textFields.forEach { $0.delegate = self; $0.returnKeyType = .next }
        textFields.last?.returnKeyType = .done
    }
    func styleTextFields() {
        textFields.forEach {
            $0.layer.cornerRadius  = $0.bounds.height / 2
            $0.layer.borderWidth   = 1
            $0.layer.borderColor   = UIColor.lightGray.cgColor
            $0.layer.masksToBounds = true

            let padding = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: $0.bounds.height))
            $0.leftView  = padding
            $0.leftViewMode  = .always
            $0.rightView = UIView(frame: padding.frame)
            $0.rightViewMode = .always
        }
    }
}

// MARK: - Keyboard
extension SignInViewController {
    func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    @objc func keyboardWillShow(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        scrollView.contentInset.bottom = frame.height + 20
        scrollView.verticalScrollIndicatorInsets.bottom = frame.height
    }
    @objc func keyboardWillHide(_ notification: Notification) {
        scrollView.contentInset.bottom = 0
        scrollView.verticalScrollIndicatorInsets.bottom = 0
    }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if let index = textFields.firstIndex(of: textField), index < textFields.count - 1 {
            textFields[index + 1].becomeFirstResponder()
        } else { textField.resignFirstResponder() }
        return true
    }
}
