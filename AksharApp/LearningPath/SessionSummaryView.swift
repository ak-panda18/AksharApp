import SwiftUI

struct SessionSummaryView: View {
    @ObservedObject var orchestrator: SessionOrchestrator

    // MARK: - Animation state
    @State private var teddyScale: CGFloat = 0.5
    @State private var teddyOpacity: Double = 0
    @State private var floatOffset: CGFloat = 0
    @State private var titleOpacity: Double = 0
    @State private var chipsOpacity: [Double] = [0, 0, 0]
    @State private var chipsOffset:  [CGFloat] = [16, 16, 16]
    @State private var btnOpacity: Double = 0

    var body: some View {
        ZStack(alignment: .bottom) {

            // ── Full-bleed cloud background ─────────────────────────────
            Image("alternateBackground")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea(.all)

            // Light overlay so cards are readable
            Color.white.opacity(0.18)
                .ignoresSafeArea(.all)

            // ── Content ──────────────────────────────────────────────────
            VStack(spacing: 0) {

                Spacer(minLength: 50)

                // Happy teddy
                Image("happy_teddy")
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
                    .scaleEffect(teddyScale)
                    .opacity(teddyOpacity)
                    .offset(y: floatOffset)
                    .onAppear {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.55)) {
                            teddyScale   = 1.0
                            teddyOpacity = 1.0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            withAnimation(
                                Animation.easeInOut(duration: 2.2)
                                    .repeatForever(autoreverses: true)
                            ) { floatOffset = -8 }
                        }
                    }

                // Title
                VStack(spacing: 6) {
                    Text("You did it! 🌟")
                        .font(.custom("ArialRoundedMTBold", size: 34))
                        .foregroundColor(Color(red: 0.27, green: 0.13, blue: 0.04))
                    Text("Amazing session today — keep it up!")
                        .font(.custom("ArialRoundedMTBold", size: 16))
                        .foregroundColor(Color(red: 0.38, green: 0.22, blue: 0.09).opacity(0.75))
                        .multilineTextAlignment(.center)
                }
                .opacity(titleOpacity)
                .onAppear {
                    withAnimation(.easeIn(duration: 0.35).delay(0.3)) {
                        titleOpacity = 1.0
                    }
                }
                .padding(.top, 18)
                .padding(.horizontal, 24)

                // Completed module chips
                HStack(spacing: 12) {
                    ForEach(Array(orchestrator.completedModules.enumerated()), id: \.offset) { index, module in
                        VStack(spacing: 8) {
                            Image(module.teddyImageName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 52, height: 52)
                            Text(module.name)
                                .font(.custom("ArialRoundedMTBold", size: 11))
                                .foregroundColor(Color(red: 0.38, green: 0.22, blue: 0.09))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color(red: 1, green: 0.97, blue: 0.92).opacity(0.9))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(Color(red: 0.91, green: 0.83, blue: 0.66), lineWidth: 1)
                                )
                        )
                        .opacity(chipsOpacity.indices.contains(index) ? chipsOpacity[index] : 1)
                        .offset(y: chipsOffset.indices.contains(index) ? chipsOffset[index] : 0)
                        .onAppear {
                            if chipsOpacity.indices.contains(index) {
                                withAnimation(.easeOut(duration: 0.35).delay(0.5 + Double(index) * 0.12)) {
                                    chipsOpacity[index] = 1.0
                                    chipsOffset[index]  = 0
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)

                // Streak badge
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(Color(red: 0.79, green: 0.53, blue: 0.06))
                        .font(.system(size: 14))
                    Text("Streak updated — great work!")
                        .font(.custom("ArialRoundedMTBold", size: 13))
                        .foregroundColor(Color(red: 0.27, green: 0.13, blue: 0.04))
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 18)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(red: 1, green: 0.97, blue: 0.92).opacity(0.9))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color(red: 0.79, green: 0.66, blue: 0.43), lineWidth: 1)
                        )
                )
                .padding(.top, 18)

                Spacer()

                // Go Home button
                Button(action: { orchestrator.phase = .idle }) {
                    HStack(spacing: 10) {
                        Image(systemName: "house.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text("Go Home")
                            .font(.custom("ArialRoundedMTBold", size: 18))
                    }
                    .foregroundColor(.yellow)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(red: 0.38, green: 0.22, blue: 0.09))
                    .cornerRadius(30)
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .opacity(btnOpacity)
                .onAppear {
                    withAnimation(.easeIn(duration: 0.3).delay(1.0)) {
                        btnOpacity = 1.0
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 50)
            }
            .ignoresSafeArea(.all)
        }
        .ignoresSafeArea(.all)
    }
}
