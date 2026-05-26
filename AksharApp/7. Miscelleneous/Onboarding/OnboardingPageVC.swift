import UIKit

class OnboardingPageVC: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {

    private let pageControl = UIPageControl()
    private var autoScrollTimer: Timer?

    let titles = [
        "Welcome to Akshar !",
        "Reading Made Clear",
        "Untangle Your Writing",
        "Build With Sounds"
    ]

    let subtitles = [
        " ",
        "Find your rhythm and master every word !",
        "Practice writing every day until your words flow smoothly !",
        "Play through games until every sound clicks into place !"
    ]

    let backgroundImages = [
        UIImage(named: "unnamed-5"),
        UIImage(named: "unnamed"),
        UIImage(named: "unnamed-2"),
        UIImage(named: "unnamed-3")
    ]

    override func viewDidLoad() {
        super.viewDidLoad()

        // TODO: Uncomment the condition below to skip onboarding if the user has already seen it.
         if UserDefaults.standard.bool(forKey: "hasSeenOnboarding") {
             navigateToSignUp()
             return
         }

        dataSource = self
        delegate = self
        guard let firstVC = makePage(at: 0) else { return }
        setViewControllers([firstVC], direction: .forward, animated: false)
        setupPageControl()
        view.bringSubviewToFront(pageControl)
        startAutoScroll()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopAutoScroll()
    }

    private func startAutoScroll() {
        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            self?.scrollToNextPage()
        }
    }

    private func stopAutoScroll() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }

    private func scrollToNextPage() {
        guard let currentVC = viewControllers?.first as? OnboardingContentVC else { return }

        let nextIndex = currentVC.pageIndex + 1
        
        if nextIndex < titles.count {
            guard let nextVC = makePage(at: nextIndex) else { return }
            setViewControllers([nextVC], direction: .forward, animated: true)
            pageControl.currentPage = nextIndex
        } else {
            stopAutoScroll()
        }
    }

    private func setupPageControl() {
        pageControl.numberOfPages = titles.count
        pageControl.currentPage = 0
        pageControl.pageIndicatorTintColor = .systemGray3
        pageControl.currentPageIndicatorTintColor = .systemYellow
        pageControl.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(pageControl)
        view.bringSubviewToFront(pageControl)

        NSLayoutConstraint.activate([
            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -80)
        ])
    }

    func makePage(at index: Int) -> OnboardingContentVC? {
        guard index >= 0 && index < titles.count else { return nil }

        let vc = storyboard?.instantiateViewController(
            withIdentifier: "OnboardingContentVC"
        ) as! OnboardingContentVC

        vc.pageIndex = index
        vc.titleText = titles[index]
        vc.subtitleText = subtitles[index]
        vc.backgroundImage = backgroundImages[index]
        vc.isLastPage = (index == titles.count - 1)
        
        return vc
    }
    
    func navigateToSignUp() {
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")

        guard let sceneDelegate = UIApplication.shared.connectedScenes
            .first?.delegate as? SceneDelegate,
              let container = sceneDelegate.container
        else { return }

        sceneDelegate.showAuth(container: container, startAtSignUp: true)
    }

    // MARK: - DataSource
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        let i = (viewController as! OnboardingContentVC).pageIndex
        return makePage(at: i + 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        let i = (viewController as! OnboardingContentVC).pageIndex
        return makePage(at: i - 1)
    }

    // MARK: - Delegate
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let currentVC = pageViewController.viewControllers?.first as? OnboardingContentVC else { return }
        
        pageControl.currentPage = currentVC.pageIndex
        
        if currentVC.pageIndex == titles.count - 1 {
            stopAutoScroll()
            currentVC.animateButtonIn()
        }
    }
}
