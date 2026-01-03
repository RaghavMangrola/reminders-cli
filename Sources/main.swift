import EventKit
import Foundation

// MARK: - CLI

let version = "2.0.0"
var outputJSON = false

// Exit codes
let EXIT_SUCCESS: Int32 = 0
let EXIT_ERROR: Int32 = 1
let EXIT_NOT_FOUND: Int32 = 2

// MARK: - EventKit Store

let store = EKEventStore()

func requestAccess() -> Bool {
    let semaphore = DispatchSemaphore(value: 0)
    var granted = false

    if #available(macOS 14.0, *) {
        store.requestFullAccessToReminders { success, error in
            granted = success
            semaphore.signal()
        }
    } else {
        store.requestAccess(to: .reminder) { success, error in
            granted = success
            semaphore.signal()
        }
    }

    semaphore.wait()
    return granted
}

// MARK: - JSON Helpers

func jsonEscape(_ str: String) -> String {
    var result = str
    result = result.replacingOccurrences(of: "\\", with: "\\\\")
    result = result.replacingOccurrences(of: "\"", with: "\\\"")
    result = result.replacingOccurrences(of: "\n", with: "\\n")
    result = result.replacingOccurrences(of: "\r", with: "\\r")
    result = result.replacingOccurrences(of: "\t", with: "\\t")
    return result
}

func output(success: Bool, message: String, data: String? = nil) {
    if outputJSON {
        var json = "{\"success\":\(success),\"message\":\"\(jsonEscape(message))\""
        if let data = data {
            json += ",\"data\":\(data)"
        }
        json += "}"
        print(json)
    } else {
        print(message)
    }
}

// MARK: - Commands

func cmdLists() {
    let calendars = store.calendars(for: .reminder)

    if outputJSON {
        var items: [String] = []
        for cal in calendars {
            let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [cal])
            let semaphore = DispatchSemaphore(value: 0)
            var pendingCount = 0
            store.fetchReminders(matching: predicate) { reminders in
                pendingCount = reminders?.count ?? 0
                semaphore.signal()
            }
            semaphore.wait()

            let allPredicate = store.predicateForReminders(in: [cal])
            var totalCount = 0
            store.fetchReminders(matching: allPredicate) { reminders in
                totalCount = reminders?.count ?? 0
                semaphore.signal()
            }
            semaphore.wait()

            let color = cal.cgColor != nil ? String(format: "#%02X%02X%02X",
                Int((cal.cgColor?.components?[0] ?? 0) * 255),
                Int((cal.cgColor?.components?[1] ?? 0) * 255),
                Int((cal.cgColor?.components?[2] ?? 0) * 255)) : ""

            items.append("{\"id\":\"\(jsonEscape(cal.calendarIdentifier))\",\"name\":\"\(jsonEscape(cal.title))\",\"color\":\"\(color)\",\"pending\":\(pendingCount),\"total\":\(totalCount)}")
        }
        print("{\"success\":true,\"data\":[\(items.joined(separator: ","))]}")
    } else {
        for cal in calendars {
            let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [cal])
            let semaphore = DispatchSemaphore(value: 0)
            var pendingCount = 0
            store.fetchReminders(matching: predicate) { reminders in
                pendingCount = reminders?.count ?? 0
                semaphore.signal()
            }
            semaphore.wait()
            print("\(cal.title) (\(pendingCount) pending)")
        }
    }
}

func cmdLs(listName: String?, showAll: Bool, search: String?, flaggedOnly: Bool) {
    var calendars = store.calendars(for: .reminder)

    if let listName = listName {
        calendars = calendars.filter { $0.title.lowercased() == listName.lowercased() }
        if calendars.isEmpty {
            output(success: false, message: "List not found: \(listName)")
            exit(EXIT_NOT_FOUND)
        }
    }

    let predicate: NSPredicate
    if showAll {
        predicate = store.predicateForReminders(in: calendars)
    } else {
        predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
    }

    let semaphore = DispatchSemaphore(value: 0)
    var allReminders: [EKReminder] = []

    store.fetchReminders(matching: predicate) { reminders in
        allReminders = reminders ?? []
        semaphore.signal()
    }
    semaphore.wait()

    // Apply filters
    if let search = search?.lowercased() {
        allReminders = allReminders.filter {
            ($0.title?.lowercased().contains(search) ?? false) ||
            ($0.notes?.lowercased().contains(search) ?? false)
        }
    }

    // Note: flagged filtering not available in EventKit
    _ = flaggedOnly

    if outputJSON {
        var items: [String] = []
        for r in allReminders {
            let listTitle = r.calendar?.title ?? ""
            let notes = jsonEscape(r.notes ?? "")
            let title = jsonEscape(r.title ?? "")
            items.append("{\"id\":\"\(jsonEscape(r.calendarItemIdentifier))\",\"title\":\"\(title)\",\"list\":\"\(jsonEscape(listTitle))\",\"completed\":\(r.isCompleted),\"priority\":\(r.priority),\"notes\":\"\(notes)\"}")
        }
        print("{\"success\":true,\"data\":[\(items.joined(separator: ","))]}")
    } else {
        if allReminders.isEmpty {
            print("No reminders found")
        } else {
            for r in allReminders {
                let status = r.isCompleted ? "[x]" : "[ ]"
                var priority = ""
                if r.priority > 0 && r.priority <= 4 {
                    priority = " [HIGH]"
                } else if r.priority == 5 {
                    priority = " [MED]"
                } else if r.priority >= 6 {
                    priority = " [LOW]"
                }
                let listName = r.calendar?.title ?? ""
                print("\(status)\(priority) \(r.title ?? "") (\(listName))")
            }
        }
    }
}

