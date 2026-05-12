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
    private let firstNameErrorLabel = UILabel()
    private let lastNameErrorLabel = UILabel()
    private var errorTimers: [UITextField: DispatchWorkItem] = [:]

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        genderPicker.dataSource = self
        genderPicker.delegate   = self

        firstNameTextField.text = currentFirstName
        lastNameTextField.text  = currentLastName
        ageTextField.text       = currentAge.map { String($0) }
        
        firstNameTextField.delegate = self
        lastNameTextField.delegate = self
        
        let ageButton = UIButton(type: .custom)
        ageButton.translatesAutoresizingMaskIntoConstraints = false
        ageButton.addTarget(self, action: #selector(showAgeDropDown(_:)), for: .touchUpInside)
        view.addSubview(ageButton)
        NSLayoutConstraint.activate([
            ageButton.topAnchor.constraint(equalTo: ageTextField.topAnchor),
            ageButton.bottomAnchor.constraint(equalTo: ageTextField.bottomAnchor),
            ageButton.leadingAnchor.constraint(equalTo: ageTextField.leadingAnchor),
            ageButton.trailingAnchor.constraint(equalTo: ageTextField.trailingAnchor)
        ])
        
        setupNameErrorLabels()

        if let g = currentGender, let idx = genderOptions.firstIndex(of: g) {
            genderPicker.selectRow(idx, inComponent: 0, animated: false)
            selectedGender = g
        }
    }

    @objc private func showAgeDropDown(_ sender: UIButton) {
        let vc = AgeDropDownViewController()
        vc.popoverPresentationController?.sourceView = sender
        vc.popoverPresentationController?.sourceRect = sender.bounds
        vc.onSelect = { [weak self] age in
            self?.ageTextField.text = "\(age)"
        }
        present(vc, animated: true)
    }

    // MARK: - UIPickerView
    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { genderOptions.count }
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? { genderOptions[row] }
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) { selectedGender = genderOptions[row] }
    func textField(_ textField: UITextField,
                   shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {

        clearNameError(for: textField)

        // Allow backspace
        if string.isEmpty {
            return true
        }

        let allowedCharacterSet = CharacterSet.letters.union(CharacterSet.whitespaces)
        if string.rangeOfCharacter(from: allowedCharacterSet.inverted) != nil {
            showNameError("Only letters and spaces are allowed.", for: textField)
            return false
        }

        return true
    }
    
    private func setupNameErrorLabels() {
        [firstNameErrorLabel, lastNameErrorLabel].forEach { label in
            label.textColor = .systemRed
            label.font = UIFont.systemFont(ofSize: 13, weight: .medium)
            label.numberOfLines = 0
            label.isHidden = true
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
        }

        NSLayoutConstraint.activate([
            firstNameErrorLabel.topAnchor.constraint(equalTo: firstNameTextField.bottomAnchor, constant: 4),
            firstNameErrorLabel.leadingAnchor.constraint(equalTo: firstNameTextField.leadingAnchor, constant: 4),
            firstNameErrorLabel.trailingAnchor.constraint(equalTo: firstNameTextField.trailingAnchor),
            
            lastNameErrorLabel.topAnchor.constraint(equalTo: lastNameTextField.bottomAnchor, constant: 4),
            lastNameErrorLabel.leadingAnchor.constraint(equalTo: lastNameTextField.leadingAnchor, constant: 4),
            lastNameErrorLabel.trailingAnchor.constraint(equalTo: lastNameTextField.trailingAnchor)
        ])
    }

    private func showNameError(_ message: String, for textField: UITextField) {
        let label = textField == firstNameTextField ? firstNameErrorLabel : lastNameErrorLabel
        label.text = message
        label.isHidden = false

        textField.layer.borderWidth = 1.5
        textField.layer.borderColor = UIColor.systemRed.cgColor
        textField.layer.cornerRadius = 6

        shake(view: textField)
        
        errorTimers[textField]?.cancel()
        let timer = DispatchWorkItem { [weak self] in
            self?.clearNameError(for: textField)
        }
        errorTimers[textField] = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: timer)
    }

    private func clearNameError(for textField: UITextField) {
        errorTimers[textField]?.cancel()
        let label = textField == firstNameTextField ? firstNameErrorLabel : lastNameErrorLabel
        label.isHidden = true
        textField.layer.borderWidth = 0
        textField.layer.borderColor = UIColor.clear.cgColor
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
              ageValue <= 20 else {

            let alert = UIAlertController(title: nil, message: "Please enter a valid age between 0 and 20.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)

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
