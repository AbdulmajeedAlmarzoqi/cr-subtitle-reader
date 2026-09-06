import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Group {
            if state.showWizard {
                SetupWizardView()
            } else {
                DashboardView()
            }
        }
    }
}

/// One line of "label: value" with an accessible status, used by the wizard and dashboard.
struct StatusLine: View {
    let label: String
    let value: String
    let ok: Bool?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbolName)
                .foregroundStyle(symbolColor)
                .accessibilityHidden(true)
            Text(label).fontWeight(.semibold)
            Text(value)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value). \(statusWord)")
    }

    private var statusWord: String {
        switch ok {
        case .some(true): return "OK"
        case .some(false): return "Needs attention"
        case .none: return ""
        }
    }

    private var symbolName: String {
        switch ok {
        case .some(true): return "checkmark.circle.fill"
        case .some(false): return "exclamationmark.triangle.fill"
        case .none: return "circle"
        }
    }

    private var symbolColor: Color {
        switch ok {
        case .some(true): return .green
        case .some(false): return .orange
        case .none: return .secondary
        }
    }
}
