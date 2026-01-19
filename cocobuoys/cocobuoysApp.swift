//
//  cocobuoysApp.swift
//  cocobuoys
//
//  Created by Jacob van Almelo on 10/17/25.
//

import SwiftUI
import UIKit
import UserNotifications

@main
struct cocobuoysApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        PushManager.shared.configure()
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushManager.shared.handleDeviceToken(deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushManager.shared.handleRegistrationFailure(error)
    }
}

extension Notification.Name {
    static let pushDeviceTokenUpdated = Notification.Name("pushDeviceTokenUpdated")
}

final class PushManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushManager()
    private static let deviceTokenKey = "pushDeviceToken"

    var deviceToken: String? {
        UserDefaults.standard.string(forKey: Self.deviceTokenKey)
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("Push auth error: \(error)")
                return
            }

            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func handleDeviceToken(_ deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        let existingToken = Self.currentToken()
        UserDefaults.standard.set(tokenString, forKey: Self.deviceTokenKey)
        if existingToken != tokenString {
            NotificationCenter.default.post(name: .pushDeviceTokenUpdated, object: nil)
        }
        Task {
            await registerDevice(tokenString)
        }
    }

    func handleRegistrationFailure(_ error: Error) {
        print("Failed to register for remote notifications: \(error)")
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    private func registerDevice(_ token: String) async {
        do {
            try await AlertsService().registerDevice(deviceToken: token)
        } catch {
            print("Failed to register device token: \(error)")
        }
    }

    private static func currentToken() -> String? {
        UserDefaults.standard.string(forKey: deviceTokenKey)
    }
}

struct AlertsSubscription: Identifiable, Decodable {
    let stationId: String
    let minPeriod: Int?

    var id: String { stationId }
}

enum AlertsServiceError: Error, LocalizedError {
    case invalidResponse
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Received an invalid response from the alerts service."
        case .decodingFailed:
            return "Failed to decode alerts data."
        }
    }
}

final class AlertsService {
    private let urlSession: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let baseURL: URL

    init(urlSession: URLSession = .shared,
         baseURL: URL = URL(string: "https://api.surfbuoys.com")!) {
        self.urlSession = urlSession
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.baseURL = baseURL
    }

    func registerDevice(deviceToken: String) async throws {
        let payload = DeviceRegisterPayload(deviceToken: deviceToken)
        _ = try await performRequest(path: "/devices/register", method: "POST", body: payload)
    }

    func fetchSubscriptions(deviceToken: String) async throws -> [AlertsSubscription] {
        let data = try await performRequest(path: "/devices/subscriptions/\(deviceToken)", method: "GET")
        if let wrapped = try? decoder.decode(SubscriptionsResponse.self, from: data) {
            return wrapped.subscriptions
        }
        if let direct = try? decoder.decode([AlertsSubscription].self, from: data) {
            return direct
        }
        throw AlertsServiceError.decodingFailed
    }

    func subscribe(deviceToken: String,
                   stationId: String,
                   minPeriod: Int?,
                   usePeriod: Bool? = nil,
                   periodSeconds: Double? = nil,
                   useWaveHeight: Bool? = nil,
                   waveHeightFeet: Double? = nil) async throws {
        let payload = SubscriptionPayload(
            deviceToken: deviceToken,
            stationId: stationId,
            minPeriod: minPeriod,
            usePeriod: usePeriod,
            periodSeconds: periodSeconds,
            useWaveHeight: useWaveHeight,
            waveHeightFeet: waveHeightFeet
        )
        _ = try await performRequest(path: "/devices/subscribe", method: "POST", body: payload)
    }

    func unsubscribe(deviceToken: String, stationId: String) async throws {
        let payload = SubscriptionPayload(
            deviceToken: deviceToken,
            stationId: stationId,
            minPeriod: nil,
            usePeriod: nil,
            periodSeconds: nil,
            useWaveHeight: nil,
            waveHeightFeet: nil
        )
        _ = try await performRequest(path: "/devices/unsubscribe", method: "DELETE", body: payload)
    }

    func sendTestNotification(deviceToken: String, title: String? = nil, body: String? = nil) async throws {
        let payload = TestNotificationPayload(deviceToken: deviceToken, title: title, body: body)
        _ = try await performRequest(path: "/devices/test-notification", method: "POST", body: payload)
    }

    private func performRequest(path: String, method: String) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw AlertsServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw AlertsServiceError.invalidResponse
        }
        return data
    }

    private func performRequest<T: Encodable>(path: String, method: String, body: T) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw AlertsServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw AlertsServiceError.invalidResponse
        }
        return data
    }
}

