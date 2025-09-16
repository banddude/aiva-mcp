import AppKit
import MCP
import Network
import OSLog
import Ontology
import SwiftUI
import SystemPackage
import UserNotifications

import struct Foundation.Data
import struct Foundation.Date
import class Foundation.JSONDecoder
import class Foundation.JSONEncoder

private let serviceType = "_mcp._tcp"
private let serviceDomain = "local."

private let log = Logger.server

@MainActor
struct ServiceConfig: Identifiable {
    let id: String
    let name: String
    let iconName: String
    let color: Color
    let service: any Service
    let binding: Binding<Bool>

    var isActivated: Bool {
        get async {
            await service.isActivated
        }
    }

    init(
        name: String,
        iconName: String,
        color: Color,
        service: any Service,
        binding: Binding<Bool>,
        idOverride: String? = nil
    ) {
        self.id = idOverride ?? String(describing: type(of: service))
        self.name = name
        self.iconName = iconName
        self.color = color
        self.service = service
        self.binding = binding
    }
}

enum ServiceRegistry {
    @MainActor static let services: [any Service] = [
        CalendarService.shared,
        CaptureService.shared,
        ContactsService.shared,
        LocationService.shared,
        MailService.shared,
        MapsService.shared,
        MemoryService.shared,
        MessageService.shared,
        AppleMusicService.shared,
        RemindersService.shared,
        SpeechService.shared,
        UtilitiesService.shared,
        WeatherService.shared,
    ]

    @MainActor static func configureServices(
        appleMusicEnabled: Binding<Bool>,
        calendarEnabled: Binding<Bool>,
        captureEnabled: Binding<Bool>,
        contactsEnabled: Binding<Bool>,
        locationEnabled: Binding<Bool>,
        mailEnabled: Binding<Bool>,
        mapsEnabled: Binding<Bool>,
        memoryEnabled: Binding<Bool>,
        messagesEnabled: Binding<Bool>,
        remindersEnabled: Binding<Bool>,
        speechEnabled: Binding<Bool>,
        utilitiesEnabled: Binding<Bool>,
        weatherEnabled: Binding<Bool>
    ) -> [ServiceConfig] {
        [
            ServiceConfig(
                name: "Calendar",
                iconName: AppIconManager.shared.getIconName(for: "Calendar"),
                color: .red,
                service: CalendarService.shared,
                binding: calendarEnabled
            ),
            ServiceConfig(
                name: "Capture",
                iconName: AppIconManager.shared.getIconName(for: "Capture"),
                color: .gray.mix(with: .black, by: 0.7),
                service: CaptureService.shared,
                binding: captureEnabled
            ),
            ServiceConfig(
                name: "Contacts",
                iconName: AppIconManager.shared.getIconName(for: "Contacts"),
                color: .brown,
                service: ContactsService.shared,
                binding: contactsEnabled
            ),
            ServiceConfig(
                name: "Location",
                iconName: AppIconManager.shared.getIconName(for: "Location"),
                color: .cyan,
                service: LocationService.shared,
                binding: locationEnabled
            ),
            ServiceConfig(
                name: "Mail",
                iconName: AppIconManager.shared.getIconName(for: "Mail"),
                color: .indigo,
                service: MailService.shared,
                binding: mailEnabled
            ),
            ServiceConfig(
                name: "Maps",
                iconName: AppIconManager.shared.getIconName(for: "Maps"),
                color: .purple,
                service: MapsService.shared,
                binding: mapsEnabled
            ),
            ServiceConfig(
                name: "Memory",
                iconName: "brain",
                color: .mint,
                service: MemoryService.shared,
                binding: memoryEnabled
            ),
            ServiceConfig(
                name: "Messages",
                iconName: AppIconManager.shared.getIconName(for: "Messages"),
                color: .green,
                service: MessageService.shared,
                binding: messagesEnabled
            ),
            ServiceConfig(
                name: "Music",
                iconName: AppIconManager.shared.getIconName(for: "Music"),
                color: .pink,
                service: AppleMusicService.shared,
                binding: appleMusicEnabled
            ),
            ServiceConfig(
                name: "Reminders",
                iconName: AppIconManager.shared.getIconName(for: "Reminders"),
                color: .orange,
                service: RemindersService.shared,
                binding: remindersEnabled
            ),
            ServiceConfig(
                name: "Speech",
                iconName: AppIconManager.shared.getIconName(for: "Speech"),
                color: .red.mix(with: .black, by: 0.3),
                service: SpeechService.shared,
                binding: speechEnabled
            ),
            ServiceConfig(
                name: "Utilities",
                iconName: AppIconManager.shared.getIconName(for: "Utilities"),
                color: .gray,
                service: UtilitiesService.shared,
                binding: utilitiesEnabled
            ),
            ServiceConfig(
                name: "Weather",
                iconName: AppIconManager.shared.getIconName(for: "Weather"),
                color: .cyan,
                service: WeatherService.shared,
                binding: weatherEnabled
            ),
        ]
    }
}

@MainActor
final class ServerController: ObservableObject {
    @Published var serverStatus: String = "Starting..."
    @Published var pendingConnectionID: String?
    @Published var pendingClientName: String = ""

