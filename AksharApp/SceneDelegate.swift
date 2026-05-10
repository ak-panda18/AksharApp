import UIKit
import SwiftUI
import FirebaseCore
import FirebaseAuth

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    var container: AppDependencyContainer?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {

        guard let _ = (scene as? UIWindowScene) else { return }

        let c = AppDependencyContainer()
        container = c

        // One-time JSON → CoreData migration. Runs once per install, no-ops thereafter.
        c.analyticsStore.migrateJSONToCoreData()

        if let currentUser = Auth.auth().currentUser {
            c.childManager.resolveChild(uid: currentUser.uid)
            showHome(container: c)
        } else {
            // TODO: Uncomment the condition below to only show onboarding if the user has never seen it.
            // if UserDefaults.standard.bool(forKey: "hasSeenOnboarding") {
            //     showAuth(container: c)
            // } else {
            //     showOnboarding()
            // }
            
            // For now, always show onboarding:
            showOnboarding()
        }
    }

    func showOnboarding() {
        guard let c = container else { return }
        let onboardingView = OnboardingView {
            self.showAuth(container: c, startAtSignUp: true)
        }
        let host = UIHostingController(rootView: onboardingView)
        host.modalPresentationStyle = .fullScreen
        window?.rootViewController = host
    }

    func showHome(container c: AppDependencyContainer) {
        let sb = UIStoryboard(name: "Main", bundle: nil)
        guard let homeNav = sb.instantiateViewController(
            withIdentifier: "HomeNavController") as? UINavigationController,
              let homeVC = homeNav.viewControllers.first as? HomeViewController
        else { return }
        c.inject(into: homeVC)
        window?.rootViewController = homeNav
    }

    func showAuth(container c: AppDependencyContainer, startAtSignUp: Bool = false) {
        let sb = UIStoryboard(name: "Main", bundle: nil)
        guard let signInVC = sb.instantiateViewController(
            withIdentifier: "SignInViewController") as? SignInViewController
        else { return }
        signInVC.childManager = c.childManager
        
        var vcs: [UIViewController] = [signInVC]
        
        if startAtSignUp, let signUpVC = sb.instantiateViewController(
            withIdentifier: "SignUpViewController") as? SignUpViewController {
            signUpVC.childManager = c.childManager
            vcs.append(signUpVC)
        }
        
        let nav = UINavigationController()
        nav.viewControllers = vcs
        nav.setNavigationBarHidden(true, animated: false)
        window?.rootViewController = nav
    }

    func showHomeAfterAuth() {
        guard let c = container else {
            let fresh = AppDependencyContainer()
            container = fresh
            if let uid = Auth.auth().currentUser?.uid {
                fresh.childManager.resolveChild(uid: uid)
            }
            _navigateHome(container: fresh)
            return
        }
        if let uid = Auth.auth().currentUser?.uid {
            c.childManager.resolveChild(uid: uid)
        }
        _navigateHome(container: c)
    }

    private func _navigateHome(container c: AppDependencyContainer) {
        let sb = UIStoryboard(name: "Main", bundle: nil)
        guard let homeNav = sb.instantiateViewController(
            withIdentifier: "HomeNavController") as? UINavigationController,
              let homeVC = homeNav.viewControllers.first as? HomeViewController
        else { return }
        c.inject(into: homeVC)
        window?.rootViewController = homeNav
        UIView.transition(with: window!, duration: 0.35,
                          options: .transitionCrossDissolve, animations: nil)
    }

    func showAuthAfterSignOut() {
        container?.coreDataStack.flushPendingSave()

        let fresh = AppDependencyContainer()
        container = fresh

        showAuth(container: fresh)
    }

    // MARK: - Scene Lifecycle
    func sceneDidDisconnect(_ scene: UIScene) {}

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard let uid = container?.childManager.currentChild.id?.uuidString else { return }
        container?.profileStore.recordAppOpen(uid: uid)
    }

    func sceneWillResignActive(_ scene: UIScene) {}
    func sceneWillEnterForeground(_ scene: UIScene) {}

    func sceneDidEnterBackground(_ scene: UIScene) {
        container?.coreDataStack.flushPendingSave()
    }
}
