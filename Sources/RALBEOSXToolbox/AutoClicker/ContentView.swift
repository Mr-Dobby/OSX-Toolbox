import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AutoClickerViewModel

    var body: some View {
        HStack(spacing: 0) {
            mainColumn

            if viewModel.isConsoleVisible {
                Divider()
                DebugConsoleView()
                    .frame(minWidth: 260, idealWidth: 300)
            }
        }
        .frame(
            minWidth: viewModel.isConsoleVisible ? 720 : 440,
            idealWidth: viewModel.isConsoleVisible ? 800 : 480,
            minHeight: 600
        )
    }

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !viewModel.accessibilityTrusted {
                accessibilityBanner
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    keysSection
                    mouseSection
                    intervalSection
                    applicationSection
                }
                .padding(.bottom, 4)
            }

            controlSection
        }
        .padding(20)
        .frame(minWidth: 440, idealWidth: 480)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Auto Clicker")
                        .font(.title2)
                        .bold()
                    Text(viewModel.isRunning ? "Running…" : "Idle")
                        .font(.caption)
                        .foregroundStyle(viewModel.isRunning ? Color.green : Color.secondary)
                }

                Spacer()

                Button {
                    viewModel.isConsoleVisible.toggle()
                } label: {
                    Label("Console", systemImage: viewModel.isConsoleVisible ? "terminal.fill" : "terminal")
                }
                .help("Show/hide the debug console.")

                Button {
                    viewModel.syncSetup()
                } label: {
                    Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("Re-check Accessibility permission and refresh the running-app list.")
            }

            if let message = viewModel.syncStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(viewModel.accessibilityTrusted ? Color.green : Color.orange)
            }
        }
    }

    private var accessibilityBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Accessibility permission required", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("AutoClicker needs Accessibility access to send keyboard and mouse events to other apps.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Already enabled it in System Settings but still seeing this? Rebuilding the app changes its signature, which can invalidate the old grant. Remove AutoClicker from the Accessibility list (select it, click “-”), re-add it, then tap Sync above.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Grant Access…") {
                    viewModel.requestAccessibilityAccess()
                }
                Button("Open Settings…") {
                    AccessibilityPermission.openAccessibilitySettings()
                }
                Button("Sync") {
                    viewModel.syncSetup()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }


    private var keysSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                TextField("e.g. 1, 2, 3  or  a, s, d, space", text: $viewModel.keysInputText)
                    .textFieldStyle(.roundedBorder)

                Text("Separate keys with commas or spaces. Supports letters, digits, F1-F12, and names like space, enter, esc, tab, up/down/left/right.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !viewModel.parsedKeys.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(viewModel.parsedKeys) { key in
                            ChipLabel(text: key.label)
                        }
                    }
                }

                if !viewModel.unrecognizedKeyTokens.isEmpty {
                    Text("Not recognized: \(viewModel.unrecognizedKeyTokens.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Keys to Click", systemImage: "keyboard")
                .font(.headline)
        }
    }

    private var mouseSection: some View {
        GroupBox {
            HStack(spacing: 8) {
                ForEach(MouseButtonOption.allCases) { button in
                    ToggleChip(
                        label: button.rawValue,
                        isSelected: viewModel.selectedMouseButtons.contains(button)
                    ) {
                        viewModel.toggleMouse(button)
                    }
                }
                Spacer()
            }
            .padding(.top, 4)
        } label: {
            Label("Mouse Buttons", systemImage: "cursorarrow.click")
                .font(.headline)
        }
    }

    private var intervalSection: some View {
        GroupBox {
            HStack {
                TextField("Value", value: $viewModel.intervalValue, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                Picker("", selection: $viewModel.intervalUnit) {
                    ForEach(TimeUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
                Spacer()
            }
            .padding(.top, 4)
        } label: {
            Label("Interval", systemImage: "timer")
                .font(.headline)
        }
    }

    private var applicationSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("If none is selected, clicks go to whichever app/window is currently in focus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Picker("", selection: $viewModel.selectedAppID) {
                        Text("Focused Window (default)").tag(pid_t?.none)
                        ForEach(viewModel.runningApps) { app in
                            Text(app.name).tag(pid_t?.some(app.id))
                        }
                    }
                    .labelsHidden()

                    Button {
                        viewModel.refreshRunningApps()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Refresh running applications")
                }
            }
            .padding(.top, 4)
        } label: {
            Label("Target Application", systemImage: "macwindow")
                .font(.headline)
        }
    }

    private var controlSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Global shortcut: \(HotkeyManager.shortcutDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Input Monitoring Settings…") {
                    AccessibilityPermission.openInputMonitoringSettings()
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(Color.accentColor)
            }

            Spacer()

            Button(viewModel.isRunning ? "Stop" : "Start") {
                viewModel.toggleRunning()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(viewModel.isRunning ? .red : .accentColor)
            .disabled(!viewModel.isRunning && !viewModel.canStart)
        }
    }
}