    private var activeApprovalDialogs: Set<String> = []
    private var pendingApprovals: [(String, @Sendable () -> Void, @Sendable () -> Void)] = []
    private var currentApprovalHandlers: (approve: @Sendable () -> Void, deny: @Sendable () -> Void)?
    private let approvalWindowController = ConnectionApprovalWindowController()

    private let networkManager = ServerNetworkManager()
    
    // Cache for subprocess and remote services to prevent recreation
    private var serviceCache: [UUID: any Service] = [:]

    // MARK: - AppStorage for Service Enablement States
    @AppStorage("appleMusicEnabled") private var appleMusicEnabled = false
    @AppStorage("calendarEnabled") private var calendarEnabled = false
    @AppStorage("captureEnabled") private var captureEnabled = false
    @AppStorage("contactsEnabled") private var contactsEnabled = false
    @AppStorage("locationEnabled") private var locationEnabled = false
    @AppStorage("mailEnabled") private var mailEnabled = false
    @AppStorage("mapsEnabled") private var mapsEnabled = true  // Default for maps
    @AppStorage("memoryEnabled") private var memoryEnabled = false
    @AppStorage("messagesEnabled") private var messagesEnabled = false
    @AppStorage("remindersEnabled") private var remindersEnabled = false
    @AppStorage("speechEnabled") private var speechEnabled = true  // Default for speech
    @AppStorage("utilitiesEnabled") private var utilitiesEnabled = true  // Default for utilities
    @AppStorage("weatherEnabled") private var weatherEnabled = false

    // MARK: - AppStorage for Trusted Clients
    @AppStorage("trustedClients") private var trustedClientsData = Data()

    // MARK: - Computed Properties for Service Configurations and Bindings
    var computedServiceConfigs: [ServiceConfig] {
        var configs = ServiceRegistry.configureServices(
            appleMusicEnabled: $appleMusicEnabled,
            calendarEnabled: $calendarEnabled,
            captureEnabled: $captureEnabled,
            contactsEnabled: $contactsEnabled,
            locationEnabled: $locationEnabled,
            mailEnabled: $mailEnabled,
            mapsEnabled: $mapsEnabled,
            memoryEnabled: $memoryEnabled,
            messagesEnabled: $messagesEnabled,
            remindersEnabled: $remindersEnabled,
            speechEnabled: $speechEnabled,
            utilitiesEnabled: $utilitiesEnabled,
            weatherEnabled: $weatherEnabled
        )

        // Append any custom remote servers as services
        if let extras = loadCustomServers() {
            for entry in extras {
                // Use cached service if available, otherwise create new
                if let cachedService = serviceCache[entry.id] {
                    let enableBinding = remoteEnabledBinding(for: entry.id)
                    let iconName = entry.icon ?? AppIconManager.shared.getServerIcon(for: cachedService is SubprocessService ? .subprocess : .sse)
                    let color: Color = AppIconManager.shared.getServerColor(for: cachedService is SubprocessService ? .subprocess : .sse)
                    let idPrefix = cachedService is SubprocessService ? "SubprocessService" : "RemoteServerService"
                    
                    configs.append(
                        ServiceConfig(
                            name: entry.name,
                            iconName: iconName,
                            color: color,
                            service: cachedService,
                            binding: enableBinding,
                            idOverride: "\(idPrefix)_\(entry.id.uuidString)"
                        )
                    )
                } else {
                    // Create new service and cache it
                    if let remote = RemoteServerService(server: entry) {
                        serviceCache[entry.id] = remote
                        let enableBinding = remoteEnabledBinding(for: entry.id)
                        configs.append(
                            ServiceConfig(
                                name: entry.name,
                                iconName: entry.icon ?? AppIconManager.shared.getServerIcon(for: .sse),
                                color: AppIconManager.shared.getServerColor(for: .sse),
                                service: remote,
                                binding: enableBinding,
                                idOverride: "RemoteServerService_\(entry.id.uuidString)"
                            )
                        )
                    } else if let subprocess = SubprocessService(server: entry) {
                        serviceCache[entry.id] = subprocess
                        let enableBinding = remoteEnabledBinding(for: entry.id)
                        print("🔧 [ServerController] Created SubprocessService config for: \(entry.name), enabled: \(enableBinding.wrappedValue)")
                        configs.append(
                            ServiceConfig(
                                name: entry.name,
                                iconName: entry.icon ?? AppIconManager.shared.getServerIcon(for: .subprocess),
                                color: AppIconManager.shared.getServerColor(for: .subprocess),
                                service: subprocess,
                                binding: enableBinding,
                                idOverride: "SubprocessService_\(entry.id.uuidString)"
                            )
                        )
                    }
                }
            }
        }

        return configs
    }

    private var currentServiceBindings: [String: Binding<Bool>] {
        Dictionary(
            uniqueKeysWithValues: computedServiceConfigs.map {
                ($0.id, $0.binding)
            }
        )
    }
    
    // MARK: - Custom Servers
    @AppStorage("customServers") private var customServersData = Data()