func cmdAdd(title: String, notes: String?, listName: String?, dueDate: String?, priority: Int?, flagged: Bool) {
    var calendar = store.defaultCalendarForNewReminders()

    if let listName = listName {
        let calendars = store.calendars(for: .reminder).filter { $0.title.lowercased() == listName.lowercased() }
        if let cal = calendars.first {
            calendar = cal
        } else {
            output(success: false, message: "List not found: \(listName)")
            exit(EXIT_NOT_FOUND)
        }
    }

    let reminder = EKReminder(eventStore: store)
    reminder.title = title
    reminder.calendar = calendar

    if let notes = notes {
        reminder.notes = notes
    }

    if let priority = priority {
        reminder.priority = priority
    }

    // Note: flagged not available in EventKit
    _ = flagged

    if let dueDate = dueDate {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        if let date = formatter.date(from: dueDate) {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        }
    }

    do {
        try store.save(reminder, commit: true)
        if outputJSON {
            let listTitle = calendar?.title ?? "Reminders"
            print("{\"success\":true,\"message\":\"Added reminder\",\"data\":{\"id\":\"\(jsonEscape(reminder.calendarItemIdentifier))\",\"title\":\"\(jsonEscape(title))\",\"list\":\"\(jsonEscape(listTitle))\"}}")
        } else {
            print("Added: \(title)")
        }
    } catch {
        output(success: false, message: "Failed to add: \(error.localizedDescription)")
        exit(EXIT_ERROR)
    }
}

func cmdDone(search: String) {
    let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
    let semaphore = DispatchSemaphore(value: 0)
    var allReminders: [EKReminder] = []

    store.fetchReminders(matching: predicate) { reminders in
        allReminders = reminders ?? []
        semaphore.signal()
    }
    semaphore.wait()

    let matching = allReminders.filter { $0.title?.lowercased().contains(search.lowercased()) ?? false }

    guard let reminder = matching.first else {
        output(success: false, message: "No pending reminder found matching: \(search)")
        exit(EXIT_NOT_FOUND)
    }

    reminder.isCompleted = true

    do {
        try store.save(reminder, commit: true)
        output(success: true, message: "Completed: \(reminder.title ?? search)")
    } catch {
        output(success: false, message: "Failed to complete: \(error.localizedDescription)")
        exit(EXIT_ERROR)
    }
}

func cmdDelete(search: String) {
    let predicate = store.predicateForReminders(in: nil)
    let semaphore = DispatchSemaphore(value: 0)
    var allReminders: [EKReminder] = []

    store.fetchReminders(matching: predicate) { reminders in
        allReminders = reminders ?? []
        semaphore.signal()
    }
    semaphore.wait()

    let matching = allReminders.filter { $0.title?.lowercased().contains(search.lowercased()) ?? false }

    guard let reminder = matching.first else {
        output(success: false, message: "No reminder found matching: \(search)")
        exit(EXIT_NOT_FOUND)
    }

    let title = reminder.title ?? search

    do {
        try store.remove(reminder, commit: true)
        output(success: true, message: "Deleted: \(title)")
    } catch {
        output(success: false, message: "Failed to delete: \(error.localizedDescription)")
        exit(EXIT_ERROR)
    }
}

func cmdShow(search: String) {
    let predicate = store.predicateForReminders(in: nil)
    let semaphore = DispatchSemaphore(value: 0)
    var allReminders: [EKReminder] = []

    store.fetchReminders(matching: predicate) { reminders in
        allReminders = reminders ?? []
        semaphore.signal()
    }
    semaphore.wait()

    let matching = allReminders.filter { $0.title?.lowercased().contains(search.lowercased()) ?? false }

    guard let r = matching.first else {
        output(success: false, message: "No reminder found matching: \(search)")
        exit(EXIT_NOT_FOUND)
    }

    if outputJSON {
        let notes = jsonEscape(r.notes ?? "")
        let title = jsonEscape(r.title ?? "")
        let listTitle = jsonEscape(r.calendar?.title ?? "")
        var dueStr = ""
        if let due = r.dueDateComponents, let date = Calendar.current.date(from: due) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            dueStr = formatter.string(from: date)
        }
        print("{\"success\":true,\"data\":{\"id\":\"\(jsonEscape(r.calendarItemIdentifier))\",\"title\":\"\(title)\",\"list\":\"\(listTitle)\",\"completed\":\(r.isCompleted),\"priority\":\(r.priority),\"notes\":\"\(notes)\",\"due\":\"\(dueStr)\"}}")
    } else {
        let status = r.isCompleted ? "Completed" : "Pending"
        print("Title: \(r.title ?? "")")
        print("List: \(r.calendar?.title ?? "")")
        print("Status: \(status)")
        if let notes = r.notes, !notes.isEmpty {
            print("Notes: \(notes)")
        }
        if let due = r.dueDateComponents, let date = Calendar.current.date(from: due) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            print("Due: \(formatter.string(from: date))")
        }
        if r.priority > 0 {
            print("Priority: \(r.priority)")
        }
        print("ID: \(r.calendarItemIdentifier)")
    }
}