private struct DeviceRegisterPayload: Encodable {
    let deviceToken: String
}

private struct SubscriptionPayload: Encodable {
    let deviceToken: String
    let stationId: String
    let minPeriod: Int?
    let usePeriod: Bool?
    let periodSeconds: Double?
    let useWaveHeight: Bool?
    let waveHeightFeet: Double?
}

private struct SubscriptionsResponse: Decodable {
    let subscriptions: [AlertsSubscription]
}

private struct TestNotificationPayload: Encodable {
    let deviceToken: String
    let title: String?
    let body: String?
}

private struct AlertThresholdSelection {
    var usePeriod: Bool = true
    var periodSeconds: Double = 15
    var useWaveHeight: Bool = false
    var waveHeightFeet: Double = 4
}

struct AlertsSignupView: View {
    let title: String
    let stations: [Buoy]

    @State private var selectedStationIds: Set<String>
    @State private var manualStationId = ""
    @State private var thresholds = AlertThresholdSelection()
    @State private var isSubmitting = false
    @State private var isLoadingSubscriptions = false
    @State private var existingSubscriptions: [AlertsSubscription] = []
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @Environment(\.dismiss) private var dismiss

    init(title: String, stations: [Buoy]) {
        self.title = title
        self.stations = stations
        _selectedStationIds = State(initialValue: Set(stations.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let token = PushManager.shared.deviceToken {
                        Text("Device registered")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(token)
                            .font(.caption2)
                            .textSelection(.enabled)
                    } else {
                        Text("Enable alerts to register this device for buoy notifications.")
                            .font(.callout)
                    }

                    Button("Enable Buoy Alerts") {
                        PushManager.shared.requestAuthorization()
                    }
                    .disabled(isSubmitting)
                }

                if stations.isEmpty {
                    Section("Station") {
                        TextField("Enter buoy station ID", text: $manualStationId)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .disabled(isSubmitting || isLoadingSubscriptions)
                        Button("Add Station") {
                            let trimmed = manualStationId.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            selectedStationIds.insert(trimmed)
                            manualStationId = ""
                        }
                        .disabled(
                            isSubmitting ||
                            isLoadingSubscriptions ||
                            manualStationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                        if !selectedStationIds.isEmpty {
                            ForEach(selectedStationIds.sorted(), id: \.self) { stationId in
                                HStack {
                                    Text(stationId)
                                    Spacer()
                                    Button(role: .destructive) {
                                        selectedStationIds.remove(stationId)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .disabled(isSubmitting || isLoadingSubscriptions)
                                }
                            }
                        }
                    }
                } else if stations.count > 1 {
                    Section("Stations") {
                        ForEach(stations) { station in
                            Toggle(station.name, isOn: bindingForStation(station.id))
                                .disabled(isSubmitting || isLoadingSubscriptions)
                        }
                    }
                } else if let station = stations.first {
                    Section("Station") {
                        Text(station.name)
                    }
                }

                if !existingSubscriptions.isEmpty {
                    Section("Current subscriptions") {
                        ForEach(existingSubscriptions) { subscription in
                            HStack {
                                Text(subscription.stationId)
                                Spacer()
                                Button(role: .destructive) {
                                    Task { await unsubscribe(stationId: subscription.stationId) }
                                } label: {
                                    Image(systemName: "bell.slash")
                                }
                                .disabled(isSubmitting || isLoadingSubscriptions)
                            }
                        }
                    }
                }

                Section("Thresholds") {
                    Toggle("Alert on period", isOn: $thresholds.usePeriod)
                        .disabled(isSubmitting || isLoadingSubscriptions)
                    HStack {
                        Text("Period threshold")
                        Spacer()
                        Text("\(thresholds.periodSeconds, specifier: "%.0f") sec")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $thresholds.periodSeconds, in: 5...30, step: 1)
                        .disabled(isSubmitting || isLoadingSubscriptions || !thresholds.usePeriod)
                    Toggle("Alert on wave height", isOn: $thresholds.useWaveHeight)
                        .disabled(isSubmitting || isLoadingSubscriptions)
                    HStack {
                        Text("Wave height")
                        Spacer()
                        Text("\(thresholds.waveHeightFeet, specifier: "%.1f") ft")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $thresholds.waveHeightFeet, in: 1...20, step: 0.5)
                        .disabled(isSubmitting || isLoadingSubscriptions || !thresholds.useWaveHeight)
                }

                Section {
                    Button("Save Alerts") {
                        Task { await subscribe() }
                    }
                    .disabled(
                        isSubmitting ||
                        isLoadingSubscriptions ||
                        selectedStationIds.isEmpty ||
                        !(thresholds.usePeriod || thresholds.useWaveHeight)
                    )
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .disabled(isSubmitting || isLoadingSubscriptions)
                }
            }
            .task {
                await loadSubscriptions()
            }
        }
    }

    private func bindingForStation(_ stationId: String) -> Binding<Bool> {
        Binding(
            get: { selectedStationIds.contains(stationId) },
            set: { isSelected in
                if isSelected {
                    selectedStationIds.insert(stationId)
                } else {
                    selectedStationIds.remove(stationId)
                }
            }
        )
    }

    private func subscribe() async {
        guard !isSubmitting else { return }
        guard thresholds.usePeriod || thresholds.useWaveHeight else {
            errorMessage = "Select at least one alert threshold."
            return
        }
        guard let token = PushManager.shared.deviceToken else {
            errorMessage = "Enable alerts to get a device token first."
            return
        }
        let targetStations = stations.filter { selectedStationIds.contains($0.id) }
        guard !targetStations.isEmpty else {
            errorMessage = "Select at least one station."
            return
        }

        isSubmitting = true
        errorMessage = nil
        statusMessage = nil
        let service = AlertsService()
        do {
            let currentIds = Set(existingSubscriptions.map(\.stationId))
            let scopeIds = Set(stations.map(\.id))
            let addIds = selectedStationIds.subtracting(currentIds)
            let removeIds = currentIds.intersection(scopeIds).subtracting(selectedStationIds)

            for stationId in addIds {
                try await service.subscribe(
                    deviceToken: token,
                    stationId: stationId,
                    minPeriod: thresholds.usePeriod ? Int(thresholds.periodSeconds.rounded()) : nil,
                    usePeriod: thresholds.usePeriod,
                    periodSeconds: thresholds.periodSeconds,
                    useWaveHeight: thresholds.useWaveHeight,
                    waveHeightFeet: thresholds.waveHeightFeet
                )
            }

            for stationId in removeIds {
                try await service.unsubscribe(deviceToken: token, stationId: stationId)
            }

            await loadSubscriptions(allowWhileLoading: true)
            statusMessage = "Alerts updated."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isSubmitting = false
    }

    private func unsubscribe(stationId: String) async {
        guard !isSubmitting else { return }
        guard let token = PushManager.shared.deviceToken else {
            errorMessage = "Enable alerts to get a device token first."
            return
        }
        isSubmitting = true
        errorMessage = nil
        let service = AlertsService()
        do {
            try await service.unsubscribe(deviceToken: token, stationId: stationId)
            selectedStationIds.remove(stationId)
            await loadSubscriptions(allowWhileLoading: true)
            statusMessage = "Removed \(stationId)."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isSubmitting = false
    }

    private func loadSubscriptions(allowWhileLoading: Bool = false) async {
        guard let token = PushManager.shared.deviceToken else {
            existingSubscriptions = []
            return
        }
        guard !isLoadingSubscriptions || allowWhileLoading else { return }
        isLoadingSubscriptions = true
        let service = AlertsService()
        do {
            let subscriptions = try await service.fetchSubscriptions(deviceToken: token)
            existingSubscriptions = subscriptions
            let subscriptionIds = Set(subscriptions.map(\.stationId))
            let inScope = Set(stations.map(\.id))
            selectedStationIds.formUnion(subscriptionIds.intersection(inScope))
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoadingSubscriptions = false
    }
}

struct AlertsView: View {
    @StateObject private var viewModel = AlertsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let token = viewModel.deviceToken {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Device token")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(token)
                                .font(.caption2)
                                .textSelection(.enabled)
                        }
                    } else {
                        Text("Enable alerts to register this device for buoy notifications.")
                            .font(.callout)
                    }

                    Button("Enable Buoy Alerts") {
                        PushManager.shared.requestAuthorization()
                    }
                }

                Section("Subscriptions") {
                    if viewModel.isLoading && viewModel.subscriptions.isEmpty {
                        ProgressView()
                    } else if viewModel.subscriptions.isEmpty {
                        Text("No subscriptions yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.subscriptions) { subscription in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(subscription.stationId)
                                        .font(.headline)
                                    if let minPeriod = subscription.minPeriod {
                                        Text("Period: \(minPeriod) sec")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    Task {
                                        await viewModel.unsubscribe(stationId: subscription.stationId)
                                    }
                                } label: {
                                    Image(systemName: "bell.slash")
                                }
                                .disabled(viewModel.isLoading)
                            }
                        }
                    }
                }

                Section("Add subscription") {
                    TextField("Station ID", text: $viewModel.stationIdInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("Alert on period", isOn: $viewModel.usePeriodThreshold)
                    HStack {
                        Text("Period threshold")
                        Spacer()
                        Text("\(viewModel.periodSeconds, specifier: "%.0f") sec")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $viewModel.periodSeconds, in: 5...30, step: 1)
                        .disabled(!viewModel.usePeriodThreshold)
                    Toggle("Alert on wave height", isOn: $viewModel.useWaveThreshold)
                    HStack {
                        Text("Wave height")
                        Spacer()
                        Text("\(viewModel.waveHeightFeet, specifier: "%.1f") ft")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $viewModel.waveHeightFeet, in: 1...20, step: 0.5)
                        .disabled(!viewModel.useWaveThreshold)
                    Button("Subscribe") {
                        Task {
                            await viewModel.subscribe()
                        }
                    }
                    .disabled(
                        viewModel.isLoading ||
                        viewModel.stationIdInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        (!viewModel.usePeriodThreshold && !viewModel.useWaveThreshold)
                    )
                }

                Section("Test notification") {
                    TextField("Title", text: $viewModel.testTitleInput)
                    TextField("Body", text: $viewModel.testBodyInput)
                    Button("Send Test Notification") {
                        Task {
                            await viewModel.sendTestNotification()
                        }
                    }
                    .disabled(viewModel.deviceToken == nil || viewModel.isLoading)
                }

                if let statusMessage = viewModel.statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Buoy Alerts")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                viewModel.refreshDeviceToken()
                await viewModel.loadSubscriptions()
            }
            .onReceive(NotificationCenter.default.publisher(for: .pushDeviceTokenUpdated)) { _ in
                viewModel.refreshDeviceToken()
                Task {
                    await viewModel.loadSubscriptions()
                }
            }
        }
    }
}