    private func loadCustomServers() -> [ServerEntry]? {
        // Start with built-in servers
        let chromeId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let builtInServers = [
            ServerEntry(
                id: chromeId,
                name: "Chrome",
                command: "npx",
                arguments: ["@playwright/mcp@latest"],
                icon: AppIconManager.shared.getIconName(for: "Chrome")
            )
        ]
        
        // Load user-added custom servers
        var customServers: [ServerEntry] = []
        if !customServersData.isEmpty,
           let arr = try? JSONDecoder().decode([ServerEntry].self, from: customServersData) {
            customServers = arr
        }
        
        // Combine built-in and custom servers
        let allServers = builtInServers + customServers
        print("🔍 [ServerController] Loading servers: \(allServers.map { "\($0.name) (type: \($0.type))" })")
        
        // Clean up cache for servers that no longer exist
        let currentIds = Set(allServers.map { $0.id })
        serviceCache = serviceCache.filter { currentIds.contains($0.key) }
        
        return allServers
    }

    private func remoteEnabledBinding(for id: UUID) -> Binding<Bool> {
        let key = "remoteServerEnabled.\(id.uuidString)"
        return Binding<Bool>(
            get: { UserDefaults.standard.object(forKey: key) == nil ? true : UserDefaults.standard.bool(forKey: key) },
            set: { newValue in
                UserDefaults.standard.set(newValue, forKey: key)
            }
        )
    }

    // MARK: - Trusted Clients Management
    private var trustedClients: Set<String> {
        get {
            (try? JSONDecoder().decode(Set<String>.self, from: trustedClientsData)) ?? []
        }
        set {
            trustedClientsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    private func isClientTrusted(_ clientName: String) -> Bool {
        trustedClients.contains(clientName)
    }

    private func addTrustedClient(_ clientName: String) {
        var clients = trustedClients
        clients.insert(clientName)
        trustedClients = clients
    }

    func removeTrustedClient(_ clientName: String) {
        var clients = trustedClients
        clients.remove(clientName)
        trustedClients = clients
    }

    func getTrustedClients() -> [String] {
        Array(trustedClients).sorted()
    }

    func resetTrustedClients() {
        trustedClients = Set<String>()
    }

    // MARK: - Connection Approval Methods
    private func cleanupApprovalState() {
        pendingClientName = ""
        currentApprovalHandlers = nil

        if let clientID = pendingConnectionID {
            activeApprovalDialogs.remove(clientID)
            pendingConnectionID = nil
        }
    }

    private func handlePendingApprovals(for clientID: String, approved: Bool) {
        while let pendingIndex = pendingApprovals.firstIndex(where: { $0.0 == clientID }) {
            let (_, pendingApprove, pendingDeny) = pendingApprovals.remove(at: pendingIndex)
            if approved {
                log.notice("Approving pending connection for client: \(clientID)")
                pendingApprove()
            } else {
                log.notice("Denying pending connection for client: \(clientID)")
                pendingDeny()
            }
        }
    }

    init() {
        // Load system app icons at startup
        AppIconManager.shared.loadAppIcons()
        
        Task {
            // Compute and set initial services + bindings before starting the server
            let configs = self.computedServiceConfigs
            let services = configs.map { $0.service }
            let idMap = Dictionary(uniqueKeysWithValues: zip(services.map { ObjectIdentifier($0 as AnyObject) }, configs.map { $0.id }))
            await self.networkManager.setServices(services, idMap: idMap)
            await networkManager.updateServiceBindings(self.currentServiceBindings)
            await self.networkManager.start()
            self.updateServerStatus("Running")
            
            // Auto-activate enabled subprocess servers
            var anySubprocessActivated = false
            for config in configs {
                if config.binding.wrappedValue {
                    if config.service is SubprocessService {
                        do {
                            try await config.service.activate()
                            print("✅ [ServerController] Auto-started subprocess server: \(config.name)")
                            anySubprocessActivated = true
                        } catch {
                            print("❌ [ServerController] Failed to auto-start subprocess server \(config.name): \(error)")
                        }
                    }
                }
            }
            
            // If any subprocess was activated, notify to update tools view
            if anySubprocessActivated {
                await MainActor.run {
                    NotificationCenter.default.post(name: .aivaToolTogglesChanged, object: nil)
                }
            }

            // Listen for tool toggle changes and notify connected clients
            NotificationCenter.default.addObserver(forName: .aivaToolTogglesChanged, object: nil, queue: .main) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    let configs = self.computedServiceConfigs
                    let services = configs.map { $0.service }
                    let idMap = Dictionary(uniqueKeysWithValues: zip(services.map { ObjectIdentifier($0 as AnyObject) }, configs.map { $0.id }))
                    await self.networkManager.setServices(services, idMap: idMap)
                    // Ensure latest on/off bindings are applied immediately
                    await self.networkManager.updateServiceBindings(self.currentServiceBindings)
                    await self.networkManager.notifyToolsChanged()
                }
            }

            networkManager.setConnectionApprovalHandler {
                [weak self] connectionID, clientInfo in
                guard let self = self else {
                    return false
                }

                log.debug("ServerManager: Approval handler called for client \(clientInfo.name)")

                // Create a continuation to wait for the user's response
                return await withCheckedContinuation { continuation in
                    Task { @MainActor in
                        self.showConnectionApprovalAlert(
                            clientID: clientInfo.name,
                            approve: {
                                continuation.resume(returning: true)
                            },
                            deny: {
                                continuation.resume(returning: false)
                            }
                        )
                    }
                }
            }
        }
    }

