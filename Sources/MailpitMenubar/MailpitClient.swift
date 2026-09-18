import Foundation

@MainActor
protocol MailpitClientDelegate: AnyObject {
    func client(_ client: MailpitClient, connectionChanged connected: Bool)
    func client(_ client: MailpitClient, receivedNew message: MailpitMessage)
    func client(_ client: MailpitClient, receivedStats stats: MailpitStats)
    func client(_ client: MailpitClient, recentMessages messages: [MailpitMessage], newSinceLastSync: [MailpitMessage])
}

/// Keeps a websocket open to Mailpit's `/api/events` stream, reconnecting with backoff,
/// and exposes a couple of REST calls for the menu.
@MainActor
final class MailpitClient {
    weak var delegate: MailpitClientDelegate?

    private(set) var isConnected = false {
        didSet {
            if oldValue != isConnected {
                log.info("websocket \(self.isConnected ? "connected" : "disconnected", privacy: .public)")
                delegate?.client(self, connectionChanged: isConnected)
            }
        }
    }

    private var socket: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectDelay: TimeInterval = 1
    private var generation = 0
    private var knownIDs = Set<String>()
    private var hasSyncedOnce = false
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    // MARK: Lifecycle

    func start() {
        connect()
    }

    /// Drop everything and start again (used when the base URL changes).
    func restart() {
        knownIDs.removeAll()
        hasSyncedOnce = false
        reconnectDelay = 1
        connect()
    }

    private func connect() {
        teardownSocket()
        generation += 1
        let myGeneration = generation

        log.info("connecting to \(Settings.eventsURL.absoluteString, privacy: .public)")
        let task = session.webSocketTask(with: Settings.eventsURL)
        socket = task
        task.resume()
        receiveLoop(task: task, generation: myGeneration)

        pingTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendPing(generation: myGeneration) }
        }

        // Sync the recent list straight away; the socket's first message will flip us to connected.
        Task { await syncRecent() }
    }

    private func teardownSocket() {
        reconnectTask?.cancel()
        reconnectTask = nil
        pingTimer?.invalidate()
        pingTimer = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil else { return }
        isConnected = false
        let delay = reconnectDelay
        reconnectDelay = min(reconnectDelay * 2, 30)
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.reconnectTask = nil
            self.connect()
        }
    }

    // MARK: Socket I/O

    private func receiveLoop(task: URLSessionWebSocketTask, generation: Int) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, generation == self.generation else { return }
                switch result {
                case .success(let message):
                    self.handle(message)
                    self.receiveLoop(task: task, generation: generation)
                case .failure:
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func sendPing(generation: Int) {
        guard generation == self.generation, let socket else { return }
        socket.sendPing { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in
                guard let self, generation == self.generation else { return }
                self.scheduleReconnect()
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let text): data = Data(text.utf8)
        case .data(let raw): data = raw
        @unknown default: return
        }

        if !isConnected {
            isConnected = true
            reconnectDelay = 1
        }

        guard let event = try? MailpitEvent.decode(data) else { return }
        switch event {
        case .new(let mail):
            let unseen = knownIDs.insert(mail.id).inserted
            if unseen { delegate?.client(self, receivedNew: mail) }
        case .stats(let stats):
            delegate?.client(self, receivedStats: stats)
        case .other(let type):
            // deleted / truncate / update: refresh the recent list so the menu stays honest.
            if ["delete", "truncate", "update"].contains(type) {
                Task { await syncRecent() }
            }
        }
    }

    // MARK: REST

    private func apiURL(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: Settings.webURL(path: "api/v1/\(path)"), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    /// Fetches the newest messages and tells the delegate which ones arrived since the last sync.
    func syncRecent(limit: Int = 12) async {
        let url = apiURL("messages", query: [URLQueryItem(name: "limit", value: String(limit))])
        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(MessagesResponse.self, from: data)
            let fresh = hasSyncedOnce ? response.messages.filter { !knownIDs.contains($0.id) } : []
            knownIDs.formUnion(response.messages.map(\.id))
            hasSyncedOnce = true
            delegate?.client(self, recentMessages: response.messages, newSinceLastSync: fresh)
            delegate?.client(self, receivedStats: MailpitStats(total: response.total, unread: response.unread))
        } catch {
            // The websocket loop owns reconnect/backoff; nothing else to do here.
            log.error("recent sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func markAllRead() async {
        var request = URLRequest(url: apiURL("messages"))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"Read":true}"#.utf8)
        _ = try? await session.data(for: request)
        await syncRecent()
    }
}