@MainActor
final class AlertsViewModel: ObservableObject {
    @Published var deviceToken: String?
    @Published var subscriptions: [AlertsSubscription] = []
    @Published var stationIdInput = ""
    @Published var usePeriodThreshold = true
    @Published var periodSeconds = 15.0
    @Published var useWaveThreshold = false
    @Published var waveHeightFeet = 4.0
    @Published var testTitleInput = "Test"
    @Published var testBodyInput = "This is a test notification"
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    private let service: AlertsService

    init(service: AlertsService = AlertsService()) {
        self.service = service
        refreshDeviceToken()
    }

    func refreshDeviceToken() {
        deviceToken = PushManager.shared.deviceToken
    }

    func loadSubscriptions(allowWhileLoading: Bool = false) async {
        guard let token = deviceToken else {
            subscriptions = []
            return
        }
        guard !isLoading || allowWhileLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            subscriptions = try await service.fetchSubscriptions(deviceToken: token)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func subscribe() async {
        guard let token = deviceToken else {
            errorMessage = "Enable alerts to get a device token first."
            return
        }
        guard !isLoading else { return }
        let stationId = stationIdInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stationId.isEmpty else {
            errorMessage = "Enter a station id to subscribe."
            return
        }
        guard usePeriodThreshold || useWaveThreshold else {
            errorMessage = "Select at least one alert threshold."
            return
        }
        let minPeriod = usePeriodThreshold ? Int(periodSeconds.rounded()) : nil
        isLoading = true
        errorMessage = nil
        do {
            try await service.subscribe(
                deviceToken: token,
                stationId: stationId,
                minPeriod: minPeriod,
                usePeriod: usePeriodThreshold,
                periodSeconds: periodSeconds,
                useWaveHeight: useWaveThreshold,
                waveHeightFeet: waveHeightFeet
            )
            stationIdInput = ""
            statusMessage = "Subscribed to \(stationId)."
            await loadSubscriptions(allowWhileLoading: true)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func unsubscribe(stationId: String) async {
        guard let token = deviceToken else {
            errorMessage = "Enable alerts to get a device token first."
            return
        }
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await service.unsubscribe(deviceToken: token, stationId: stationId)
            statusMessage = "Removed \(stationId)."
            await loadSubscriptions(allowWhileLoading: true)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func sendTestNotification() async {
        guard let token = deviceToken else {
            errorMessage = "Enable alerts to get a device token first."
            return
        }
        guard !isLoading else { return }
        let title = testTitleInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = testBodyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        isLoading = true
        errorMessage = nil
        do {
            try await service.sendTestNotification(
                deviceToken: token,
                title: title.isEmpty ? nil : title,
                body: body.isEmpty ? nil : body
            )
            statusMessage = "Test notification sent."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}