    func updateServiceBindings(_ bindings: [String: Binding<Bool>]) async {
        // This function is still called by ContentView's onChange when user toggles services.
        // It ensures ServerNetworkManager is updated and clients are notified.
        let configs = self.computedServiceConfigs
        let services = configs.map { $0.service }
        let idMap = Dictionary(uniqueKeysWithValues: zip(services.map { ObjectIdentifier($0 as AnyObject) }, configs.map { $0.id }))
        await networkManager.setServices(services, idMap: idMap)
        await networkManager.updateServiceBindings(bindings)
        
        // Handle subprocess server activation/deactivation based on binding changes
        for config in configs {
            if let subprocess = config.service as? SubprocessService {
                let shouldBeEnabled = config.binding.wrappedValue
                let isCurrentlyActive = await subprocess.isActivated
                
                if shouldBeEnabled && !isCurrentlyActive {
                    // Activate the subprocess server
                    do {
                        try await subprocess.activate()
                        print("✅ [ServerController] Activated subprocess server: \(config.name)")
                        // Notify that tools have changed
                        await MainActor.run {
                            NotificationCenter.default.post(name: .aivaToolTogglesChanged, object: nil)
                        }
                    } catch {
                        print("❌ [ServerController] Failed to activate subprocess server \(config.name): \(error)")
                    }
                } else if !shouldBeEnabled && isCurrentlyActive {
                    // Deactivate the subprocess server
                    await subprocess.deactivate()
                    print("🛑 [ServerController] Deactivated subprocess server: \(config.name)")
                    // Notify that tools have changed
                    await MainActor.run {
                        NotificationCenter.default.post(name: .aivaToolTogglesChanged, object: nil)
                    }
                }
            }
        }
    }

    // Notify connected clients that the tool list may have changed (e.g., per-tool toggle)
    func notifyToolsChanged() async {
        await networkManager.notifyToolsChanged()
    }

    func startServer() async {
        await networkManager.start()
        updateServerStatus("Running")
    }

    func stopServer() async {
        await networkManager.stop()
        updateServerStatus("Stopped")
    }

    func setEnabled(_ enabled: Bool) async {
        await networkManager.setEnabled(enabled)
        updateServerStatus(enabled ? "Running" : "Disabled")
    }

    private func updateServerStatus(_ status: String) {
        log.info("Server status updated: \(status)")
        self.serverStatus = status
    }

    private func sendClientConnectionNotification(clientName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Client Connected"
        content.body = "Client '\(clientName)' has connected to AIVA"
        content.threadIdentifier = "client-connection-\(clientName)"

        let request = UNNotificationRequest(
            identifier: "client-connection-\(clientName)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                log.error("Failed to send notification: \(error.localizedDescription)")
            } else {
                log.info("Sent notification for client connection: \(clientName)")
            }
        }
    }

    private func showConnectionApprovalAlert(
        clientID: String, approve: @escaping @Sendable () -> Void, deny: @escaping @Sendable () -> Void
    ) {
        log.notice("Connection approval requested for client: \(clientID)")

        // Check if this client is already trusted
        if isClientTrusted(clientID) {
            log.notice("Client \(clientID) is already trusted, auto-approving")
            approve()

            // Send notification for trusted connections
            sendClientConnectionNotification(clientName: clientID)

            return
        }

        self.pendingConnectionID = clientID

        // Check if there's already an active dialog for this client
        guard !activeApprovalDialogs.contains(clientID) else {
            log.info("Adding to pending approvals for client: \(clientID)")
            pendingApprovals.append((clientID, approve, deny))
            return
        }

        activeApprovalDialogs.insert(clientID)

        // Set up the SwiftUI approval dialog
        pendingClientName = clientID
        currentApprovalHandlers = (approve: approve, deny: deny)

        approvalWindowController.showApprovalWindow(
            clientName: clientID,
            onApprove: { alwaysTrust in
                if alwaysTrust {
                    self.addTrustedClient(clientID)

                    // Request notification permissions so that the user can be notified when a trusted client connects
                    UNUserNotificationCenter.current().requestAuthorization(options: [
                        .alert, .sound, .badge,
                    ]) { granted, error in
                        if let error = error {
                            log.error(
                                "Failed to request notification permissions: \(error.localizedDescription)"
                            )
                        } else {
                            log.info("Notification permissions granted: \(granted)")
                        }
                    }
                }

                approve()
                self.cleanupApprovalState()
                self.handlePendingApprovals(for: clientID, approved: true)
            },
            onDeny: {
                deny()
                self.cleanupApprovalState()
                self.handlePendingApprovals(for: clientID, approved: false)
            }
        )

        NSApp.activate(ignoringOtherApps: true)

        // Handle any pending approvals for the same client after this one completes
        // We'll check for pending approvals when the dialog is dismissed
    }
}

// MARK: - Connection Management Components

