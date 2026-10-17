import SwiftUI

struct QuickAddView: View {
    let existing: TodoItem?
    let startWithVoice: Bool

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechRecognizer()

    @State private var text = ""
    @State private var hasDate = false
    @State private var date = Self.defaultDate()
    @State private var remind = true
    @State private var addToCalendar = false
    @State private var arabic = true
    @State private var isThinking = false
    @State private var message: String?
    @State private var lastParsed = ""
    @State private var saving = false
    @FocusState private var focused: Bool

    private var hasKey: Bool { !AppSettings.apiKey.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What needs doing? · ماذا تريد أن تفعل؟", text: $text, axis: .vertical)
                        .font(.system(size: 17))
                        .lineLimit(1...4)
                        .focused($focused)
                }

                Section {
                    voiceControls
                    if hasKey && !speech.isRecording {
                        Button {
                            Task { await understand() }
                        } label: {
                            Label(isThinking ? "Understanding…" : "Fill date from text", systemImage: "sparkles")
                        }
                        .disabled(isThinking || text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(DueLevel.urgent.foreground)
                    }
                } footer: {
                    if !hasKey {
                        Text("Add your Claude API key in Settings so dates and times are picked up from what you say.")
                    }
                }

                Section("Date · optional") {
                    Toggle("Has a date", isOn: $hasDate.animation())
                    if hasDate {
                        DatePicker("When", selection: $date)
                        HStack {
                            quick("Today 6 PM", hour: 18, dayOffset: 0)
                            quick("Tomorrow 9 AM", hour: 9, dayOffset: 1)
                        }
                    }
                }

                if hasDate {
                    Section {
                        Toggle(isOn: $remind) {
                            Label("Remind me", systemImage: "bell")
                        }
                        Toggle(isOn: $addToCalendar) {
                            Label("Add to Calendar", systemImage: "calendar")
                        }
                    } footer: {
                        Text("Reminders come 30 minutes before and at the time.")
                    }
                }

                if let existing {
                    Section {
                        Button(role: .destructive) {
                            model.delete(existing)
                            dismiss()
                        } label: {
                            Label("Delete task", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New task" : "Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { speech.stop(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear(perform: setUp)
        .onChange(of: speech.isRecording) { wasRecording, isRecording in
            if wasRecording && !isRecording && !speech.transcript.isEmpty {
                text = speech.transcript
                if hasKey { Task { await understand() } }
            }
        }
        .onChange(of: speech.transcript) { _, value in
            if speech.isRecording { text = value }
        }
    }

    private var voiceControls: some View {
        VStack(spacing: 12) {
            Picker("Language", selection: $arabic) {
                Text("عربي").tag(true)
                Text("English").tag(false)
            }
            .pickerStyle(.segmented)
            .disabled(speech.isRecording)

            Button {
                if speech.isRecording {
                    speech.stop()
                } else {
                    focused = false
                    Task { await speech.start(localeID: arabic ? "ar-EG" : "en-US") }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                    Text(speech.isRecording ? "Done talking" : "Tap and speak")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 14).fill(speech.isRecording ? Theme.primary : Theme.accent))
            }
            .buttonStyle(.plain)

            if let error = speech.error {
                Text(error).font(.footnote).foregroundStyle(DueLevel.urgent.foreground)
            }
        }
        .padding(.vertical, 4)
    }

    private func quick(_ title: String, hour: Int, dayOffset: Int) -> some View {
        Button(title) {
            let cal = Calendar.current
            let day = cal.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
            date = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? date
        }
        .buttonStyle(.bordered)
        .font(.footnote)
    }

    private func setUp() {
        if let existing {
            text = existing.title
            lastParsed = existing.title
            remind = existing.remind
            if let due = existing.due {
                hasDate = true
                date = due
            }
        } else if startWithVoice {
            Task { await speech.start(localeID: arabic ? "ar-EG" : "en-US") }
        } else {
            focused = true
        }
    }

    /// Sends the text to Claude and fills in the title, date and calendar switch.
    private func understand() async {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        isThinking = true
        message = nil
        defer { isThinking = false }
        do {
            let parsed = try await ClaudeClient.parse(input)
            text = parsed.title
            lastParsed = parsed.title
            if let due = parsed.due {
                hasDate = true
                date = due
                addToCalendar = parsed.isAppointment
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        speech.stop()

        // New typed task with no date picked: let Claude look for a date first.
        if existing == nil && hasKey && !hasDate && text != lastParsed {
            await understand()
        }

        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        var item = existing ?? TodoItem(title: title)
        item.title = title
        item.due = hasDate ? date : nil
        item.remind = hasDate && remind
        await model.save(item, addToCalendar: hasDate && addToCalendar)
        dismiss()
    }

    private static func defaultDate() -> Date {
        let cal = Calendar.current
        let next = cal.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        return cal.date(bySetting: .minute, value: 0, of: next) ?? next
    }
}
