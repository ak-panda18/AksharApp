import SwiftUI

struct LearningPathHomeView: View {
    @ObservedObject var orchestrator: SessionOrchestrator
    
    @State private var teddyScale: CGFloat = 0.7
    @State private var teddyOpacity: Double = 0.0
    @State private var pillOpacities: [Double] = [0.0, 0.0, 0.0]
    @State private var pillOffsets: [CGFloat] = [8, 8, 8]
    @State private var ctaScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            Color.aksharCreamBG.edgesIgnoringSafeArea(.all)
            
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        // Profile Action
                    }) {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .foregroundColor(.aksharGoldDark)
                    }
                    .padding()
                }
                
                Text("Good morning!")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Today's session is ready")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Image(systemName: "star.fill") // placeholder for reader_teddy
                    .resizable()
                    .scaledToFit()
                    .frame(height: 120)
                    .foregroundColor(.aksharPrimaryGold)
                    .scaleEffect(teddyScale)
                    .opacity(teddyOpacity)
                    .onAppear {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)) {
                            teddyScale = 1.0
                            teddyOpacity = 1.0
                        }
                    }
                
                VStack(spacing: 12) {
                    Text("TODAY'S ORDER — WEAKEST FIRST")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.aksharGoldDark)
                    
                    if let plan = orchestrator.todaysPlan {
                        ForEach(Array(plan.order.enumerated()), id: \.offset) { index, module in
                            HStack {
                                Text("\(index + 1)")
                                    .font(.headline)
                                    .foregroundColor(index == 0 ? .white : .aksharGoldDark)
                                    .frame(width: 24, height: 24)
                                    .background(index == 0 ? Color.aksharPrimaryGold : Color.clear)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.aksharPrimaryGold, lineWidth: index == 0 ? 0 : 2)
                                    )
                                
                                Text(module.name)
                                    .font(.headline)
                                Spacer()
                            }
                            .padding()
                            .background(Color.aksharCreamBG)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(index == 0 ? Color.clear : Color.aksharPrimaryGold, lineWidth: 1)
                            )
                            .opacity(pillOpacities[index])
                            .offset(y: pillOffsets[index])
                            .onAppear {
                                withAnimation(.easeOut(duration: 0.3).delay(Double(index) * 0.1)) {
                                    pillOpacities[index] = 1.0
                                    pillOffsets[index] = 0
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(Color.aksharGoldLight)
                .cornerRadius(16)
                .padding()
                
                Spacer()
                
                Button(action: {
                    orchestrator.startSession()
                }) {
                    Text("Start session")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.aksharPrimaryGold)
                        .cornerRadius(25)
                }
                .scaleEffect(ctaScale)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                            ctaScale = 1.03
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                                ctaScale = 1.0
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }
}