/// Manages a single MCP connection
actor MCPConnectionManager {
    private let connectionID: UUID
    private let connection: NWConnection
    private let server: MCP.Server
    private var transport: NetworkTransport?
    private let parentManager: ServerNetworkManager
    private var isStarted = false
    private var isStopped = false

    init(connectionID: UUID, connection: NWConnection, parentManager: ServerNetworkManager) {
        self.connectionID = connectionID
        self.connection = connection
        self.parentManager = parentManager

        // Transport will be created lazily to avoid premature initialization
        self.transport = nil

        // Create the MCP server
        self.server = MCP.Server(
            name: Bundle.main.name ?? "AIVA",
            version: Bundle.main.shortVersionString ?? "unknown",
            capabilities: MCP.Server.Capabilities(
                tools: .init(listChanged: true)
            )
        )
    }

    func start(approvalHandler: @escaping @Sendable (MCP.Client.Info) async -> Bool) async throws {
        // Prevent double start
        guard !isStarted && !isStopped else {
            log.warning("Connection \(self.connectionID) already started or stopped, ignoring start request")
            return
        }
        
        do {
            // Create transport only when needed with reconnection disabled
            self.transport = NetworkTransport(
                connection: connection,
                logger: nil,
                reconnectionConfig: .disabled,  // Disable reconnection to avoid MCP SDK bug
                bufferConfig: .unlimited
            )
            
            guard let transport = self.transport else {
                throw MCPError.connectionClosed
            }
            
            isStarted = true
            log.notice("Starting MCP server for connection: \(self.connectionID)")
            try await server.start(transport: transport) { [weak self] clientInfo, capabilities in
                guard let self = self else { throw MCPError.connectionClosed }

                log.info("Received initialize request from client: \(clientInfo.name)")

                // Request user approval
                let approved = await approvalHandler(clientInfo)
                log.info(
                    "Approval result for connection \(self.connectionID): \(approved ? "Approved" : "Denied")"
                )

                if !approved {
                    await self.parentManager.removeConnection(self.connectionID)
                    throw MCPError.connectionClosed
                }
            }

            log.notice("MCP Server started successfully for connection: \(self.connectionID)")

            // Register handlers after successful approval
            await registerHandlers()

            // Monitor connection health
            await startHealthMonitoring()
        } catch {
            log.error("Failed to start MCP server: \(error.localizedDescription)")
            throw error
        }
    }

    private func registerHandlers() async {
        await parentManager.registerHandlers(for: server, connectionID: connectionID)
    }

    private func startHealthMonitoring() async {
        // Set up a connection health monitoring task
        Task {
            outer: while await parentManager.isRunning() {
                switch connection.state {
                case .ready, .setup, .preparing, .waiting:
                    break
                case .cancelled:
                    log.error("Connection \(self.connectionID) was cancelled, removing")
                    await parentManager.removeConnection(connectionID)
                    break outer
                case .failed(let error):
                    log.error(
                        "Connection \(self.connectionID) failed with error \(error), removing"
                    )
                    await parentManager.removeConnection(connectionID)
                    break outer
                @unknown default:
                    log.debug("Connection \(self.connectionID) in unknown state, skipping")
                }

                // Check again after 30 seconds
                try? await Task.sleep(nanoseconds: 30_000_000_000)  // 30 seconds
            }
        }
    }

    func notifyToolListChanged() async {
        do {
            log.info("Notifying client that tool list changed")
            try await server.notify(ToolListChangedNotification.message())
        } catch {
            log.error("Failed to notify client of tool list change: \(error)")

            // If the error is related to connection issues, clean up the connection
            if let nwError = error as? NWError,
                nwError.errorCode == 57 || nwError.errorCode == 54
            {
                log.debug("Connection appears to be closed")
                await parentManager.removeConnection(connectionID)
            }
        }
    }

    func stop() async {
        // Prevent double stop
        guard !isStopped else {
            log.debug("Connection \(self.connectionID) already stopped, ignoring stop request")
            return
        }
        
        isStopped = true
        log.debug("Stopping connection \(self.connectionID)")
        
        // Stop server first
        await server.stop()
        
        // Clean up transport
        self.transport = nil
        
        // Cancel network connection
        connection.cancel()
    }
}

/// Manages Bonjour service discovery and advertisement
actor NetworkDiscoveryManager {
    private let serviceType: String
    private let serviceDomain: String
    var listener: NWListener
    private let browser: NWBrowser

    init(serviceType: String, serviceDomain: String) throws {
        self.serviceType = serviceType
        self.serviceDomain = serviceDomain

        // Set up network parameters
        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true
        parameters.includePeerToPeer = false

        if let tcpOptions = parameters.defaultProtocolStack.internetProtocol
            as? NWProtocolIP.Options
        {
            tcpOptions.version = .v4
        }

        // Create the listener with service discovery
        self.listener = try NWListener(using: parameters)
        self.listener.service = NWListener.Service(type: serviceType, domain: serviceDomain)

        // Set up browser for debugging/monitoring
        self.browser = NWBrowser(
            for: .bonjour(type: serviceType, domain: serviceDomain),
            using: parameters
        )

        log.info("Network discovery manager initialized with Bonjour service type: \(serviceType)")
    }

    func start(
        stateHandler: @escaping @Sendable (NWListener.State) -> Void,
        connectionHandler: @escaping @Sendable (NWConnection) -> Void
    ) {
        // Set up state handler
        listener.stateUpdateHandler = stateHandler

        // Set up connection handler
        listener.newConnectionHandler = connectionHandler

        // Start the listener and browser
        listener.start(queue: .main)
        browser.start(queue: .main)

        log.info("Started network discovery and advertisement")
    }

    func stop() {
        listener.cancel()
        browser.cancel()
        log.info("Stopped network discovery and advertisement")
    }

    func restartWithRandomPort() async throws {
        // Cancel the current listener
        listener.cancel()

        // Create new parameters with a random port
        let parameters: NWParameters = NWParameters.tcp  // Explicit type
        parameters.acceptLocalOnly = true
        parameters.includePeerToPeer = false

        if let tcpOptions = parameters.defaultProtocolStack.internetProtocol
            as? NWProtocolIP.Options
        {
            tcpOptions.version = .v4
        }

        // Create a new listener with the updated parameters
        let newListener: NWListener = try NWListener(using: parameters)  // Explicit type
        let service = NWListener.Service(type: self.serviceType, domain: self.serviceDomain)  // Explicitly create service
        newListener.service = service

        // Update the state handler and connection handler
        if let currentStateHandler = listener.stateUpdateHandler {
            newListener.stateUpdateHandler = currentStateHandler
        }

        if let currentConnectionHandler = listener.newConnectionHandler {
            newListener.newConnectionHandler = currentConnectionHandler
        }

        // Start the new listener
        newListener.start(queue: .main)

        self.listener = newListener  // Update the instance member

        log.notice("Restarted listener with a dynamic port")
    }
}

