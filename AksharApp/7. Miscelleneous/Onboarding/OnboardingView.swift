import SwiftUI
import Combine

// MARK: - Data Model
struct OnboardingPage {
    let sceneImageName: String
    let title: String
    let subtitle: String
    var shiftImageRight: Bool = false
}

// MARK: - Main Onboarding View
struct OnboardingView: View {

    var onFinished: () -> Void

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            sceneImageName: "onboarding_opening",
            title: "Welcome to Aksharr !",
            subtitle: "",
            shiftImageRight: true
        ),
        OnboardingPage(
            sceneImageName: "onboarding_reading",
            title: "Reading Made Clear",
            subtitle: "Find your rhythm and master every word !"
        ),
        OnboardingPage(
            sceneImageName: "onboarding_writing",
            title: "Untangle Your Writing",
            subtitle: "Practice writing every day until your words flow smoothly !"
        ),
        OnboardingPage(
            sceneImageName: "onboarding_phonics",
            title: "Build With Sounds",
            subtitle: "Play through games until every sound clicks into place !"
        )
    ]

    @State private var currentIndex: Int = 0
    private let autoScrollInterval: TimeInterval = 4.0

    private var pagingTabView: some View {
        TabView(selection: $currentIndex) {
            ForEach(pages.indices, id: \.self) { idx in
                OnboardingPageView(
                    page: pages[idx],
                    isLast: idx == pages.count - 1,
                    onGetStarted: onFinished
                )
                .tag(idx)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.easeInOut(duration: 0.45), value: currentIndex)
    }

    private var pageDotsView: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { idx in
                let isActive = (idx == currentIndex)
                Circle()
                    .fill(isActive
                          ? Color(red: 0.87, green: 0.70, blue: 0.20)
                          : Color.gray.opacity(0.4))
                    .frame(width: isActive ? 10 : 8, height: isActive ? 10 : 8)
                    .animation(.easeInOut(duration: 0.25), value: currentIndex)
            }
        }
        .padding(.bottom, 52)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            pagingTabView
            pageDotsView
        }
        .ignoresSafeArea()
        .onReceive(Timer.publish(every: autoScrollInterval, on: .main, in: .common).autoconnect()) { _ in
            if currentIndex < pages.count - 1 {
                currentIndex += 1
            }
        }
    }
}

// MARK: - Single Page View
private struct OnboardingPageView: View {
    let page: OnboardingPage
    let isLast: Bool
    var onGetStarted: () -> Void

    @State private var buttonVisible: Bool = false

    private func arialRounded(_ size: CGFloat) -> Font {
        .custom("ArialRoundedMTBold", size: size)
    }

    private var isFirstPage: Bool { page.shiftImageRight }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {

                VStack(spacing: 0) {

                    Image("boardingText")
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width * 0.52)
                        .padding(.top, geo.safeAreaInsets.top + 24)

                    Spacer(minLength: 6)

                    Image(page.sceneImageName)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: geo.size.height * (isFirstPage ? 0.50 : 0.56))
                        .scaleEffect(isFirstPage ? 1.3 : 1.0)
                        .padding(.horizontal, isFirstPage ? 0 : 10)
                        .offset(x: page.shiftImageRight ? (geo.size.width * 0.04) : 0)

                    Spacer(minLength: 2)

                    Text(page.title)
                        .font(arialRounded(geo.size.width * 0.056))
                        .foregroundColor(Color(red: 0.27, green: 0.13, blue: 0.04))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)

                    if !page.subtitle.isEmpty || isLast {
                        HStack(alignment: .bottom, spacing: 12) {
                            Spacer()

                            if !page.subtitle.isEmpty {
                                Text(page.subtitle)
                                    .font(arialRounded(geo.size.width * 0.034))
                                    .foregroundColor(Color(red: 0.27, green: 0.13, blue: 0.04))
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, isLast ? 0 : 32)
                                    .padding(.top, 4)
                            }

                            if isLast {
                                Button(action: onGetStarted) {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.yellow)
                                        .frame(width: 60, height: 60)
                                        .background(Color(red: 0.38, green: 0.22, blue: 0.09))
                                        .clipShape(Circle())
                                }
                                .opacity(buttonVisible ? 1 : 0)
                                .onAppear {
                                    withAnimation(.easeOut(duration: 0.5).delay(0.8)) {
                                        buttonVisible = true
                                    }
                                }
                                .padding(.trailing, 32)
                            }

                            if !isLast { Spacer() }
                        }
                        .padding(.top, 4)
                    }

                    Spacer(minLength: 60)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .background(Color.white)
        }
    }
}
