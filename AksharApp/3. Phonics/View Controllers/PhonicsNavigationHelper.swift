import UIKit

extension UIViewController {
    func goBackToPhonicsCover() {
        guard let nav = navigationController else { return }

        for vc in nav.viewControllers {
            if vc is PhonicsCoverViewController {
                nav.popToViewController(vc, animated: false)
                return
            }
        }
    }
    func goHomeFromPhonics() {
        // popToRootViewController returns to LearningPathHostVC when guided mode is on.
        // LearningPathHostVC.viewWillAppear() automatically resets the orchestrator
        // phase from .inProgress → .previewing so the guided flow resumes correctly.
        navigationController?.popToRootViewController(animated: true)
    }
}