@MainActor
final class ServerNetworkManager {
    private var isRunningState: Bool = false
    private var isEnabledState: Bool = true
    private var discoveryManager: NetworkDiscoveryManager?
    private var connections: [UUID: MCPConnectionManager] = [:]
    private var connectionTasks: [UUID: Task<Void, Never>] = [:]
    private var pendingConnections: [UUID: String] = [:]
    private var clientConnections: [String: UUID] = [:]  // Track connections by client name

    typealias ConnectionApprovalHandler = @Sendable (UUID, MCP.Client.Info) async -> Bool
    private var connectionApprovalHandler: ConnectionApprovalHandler?

    // Services are dynamic (built-in + remote)
    private var services: [any Service] = []
    private var serviceIdMap: [ObjectIdentifier: String] = [:]
    private var serviceBindings: [String: Binding<Bool>] = [:]

    init() {
        do {
            self.discoveryManager = try NetworkDiscoveryManager(
                serviceType: serviceType,
                serviceDomain: serviceDomain
            )
        } catch {
            log.error("Failed to initialize network discovery manager: \(error)")
        }
    }
    
    func initializeServices() async {
        let registryServices = ServiceRegistry.services
        self.services = registryServices
    }
    
    private func handleClientApproval(connectionID: UUID, clientInfo: MCP.Client.Info, approvalHandler: ConnectionApprovalHandler) async -> Bool {
        // Check for existing connection from same client
        if let existingConnectionID = self.clientConnections[clientInfo.name] {
            log.warning("Client \(clientInfo.name) already has connection \(existingConnectionID), closing old one")
            await self.removeConnection(existingConnectionID)
        }
        
        let approved = await approvalHandler(connectionID, clientInfo)
        
        // Track client connection if approved
        if approved {
            self.clientConnections[clientInfo.name] = connectionID
        }
        
        return approved
    }

    func lookupServiceId(for service: any Service) -> String {
        let key = ObjectIdentifier(service as AnyObject)
        return serviceIdMap[key] ?? String(describing: type(of: service))
    }

    func setServices(_ services: [any Service], idMap: [ObjectIdentifier: String]) async {
        self.services = services
        self.serviceIdMap = idMap
        // Notify connected clients that tools may have changed
        for (_, connectionManager) in connections {
            await connectionManager.notifyToolListChanged()
        }

        // Best-effort: activate remote servers to fetch tools automatically
        Task { @MainActor in
            var activatedAny = false
            for service in services {
                if let remote = service as? RemoteServerService {
                    do {
                        if await !remote.isActivated {
                            try await remote.activate()
                            activatedAny = true
                        }
                    } catch {
                        log.error("Failed to activate remote server: \(error.localizedDescription)")
                    }
                }
            }
            if activatedAny {
                // Tools changed after activation; notify clients again
                await self.notifyToolsChanged()
            }
        }
    }

    func isRunning() -> Bool {
        isRunningState
    }

    func setConnectionApprovalHandler(_ handler: @escaping ConnectionApprovalHandler) {
        log.debug("Setting connection approval handler")
        self.connectionApprovalHandler = handler
    }

