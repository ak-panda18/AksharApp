import SwiftUI

struct SessionTransitionView: View {
    @ObservedObject var orchestrator: SessionOrchestrator
    
    @State private var emojiScale: CGFloat = 0.5
    @State private var arrowOffset: CGFloat = 0
    @State private var cardOpacity: Double = 0.0
    @State private var cardOffset: CGFloat = 30
    @State private var ctaOpacity: Double = 0.0
    
    var completedModule: AksharModule
    var nextModule: AksharModule
    
    var body: some View {
        ZStack {
            Color.aksharSurfaceDark.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 32) {
                Text(moduleEmoji(completedModule))
                    .font(.system(size: 48))
                    .scaleEffect(emojiScale)
                    .onAppear {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                            emojiScale = 1.3
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                                emojiScale = 1.0
                            }
                        }
                    }
                
                VStack(spacing: 8) {
                    Text("You found the sounds!")
                        .font(.title2)
                        .bold()
                        .foregroundColor(.white)
                    
                    Text("Your ears are really sharp today.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Image(systemName: "arrow.down.circle.fill")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .foregroundColor(.aksharPrimaryGold)
                    .offset(y: arrowOffset)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                                arrowOffset = -3
                            }
                        }
                    }
                
                VStack(spacing: 8) {
                    Text("NEXT UP")
                        .font(.system(size: 9))
                        .fontWeight(.bold)
                        .foregroundColor(.aksharPrimaryGold)
                        .tracking(2)
                    
                    VStack(spacing: 12) {
                        Image(systemName: "pencil") // fallback
                            .resizable()
                            .scaledToFit()
                            .frame(height: 120)
                            .foregroundColor(.white)
                        
                        Text("\(nextModule.name) Practice")
                            .font(.title3)
                            .bold()
                            .foregroundColor(.white)
                        
                        Text("Time to learn some more!")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.aksharSurfaceDark)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.aksharMuted, lineWidth: 1)
                    )
                    .opacity(cardOpacity)
                    .offset(y: cardOffset)
                    .onAppear {
                        withAnimation(.easeOut(duration: 0.4).delay(0.25)) {
                            cardOpacity = 1.0
                            cardOffset = 0
                        }
                    }
                }
                
                Spacer()
                
                Button(action: {
                    orchestrator.confirmTransition()
                }) {
                    Text("Let's go! 🚀")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.aksharPrimaryGold)
                        .cornerRadius(25)
                }
                .opacity(ctaOpacity)
                .onAppear {
                    withAnimation(.easeIn(duration: 0.3).delay(0.6)) {
                        ctaOpacity = 1.0
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
