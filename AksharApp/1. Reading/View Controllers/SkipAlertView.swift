import SwiftUI

// MARK: - App Theme Colors
// Brown: #805737  →  RGB(128, 87, 55)
// Yellow: systemYellow (used for borders & buttons throughout the app)
private let appBrown = Color(red: 128/255, green: 87/255, blue: 55/255)
private let appYellow = Color(UIColor.systemYellow)
private let selectButtonBrown = Color(red: 0.4782714844, green: 0.3479003906, blue: 0.2358398587)
private let skipAlertWidth = min(UIScreen.main.bounds.width - 80, 620)

// MARK: - Full-Screen Skip Alert (Pure SwiftUI)
struct SkipAlertView: View {
    let availableTickets: Int
    var onUseTicket: () -> Void
    var onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 22) {

                // 1️⃣ Title
                Text("Use Magic Ticket?")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(appBrown)
                    .padding(.top, 8)

                // 2️⃣ Three Tilted Tickets
                HStack(spacing: 18) {
                    ForEach(0..<3, id: \.self) { index in
                        TicketView(isAvailable: index < availableTickets)
                            .rotationEffect(.degrees(18))
                    }
                }
                .padding(.vertical, 8)

                // 3️⃣ Description
                Text("You have \(availableTickets) ticket\(availableTickets == 1 ? "" : "s") left!\nNew tickets are ready every 2 days.")
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(appBrown.opacity(0.7))
                    .padding(.horizontal, 10)

                // 4️⃣ Action Button (compact, not full width)
                Button(action: onUseTicket) {
                    Text("Use Ticket & Skip")
                        .font(.custom("ArialRoundedMTBold", size: 21))
                        .foregroundColor(.white)
                        .frame(height: 60)
                        .padding(.horizontal, 28)
                        .background(selectButtonBrown)
                        .clipShape(Capsule())
                }

                // 5️⃣ Cancel
                Button(action: onCancel) {
                    Text("Not Now")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 4)
            }
            .padding(24)
            .frame(width: skipAlertWidth)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(25)
            .overlay(
                RoundedRectangle(cornerRadius: 25)
                    .stroke(appYellow, lineWidth: 5)
            )
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
            .padding(.horizontal, 100)
        }
    }
}

// MARK: - Individual Ticket
struct TicketView: View {
    let isAvailable: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(isAvailable ? appYellow : Color.gray.opacity(0.25))
                .frame(width: 65, height: 40)

            HStack {
                Circle()
                    .fill(Color(UIColor.systemBackground))
                    .frame(width: 10, height: 10)
                    .offset(x: -5)
                Spacer()
                Circle()
                    .fill(Color(UIColor.systemBackground))
                    .frame(width: 10, height: 10)
                    .offset(x: 5)
            }
            .frame(width: 65)

            if isAvailable {
                Image(systemName: "star.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(appBrown)
            } else {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.gray.opacity(0.4))
            }
        }
        .shadow(color: isAvailable ? appYellow.opacity(0.4) : .clear, radius: 4, x: 0, y: 2)
    }
}

// MARK: - No Tickets Alert
struct NoTicketsAlertView: View {
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 22) {
                Text("No Tickets Left!")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(appBrown)
                    .padding(.top, 8)

                HStack(spacing: 18) {
                    ForEach(0..<3, id: \.self) { _ in
                        TicketView(isAvailable: false)
                            .rotationEffect(.degrees(18))
                    }
                }
                .padding(.vertical, 8)

                Text("Your next tickets will be ready in 2 days.\nCome back soon!")
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(appBrown.opacity(0.7))
                    .padding(.horizontal, 10)

                Button(action: onDismiss) {
                    Text("Okay!")
                        .font(.custom("ArialRoundedMTBold", size: 21))
                        .foregroundColor(.white)
                        .frame(height: 60)
                        .padding(.horizontal, 28)
                        .background(selectButtonBrown)
                        .clipShape(Capsule())
                }
            }
            .padding(24)
            .frame(width: skipAlertWidth)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(25)
            .overlay(
                RoundedRectangle(cornerRadius: 25)
                    .stroke(appYellow, lineWidth: 5)
            )
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
            .padding(.horizontal, 100)
        }
    }
}

#Preview {
    SkipAlertView(availableTickets: 2, onUseTicket: {}, onCancel: {})
}
