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
    let subscriptionId: String?
    let stationId: String
    let minPeriod: Int?
    let enabled: Bool?
    let usePeriod: Bool?
    let periodSeconds: Double?
    let useWaveHeight: Bool?
    let minSwellHeight: Double?
    let notificationFrequencyHours: Int?

    var id: String { subscriptionId ?? stationId }

    enum CodingKeys: String, CodingKey {
        case subscriptionId = "_id"
        case stationId
        case minPeriod
        case enabled
        case usePeriod
        case periodSeconds
        case useWaveHeight
        case minSwellHeight
        case notificationFrequencyHours
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subscriptionId = try container.decodeIfPresent(String.self, forKey: .subscriptionId)
        stationId = try container.decode(String.self, forKey: .stationId)
        minPeriod = try container.decodeIfPresent(Int.self, forKey: .minPeriod)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
        usePeriod = try container.decodeIfPresent(Bool.self, forKey: .usePeriod)
        periodSeconds = try container.decodeIfPresent(Double.self, forKey: .periodSeconds)
        useWaveHeight = try container.decodeIfPresent(Bool.self, forKey: .useWaveHeight)
        minSwellHeight = try container.decodeIfPresent(Double.self, forKey: .minSwellHeight)
        notificationFrequencyHours = try container.decodeIfPresent(
            Int.self,
            forKey: .notificationFrequencyHours
        )
    }
}