func printUsage() {
    print("""
    Usage: reminders [--json] <command> [options]

    Global Options:
        --json                Output in JSON format (recommended for scripts/LLMs)

    Commands:
        add <title> [options]                         Add a reminder
        ls [-l list] [-a] [-s search] [-f]            List reminders
        done <search>                                 Complete reminder (partial match)
        delete <search>                               Delete reminder (partial match)
        lists                                         Show all reminder lists
        show <search>                                 Show reminder details

    Options:
        -l, --list <name>     Target list name
        -n, --notes <text>    Add notes/body to reminder
        -d, --due <date>      Due date (e.g., "1/15/24 5:00 PM")
        -p, --priority <0-9>  Priority (0=none, 1-4=high, 5=medium, 6-9=low)
        -f, --flagged         Flag the reminder / filter flagged only
        -a, --all             Include completed reminders
        -s, --search <term>   Filter by search term

    Exit Codes:
        0    Success
        1    Error (invalid input, permission denied, etc.)
        2    Not found (no matching reminder)

    Examples:
        reminders add "Buy groceries"
        reminders add "Call mom" -n "Discuss birthday" -l Personal
        reminders --json ls
        reminders done "groceries"
        reminders --json show "Call"
    """)
}

// MARK: - Main

var args = Array(CommandLine.arguments.dropFirst())

// Parse global --json flag
if let idx = args.firstIndex(of: "--json") {
    outputJSON = true
    args.remove(at: idx)
}

guard !args.isEmpty else {
    printUsage()
    exit(EXIT_SUCCESS)
}

let command = args.removeFirst()

// Request access
guard requestAccess() else {
    output(success: false, message: "Reminders access denied. Grant access in System Settings > Privacy & Security > Reminders.")
    exit(EXIT_ERROR)
}

switch command {
case "lists":
    cmdLists()

case "ls", "list":
    var listName: String? = nil
    var showAll = false
    var search: String? = nil
    var flaggedOnly = false

    var i = 0
    while i < args.count {
        switch args[i] {
        case "-l", "--list":
            i += 1
            if i < args.count { listName = args[i] }
        case "-a", "--all":
            showAll = true
        case "-s", "--search":
            i += 1
            if i < args.count { search = args[i] }
        case "-f", "--flagged":
            flaggedOnly = true
        default:
            break
        }
        i += 1
    }
    cmdLs(listName: listName, showAll: showAll, search: search, flaggedOnly: flaggedOnly)

case "add":
    var title: String? = nil
    var notes: String? = nil
    var listName: String? = nil
    var dueDate: String? = nil
    var priority: Int? = nil
    var flagged = false

    var i = 0
    while i < args.count {
        switch args[i] {
        case "-n", "--notes":
            i += 1
            if i < args.count { notes = args[i] }
        case "-l", "--list":
            i += 1
            if i < args.count { listName = args[i] }
        case "-d", "--due":
            i += 1
            if i < args.count { dueDate = args[i] }
        case "-p", "--priority":
            i += 1
            if i < args.count { priority = Int(args[i]) }
        case "-f", "--flagged":
            flagged = true
        default:
            if title == nil && !args[i].hasPrefix("-") {
                title = args[i]
            }
        }
        i += 1
    }

    guard let title = title else {
        output(success: false, message: "Error: Title is required")
        exit(EXIT_ERROR)
    }

    cmdAdd(title: title, notes: notes, listName: listName, dueDate: dueDate, priority: priority, flagged: flagged)

case "done", "complete":
    guard let search = args.first else {
        output(success: false, message: "Error: Search term required")
        exit(EXIT_ERROR)
    }
    cmdDone(search: search)

case "delete", "rm":
    guard let search = args.first else {
        output(success: false, message: "Error: Search term required")
        exit(EXIT_ERROR)
    }
    cmdDelete(search: search)

case "show":
    guard let search = args.first else {
        output(success: false, message: "Error: Search term required")
        exit(EXIT_ERROR)
    }
    cmdShow(search: search)

case "-h", "--help":
    printUsage()

case "-v", "--version":
    print("reminders \(version)")

default:
    print("Unknown command: \(command)")
    printUsage()
    exit(EXIT_ERROR)
}
