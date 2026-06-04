import SwiftUI

/// Shown before every module starts — "Begin with Phonics", "Continue with Writing", etc.
struct LearningPathPreviewView: View {
    @ObservedObject var orchestrator: SessionOrchestrator
    let module: AksharModule
    let isFirst: Bool
    var onExitTapped: () -> Void

    @State private var teddyOpacity: Double = 0
    @State private var teddyOffset: CGFloat = 28
    @State private var floatOffset: CGFloat = 0
    @State private var textOpacity: Double = 0
    @State private var btnVisible: Bool = false

    var titleText: String {
        isFirst ? "Begin with \(module.name)!" : "Continue with \(module.name)!"
    }

    var subtitleText: String {
        switch module {
        case .phonics: return "Let's warm up your ears!"
        case .writing: return "Time to trace some letters!"
        case .reading: return "Pick up where you left off!"
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {

            // ── Full-bleed background ─────────────────────────────────────
            Image("alternateBackground")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea(.all)

            // ── X exit button — top-left ──────────────────────────────────
            VStack {
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
            }
            .ignoresSafeArea(.all)

            // ── Content column ────────────────────────────────────────────
            VStack(spacing: 0) {

                Image(module.teddyImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                    .offset(y: floatOffset + teddyOffset)
                    .opacity(teddyOpacity)
                    .onAppear {
                        withAnimation(.spring(response: 0.60, dampingFraction: 0.65).delay(0.08)) {
                            teddyOffset  = 0
                            teddyOpacity = 1.0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                            withAnimation(
                                Animation.easeInOut(duration: 2.4)
                                    .repeatForever(autoreverses: true)
                            ) { floatOffset = -10 }
                        }
                    }

                Spacer(minLength: 0)

                VStack(spacing: 8) {
                    Text(titleText)
                        .font(.custom("ArialRoundedMTBold", size: 42))
                        .foregroundColor(Color(red: 0.27, green: 0.13, blue: 0.04))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitleText)
                        .font(.custom("ArialRoundedMTBold", size: 21))
                        .foregroundColor(Color(red: 0.38, green: 0.22, blue: 0.09).opacity(0.75))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)
                .opacity(textOpacity)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.45).delay(0.25)) {
                        textOpacity = 1.0
                    }
                }

                // Equal spacer below text pushes it to midpoint between teddy and button
                Spacer(minLength: 90)
            }
            .ignoresSafeArea(.all)

            // ── Bottom-right circle arrow ────────────────────────────────
            HStack {
                Spacer()
                Button(action: { orchestrator.beginCurrentModule() }) {
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
                    withAnimation(.easeOut(duration: 0.5).delay(0.7)) {
                        btnVisible = true
                    }
                }
                .padding(.trailing, 32)
                .padding(.bottom, 44)
            }
            .ignoresSafeArea(.all)
        }
        .ignoresSafeArea(.all)
    }
}
