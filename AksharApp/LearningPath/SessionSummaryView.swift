import SwiftUI

struct SessionSummaryView: View {
    @ObservedObject var orchestrator: SessionOrchestrator
    
    @State private var showConfetti = false
    @State private var starScale: CGFloat = 0.0
    @State private var chipOpacities: [Double] = [0.0, 0.0, 0.0]
    @State private var chipOffsets: [CGFloat] = [12, 12, 12]
    @State private var homeBtnOpacity: Double = 0.0
    
    var body: some View {
        ZStack {
            Color.white.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 28) {
                Text("🌟")
                    .font(.system(size: 72))
                    .scaleEffect(starScale)
                    .onAppear {
                        showConfetti = true
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.4)) {
                            starScale = 1.2
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.4)) {
                                starScale = 1.0
                            }
                        }
                    }
                
                VStack(spacing: 8) {
                    Text("You did it!")
                        .font(.largeTitle)
                        .bold()
                        .foregroundColor(.primary)
                    
                    Text("Amazing session today.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 12) {
                    ForEach(Array(orchestrator.completedModules.enumerated()), id: \.offset) { index, module in
                        VStack {
                            Text(moduleEmoji(module))
                                .font(.system(size: 28))
                            Text(module.name)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.aksharGoldDark)
                        }
                        .frame(width: 80)
                        .padding(.vertical, 12)
                        .background(Color.aksharGoldLight)
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color(hex: 0xE8D4A8), lineWidth: 0.5)
                        )
                        .opacity(chipOpacities.indices.contains(index) ? chipOpacities[index] : 1.0)
                        .offset(y: chipOffsets.indices.contains(index) ? chipOffsets[index] : 0)
                        .onAppear {
                            if chipOpacities.indices.contains(index) {
                                withAnimation(.easeOut(duration: 0.35).delay(Double(index) * 0.12)) {
                                    chipOpacities[index] = 1.0
                                    chipOffsets[index] = 0
                                }
                            }
                        }
                    }
                }
                
                HStack {
                    Text("Streak updated")
                        .bold()
                    HStack {
                        ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { day in
                            Text(day)
                                .font(.caption2)
                                .frame(width: 20, height: 20)
                                .background(Color.aksharPrimaryGold)
                                .foregroundColor(.white)
                                .clipShape(Circle())
                        }
                    }
                }
                .padding()
                .background(Color.aksharCreamBG)
                .cornerRadius(16)
                
                Spacer()
                
                Button(action: {
                    orchestrator.phase = .idle
                }) {
                    Text("Go home")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.aksharPrimaryGold)
                        .cornerRadius(25)
                }
                .opacity(homeBtnOpacity)
                .onAppear {
                    withAnimation(.easeIn(duration: 0.3).delay(0.9)) {
                        homeBtnOpacity = 1.0
                    }
                }
                .padding(.bottom, 40)
                .padding(.horizontal)
            }
            .padding(.top, 40)
        }
    }
    
    private func moduleEmoji(_ module: AksharModule) -> String {
        switch module {
        case .phonics: return "🎵"
        case .writing: return "✏️"
        case .reading: return "📖"
        }
    }
}
