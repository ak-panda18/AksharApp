import SwiftUI

struct LearningPathHomeView: View {
    @ObservedObject var orchestrator: SessionOrchestrator
    var onExitTapped: () -> Void

    // MARK: - Animation state
    @State private var teddyOpacity: Double = 0.0
    @State private var teddyOffset: CGFloat = 30
    @State private var floatOffset: CGFloat = 0
    @State private var textOpacity: Double = 0.0
    @State private var btnVisible: Bool = false

    var body: some View {
        ZStack {

            // ── Full-bleed background ─────────────────────────────────────
            Image("alternateBackground")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea(.all)

            // ── Greeting teddy — centred in the ZStack ────────────────────
            Image("greeting_teddy")
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 520)
                .padding(.horizontal, 20)
                .offset(y: floatOffset + teddyOffset)
                .opacity(teddyOpacity)
                .onAppear {
                    withAnimation(.spring(response: 0.65, dampingFraction: 0.65).delay(0.1)) {
                        teddyOffset  = 0
                        teddyOpacity = 1.0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                        withAnimation(
                            Animation.easeInOut(duration: 2.5)
                                .repeatForever(autoreverses: true)
                        ) { floatOffset = -10 }
                    }
                }

            // ── Overlay layer: X button (top) + text (bottom) ─────────────
            VStack(spacing: 0) {

                // X exit button — top-left
                HStack {
                    Button(action: onExitTapped) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.yellow)
                            .frame(width: 48, height: 48)
                            .background(Color(red: 0.38, green: 0.22, blue: 0.09))
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
                    }
                    .padding(.leading, 24)
                    .padding(.top, 56)
                    Spacer()
                }

                Spacer()

                // Text block — bottom of screen
                VStack(spacing: 8) {
                    Text("Hello Kiddo!")
                        .font(.custom("ArialRoundedMTBold", size: 46))
                        .foregroundColor(Color(red: 0.27, green: 0.13, blue: 0.04))
                        .multilineTextAlignment(.center)

                    Text("Ready to learn today?")
                        .font(.custom("ArialRoundedMTBold", size: 22))
                        .foregroundColor(Color(red: 0.38, green: 0.22, blue: 0.09).opacity(0.75))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 100)
                .opacity(textOpacity)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
                        textOpacity = 1.0
                    }
                }
            }
            .ignoresSafeArea(.all)

            // ── Arrow button — bottom-right ───────────────────────────────
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: { orchestrator.startSession() }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.yellow)
                            .frame(width: 66, height: 66)
                            .background(Color(red: 0.38, green: 0.22, blue: 0.09))
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
                    }
                    .opacity(btnVisible ? 1 : 0)
                    .onAppear {
                        withAnimation(.easeOut(duration: 0.5).delay(0.9)) {
                            btnVisible = true
                        }
                    }
                    .padding(.trailing, 32)
                    .padding(.bottom, 44)
                }
            }
            .ignoresSafeArea(.all)
        }
        .ignoresSafeArea(.all)
    }
}