    func start() async {
        log.info("Starting network manager")
        isRunningState = true

        guard let discoveryManager = discoveryManager else {
            log.error("Cannot start network manager: discovery manager not initialized")
            return
        }

        // Configure listener state handler
        await discoveryManager.start(
            stateHandler: { [weak self] (state: NWListener.State) -> Void in
                guard let strongSelf = self else { return }

                Task {
                    await strongSelf.handleListenerStateChange(state)
                }
            },
            connectionHandler: { [weak self] (connection: NWConnection) -> Void in
                guard let strongSelf = self else { return }

                Task {
                    await strongSelf.handleNewConnection(connection)
                }
            }
        )

        // Start a monitoring task to check service health periodically
        Task {
            while self.isRunningState {  // Explicit self.
                // Check if the listener is in a ready state
                if let currentDM = self.discoveryManager,  // Explicit self.
                    self.isRunningState  // Ensure still running before proceeding
                {
                    // Fetch the state of the listener explicitly.
                    let listenerState: NWListener.State = await currentDM.listener.state

                    if listenerState != .ready {
                        log.warning(
                            "Listener not in ready state, current state: \\(listenerState)"
                        )

                        let shouldAttemptRestart: Bool
                        switch listenerState {
                        case .failed, .cancelled:
                            shouldAttemptRestart = true
                        default:
                            shouldAttemptRestart = false
                        }

                        if shouldAttemptRestart {
                            log.info(
                                "Attempting to restart listener (state: \\(listenerState)) because it was failed or cancelled."
                            )
                            try? await currentDM.restartWithRandomPort()
                        }
                    }
                }

                // Sleep for 10 seconds before checking again
                try? await Task.sleep(nanoseconds: 10_000_000_000)  // 10s
            }
        }
    }

    private func handleListenerStateChange(_ state: NWListener.State) async {
        switch state {
        case .ready:
            log.info("Server ready and advertising via Bonjour as \(serviceType)")
        case .setup:
            log.debug("Server setting up...")
        case .waiting(let error):
            log.warning("Server waiting: \(error)")

            // If the port is already in use, try to restart with a different port
            if error.errorCode == 48 {
                log.error("Port already in use, will try to restart service")

                // Wait a bit and restart
                try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds

                // Try to restart with a different port
                if isRunningState {
                    try? await discoveryManager?.restartWithRandomPort()
                }
            }
        case .failed(let error):
            log.error("Server failed: \(error)")

            // Attempt recovery
            if isRunningState {
                log.info("Attempting to recover from server failure")
                try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second

                // Try to restart the listener
                try? await discoveryManager?.restartWithRandomPort()
            }
        case .cancelled:
            log.info("Server cancelled")
        @unknown default:
            log.warning("Unknown server state")
        }
    }

    func stop() async {
        log.info("Stopping network manager")
        isRunningState = false

        // Stop all connections
        for (id, connectionManager) in connections {
            log.debug("Stopping connection: \(id)")
            await connectionManager.stop()
            connectionTasks[id]?.cancel()
        }

        connections.removeAll()
        connectionTasks.removeAll()
        pendingConnections.removeAll()
        clientConnections.removeAll()

        // Stop discovery
        await discoveryManager?.stop()
    }

    func removeConnection(_ id: UUID) async {
        log.debug("Removing connection: \(id)")

        // Stop the connection manager
        if let connectionManager = connections[id] {
            await connectionManager.stop()
        }

        // Cancel any associated tasks
        if let task = connectionTasks[id] {
            task.cancel()
        }

        // Remove from all collections
        connections.removeValue(forKey: id)
        connectionTasks.removeValue(forKey: id)
        pendingConnections.removeValue(forKey: id)
        
        // Remove from client tracking
        if let clientName = pendingConnections[id] {
            clientConnections.removeValue(forKey: clientName)
        }
        // Also check by reverse lookup
        for (clientName, connectionID) in clientConnections {
            if connectionID == id {
                clientConnections.removeValue(forKey: clientName)
                break
            }
        }
    }

    // Handle new incoming connections
    private func handleNewConnection(_ connection: NWConnection) async {
        let connectionID = UUID()
        log.info("Handling new connection: \(connectionID)")

        // Create a connection manager
        let connectionManager = MCPConnectionManager(
            connectionID: connectionID,
            connection: connection,
            parentManager: self
        )

        // Store the connection manager
        connections[connectionID] = connectionManager

        // Start a task to monitor connection state
        let task = Task {
            // Ensure this task is removed from the registry upon completion (success or handled failure)
            // so the timeout logic below doesn't act on an already completed task.
            defer {
                // This runs on ServerNetworkManager's actor context
                self.connectionTasks.removeValue(forKey: connectionID)
            }

            do {
                // Set up the connection approval handler
                guard let approvalHandler = self.connectionApprovalHandler else {
                    log.error("No connection approval handler set, rejecting connection")
                    await removeConnection(connectionID)
                    return
                }

                // Start the MCP server with our approval handler
                try await connectionManager.start { clientInfo in
                    return await self.handleClientApproval(connectionID: connectionID, clientInfo: clientInfo, approvalHandler: approvalHandler)
                }

                log.notice("Connection \(connectionID) successfully established")
            } catch {
                log.error("Failed to establish connection \(connectionID): \(error)")
                await removeConnection(connectionID)
            }
        }

        // Store the task
        connectionTasks[connectionID] = task

        // Set up a timeout to ensure the connection becomes ready in a reasonable time
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)  // 10 seconds

