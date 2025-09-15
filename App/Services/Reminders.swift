@preconcurrency import EventKit
import Foundation
import OSLog
import Ontology

private let log = Logger.service("reminders")

// EKReminder is not marked Sendable by EventKit, but we only pass
// instances across continuations without mutation. Mark as unchecked.
extension EKReminder: @retroactive @unchecked Sendable {}

@MainActor final class RemindersService: Service, Sendable {
    private let eventStore = EKEventStore()

    static let shared = RemindersService()

    var isActivated: Bool {
        get async {
            return EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
        }
    }

    nonisolated func activate() async throws {
        let store = EKEventStore()
        try await store.requestFullAccessToReminders()
    }

    nonisolated var tools: [Tool] {
        Tool(
            name: "reminders_lists",
            description: "List available reminder lists",
            inputSchema: .object(
                properties: [:],
                additionalProperties: false
            ),
            annotations: .init(
                title: "List Reminder Lists",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { @MainActor arguments in
            guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
                log.error("Reminders access not authorized")
                throw NSError(
                    domain: "RemindersError", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Reminders access not authorized"]
                )
            }

            let reminderLists = self.eventStore.calendars(for: .reminder)

            return reminderLists.map { reminderList in
                Value.object([
                    "title": .string(reminderList.title),
                    "source": .string(reminderList.source.title),
                    "color": .string(reminderList.color.accessibilityName),
                    "isEditable": .bool(reminderList.allowsContentModifications),
                    "isSubscribed": .bool(reminderList.isSubscribed),
                ])
            }
        }

        Tool(
            name: "reminders_fetch",
            description: "Get reminders from the reminders app with flexible filtering options",
            inputSchema: .object(
                properties: [
                    "completed": .boolean(
                        description:
                            "If true, fetch completed reminders; if false, fetch incomplete; if omitted, fetch all"
                    ),
                    "start": .string(
                        description: "Start date range for fetching reminders",
                        format: .dateTime
                    ),
                    "end": .string(
                        description: "End date range for fetching reminders",
                        format: .dateTime
                    ),
                    "lists": .array(
                        description:
                            "Names of reminder lists to fetch from; if empty, fetches from all lists",
                        items: .string()
                    ),
                    "query": .string(
                        description: "Text to search for in reminder titles"
                    ),
                ],
                additionalProperties: false
            ),
            annotations: .init(
                title: "Fetch Reminders",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { @MainActor arguments in
            try await self.activate()

            guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
                log.error("Reminders access not authorized")
                throw NSError(
                    domain: "RemindersError", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Reminders access not authorized"]
                )
            }

            // Filter reminder lists based on provided names
            var reminderLists = self.eventStore.calendars(for: .reminder)
            if case let .array(listNames) = arguments["lists"],
                !listNames.isEmpty
            {
                let requestedNames = Set(
                    listNames.compactMap { $0.stringValue?.lowercased() })
                reminderLists = reminderLists.filter {
                    requestedNames.contains($0.title.lowercased())
                }
            }

            // Parse dates if provided
            var startDate: Date? = nil
            var endDate: Date? = nil

            if case let .string(start) = arguments["start"] {
                startDate = ISO8601DateFormatter.parseFlexibleISODate(start)
            }
            if case let .string(end) = arguments["end"] {
                endDate = ISO8601DateFormatter.parseFlexibleISODate(end)
            }

            // Create predicate based on completion status
            let predicate: NSPredicate
            if case let .bool(completed) = arguments["completed"] {
                if completed {
                    predicate = self.eventStore.predicateForCompletedReminders(
                        withCompletionDateStarting: startDate,
                        ending: endDate,
                        calendars: reminderLists
                    )
                } else {
                    predicate = self.eventStore.predicateForIncompleteReminders(
                        withDueDateStarting: startDate,
                        ending: endDate,
                        calendars: reminderLists
                    )
                }
            } else {
                // If completion status not specified, use incomplete predicate as default
                predicate = self.eventStore.predicateForReminders(in: reminderLists)
            }

            // Fetch reminders
            let reminders: [EKReminder] = try await withCheckedThrowingContinuation { continuation in
                self.eventStore.fetchReminders(matching: predicate) { fetchedReminders in
                    let sendableReminders = (fetchedReminders ?? [])
                    continuation.resume(returning: sendableReminders)
                }
            }

            // Apply additional filters
            var filteredReminders = reminders

            // Filter by search text if provided
            if case let .string(searchText) = arguments["query"],
                !searchText.isEmpty
            {
                filteredReminders = filteredReminders.filter {
                    $0.title?.localizedCaseInsensitiveContains(searchText) == true
                }
            }

            return filteredReminders.map { PlanAction($0) }
        }

        Tool(
            name: "reminders_create",
            description: "Create a new reminder with specified properties",
            inputSchema: .object(
                properties: [
                    "title": .string(),
                    "due": .string(
                        format: .dateTime
                    ),
                    "list": .string(
                        description: "Reminder list name (uses default if not specified)"
                    ),
                    "notes": .string(),
                    "priority": .string(
                        default: .string(EKReminderPriority.none.stringValue),
                        enum: EKReminderPriority.allCases.map { .string($0.stringValue) }
                    ),
                    "alarms": .array(
                        description: "Minutes before due date to set alarms",
                        items: .integer()
                    ),
                ],
                required: ["title"],
                additionalProperties: false
            ),
            annotations: .init(
                title: "Create Reminder",
                destructiveHint: true,
                openWorldHint: false
            )
        ) { @MainActor arguments in
            try await self.activate()

            guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
                log.error("Reminders access not authorized")
                throw NSError(
                    domain: "RemindersError", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Reminders access not authorized"]
                )
            }

            let reminder = EKReminder(eventStore: self.eventStore)

            // Set required properties
            guard case let .string(title) = arguments["title"] else {
                throw NSError(
                    domain: "RemindersError", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Reminder title is required"]
                )
            }
            reminder.title = title

            // Set calendar (list)
            var calendar = self.eventStore.defaultCalendarForNewReminders()
            if case let .string(listName) = arguments["list"] {
                if let matchingCalendar = self.eventStore.calendars(for: .reminder)
                    .first(where: { $0.title.lowercased() == listName.lowercased() })
                {
                    calendar = matchingCalendar
                }
            }
            reminder.calendar = calendar

            // Set optional properties
            if case let .string(dueDateStr) = arguments["due"],
                let dueDate = ISO8601DateFormatter.parseFlexibleISODate(dueDateStr)
            {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second], from: dueDate)
            }

            if case let .string(notes) = arguments["notes"] {
                reminder.notes = notes
            }

            if case let .string(priorityStr) = arguments["priority"] {
                reminder.priority = Int(EKReminderPriority.from(string: priorityStr).rawValue)
            }

            // Set alarms
            if case let .array(alarmMinutes) = arguments["alarms"] {
                reminder.alarms = alarmMinutes.compactMap {
                    guard case let .int(minutes) = $0 else { return nil }
                    return EKAlarm(relativeOffset: TimeInterval(-minutes * 60))
                }
            }

            // Save the reminder
            try self.eventStore.save(reminder, commit: true)

            return PlanAction(reminder)
        }

