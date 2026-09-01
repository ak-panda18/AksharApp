import UIKit
import FirebaseAuth
import FirebaseFirestore
import UserNotifications
import CoreData
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AksharApp", category: "ProfileViewController")

class Profile_ViewController: UIViewController,
                              EditPersonalInfoDelegate, SetPINDelegate,
                              UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    // MARK: - Injected
    var analyticsStore: AnalyticsStore!
    var checkpointHistoryManager: CheckpointHistoryManager!
    var childManager: ChildManager!
    var profileStore: ProfileStore!

    // MARK: - Outlets: Cards
    @IBOutlet weak var streakCard: UIView!
    @IBOutlet weak var privacyCard: UIView!
    @IBOutlet weak var personalInfoBackground: UIView!
    @IBOutlet weak var remindersCard: UIView!
    @IBOutlet weak var ParentalControlCard: UIView!

    // MARK: - Outlets: Streak
    @IBOutlet weak var mondayStreak: UIView!
    @IBOutlet weak var tuesdayStreak: UIView!
    @IBOutlet weak var wednesdayStreak: UIView!
    @IBOutlet weak var thursdayStreak: UIView!
    @IBOutlet weak var fridayStreak: UIView!
    @IBOutlet weak var saturdayStreak: UIView!
    @IBOutlet weak var sundayStreak: UIView!
    @IBOutlet weak var streakNumber: UILabel!

    // MARK: - Outlets: Header
    @IBOutlet weak var profileImage: UIImageView!
    @IBOutlet weak var profileName: UILabel!

    // MARK: - Outlets: Personal Info
    @IBOutlet weak var firstName: UILabel!
    @IBOutlet weak var lastName: UILabel!
    @IBOutlet weak var gender: UILabel!
    @IBOutlet weak var age: UILabel!
    @IBOutlet weak var editProfileButton: UIButton!

    // MARK: - Outlets: Reminders
    @IBOutlet weak var mondayReminder: UIButton!
    @IBOutlet weak var tuesdayReminder: UIButton!
    @IBOutlet weak var wednesdayReminder: UIButton!
    @IBOutlet weak var thursdayReminder: UIButton!
    @IBOutlet weak var fridayReminder: UIButton!
    @IBOutlet weak var saturdayReminder: UIButton!
    @IBOutlet weak var sundayReminder: UIButton!
    @IBOutlet weak var reminderSwitch: UISwitch!

    // MARK: - Outlets: Parental
    @IBOutlet weak var setPinButton: UIButton!
    @IBOutlet weak var forgotPINButton: UIButton!

    // MARK: - Outlets: Account
    @IBOutlet weak var deleteAccountButton: UIButton!
    @IBOutlet weak var logOutButton: UIButton!

    // MARK: - Constants
    private let yellowOn = UIColor(red: 255/255, green: 231/255, blue: 131/255, alpha: 1.0)
    private let whiteOff = UIColor.white

    private var dayButtons: [UIButton] {
        [mondayReminder, tuesdayReminder, wednesdayReminder,
         thursdayReminder, fridayReminder, saturdayReminder, sundayReminder]
            .compactMap { $0 }
    }

    // FIX 1: childUID is now guaranteed to be the Firebase UID.
    // The old fallback to CoreData UUID or the literal "default" caused all profiles
    // to share the same UserDefaults keys whenever uid or id was nil.
    private var childUID: String {
        guard let uid = Auth.auth().currentUser?.uid else {
            assertionFailure("childUID accessed before Firebase auth — this should never happen")
            // Safe fallback: prefix ensures it never collides with a real Firebase UID
            return "local_\(childManager.currentChild.id?.uuidString ?? "unknown")"
        }
        return uid
    }

    // MARK: - Lifecycle
    private func verifyDependencies() {
        assert(analyticsStore != nil, "analyticsStore was not injected into \(type(of: self))")
        assert(checkpointHistoryManager != nil, "checkpointHistoryManager was not injected into \(type(of: self))")
        assert(childManager != nil, "childManager was not injected into \(type(of: self))")
        assert(profileStore != nil, "profileStore was not injected into \(type(of: self))")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        verifyDependencies()
        applyCardStyles()
        setupStreakViews()
        setupProfileImageTap()
        setupProgressStatisticsRow()
        loadProfileData()
        updateStreakCard()
        fetchStreakFromFirestore()       // merges remote streak dates in the background
        fetchProfileInfoFromFirestore()  // syncs name/gender/age/PIN from Firestore
        loadReminderState()
        checkPINStatus()

        // Pull latest reminder prefs from Firestore and refresh UI once they arrive.
        profileStore.fetchSettings(uid: childUID) { [weak self] enabled, days, _, _ in
            guard let self else { return }
            self.reminderSwitch.isOn = enabled
            self.setDayButtonsInteractive(enabled)
            for (i, btn) in self.dayButtons.enumerated() {
                btn.backgroundColor = days[i] ? self.yellowOn : self.whiteOff
            }
        }

        // FIX 2: Recalculate the streak whenever the app returns from the background.
        // Without this, viewDidLoad only fires once and the streak never updates
        // after midnight or after the app is backgrounded.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    // FIX 2 (continued): Also recalculate each time this screen becomes visible,
    // e.g. returning from a sub-screen within the same session.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateStreakCard()
    }

    @objc private func appDidBecomeActive() {
        updateStreakCard()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
    }

    // MARK: - Profile Data

    // Firestore path: users/{uid}/profile/info
    // Fields: firstName, lastName, gender, age, pin
    private func infoRef(uid: String) -> DocumentReference {
        Firestore.firestore()
            .collection("users").document(uid)
            .collection("profile").document("info")
    }

    /// Renders whatever is currently in CoreData. Called immediately so the
    /// screen is never blank while the Firestore fetch is in flight.
    private func loadProfileData() {
        let child        = childManager.currentChild
        let firebaseName = Auth.auth().currentUser?.displayName

        let resolvedFirstName: String
        let resolvedLastName: String

        if let saved = child.firstName?.nilIfEmpty {
            resolvedFirstName = saved
            resolvedLastName  = child.lastName ?? ""
        } else {
            let fullName  = child.name?.nilIfEmpty ?? firebaseName ?? ""
            let parts     = fullName.split(separator: " ", maxSplits: 1).map(String.init)
            resolvedFirstName = parts.first ?? fullName
            resolvedLastName  = parts.count > 1 ? parts[1] : (child.lastName ?? "")

            if !resolvedFirstName.isEmpty {
                child.firstName = resolvedFirstName
                child.lastName  = resolvedLastName
                childManager.saveProfileData()
            }
        }

        let displayName = resolvedFirstName.nilIfEmpty ?? firebaseName ?? "Profile"
        logger.debug("ProfileVC: loading profile for child id=\(child.id?.uuidString ?? "nil") name=\(child.name ?? "nil")")

        applyProfileUI(
            firstName:   resolvedFirstName,
            lastName:    resolvedLastName,
            gender:      child.gender ?? "",
            age:         child.age == 0 ? "" : String(child.age),
            displayName: displayName
        )
    }

    /// Pulls the authoritative profile info from Firestore and overwrites
    /// CoreData + UI. This is what makes edits show up cross-device.
    private func fetchProfileInfoFromFirestore() {
        infoRef(uid: childUID).getDocument { [weak self] snapshot, error in
            guard let self, let data = snapshot?.data(), error == nil else {
                if let error { logger.error("ProfileVC: fetchProfileInfo failed – \(error)") }
                return
            }
            let fn     = data["firstName"] as? String ?? ""
            let ln     = data["lastName"]  as? String ?? ""
            let gn     = data["gender"]    as? String ?? ""
            let ageVal = data["age"]       as? Int    ?? 0
            let pin    = data["pin"]       as? String

            // Write back into CoreData so local reads stay in sync
            let child       = self.childManager.currentChild
            child.firstName = fn
            child.lastName  = ln
            child.gender    = gn
            child.age       = Int16(ageVal)
            if !fn.isEmpty { child.name = fn }
            self.childManager.saveProfileData()

            // Sync PIN into UserDefaults so SetPIN/VerifyPIN VCs work unchanged
            if let pin {
                UserDefaults.standard.set(pin, forKey: self.pinKey)
            } else {
                UserDefaults.standard.removeObject(forKey: self.pinKey)
            }

            DispatchQueue.main.async {
                self.applyProfileUI(
                    firstName:   fn,
                    lastName:    ln,
                    gender:      gn,
                    age:         ageVal == 0 ? "" : String(ageVal),
                    displayName: fn.nilIfEmpty ?? Auth.auth().currentUser?.displayName ?? "Profile"
                )
                self.checkPINStatus()
            }
        }
    }

    /// Writes profile info to Firestore. Call this whenever info changes.
    func saveProfileInfoToFirestore(firstName fn: String, lastName ln: String,
                                    age: Int16, gender gn: String) {
        var payload: [String: Any] = [
            "firstName": fn,
            "lastName":  ln,
            "gender":    gn,
            "age":       Int(age)
        ]
        // Carry the PIN along so it isn't wiped on a partial update
        if let pin = UserDefaults.standard.string(forKey: pinKey) {
            payload["pin"] = pin
        }
        infoRef(uid: childUID).setData(payload, merge: true) { error in
            if let error { logger.error("ProfileVC: saveProfileInfo failed – \(error)") }
        }
    }

    private func applyProfileUI(firstName fn: String, lastName ln: String,
                                 gender gn: String, age ag: String, displayName: String) {
        profileName.text = displayName
        firstName.text   = fn
        lastName.text    = ln
        gender.text      = gn
        age.text         = ag

        profileImage.layer.cornerRadius  = profileImage.frame.width / 2
        profileImage.layer.masksToBounds = true
        profileImage.contentMode         = .scaleAspectFill

        let child = childManager.currentChild
        if let data = child.profileImageData, let img = UIImage(data: data) {
            profileImage.image = img
            removeCameraOverlay()
            showPencilButton(true)
        } else {
            profileImage.image           = nil
            profileImage.backgroundColor = UIColor.systemGray5
            addCameraOverlay()
            showPencilButton(false)
        }
    }

    // MARK: - Streak Card
    private func updateStreakCard() {
        // FIX 1 + FIX 3: Use childUID (Firebase UID) as the key — not the nullable
        // CoreData UUID. This prevents data leaking between profiles and ensures the
        // same key is used on every device (since the Firebase UID is account-scoped).
        let visitKey = "visitDates_\(childUID)"
        let today    = Calendar.current.startOfDay(for: Date())

        var visits = loadDates(forKey: visitKey)

        if !visits.contains(today) {
            visits.append(today)
            // Write only today's date to Firestore using arrayUnion — this atomically
            // adds the date without overwriting dates written by other devices.
            recordTodayInFirestore(today: today, visitKey: visitKey)
        }

        // Prune local cache only (Firestore pruning happens in fetchStreakFromFirestore).
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: today)!
        visits = visits.filter { $0 >= cutoff }

        // Save pruned list to local cache only — don't push full array to Firestore.
        saveDatesToCache(visits, forKey: visitKey)

        // Calculate consecutive-day streak working backwards from today.
        var streak = 0
        var check  = today
        while visits.contains(check) {
            streak += 1
            check   = Calendar.current.date(byAdding: .day, value: -1, to: check)!
        }
        streakNumber.text = "\(streak)"

        let dayViews = [mondayStreak, tuesdayStreak, wednesdayStreak,
                        thursdayStreak, fridayStreak, saturdayStreak, sundayStreak]
        var comps     = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        comps.weekday = 2
        guard let monday = Calendar.current.date(from: comps) else { return }

        for (i, view) in dayViews.enumerated() {
            guard let view else { continue }
            let day      = Calendar.current.date(byAdding: .day, value: i, to: monday)!
            let isToday  = Calendar.current.isDate(day, inSameDayAs: today)
            let isFuture = day > today
            let visited  = visits.contains(Calendar.current.startOfDay(for: day))
            let label    = view.subviews.first(where: { $0 is UILabel }) as? UILabel

            if isToday {
                // Today: solid blue fill regardless of visited state
                view.backgroundColor   = UIColor.systemBlue
                view.layer.borderColor = UIColor.systemBlue.cgColor
                label?.textColor       = .white
            } else if visited && !isFuture {
                // Past day visited: solid green fill
                view.backgroundColor   = UIColor(red: 0.25, green: 0.80, blue: 0.35, alpha: 1.0)
                view.layer.borderColor = UIColor.clear.cgColor
                label?.textColor       = .white
            } else if !isFuture {
                // Past day missed: red outline, no fill
                view.backgroundColor   = .white
                view.layer.borderColor = UIColor.systemRed.cgColor
                label?.textColor       = .systemRed
            } else {
                // Future day: neutral grey outline
                view.backgroundColor   = .white
                view.layer.borderColor = UIColor.systemGray4.cgColor
                label?.textColor       = .systemGray
            }
        }
    }

    // FIX 3: Streak dates are stored in Firestore so they sync across devices.
    // UserDefaults is used as a fast local cache — the UI reads from cache instantly
    // while a background Firestore fetch keeps it in sync.
    //
    // Firestore path:  users/{uid}/profile/streak
    // Field:           visitDates : [Timestamp]

    private func streakRef(uid: String) -> DocumentReference {
        Firestore.firestore()
            .collection("users").document(uid)
            .collection("profile").document("streak")
    }

    private func loadDates(forKey key: String) -> [Date] {
        guard let data  = UserDefaults.standard.data(forKey: key),
              let dates = try? JSONDecoder().decode([Date].self, from: data)
        else { return [] }
        return dates
    }

    /// Writes dates to UserDefaults cache only. Does NOT touch Firestore.
    private func saveDatesToCache(_ dates: [Date], forKey key: String) {
        if let data = try? JSONEncoder().encode(dates) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Atomically adds a single date to Firestore using arrayUnion.
    /// This means two devices writing different dates simultaneously will both
    /// be preserved — neither overwrites the other.
    private func recordTodayInFirestore(today: Date, visitKey: String) {
        streakRef(uid: childUID).setData(
            ["visitDates": FieldValue.arrayUnion([Timestamp(date: today)])],
            merge: true
        ) { error in
            if let error {
                logger.error("ProfileVC: recordTodayInFirestore failed – \(error)")
            }
        }
    }

    /// Legacy wrapper kept so fetchStreakFromFirestore can still write a pruned
    /// full-array back after a fetch (the only place a full overwrite is correct).
    private func saveDates(_ dates: [Date], forKey key: String) {
        saveDatesToCache(dates, forKey: key)
        let timestamps = dates.map { Timestamp(date: $0) }
        streakRef(uid: childUID).setData(["visitDates": timestamps], merge: true) { error in
            if let error {
                logger.error("ProfileVC: saveDates Firestore write failed – \(error)")
            }
        }
    }

    /// Call once on first load to pull streak dates down from Firestore
    /// and merge with anything already in the local cache.
    private func fetchStreakFromFirestore() {
        let key = "visitDates_\(childUID)"
        streakRef(uid: childUID).getDocument { [weak self] snapshot, error in
            guard let self, let data = snapshot?.data(), error == nil else { return }
            let remote = (data["visitDates"] as? [Timestamp] ?? [])
                .map { Calendar.current.startOfDay(for: $0.dateValue()) }
            var merged = self.loadDates(forKey: key)
            for d in remote where !merged.contains(d) { merged.append(d) }
            let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
            merged = merged.filter { $0 >= cutoff }
            // Use saveDates (not UserDefaults directly) so the merged result
            // is written back to Firestore and becomes visible on all other devices.
            self.saveDates(merged, forKey: key)
            DispatchQueue.main.async { self.updateStreakCard() }
        }
    }

    // MARK: - Reminders
    private func loadReminderState() {
        let uid     = childUID
        let enabled = profileStore.isReminderEnabled(uid: uid)
        let days    = profileStore.reminderDays(uid: uid)

        reminderSwitch.isOn = enabled
        setDayButtonsInteractive(enabled)

        for (i, btn) in dayButtons.enumerated() {
            btn.tintColor           = .clear
            btn.layer.cornerRadius  = btn.bounds.height / 2
            btn.layer.masksToBounds = true
            btn.setTitleColor(.black, for: .normal)
            btn.backgroundColor = days[i] ? yellowOn : whiteOff
        }
    }

    @IBAction func toggleReminderDay(_ sender: UIButton) {
        guard let i = dayButtons.firstIndex(of: sender) else { return }
        var days = profileStore.reminderDays(uid: childUID)
        days[i]  = !days[i]
        profileStore.setReminderDays(days, uid: childUID)
        sender.backgroundColor = days[i] ? yellowOn : whiteOff
        profileStore.scheduleNotifications(uid: childUID)
    }

    @IBAction func reminderSwitchToggled(_ sender: UISwitch) {
        profileStore.setReminderEnabled(sender.isOn, uid: childUID)
        setDayButtonsInteractive(sender.isOn)
        if sender.isOn {
            profileStore.scheduleNotifications(uid: childUID)
        } else {
            profileStore.cancelAllNotifications()
        }
    }

    @IBAction func setReminderTimeTapped(_ sender: UIButton) {
        let alert  = UIAlertController(title: "Reminder Time", message: "\n\n\n\n\n\n", preferredStyle: .alert)
        let picker = UIDatePicker()
        picker.datePickerMode           = .time
        picker.preferredDatePickerStyle = .wheels
        picker.translatesAutoresizingMaskIntoConstraints = false

        var comps    = DateComponents()
        comps.hour   = profileStore.reminderHour(uid: childUID)
        comps.minute = profileStore.reminderMinute(uid: childUID)
        if let date  = Calendar.current.date(from: comps) { picker.date = date }

        alert.view.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor),
            picker.topAnchor.constraint(equalTo: alert.view.topAnchor, constant: 50),
        ])
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self else { return }
            let c = Calendar.current.dateComponents([.hour, .minute], from: picker.date)
            self.profileStore.setReminderTime(hour: c.hour ?? 17, minute: c.minute ?? 0, uid: self.childUID)
            self.profileStore.scheduleNotifications(uid: self.childUID)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func setDayButtonsInteractive(_ on: Bool) {
        dayButtons.forEach {
            $0.isEnabled = on
            $0.alpha     = on ? 1.0 : 0.5
        }
    }

    // MARK: - Profile Image
    private func setupProfileImageTap() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(profileImageTapped))
        profileImage.isUserInteractionEnabled = true
        profileImage.addGestureRecognizer(tap)
        setupPencilButton()
    }

    private func setupPencilButton() {
        guard let parent = profileImage.superview else { return }
        guard parent.viewWithTag(9002) == nil else { return }

        let size: CGFloat = 28
        let pencilButton  = UIButton(type: .system)
        pencilButton.tag  = 9002
        pencilButton.translatesAutoresizingMaskIntoConstraints = false

        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        pencilButton.setImage(UIImage(systemName: "pencil", withConfiguration: config), for: .normal)
        pencilButton.tintColor        = UIColor(red: 0.38, green: 0.22, blue: 0.09, alpha: 1.0)
        pencilButton.backgroundColor  = UIColor(red: 1.0, green: 0.87, blue: 0.51, alpha: 1.0)
        pencilButton.layer.cornerRadius  = size / 2
        pencilButton.layer.masksToBounds = false
        pencilButton.layer.shadowColor   = UIColor.black.cgColor
        pencilButton.layer.shadowOpacity = 0.18
        pencilButton.layer.shadowOffset  = CGSize(width: 0, height: 1)
        pencilButton.layer.shadowRadius  = 3
        pencilButton.isHidden = true

        pencilButton.addTarget(self, action: #selector(profileImageTapped), for: .touchUpInside)
        parent.addSubview(pencilButton)

        NSLayoutConstraint.activate([
            pencilButton.widthAnchor.constraint(equalToConstant: size),
            pencilButton.heightAnchor.constraint(equalToConstant: size),
            pencilButton.trailingAnchor.constraint(equalTo: profileImage.trailingAnchor, constant: 2),
            pencilButton.bottomAnchor.constraint(equalTo: profileImage.bottomAnchor, constant: 2)
        ])
    }

    private func showPencilButton(_ visible: Bool) {
        profileImage.superview?.viewWithTag(9002)?.isHidden = !visible
    }

//    @objc private func profileImageTapped() {
//        let alert = UIAlertController(title: "Profile Photo", message: nil, preferredStyle: .actionSheet)
//        alert.addAction(UIAlertAction(title: "Take Photo",          style: .default) { [weak self] _ in self?.openPicker(.camera) })
//        alert.addAction(UIAlertAction(title: "Choose from Library", style: .default) { [weak self] _ in self?.openPicker(.photoLibrary) })
//        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
//        if let pop = alert.popoverPresentationController {
//            pop.sourceView = profileImage
//            pop.sourceRect = profileImage.bounds
//        }
//        present(alert, animated: true)
//    }
    @objc private func profileImageTapped() {

        let alert = UIAlertController(
            title: "Profile Photo",
            message: nil,
            preferredStyle: .actionSheet
        )

        alert.addAction(UIAlertAction(
            title: "Take Photo",
            style: .default
        ) { [weak self] _ in
            self?.openPicker(.camera)
        })

        alert.addAction(UIAlertAction(
            title: "Choose from Library",
            style: .default
        ) { [weak self] _ in
            self?.openPicker(.photoLibrary)
        })

        // Show remove option only if photo exists
        if profileImage.image != nil {

            alert.addAction(UIAlertAction(
                title: "Remove Photo",
                style: .destructive
            ) { [weak self] _ in

                guard let self else { return }

                let child = childManager.currentChild
                child.profileImageData = nil

                childManager.saveProfileData()

                // Restore default grey profile state immediately
                profileImage.image = nil
                profileImage.backgroundColor = UIColor.systemGray5

                addCameraOverlay()
                showPencilButton(false)

                // Update other screens immediately
                NotificationCenter.default.post(
                    name: .profileImageDidChange,
                    object: nil
                )
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let pop = alert.popoverPresentationController {
            pop.sourceView = profileImage
            pop.sourceRect = profileImage.bounds
        }

        present(alert, animated: true)
    }

    private func openPicker(_ source: UIImagePickerController.SourceType) {
        guard UIImagePickerController.isSourceTypeAvailable(source) else { return }
        let p = UIImagePickerController()
        p.sourceType = source; p.allowsEditing = true; p.delegate = self
        present(p, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let img = (info[.editedImage] ?? info[.originalImage]) as? UIImage else { return }
        profileImage.image = img
        removeCameraOverlay()
        showPencilButton(true)
        NotificationCenter.default.post(name: .profileImageDidChange, object: img)
        let child = childManager.currentChild
        child.profileImageData = img.jpegData(compressionQuality: 0.7)
        childManager.saveProfileData()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    private func addCameraOverlay() {
        guard profileImage.viewWithTag(9001) == nil else { return }
        let overlay = UIView(frame: profileImage.bounds)
        overlay.tag = 9001; overlay.isUserInteractionEnabled = false

        let cam = UIImageView(image: UIImage(systemName: "camera.fill"))
        cam.tintColor = .white; cam.contentMode = .scaleAspectFit
        cam.translatesAutoresizingMaskIntoConstraints = false

        let lbl = UILabel()
        lbl.text = "Add Photo"; lbl.textColor = .white
        lbl.font = .systemFont(ofSize: 12, weight: .medium)
        lbl.textAlignment = .center
        lbl.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [cam, lbl])
        stack.axis = .vertical; stack.spacing = 4; stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            cam.widthAnchor.constraint(equalToConstant: 32),
            cam.heightAnchor.constraint(equalToConstant: 32),
        ])
        profileImage.addSubview(overlay)
    }

    private func removeCameraOverlay() {
        profileImage.viewWithTag(9001)?.removeFromSuperview()
        profileImage.backgroundColor = .clear
    }

    // MARK: - Progress Statistics Row
    /// Builds the "Progress Statistics" card matching the layout of the
    /// Parental Controls / Reminders cards: title row on top, content card below.
    private func setupProgressStatisticsRow() {
        // Walk up: logOutButton → button-stack → LogOut-and-Delete view → Right View
        guard let logOutDeleteView = logOutButton.superview?.superview,
              let rightView = logOutDeleteView.superview else { return }

        // ════════════════════════════════════════════════════════════
        // 1. TITLE LABEL  — matches "Parental Controls" / "Reminders"
        //    (system 22, same dark-grey as other section titles)
        // ════════════════════════════════════════════════════════════
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text      = "Progress Statistics"
        titleLabel.font      = .systemFont(ofSize: 22)
        titleLabel.textColor = UIColor(white: 0.333, alpha: 1.0)

        // ════════════════════════════════════════════════════════════
        // 2. CONTENT CARD — rounded sub-card like the Analytics Lock row
        // ════════════════════════════════════════════════════════════
        let contentCard = UIView()
        contentCard.translatesAutoresizingMaskIntoConstraints = false
        contentCard.backgroundColor    = .clear
        contentCard.layer.cornerRadius = 27
        contentCard.layer.masksToBounds = true
        contentCard.layer.borderColor   = UIColor.black.withAlphaComponent(0.1).cgColor
        contentCard.layer.borderWidth   = 1.0
        contentCard.isUserInteractionEnabled = true

        // ── Content text — matches "Analytics Lock" style (system 22) ──
        let contentLabel = UILabel()
        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        contentLabel.text      = "View Analytics"
        contentLabel.font      = .systemFont(ofSize: 22)
        contentLabel.textColor = .label

        // ── Chevron ──
        let chevron = UIImageView()
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.image       = UIImage(systemName: "chevron.right")
        chevron.tintColor   = .tertiaryLabel
        chevron.contentMode = .scaleAspectFit

        // ── Row: label + chevron ──
        let rowStack = UIStackView(arrangedSubviews: [contentLabel, chevron])
        rowStack.axis      = .horizontal
        rowStack.alignment = .center
        rowStack.spacing   = 10
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        contentCard.addSubview(rowStack)

        // ════════════════════════════════════════════════════════════
        // 3. OUTER WRAPPER — title + content stacked vertically
        // ════════════════════════════════════════════════════════════
        let outerStack = UIStackView(arrangedSubviews: [titleLabel, contentCard])
        outerStack.axis    = .vertical
        outerStack.spacing = 8
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        rightView.addSubview(outerStack)

        // ── Constraints ──
        NSLayoutConstraint.activate([
            // Chevron size
            chevron.widthAnchor.constraint(equalToConstant: 10),
            chevron.heightAnchor.constraint(equalToConstant: 16),
            // Row insets inside the content card (matches Analytics Lock padding)
            rowStack.leadingAnchor.constraint(equalTo: contentCard.leadingAnchor, constant: 15),
            rowStack.trailingAnchor.constraint(equalTo: contentCard.trailingAnchor, constant: -15),
            rowStack.topAnchor.constraint(equalTo: contentCard.topAnchor, constant: 15),
            rowStack.bottomAnchor.constraint(equalTo: contentCard.bottomAnchor, constant: -15),
            // Content card minimum height
            contentCard.heightAnchor.constraint(greaterThanOrEqualToConstant: 70),
            // Outer stack matches the column width
            outerStack.leadingAnchor.constraint(equalTo: logOutDeleteView.leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: logOutDeleteView.trailingAnchor),
        ])

        // Reposition: outer stack sits below the Parental/Reminders stack,
        // LogOut view sits below the outer stack.
        for constraint in rightView.constraints {
            if constraint.firstItem === logOutDeleteView,
               constraint.firstAttribute == .top {
                constraint.isActive = false
                break
            }
        }

        if let parentalStack = rightView.subviews.first(where: { $0 is UIStackView && $0 !== outerStack }) {
            NSLayoutConstraint.activate([
                outerStack.topAnchor.constraint(equalTo: parentalStack.bottomAnchor, constant: 12),
                logOutDeleteView.topAnchor.constraint(equalTo: outerStack.bottomAnchor, constant: 12),
            ])
        }

        // ── Tap gesture — reuses the same Analytics flow (PIN-gated) ──
        let tap = UITapGestureRecognizer(target: self, action: #selector(progressStatisticsTapped))
        contentCard.addGestureRecognizer(tap)

        // ── Make Log Out / Delete Account buttons bigger ──
        for btn in [logOutButton, deleteAccountButton] {
            guard let btn else { continue }
            // Remove any existing storyboard height constraints
            for c in btn.constraints where c.firstAttribute == .height {
                c.isActive = false
            }
            btn.heightAnchor.constraint(equalToConstant: 50).isActive = true
            btn.titleLabel?.font = .systemFont(ofSize: 20, weight: .semibold)
        }
    }

    @objc private func progressStatisticsTapped() {
        if UserDefaults.standard.string(forKey: pinKey) != nil {
            pendingAnalyticsAccess = true
            performSegue(withIdentifier: "showVerifyPIN", sender: self)
        } else {
            pushAnalyticsVC()
        }
    }

    // MARK: - Navigation
    @IBAction func goToAnalyticsTapped(_ sender: UIButton) {
        if UserDefaults.standard.string(forKey: pinKey) != nil {
            pendingAnalyticsAccess = true
            performSegue(withIdentifier: "showVerifyPIN", sender: self)
        } else {
            pushAnalyticsVC()
        }
    }

    var pendingAnalyticsAccess = false

    func analyticsUnlocked() {
        pendingAnalyticsAccess = false
        pushAnalyticsVC()
    }

    private func pushAnalyticsVC() {
        let sb = UIStoryboard(name: "Main", bundle: nil)
        guard let vc = sb.instantiateViewController(withIdentifier: "AnalyticsViewController")
                as? AnalyticsViewController else { return }
        vc.analyticsStore           = analyticsStore
        vc.checkpointHistoryManager = checkpointHistoryManager
        navigationController?.pushViewController(vc, animated: true)
    }

    @IBAction func logOutTapped(_ sender: UIButton) {
        let alert = UIAlertController(
            title: "Log Out",
            message: "Are you sure you want to log out?",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Log Out", style: .destructive) { [weak self] _ in
            guard let self else { return }
            do {
                try Auth.auth().signOut()
                guard let sd = self.view.window?.windowScene?.delegate as? SceneDelegate else { return }
                sd.showAuthAfterSignOut()
            } catch {
                logger.error("ProfileVC: sign out failed – \(error)")
            }
        })
        present(alert, animated: true)
    }

    @IBAction func deleteAccountTapped(_ sender: UIButton) {
        let alert = UIAlertController(
            title: "Delete Account",
            message: "This will permanently delete your account and all progress data. This cannot be undone.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.performAccountDeletion()
        })
        present(alert, animated: true)
    }

    private func performAccountDeletion() {
        guard let user = Auth.auth().currentUser else { return }

        let context = childManager.currentChild.managedObjectContext
        context?.delete(childManager.currentChild)
        try? context?.save()

        user.delete { [weak self] error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let error {
                    let nsError = error as NSError
                    if nsError.code == 17014 {
                        self.showAlert("Please sign out and sign back in, then try deleting again.")
                    } else {
                        self.showAlert("Failed to delete account. Please try again.")
                    }
                    return
                }
                guard let sd = self.view.window?.windowScene?.delegate as? SceneDelegate else { return }
                sd.showAuthAfterSignOut()
            }
        }
    }

    private func showAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @IBAction func homeTapped(_ sender: Any) {
        navigationController?.popViewController(animated: true)
    }

    // MARK: - Parental Controls
    @IBAction func setPinButtonTapped(_ sender: UIButton) {
        if UserDefaults.standard.string(forKey: pinKey) != nil {
            pendingAnalyticsAccess = false
            performSegue(withIdentifier: "showVerifyPIN", sender: self)
        } else {
            performSegue(withIdentifier: "showSetPIN", sender: self)
        }
    }

    @IBAction func forgotPINButtonTapped(_ sender: UIButton) {
        guard let email = Auth.auth().currentUser?.email else {
            showAlert("No email address found for this account.")
            return
        }
        let alert = UIAlertController(
            title: "Forgot PIN",
            message: "A reset link will be sent to \(email). Your current PIN will be cleared so you can set a new one.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Send Email", style: .default) { [weak self] _ in
            guard let self else { return }
            Auth.auth().sendPasswordReset(withEmail: email) { _ in }
            UserDefaults.standard.removeObject(forKey: self.pinKey)
            // Clear PIN from Firestore so other devices see it removed too
            self.infoRef(uid: self.childUID).setData(
                ["pin": FieldValue.delete()], merge: true
            ) { error in
                if let error { logger.error("ProfileVC: forgotPIN Firestore clear failed – \(error)") }
            }
            self.checkPINStatus()
            let confirm = UIAlertController(
                title: "Email Sent",
                message: "Check your inbox. Your PIN has been cleared — tap Set PIN to create a new one.",
                preferredStyle: .alert)
            confirm.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(confirm, animated: true)
        })
        present(alert, animated: true)
    }

    // pinKey is still used for UserDefaults as a local cache.
    // Firestore (users/{uid}/profile/info → "pin") is the cross-device source of truth.
    // fetchProfileInfoFromFirestore() populates UserDefaults on every load.
    private var pinKey: String { "userPIN_\(childUID)" }

    private func checkPINStatus() {
        setPinButton.isEnabled = true
        setPinButton.alpha     = 1.0
        let hasPIN = UserDefaults.standard.string(forKey: pinKey) != nil
        setPinButton.setTitle(hasPIN ? "Change PIN" : "Set PIN", for: .normal)
        forgotPINButton?.isHidden = !hasPIN
    }

    // MARK: - Card UI Setup
    private func applyCardStyles() {
        [streakCard, privacyCard, personalInfoBackground, remindersCard, ParentalControlCard]
            .compactMap { $0 }.forEach { v in
                v.layer.shadowColor        = UIColor.black.cgColor
                v.layer.shadowOpacity      = 0.1
                v.layer.shadowOffset       = CGSize(width: 0, height: 1)
                v.layer.shadowRadius       = 4
                v.layer.masksToBounds      = false
                v.layer.borderColor        = UIColor.black.withAlphaComponent(0.1).cgColor
                v.layer.borderWidth        = 1.0
                v.layer.shouldRasterize    = true
                v.layer.rasterizationScale = traitCollection.displayScale
            }
    }

    private func setupStreakViews() {
        [mondayStreak, tuesdayStreak, wednesdayStreak, thursdayStreak,
         fridayStreak, saturdayStreak, sundayStreak].compactMap { $0 }.forEach {
            $0.layer.cornerRadius  = $0.frame.height / 2
            $0.layer.masksToBounds = true
            $0.layer.borderWidth   = 1.5
        }
    }

    // MARK: - Segue
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "editProfile" {
            let dest   = segue.destination
            let editVC = (dest as? UINavigationController)?.topViewController as? EditPersonalInfo_ViewController
                      ?? dest as? EditPersonalInfo_ViewController

            guard let editVC else { return }
            editVC.delegate         = self
            editVC.childManager     = childManager
            let child               = childManager.currentChild
            editVC.currentFirstName = child.firstName?.nilIfEmpty ?? child.name?.nilIfEmpty ?? ""
            editVC.currentLastName  = child.lastName  ?? ""
            editVC.currentAge       = child.age == 0 ? nil : child.age
            editVC.currentGender    = child.gender    ?? ""

        } else if segue.identifier == "showSetPIN",
                  let vc = segue.destination as? SetPIN_ViewController {
            vc.delegate      = self
            vc.isChangingPIN = false
            vc.pinStorageKey = pinKey

        } else if segue.identifier == "showVerifyPIN",
                  let vc = segue.destination as? VerifyPIN_ViewController {
            vc.pinStorageKey   = pinKey
            vc.profileVC       = self
            vc.isAnalyticsGate = pendingAnalyticsAccess
        }
    }

    // MARK: - Delegates
    func didUpdatePersonalInfo(firstName: String, lastName: String, age: Int16, gender: String) {
        self.firstName.text   = firstName
        self.lastName.text    = lastName
        self.age.text         = age == 0 ? "" : String(age)
        self.gender.text      = gender
        self.profileName.text = firstName.nilIfEmpty ?? self.profileName.text
        // Persist cross-device
        saveProfileInfoToFirestore(firstName: firstName, lastName: lastName, age: age, gender: gender)
    }

    func didSetPIN(_ pin: String) {
        checkPINStatus()
        // Persist PIN to Firestore so it syncs to all devices
        let child = childManager.currentChild
        let fn    = child.firstName ?? ""
        let ln    = child.lastName  ?? ""
        let gn    = child.gender    ?? ""
        let ag    = Int(child.age)
        infoRef(uid: childUID).setData(
            ["firstName": fn, "lastName": ln, "gender": gn, "age": ag, "pin": pin],
            merge: true
        ) { error in
            if let error { logger.error("ProfileVC: didSetPIN Firestore write failed – \(error)") }
        }
    }
}

// MARK: - Helpers
private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension Notification.Name {
    static let profileImageDidChange = Notification.Name("profileImageDidChange")
}