            // Check if the setup task is still in the registry. If so, it implies
            // it hasn't completed its defer block (e.g., it's stuck or genuinely timed out)
            // and wasn't cleaned up by an error path calling removeConnection.
            // Also, ensure the connection object itself still exists.
            if self.connectionTasks[connectionID] != nil,  // Task entry still exists (meaning it hasn't completed defer)
                self.connections[connectionID] != nil
            {  // Connection object still exists
                log.warning(
                    "Connection \(connectionID) setup timed out (task still in registry), closing it"
                )
                await removeConnection(connectionID)
            }
        }
    }

    func registerHandlers(for server: MCP.Server, connectionID: UUID) async {
        // Register prompts/list handler
        await server.withMethodHandler(ListPrompts.self) { _ in
            log.debug("Handling ListPrompts request for \(connectionID)")
            return ListPrompts.Result(prompts: [])
        }

        // Register the resources/list handler
        await server.withMethodHandler(ListResources.self) { _ in
            log.debug("Handling ListResources request for \(connectionID)")
            return ListResources.Result(resources: [])
        }

        // Register tools/list handler
        await server.withMethodHandler(ListTools.self) { @MainActor [weak self] _ in
            guard let self = self else {
                return ListTools.Result(tools: [])
            }

            log.debug("Handling ListTools request for \(connectionID)")

            var tools: [MCP.Tool] = []
            if self.isEnabledState {
                for service in self.services {
                    let serviceId = self.lookupServiceId(for: service)

                    // Get the binding value in an actor-safe way
                    if let isServiceEnabled = self.serviceBindings[serviceId]?.wrappedValue,
                        isServiceEnabled
                    {
                        for tool in service.tools {
                            let key = "toolEnabled.\(serviceId).\(tool.name)"
                            let enabled: Bool = {
                                if UserDefaults.standard.object(forKey: key) == nil { return true }
                                return UserDefaults.standard.bool(forKey: key)
                            }()
                            if enabled {
                                log.debug("Adding tool: \(tool.name)")
                                tools.append(
                                    .init(
                                        name: tool.name,
                                        description: tool.description,
                                        inputSchema: tool.inputSchema,
                                        annotations: tool.annotations
                                    )
                                )
                            } else {
                                log.debug("Skipping disabled tool: \(tool.name)")
                            }
                        }
                    }
                }
            }

            log.info("Returning \(tools.count) available tools for \(connectionID)")
            return ListTools.Result(tools: tools)
        }

        // Register tools/call handler
        await server.withMethodHandler(CallTool.self) { @MainActor [weak self] params in
            guard let self = self else {
                return CallTool.Result(
                    content: [.text("Server unavailable")],
                    isError: true
                )
            }

            log.notice("Tool call received from \(connectionID): \(params.name)")

            guard self.isEnabledState else {
                log.notice("Tool call rejected: AIVA is disabled")
                return CallTool.Result(
                    content: [.text("AIVA is currently disabled. Please enable it to use tools.")],
                    isError: true
                )
            }

            for service in self.services {
                let serviceId = self.lookupServiceId(for: service)

                // Get the binding value in an actor-safe way
                if let isServiceEnabled = self.serviceBindings[serviceId]?.wrappedValue,
                    isServiceEnabled
                {
                    do {
                        guard
                            let value = try await service.call(
                                tool: params.name,
                                with: params.arguments ?? [:]
                            )
                        else {
                            continue
                        }

                        log.notice("Tool \(params.name) executed successfully for \(connectionID)")
                        print("🎭 [ServerController] Tool \(params.name) returned value: \(value)")
                        switch value {
                        case .data(let mimeType?, let data) where mimeType.hasPrefix("audio/"):
                            return CallTool.Result(
                                content: [
                                    .audio(
                                        data: data.base64EncodedString(),
                                        mimeType: mimeType
                                    )
                                ], isError: false)
                        case .data(let mimeType?, let data) where mimeType.hasPrefix("image/"):
                            return CallTool.Result(
                                content: [
                                    .image(
                                        data: data.base64EncodedString(),
                                        mimeType: mimeType,
                                        metadata: nil
                                    )
                                ], isError: false)
                        default:
                            let encoder = JSONEncoder()
                            encoder.userInfo[Ontology.DateTime.timeZoneOverrideKey] =
                                TimeZone.current
                            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

                            let data = try encoder.encode(value)
                            let text = String(data: data, encoding: .utf8)!

                            return CallTool.Result(content: [.text(text)], isError: false)
                        }
                    } catch {
                        log.error(
                            "Error executing tool \(params.name): \(error.localizedDescription)")
                        return CallTool.Result(content: [.text("Error: \(error)")], isError: true)
                    }
                }
            }

            log.error("Tool not found or service not enabled: \(params.name)")
            return CallTool.Result(
                content: [.text("Tool not found or service not enabled: \(params.name)")],
                isError: true
            )
        }
    }

    // Update the enabled state and notify clients
    func setEnabled(_ enabled: Bool) async {
        // Only do something if the state actually changes
        guard isEnabledState != enabled else { return }

        isEnabledState = enabled
        log.info("AIVA enabled state changed to: \(enabled)")

        // Notify all connected clients that the tool list has changed
        for (_, connectionManager) in connections {
            Task {
                await connectionManager.notifyToolListChanged()
            }
        }
    }

    // Update service bindings
    func updateServiceBindings(_ newBindings: [String: Binding<Bool>]) async {
        self.serviceBindings = newBindings

        // Notify clients that tool availability may have changed
        Task {
            for (_, connectionManager) in connections {
                await connectionManager.notifyToolListChanged()
            }
        }
    }

    // Notify all connected clients that tool list changed (e.g., per-tool toggles)
    func notifyToolsChanged() async {
        for (_, connectionManager) in connections {
            await connectionManager.notifyToolListChanged()
        }
    }
}