        Tool(
            name: "reminders_update",
            description: "Update fields on an existing reminder",
            inputSchema: .object(
                properties: [
                    "identifier": .string(
                        description: "Reminder identifier"
                    ),
                    "title": .string(),
                    "due": .string(format: .dateTime),
                    "list": .string(
                        description: "Reminder list name"
                    ),
                    "notes": .string(),
                    "priority": .string(
                        enum: EKReminderPriority.allCases.map { .string($0.stringValue) }
                    ),
                    "completed": .boolean(),
                    "alarms": .array(
                        description: "Minutes before due date to set alarms",
                        items: .integer()
                    ),
                ],
                required: ["identifier"],
                additionalProperties: false
            ),
            annotations: .init(
                title: "Update Reminder",
                destructiveHint: false,
                openWorldHint: false
            )
        ) { @MainActor arguments in
            try await self.activate()

            guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
                throw NSError(
                    domain: "RemindersError", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Reminders access not authorized"]
                )
            }

            guard let identifier = arguments["identifier"]?.stringValue else {
                throw NSError(
                    domain: "RemindersError", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Identifier is required"]
                )
            }

            guard let reminder = try await self.findReminder(by: identifier) else {
                throw NSError(
                    domain: "RemindersError", code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Reminder not found"]
                )
            }

