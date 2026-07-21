import SwiftUI
import RealTodoKit

struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @State private var selectedCalendarKey = ""
    @State private var selectedCategoryForMap = "work"
    @State private var morningHour = 8
    @State private var morningMinute = 0
    @State private var refreshInterval = 30

    var body: some View {
        TabView {
            calendarSettingsTab
                .tabItem { Label("캘린더", systemImage: "calendar") }
            categorySettingsTab
                .tabItem { Label("카테고리", systemImage: "tag") }
            timerSettingsTab
                .tabItem { Label("알림", systemImage: "bell") }
            aiSettingsTab
                .tabItem { Label("AI", systemImage: "sparkles") }
        }
        .frame(minWidth: 480, idealWidth: 500, maxWidth: 560, minHeight: 420, idealHeight: 460, maxHeight: 520)
        .onAppear {
            Task { await viewModel.loadAll() }
            morningHour = viewModel.timerSettings?.morningHour ?? 8
            morningMinute = viewModel.timerSettings?.morningMinute ?? 0
            refreshInterval = viewModel.timerSettings?.refreshIntervalMinutes ?? 30
        }
    }

    private var calendarSettingsTab: some View {
        Form {
            Section("Google 계정") {
                if viewModel.accounts.isEmpty {
                    Label("연결 안됨", systemImage: "xmark.circle")
                        .foregroundStyle(.red)
                } else {
                    ForEach(viewModel.accounts) { account in
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading) {
                                Text(account.displayName ?? account.email)
                                Text(account.email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                Task { await viewModel.removeAccount(id: account.id) }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button(viewModel.isAuthenticating ? "인증 진행 중..." : "계정 추가") {
                    Task { await viewModel.signInWithGoogle() }
                }
                .disabled(viewModel.isAuthenticating)
                if let err = viewModel.errorMessage, !err.isEmpty {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section("캘린더 매핑") {
                if !viewModel.calendarMappings.isEmpty {
                    ForEach(viewModel.calendarMappings) { mapping in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(mapping.calendarName)
                                if let accountId = mapping.accountId,
                                   let account = viewModel.accounts.first(where: { $0.id == accountId }) {
                                    Text(account.email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            let catName = viewModel.categories.first(where: { $0.id == mapping.categoryId })?.name ?? mapping.categoryId
                            Text(catName)
                                .foregroundStyle(.secondary)
                            Button(action: {
                                Task { await viewModel.unmapCalendar(accountId: mapping.accountId, calendarId: mapping.calendarId) }
                            }) {
                                Image(systemName: "minus.circle")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    Picker("캘린더", selection: $selectedCalendarKey) {
                        Text("선택...").tag("")
                        ForEach(viewModel.accounts) { account in
                            Section(account.displayName ?? account.email) {
                                ForEach(viewModel.availableCalendars.filter { $0.accountId == account.id }) { item in
                                    Text(item.calendar.summary).tag(item.id)
                                }
                            }
                        }
                    }
                    Picker("카테고리", selection: $selectedCategoryForMap) {
                        ForEach(viewModel.categories) { cat in
                            Text(cat.name).tag(cat.id)
                        }
                    }
                    Button("추가") {
                        guard !selectedCalendarKey.isEmpty else { return }
                        let item = viewModel.availableCalendars.first(where: { $0.id == selectedCalendarKey })
                        Task {
                            await viewModel.mapCalendar(
                                accountId: item?.accountId,
                                calendarId: item?.calendar.id ?? selectedCalendarKey,
                                calendarName: item?.calendar.summary ?? selectedCalendarKey,
                                categoryId: selectedCategoryForMap
                            )
                            selectedCalendarKey = ""
                        }
                    }
                    .disabled(selectedCalendarKey.isEmpty)
                }
            }
            Section {
                Button("캘린더 목록 새로고침") {
                    Task { await viewModel.fetchAvailableCalendars() }
                }
                .disabled(!viewModel.isCalendarAuthenticated)
                Button("캘린더 동기화") {
                    Task { await viewModel.syncCalendar() }
                }
                .disabled(!viewModel.isCalendarAuthenticated)
            }
        }
        .formStyle(.grouped)
    }

    private var categorySettingsTab: some View {
        Form {
            Section("카테고리 목록") {
                ForEach(viewModel.categories) { cat in
                    HStack {
                        Circle()
                            .fill(Color(hex: cat.color) ?? .gray)
                            .frame(width: 12, height: 12)
                        Text(cat.name)
                        Spacer()
                        if cat.id != "work" && cat.id != "personal" {
                            Button(action: { Task { await viewModel.deleteCategory(id: cat.id) } }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Section("새 카테고리 추가") {
                HStack {
                    TextField("이름", text: $viewModel.newCategoryName)
                    ColorPicker("색상", selection: Binding(
                        get: { Color(hex: viewModel.newCategoryColor) ?? .orange },
                        set: { newValue in
                            let uiColor = NSColor(newValue)
                            let r = Int(uiColor.redComponent * 255)
                            let g = Int(uiColor.greenComponent * 255)
                            let b = Int(uiColor.blueComponent * 255)
                            viewModel.newCategoryColor = String(format: "#%02X%02X%02X", r, g, b)
                        }
                    ))
                    Button("추가") {
                        let name = viewModel.newCategoryName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        Task {
                            await viewModel.addCategory(name: name, color: viewModel.newCategoryColor)
                            viewModel.newCategoryName = ""
                        }
                    }
                    .disabled(viewModel.newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var timerSettingsTab: some View {
        Form {
            Section("아침 루틴") {
                HStack {
                    Stepper("시: \(morningHour)", value: $morningHour, in: 0...23)
                    Stepper("분: \(morningMinute)", value: $morningMinute, in: 0...59)
                }
            }
            Section("주기 업데이트") {
                Picker("간격", selection: $refreshInterval) {
                    Text("15분").tag(15)
                    Text("30분").tag(30)
                    Text("1시간").tag(60)
                    Text("수동").tag(0)
                }
            }
            Section {
                Button("설정 저장") {
                    Task {
                        await viewModel.updateTimerSettings(
                            hour: morningHour,
                            minute: morningMinute,
                            interval: refreshInterval
                        )
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var aiSettingsTab: some View {
        Form {
            Section("AI 분석") {
                Button("지금 아침 루틴 실행") {
                    Task { await viewModel.runMorningRoutineNow() }
                }
            }
            Section("정보") {
                LabeledContent("AI 엔진") { Text("agy CLI") }
                LabeledContent("경로") { Text(AppConstants.agyPath).font(.caption) }
            }
        }
        .formStyle(.grouped)
    }
}
