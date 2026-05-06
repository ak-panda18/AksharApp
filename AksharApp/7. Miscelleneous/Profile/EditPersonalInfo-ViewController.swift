import UIKit

protocol EditPersonalInfoDelegate: AnyObject {
    func didUpdatePersonalInfo(firstName: String, lastName: String, age: Int16, gender: String)
}

class EditPersonalInfo_ViewController: UIViewController, UIPickerViewDataSource, UIPickerViewDelegate, UITextFieldDelegate {

    @IBOutlet weak var genderPicker: UIPickerView!
    @IBOutlet weak var ageTextField: UITextField!
    @IBOutlet weak var lastNameTextField: UITextField!
    @IBOutlet weak var firstNameTextField: UITextField!
    @IBOutlet weak var saveButton: UIBarButtonItem!
    @IBOutlet weak var cancelButton: UIBarButtonItem!

    // MARK: - Injected
    var childManager: ChildManager?
    weak var delegate: EditPersonalInfoDelegate?

    var currentFirstName: String?
    var currentLastName:  String?
    var currentAge:       Int16?
    var currentGender:    String?

    let genderOptions  = ["Male", "Female", "Other"]
    var selectedGender = "Male"
    private let ageErrorLabel = UILabel()

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        genderPicker.dataSource = self
        genderPicker.delegate   = self

        firstNameTextField.text = currentFirstName
        lastNameTextField.text  = currentLastName
        ageTextField.text       = currentAge.map { String($0) }
        
        ageTextField.delegate = self
        ageTextField.keyboardType = .numberPad
        setupAgeErrorLabel()

        if let g = currentGender, let idx = genderOptions.firstIndex(of: g) {
            genderPicker.selectRow(idx, inComponent: 0, animated: false)
            selectedGender = g
        }
    }

    // MARK: - UIPickerView
    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { genderOptions.count }
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? { genderOptions[row] }
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) { selectedGender = genderOptions[row] }
    func textField(_ textField: UITextField,
                   shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {

        clearAgeError()

        // Allow backspace
        if string.isEmpty {
            return true
        }

        // Only numbers allowed
        if string.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) != nil {

            showAgeError("Only numbers are allowed.")

            return false
        }

        // Predict final value
        let currentText = textField.text ?? ""
        let updatedText = (currentText as NSString).replacingCharacters(in: range, with: string)

        // Prevent age > 100
        if let value = Int(updatedText), value > 100 {

            showAgeError("Age must be between 0 and 100.")

            return false
        }

        return true
    }
    private func setupAgeErrorLabel() {

        ageErrorLabel.textColor = .systemRed
        ageErrorLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        ageErrorLabel.numberOfLines = 0
        ageErrorLabel.isHidden = true
        ageErrorLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(ageErrorLabel)

        NSLayoutConstraint.activate([
            ageErrorLabel.topAnchor.constraint(equalTo: ageTextField.bottomAnchor, constant: 4),
            ageErrorLabel.leadingAnchor.constraint(equalTo: ageTextField.leadingAnchor, constant: 4),
            ageErrorLabel.trailingAnchor.constraint(equalTo: ageTextField.trailingAnchor)
        ])
    }

    private func showAgeError(_ message: String) {

        ageErrorLabel.text = message
        ageErrorLabel.isHidden = false

        ageTextField.layer.borderWidth = 1.5
        ageTextField.layer.borderColor = UIColor.systemRed.cgColor
        ageTextField.layer.cornerRadius = 6

        shake(view: ageTextField)
    }

    private func clearAgeError() {

        ageErrorLabel.isHidden = true
        ageTextField.layer.borderWidth = 0
        ageTextField.layer.borderColor = UIColor.clear.cgColor
    }

    private func shake(view: UIView) {

        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")

        animation.values = [-10, 10, -8, 8, -5, 5, 0]
        animation.duration = 0.35
        animation.timingFunction = CAMediaTimingFunction(name: .linear)

        view.layer.add(animation, forKey: "shake")
    }

    // MARK: - Actions
    @IBAction func cancelButtonTapped(_ sender: UIBarButtonItem) {
        dismiss(animated: true)
    }

    @IBAction func saveButtonTapped(_ sender: UIBarButtonItem) {
        let fn     = firstNameTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ln     = lastNameTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let agText = ageTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let ageValue = Int(agText),
              ageValue >= 0,
              ageValue <= 100 else {

            showAgeError("Please enter a valid age between 0 and 100.")

            return
        }

        let ag = Int16(ageValue)
        let gn     = selectedGender

        if let child = childManager?.currentChild {
            child.firstName = fn
            child.lastName  = ln
            child.age       = ag
            child.gender    = gn
            if !fn.isEmpty { child.name = fn }
            childManager?.saveProfileData()
        }

        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.delegate?.didUpdatePersonalInfo(
                firstName: fn,
                lastName:  ln,
                age:       ag,
                gender:    gn
            )
        }
    }
}