            if case let .string(title) = arguments["title"] { reminder.title = title }

            if case let .string(dueDateStr) = arguments["due"],
               let dueDate = ISO8601DateFormatter.parseFlexibleISODate(dueDateStr) {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second], from: dueDate)
            }

            if case let .string(listName) = arguments["list"] {
                if let matchingCalendar = self.eventStore.calendars(for: .reminder)
                    .first(where: { $0.title.lowercased() == listName.lowercased() }) {
                    reminder.calendar = matchingCalendar
                }
            }

            if case let .string(notes) = arguments["notes"] { reminder.notes = notes }

            if case let .string(priorityStr) = arguments["priority"] {
                reminder.priority = Int(EKReminderPriority.from(string: priorityStr).rawValue)
            }

            if case let .bool(completed) = arguments["completed"] {
                reminder.isCompleted = completed
                reminder.completionDate = completed ? Date() : nil
            }

            if case let .array(alarmMinutes) = arguments["alarms"] {
                reminder.alarms = alarmMinutes.compactMap {
                    guard case let .int(minutes) = $0 else { return nil }
                    return EKAlarm(relativeOffset: TimeInterval(-minutes * 60))
                }
            }

            try self.eventStore.save(reminder, commit: true)
            return PlanAction(reminder)
        }

        Tool(
            name: "reminders_delete",
            description: "Delete a reminder by identifier",
            inputSchema: .object(
                properties: [
                    "identifier": .string(
                        description: "Reminder identifier"
                    ),
                ],
                required: ["identifier"],
                additionalProperties: false
            ),
            annotations: .init(
                title: "Delete Reminder",
                destructiveHint: true,
                openWorldHint: false
            )
        ) { @MainActor arguments in
            try await self.activate()

            guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
                throw NSError(
                    domain: "RemindersError", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Reminders access not authorized"]
                )
            }

            guard let identifier = arguments["identifier"]?.stringValue else {
                throw NSError(
                    domain: "RemindersError", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Identifier is required"]
                )
            }

            guard let reminder = try await self.findReminder(by: identifier) else {
                throw NSError(
                    domain: "RemindersError", code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Reminder not found"]
                )
            }

            try self.eventStore.remove(reminder, commit: true)
            return Value.string("deleted")
        }

        Tool(
            name: "reminders_complete",
            description: "Mark a reminder as completed by identifier",
            inputSchema: .object(
                properties: [
                    "identifier": .string(
                        description: "Reminder identifier"
                    ),
                ],
                required: ["identifier"],
                additionalProperties: false
            ),
            annotations: .init(
                title: "Complete Reminder",
                destructiveHint: false,
                openWorldHint: false
            )
        ) { @MainActor arguments in
            try await self.activate()

            guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
                throw NSError(
                    domain: "RemindersError", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Reminders access not authorized"]
                )
            }

            guard let identifier = arguments["identifier"]?.stringValue else {
                throw NSError(
                    domain: "RemindersError", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Identifier is required"]
                )
            }

            guard let reminder = try await self.findReminder(by: identifier) else {
                throw NSError(
                    domain: "RemindersError", code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Reminder not found"]
                )
            }

            reminder.isCompleted = true
            reminder.completionDate = Date()

            try self.eventStore.save(reminder, commit: true)
            return PlanAction(reminder)
        }
    }

    private func findReminder(by identifier: String) async throws -> EKReminder? {
        // Try fast path (API available on recent macOS)
        if let item = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder {
            return item
        }

        // Fallback: scan all reminders and match identifier fields
        let calendars = eventStore.calendars(for: .reminder)
        let predicate = eventStore.predicateForReminders(in: calendars)
        let reminders: [EKReminder] = try await withCheckedThrowingContinuation { continuation in
            self.eventStore.fetchReminders(matching: predicate) { fetchedReminders in
                let sendableReminders = (fetchedReminders ?? [])
                continuation.resume(returning: sendableReminders)
            }
        }
        return reminders.first {
            $0.calendarItemIdentifier == identifier ||
            $0.calendarItemExternalIdentifier == identifier
        }
    }
}
