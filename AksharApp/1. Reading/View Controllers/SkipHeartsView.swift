import SwiftUI

struct SkipHeartsView: View {
    let skipCount: Int
    let maxSkips: Int = 3
    
    var body: some View {
        HStack(spacing: 15) {
            ForEach(0..<maxSkips, id: \.self) { index in
                Image(systemName: index < skipCount ? "heart.fill" : "heart")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 50, height: 50)
                    .foregroundColor(index < skipCount ? .red : .gray)
                    .shadow(color: index < skipCount ? .red.opacity(0.3) : .clear, radius: 5)
            }
        }
        .padding(.vertical, 10)
    }
}

#Preview {
    SkipHeartsView(skipCount: 2)
}