struct SubscriptionEditValues: Equatable {
    var notificationFrequencyHours: Int
    var usePeriod: Bool
    var periodSeconds: Double
    var useWaveHeight: Bool
    var minSwellHeight: Double
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
                   minSwellHeight: Double? = nil,
                   notificationFrequencyHours: Int? = nil) async throws {
        let payload = SubscriptionPayload(
            deviceToken: deviceToken,
            stationId: stationId,
            minPeriod: minPeriod,
            usePeriod: usePeriod,
            periodSeconds: periodSeconds,
            useWaveHeight: useWaveHeight,
            minSwellHeight: minSwellHeight,
            notificationFrequencyHours: notificationFrequencyHours
        )
        _ = try await performRequest(path: "/devices/subscribe", method: "POST", body: payload)
    }

    func updateSubscription(deviceToken: String,
                            subscriptionId: String,
                            stationId: String,
                            minPeriod: Int?,
                            usePeriod: Bool?,
                            periodSeconds: Double?,
                            useWaveHeight: Bool?,
                            minSwellHeight: Double?,
                            notificationFrequencyHours: Int?) async throws {
        let payload = SubscriptionUpdatePayload(
            deviceToken: deviceToken,
            stationId: stationId,
            minPeriod: minPeriod,
            usePeriod: usePeriod,
            periodSeconds: periodSeconds,
            useWaveHeight: useWaveHeight,
            minSwellHeight: minSwellHeight,
            notificationFrequencyHours: notificationFrequencyHours
        )
        _ = try await performRequest(
            path: "/devices/subscription/\(subscriptionId)",
            method: "PUT",
            body: payload
        )
    }

    func unsubscribe(deviceToken: String, stationId: String) async throws {
        let payload = SubscriptionPayload(
            deviceToken: deviceToken,
            stationId: stationId,
            minPeriod: nil,
            usePeriod: nil,
            periodSeconds: nil,
            useWaveHeight: nil,
            minSwellHeight: nil,
            notificationFrequencyHours: nil
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
    let minSwellHeight: Double?
    let notificationFrequencyHours: Int?

    enum CodingKeys: String, CodingKey {
        case deviceToken
        case stationId
        case minPeriod
        case usePeriod
        case periodSeconds
        case useWaveHeight
        case minSwellHeight
        case notificationFrequencyHours
    }
}

private struct SubscriptionUpdatePayload: Encodable {
    let deviceToken: String
    let stationId: String
    let minPeriod: Int?
    let usePeriod: Bool?
    let periodSeconds: Double?
    let useWaveHeight: Bool?
    let minSwellHeight: Double?
    let notificationFrequencyHours: Int?

    enum CodingKeys: String, CodingKey {
        case deviceToken
        case stationId
        case minPeriod
        case usePeriod
        case periodSeconds
        case useWaveHeight
        case minSwellHeight
        case notificationFrequencyHours
    }
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
    var minSwellHeight: Double = 4
}

struct AlertsSignupView: View {
    let title: String
    let stations: [Buoy]

    @State private var selectedStationIds: Set<String>
    @State private var manualStationId = ""
    @State private var thresholds = AlertThresholdSelection()
    @State private var notificationFrequencyHours = 6
    @State private var selectedSubscription: AlertsSubscription?
    @State private var pendingDeleteStationId: String?
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

                Section("Add station") {
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
                    if !manualStationIds.isEmpty {
                        ForEach(manualStationIds, id: \.self) { stationId in
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

                if stations.count > 1 {
                    Section("Visible Stations") {
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
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(subscription.stationId)
                                        .font(.headline)
                                    if let summary = subscriptionSummary(for: subscription) {
                                        Text(summary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    pendingDeleteStationId = subscription.stationId
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .disabled(isSubmitting || isLoadingSubscriptions)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                applySubscriptionDefaults(subscription)
                                selectedSubscription = subscription
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
                        Text("\(thresholds.minSwellHeight, specifier: "%.1f") ft")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $thresholds.minSwellHeight, in: 1...20, step: 0.5)
                        .disabled(isSubmitting || isLoadingSubscriptions || !thresholds.useWaveHeight)
                }

                Section("Notification frequency") {
                    Picker("Notify me every", selection: $notificationFrequencyHours) {
                        Text("1 hour").tag(1)
                        Text("6 hours").tag(6)
                        Text("12 hours").tag(12)
                        Text("24 hours").tag(24)
                    }
                    .pickerStyle(.segmented)
                    .disabled(isSubmitting || isLoadingSubscriptions)
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
            .sheet(item: $selectedSubscription) { subscription in
                SubscriptionDetailView(
                    subscription: subscription,
                    isSubmitting: isSubmitting
                ) { values in
                    Task {
                        await updateSubscription(subscription: subscription, values: values)
                    }
                }
            }
            .confirmationDialog(
                "Delete subscription?",
                isPresented: Binding(
                    get: { pendingDeleteStationId != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingDeleteStationId = nil
                        }
                    }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let stationId = pendingDeleteStationId {
                        Task { await unsubscribe(stationId: stationId) }
                    }
                    pendingDeleteStationId = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteStationId = nil
                }
            } message: {
                if let stationId = pendingDeleteStationId {
                    Text("Remove alerts for station \(stationId)?")
                }
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

    private var manualStationIds: [String] {
        let stationSet = Set(stations.map(\.id))
        return selectedStationIds.filter { !stationSet.contains($0) }.sorted()
    }

    private func subscriptionSummary(for subscription: AlertsSubscription) -> String? {
        var parts: [String] = []
        if let frequency = subscription.notificationFrequencyHours {
            parts.append("Every \(frequency)h")
        }
        let usePeriod = subscription.usePeriod ?? (subscription.minPeriod != nil)
        if usePeriod, let minPeriod = subscription.minPeriod {
            parts.append("Period ≥ \(minPeriod)s")
        }
        if subscription.useWaveHeight != false, let waveHeight = subscription.minSwellHeight {
            parts.append(String(format: "Wave ≥ %.1fft", waveHeight))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func applySubscriptionDefaults(_ subscription: AlertsSubscription) {
        let usePeriod = subscription.usePeriod ?? (subscription.minPeriod != nil)
        let periodSeconds = subscription.periodSeconds ?? Double(subscription.minPeriod ?? 20)
        let useWaveHeight = subscription.useWaveHeight ?? false
        let minSwellHeight = subscription.minSwellHeight ?? 4
        let notificationFrequencyHours = subscription.notificationFrequencyHours ?? 6
        thresholds = AlertThresholdSelection(
            usePeriod: usePeriod,
            periodSeconds: periodSeconds,
            useWaveHeight: useWaveHeight,
            minSwellHeight: minSwellHeight
        )
        self.notificationFrequencyHours = notificationFrequencyHours
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
        guard !selectedStationIds.isEmpty else {
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
                    minSwellHeight: thresholds.minSwellHeight,
                    notificationFrequencyHours: notificationFrequencyHours
                )
            }

            for stationId in removeIds {
                try await service.unsubscribe(deviceToken: token, stationId: stationId)
            }

            await loadSubscriptions(allowWhileLoading: true)
            let addCount = addIds.count
            let removeCount = removeIds.count
            if addCount > 0 && removeCount > 0 {
                statusMessage = "Subscribed to \(addCount) station(s), removed \(removeCount)."
            } else if addCount > 0 {
                statusMessage = "Subscribed to \(addCount) station(s)."
            } else if removeCount > 0 {
                statusMessage = "Removed \(removeCount) station(s)."
            } else {
                statusMessage = "No alert changes."
            }
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

    private func updateSubscription(subscription: AlertsSubscription, values: SubscriptionEditValues) async {
        guard !isSubmitting else { return }
        guard let token = PushManager.shared.deviceToken else {
            errorMessage = "Enable alerts to get a device token first."
            return
        }
        guard let subscriptionId = subscription.subscriptionId else {
            errorMessage = "Update requires a subscription id from the backend."
            return
        }
        isSubmitting = true
        errorMessage = nil
        let minPeriod = values.usePeriod ? Int(values.periodSeconds.rounded()) : nil
        let service = AlertsService()
        do {
            try await service.updateSubscription(
                deviceToken: token,
                subscriptionId: subscriptionId,
                stationId: subscription.stationId,
                minPeriod: minPeriod,
                usePeriod: values.usePeriod,
                periodSeconds: values.periodSeconds,
                useWaveHeight: values.useWaveHeight,
                minSwellHeight: values.minSwellHeight,
                notificationFrequencyHours: values.notificationFrequencyHours
            )
            await loadSubscriptions(allowWhileLoading: true)
            statusMessage = "Updated \(subscription.stationId)."
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

private struct SubscriptionDetailView: View {
    let subscription: AlertsSubscription
    let isSubmitting: Bool
    let onUpdate: (SubscriptionEditValues) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var values: SubscriptionEditValues
    private let initialValues: SubscriptionEditValues

    init(subscription: AlertsSubscription,
         isSubmitting: Bool,
         onUpdate: @escaping (SubscriptionEditValues) -> Void) {
        self.subscription = subscription
        self.isSubmitting = isSubmitting
        self.onUpdate = onUpdate
        let initial = SubscriptionDetailView.initialValues(for: subscription)
        _values = State(initialValue: initial)
        self.initialValues = initial
    }

    private static func initialValues(for subscription: AlertsSubscription) -> SubscriptionEditValues {
        let usePeriod = subscription.usePeriod ?? (subscription.minPeriod != nil)
        let periodSeconds = subscription.periodSeconds ?? Double(subscription.minPeriod ?? 20)
        let useWaveHeight = subscription.useWaveHeight ?? false
        let minSwellHeight = subscription.minSwellHeight ?? 4
        let notificationFrequencyHours = subscription.notificationFrequencyHours ?? 6
        return SubscriptionEditValues(
            notificationFrequencyHours: notificationFrequencyHours,
            usePeriod: usePeriod,
            periodSeconds: periodSeconds,
            useWaveHeight: useWaveHeight,
            minSwellHeight: minSwellHeight
        )
    }

    private var hasChanges: Bool {
        values != initialValues
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Station") {
                    Text(subscription.stationId)
                        .font(.headline)
                    if let minPeriod = subscription.minPeriod {
                        Text("Current period threshold: \(minPeriod)s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Notification frequency") {
                    Picker("Notify me every", selection: $values.notificationFrequencyHours) {
                        Text("1 hour").tag(1)
                        Text("6 hours").tag(6)
                        Text("12 hours").tag(12)
                        Text("24 hours").tag(24)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Thresholds") {
                    Toggle("Alert on period", isOn: $values.usePeriod)
                    HStack {
                        Text("Period threshold")
                        Spacer()
                        Text("\(values.periodSeconds, specifier: "%.0f") sec")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $values.periodSeconds, in: 5...30, step: 1)
                        .disabled(!values.usePeriod)

                    Toggle("Alert on wave height", isOn: $values.useWaveHeight)
                    HStack {
                        Text("Wave height")
                        Spacer()
                        Text("\(values.minSwellHeight, specifier: "%.1f") ft")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $values.minSwellHeight, in: 1...20, step: 0.5)
                        .disabled(!values.useWaveHeight)
                }

                Section {
                    Button("Update") {
                        onUpdate(values)
                    }
                    .disabled(!hasChanges || isSubmitting || (!values.usePeriod && !values.useWaveHeight))
                }
            }
            .navigationTitle("Subscription")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct AlertsView: View {
    @StateObject private var viewModel = AlertsViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDeleteStationId: String?
    @State private var selectedSubscription: AlertsSubscription?

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
                                    if let summary = subscriptionSummary(for: subscription) {
                                        Text(summary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    pendingDeleteStationId = subscription.stationId
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .disabled(viewModel.isLoading)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.apply(subscription: subscription)
                                selectedSubscription = subscription
                            }
                        }
                    }
                }

                Section("Add subscription") {
                    TextField("Station ID", text: $viewModel.stationIdInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("Notify me every", selection: $viewModel.notificationFrequencyHours) {
                        Text("1 hour").tag(1)
                        Text("6 hours").tag(6)
                        Text("12 hours").tag(12)
                        Text("24 hours").tag(24)
                    }
                    .pickerStyle(.segmented)
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
                        Text("\(viewModel.minSwellHeight, specifier: "%.1f") ft")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $viewModel.minSwellHeight, in: 1...20, step: 0.5)
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
            .sheet(item: $selectedSubscription) { subscription in
                SubscriptionDetailView(
                    subscription: subscription,
                    isSubmitting: viewModel.isLoading
                ) { values in
                    Task {
                        await viewModel.update(subscription: subscription, values: values)
                    }
                }
            }
            .confirmationDialog(
                "Delete subscription?",
                isPresented: Binding(
                    get: { pendingDeleteStationId != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingDeleteStationId = nil
                        }
                    }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let stationId = pendingDeleteStationId {
                        Task {
                            await viewModel.unsubscribe(stationId: stationId)
                        }
                    }
                    pendingDeleteStationId = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteStationId = nil
                }
            } message: {
                if let stationId = pendingDeleteStationId {
                    Text("Remove alerts for station \(stationId)?")
                }
            }
        }
    }

    private func subscriptionSummary(for subscription: AlertsSubscription) -> String? {
        var parts: [String] = []
        if let frequency = subscription.notificationFrequencyHours {
            parts.append("Every \(frequency)h")
        }
        let usePeriod = subscription.usePeriod ?? (subscription.minPeriod != nil)
        if usePeriod, let minPeriod = subscription.minPeriod {
            parts.append("Period ≥ \(minPeriod)s")
        }
        if subscription.useWaveHeight != false, let waveHeight = subscription.minSwellHeight {
            parts.append(String(format: "Wave ≥ %.1fft", waveHeight))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

@MainActor
final class AlertsViewModel: ObservableObject {
    @Published var deviceToken: String?
    @Published var subscriptions: [AlertsSubscription] = []
    @Published var stationIdInput = ""
    @Published var notificationFrequencyHours = 6
    @Published var usePeriodThreshold = true
    @Published var periodSeconds = 15.0
    @Published var useWaveThreshold = false
    @Published var minSwellHeight = 4.0
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

    func apply(subscription: AlertsSubscription) {
        stationIdInput = subscription.stationId
        notificationFrequencyHours = subscription.notificationFrequencyHours ?? 6
        usePeriodThreshold = subscription.usePeriod ?? (subscription.minPeriod != nil)
        periodSeconds = subscription.periodSeconds ?? Double(subscription.minPeriod ?? 20)
        useWaveThreshold = subscription.useWaveHeight ?? false
        minSwellHeight = subscription.minSwellHeight ?? 4
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
                minSwellHeight: minSwellHeight,
                notificationFrequencyHours: notificationFrequencyHours
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

    func update(subscription: AlertsSubscription, values: SubscriptionEditValues) async {
        guard let token = deviceToken else {
            errorMessage = "Enable alerts to get a device token first."
            return
        }
        guard !isLoading else { return }
        guard let subscriptionId = subscription.subscriptionId else {
            errorMessage = "Update requires a subscription id from the backend."
            return
        }
        isLoading = true
        errorMessage = nil
        let minPeriod = values.usePeriod ? Int(values.periodSeconds.rounded()) : nil
        do {
            try await service.updateSubscription(
                deviceToken: token,
                subscriptionId: subscriptionId,
                stationId: subscription.stationId,
                minPeriod: minPeriod,
                usePeriod: values.usePeriod,
                periodSeconds: values.periodSeconds,
                useWaveHeight: values.useWaveHeight,
                minSwellHeight: values.minSwellHeight,
                notificationFrequencyHours: values.notificationFrequencyHours
            )
            statusMessage = "Updated \(subscription.stationId)."
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
