// StreakWeekView.swift
//
// Drop-in UIView that renders the Mon–Sun weekly streak grid.
//
// Usage (in any ViewController):
//   let streakView = StreakWeekView()
//   streakView.translatesAutoresizingMaskIntoConstraints = false
//   view.addSubview(streakView)
//   // ... auto-layout constraints ...
//   streakView.refresh()
//
// Auto-refreshes when StreakStore posts .streakDidUpdate via NotificationCenter.

import UIKit

final class StreakWeekView: UIView {

    // MARK: - Colours
    private enum Colors {
        static let today:   UIColor = .systemBlue
        static let visited: UIColor = UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1) // green
        static let missed:  UIColor = UIColor(red: 0.82, green: 0.82, blue: 0.82, alpha: 1) // light grey
        static let future:  UIColor = UIColor(red: 0.94, green: 0.94, blue: 0.94, alpha: 1) // near-white
        static let label:   UIColor = .white
        static let futureLbl: UIColor = UIColor(red: 0.70, green: 0.70, blue: 0.70, alpha: 1)
    }

    // MARK: - Subviews
    private var dayViews: [DayCell] = []
    private let stack = UIStackView()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        stack.axis         = .horizontal
        stack.distribution = .fillEqually
        stack.spacing      = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        for _ in 0..<7 {
            let cell = DayCell()
            dayViews.append(cell)
            stack.addArrangedSubview(cell)
        }

        refresh()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refresh),
            name: .streakDidUpdate,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Refresh

    @objc func refresh() {
        let grid = StreakStore.shared.currentWeekGrid()
        for (i, state) in grid.enumerated() {
            dayViews[i].configure(with: state)
        }
    }

    // MARK: - DayCell

    private final class DayCell: UIView {

        private let circle       = UIView()
        private let streakLabel  = UILabel()   // number inside the circle
        private let weekdayLabel = UILabel()   // letter below the circle

        override init(frame: CGRect) {
            super.init(frame: frame)
            setupSubviews()
        }
        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setupSubviews()
        }

        private func setupSubviews() {
            // Circle
            circle.translatesAutoresizingMaskIntoConstraints = false
            circle.layer.masksToBounds = true
            addSubview(circle)

            // Streak number label inside circle
            streakLabel.translatesAutoresizingMaskIntoConstraints = false
            streakLabel.textAlignment = .center
            streakLabel.font          = .systemFont(ofSize: 13, weight: .bold)
            circle.addSubview(streakLabel)

            // Weekday letter below circle
            weekdayLabel.translatesAutoresizingMaskIntoConstraints = false
            weekdayLabel.textAlignment = .center
            weekdayLabel.font          = .systemFont(ofSize: 11, weight: .medium)
            addSubview(weekdayLabel)

            NSLayoutConstraint.activate([
                // Circle: square, centered horizontally, top of cell
                circle.topAnchor.constraint(equalTo: topAnchor),
                circle.centerXAnchor.constraint(equalTo: centerXAnchor),
                circle.widthAnchor.constraint(equalTo: widthAnchor),
                circle.heightAnchor.constraint(equalTo: circle.widthAnchor),

                // Streak label: centered in circle
                streakLabel.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
                streakLabel.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
                streakLabel.widthAnchor.constraint(equalTo: circle.widthAnchor),

                // Weekday label: below circle, 4pt gap
                weekdayLabel.topAnchor.constraint(equalTo: circle.bottomAnchor, constant: 4),
                weekdayLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
                weekdayLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            circle.layer.cornerRadius = circle.bounds.width / 2
        }

        func configure(with state: StreakStore.DayState) {
            weekdayLabel.text = state.weekdayLabel

            switch state.status {
            case .today:
                circle.backgroundColor  = Colors.today
                streakLabel.textColor   = Colors.label
                weekdayLabel.textColor  = Colors.today
                // Show streak count if > 1, otherwise show a dot/star
                streakLabel.text = state.streakNumber > 1 ? "\(state.streakNumber)" : "★"

            case .visited:
                circle.backgroundColor  = Colors.visited
                streakLabel.textColor   = Colors.label
                weekdayLabel.textColor  = Colors.visited
                streakLabel.text = state.streakNumber > 0 ? "\(state.streakNumber)" : "✓"

            case .missed:
                circle.backgroundColor  = Colors.missed
                streakLabel.textColor   = UIColor(white: 0.4, alpha: 1)
                weekdayLabel.textColor  = UIColor(white: 0.5, alpha: 1)
                streakLabel.text        = "–"

            case .future:
                circle.backgroundColor  = Colors.future
                streakLabel.textColor   = Colors.futureLbl
                weekdayLabel.textColor  = Colors.futureLbl
                streakLabel.text        = ""
            }
        }
    }
}
