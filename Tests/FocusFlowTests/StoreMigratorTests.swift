import XCTest
import Foundation
import SQLite3
@testable import FocusFlow

final class StoreMigratorTests: XCTestCase {
    func testMigrateAddsMissingAppSettingsColumnsWithDefaultsAndPreservesData() throws {
        let url = try makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let db = try openDB(url)
        defer { sqlite3_close(db) }

        try exec(db, """
        CREATE TABLE ZAPPSETTINGS (
            Z_PK INTEGER PRIMARY KEY,
            Z_ENT INTEGER,
            Z_OPT INTEGER,
            ZAUTOSTARTBREAK INTEGER,
            ZAUTOSTARTNEXTSESSION INTEGER,
            ZLAUNCHATLOGIN INTEGER,
            ZSESSIONSBEFORELONGBREAK INTEGER,
            ZFOCUSDURATION FLOAT,
            ZLONGBREAKDURATION FLOAT,
            ZSHORTBREAKDURATION FLOAT,
            ZCOMPLETIONSOUND VARCHAR
        );
        """)

        try exec(db, """
        INSERT INTO ZAPPSETTINGS (
            Z_PK, Z_ENT, Z_OPT, ZAUTOSTARTBREAK, ZAUTOSTARTNEXTSESSION, ZLAUNCHATLOGIN,
            ZSESSIONSBEFORELONGBREAK, ZFOCUSDURATION, ZLONGBREAKDURATION, ZSHORTBREAKDURATION, ZCOMPLETIONSOUND
        ) VALUES (1, 1, 1, 1, 0, 1, 4, 1500.0, 900.0, 300.0, 'Glass');
        """)

        try StoreMigrator.migrateStoreIfNeeded(at: url)

        let columns = try tableColumns(db, table: "ZAPPSETTINGS")
        XCTAssertTrue(columns.contains("ZDAILYFOCUSGOAL"))
        XCTAssertTrue(columns.contains("ZCALENDARINTEGRATIONENABLED"))
        XCTAssertTrue(columns.contains("ZCALENDARNAME"))
        XCTAssertTrue(columns.contains("ZSELECTEDCALENDARID"))
        XCTAssertTrue(columns.contains("ZANTIPROCRASTINATIONENABLED"))
        XCTAssertTrue(columns.contains("ZANTIPROCRASTINATIONTHRESHOLDMINUTES"))
        XCTAssertTrue(columns.contains("ZREMINDERSINTEGRATIONENABLED"))
        XCTAssertTrue(columns.contains("ZSELECTEDREMINDERLISTID"))

        let calendarValues = try querySingleCalendarColumns(
            db,
            sql: "SELECT ZDAILYFOCUSGOAL, ZCALENDARINTEGRATIONENABLED, ZCALENDARNAME FROM ZAPPSETTINGS WHERE Z_PK = 1;"
        )
        XCTAssertEqual(calendarValues.0, 7200.0, accuracy: 0.001)
        XCTAssertEqual(calendarValues.1, 0)
        XCTAssertEqual(calendarValues.2, "FocusFlow")

        let selectedCalendarId = try querySingleText(
            db,
            sql: "SELECT ZSELECTEDCALENDARID FROM ZAPPSETTINGS WHERE Z_PK = 1;"
        )
        XCTAssertEqual(selectedCalendarId, "")

        let values = try querySingleIntPair(
            db,
            sql: "SELECT ZANTIPROCRASTINATIONENABLED, ZANTIPROCRASTINATIONTHRESHOLDMINUTES FROM ZAPPSETTINGS WHERE Z_PK = 1;"
        )
        XCTAssertEqual(values.0, 1)
        XCTAssertEqual(values.1, 5)

        let remindersValues = try querySingleReminderColumns(
            db,
            sql: "SELECT ZREMINDERSINTEGRATIONENABLED, ZSELECTEDREMINDERLISTID FROM ZAPPSETTINGS WHERE Z_PK = 1;"
        )
        XCTAssertEqual(remindersValues.0, 0)
        XCTAssertEqual(remindersValues.1, "")

        let original = try querySingleText(db, sql: "SELECT ZCOMPLETIONSOUND FROM ZAPPSETTINGS WHERE Z_PK = 1;")
        XCTAssertEqual(original, "Glass")
    }

    func testMigrateIsIdempotent() throws {
        let url = try makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let db = try openDB(url)
        defer { sqlite3_close(db) }

        try exec(db, """
        CREATE TABLE ZAPPSETTINGS (
            Z_PK INTEGER PRIMARY KEY,
            Z_ENT INTEGER,
            Z_OPT INTEGER,
            ZAUTOSTARTBREAK INTEGER,
            ZAUTOSTARTNEXTSESSION INTEGER,
            ZLAUNCHATLOGIN INTEGER,
            ZSESSIONSBEFORELONGBREAK INTEGER,
            ZFOCUSDURATION FLOAT,
            ZLONGBREAKDURATION FLOAT,
            ZSHORTBREAKDURATION FLOAT,
            ZCOMPLETIONSOUND VARCHAR
        );
        """)

        try StoreMigrator.migrateStoreIfNeeded(at: url)
        try StoreMigrator.migrateStoreIfNeeded(at: url)

        let columns = try tableColumns(db, table: "ZAPPSETTINGS")
        XCTAssertEqual(columns.filter { $0 == "ZDAILYFOCUSGOAL" }.count, 1)
        XCTAssertEqual(columns.filter { $0 == "ZCALENDARINTEGRATIONENABLED" }.count, 1)
        XCTAssertEqual(columns.filter { $0 == "ZCALENDARNAME" }.count, 1)
        XCTAssertEqual(columns.filter { $0 == "ZSELECTEDCALENDARID" }.count, 1)
        XCTAssertEqual(columns.filter { $0 == "ZANTIPROCRASTINATIONENABLED" }.count, 1)
        XCTAssertEqual(columns.filter { $0 == "ZANTIPROCRASTINATIONTHRESHOLDMINUTES" }.count, 1)
        XCTAssertEqual(columns.filter { $0 == "ZREMINDERSINTEGRATIONENABLED" }.count, 1)
        XCTAssertEqual(columns.filter { $0 == "ZSELECTEDREMINDERLISTID" }.count, 1)
        XCTAssertEqual(columns.filter { $0 == "ZCOACHREALTIMEENABLED" }.count, 1)
        XCTAssertEqual(columns.filter { $0 == "ZCOACHPROMPTBUDGETPERSESSION" }.count, 1)
        XCTAssertEqual(columns.filter { $0 == "ZCOACHREASONPROMPTSENABLED" }.count, 1)
        XCTAssertEqual(columns.filter { $0 == "ZCOACHDEFAULTSNOOZEMINUTES" }.count, 1)
        XCTAssertEqual(columns.filter { $0 == "ZCOACHCOLLECTRAWDOMAINS" }.count, 1)
        XCTAssertEqual(columns.filter { $0 == "ZCOACHIDLESTARTERENABLED" }.count, 1)
        XCTAssertEqual(columns.filter { $0 == "ZCOACHAUTOOPENPOPOVERONSTRONGPROMPT" }.count, 1)
        XCTAssertEqual(columns.filter { $0 == "ZCOACHBRINGAPPTOFRONTONSTRONGPROMPT" }.count, 1)
        XCTAssertEqual(columns.filter { $0 == "ZCOACHALLOWSKIPACTION" }.count, 1)
        XCTAssertEqual(columns.filter { $0 == "ZCOACHMAXSTRONGPROMPTSPERSESSION" }.count, 1)
        XCTAssertEqual(columns.filter { $0 == "ZCOACHINTERVENTIONMODE" }.count, 1)
    }

    func testMigrateAddsFocusCoachSettingsColumnsWithDefaults() throws {
        let url = try makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let db = try openDB(url)
        defer { sqlite3_close(db) }

        try exec(db, """
        CREATE TABLE ZAPPSETTINGS (
            Z_PK INTEGER PRIMARY KEY,
            Z_ENT INTEGER,
            Z_OPT INTEGER,
            ZAUTOSTARTBREAK INTEGER,
            ZAUTOSTARTNEXTSESSION INTEGER,
            ZLAUNCHATLOGIN INTEGER,
            ZSESSIONSBEFORELONGBREAK INTEGER,
            ZFOCUSDURATION FLOAT,
            ZLONGBREAKDURATION FLOAT,
            ZSHORTBREAKDURATION FLOAT,
            ZCOMPLETIONSOUND VARCHAR
        );
        """)

        try exec(db, """
        INSERT INTO ZAPPSETTINGS (
            Z_PK, Z_ENT, Z_OPT, ZAUTOSTARTBREAK, ZAUTOSTARTNEXTSESSION, ZLAUNCHATLOGIN,
            ZSESSIONSBEFORELONGBREAK, ZFOCUSDURATION, ZLONGBREAKDURATION, ZSHORTBREAKDURATION, ZCOMPLETIONSOUND
        ) VALUES (1, 1, 1, 1, 0, 1, 4, 1500.0, 900.0, 300.0, 'Glass');
        """)

        try StoreMigrator.migrateStoreIfNeeded(at: url)

        let columns = try tableColumns(db, table: "ZAPPSETTINGS")
        XCTAssertTrue(columns.contains("ZCOACHREALTIMEENABLED"))
        XCTAssertTrue(columns.contains("ZCOACHPROMPTBUDGETPERSESSION"))
        XCTAssertTrue(columns.contains("ZCOACHREASONPROMPTSENABLED"))
        XCTAssertTrue(columns.contains("ZCOACHDEFAULTSNOOZEMINUTES"))
        XCTAssertTrue(columns.contains("ZCOACHCOLLECTRAWDOMAINS"))
        XCTAssertTrue(columns.contains("ZCOACHIDLESTARTERENABLED"))
        XCTAssertTrue(columns.contains("ZCOACHAUTOOPENPOPOVERONSTRONGPROMPT"))
        XCTAssertTrue(columns.contains("ZCOACHBRINGAPPTOFRONTONSTRONGPROMPT"))
        XCTAssertTrue(columns.contains("ZCOACHALLOWSKIPACTION"))
        XCTAssertTrue(columns.contains("ZCOACHMAXSTRONGPROMPTSPERSESSION"))
        XCTAssertTrue(columns.contains("ZCOACHINTERVENTIONMODE"))

        let coachValues = try querySingleCoachColumns(
            db,
            sql: "SELECT ZCOACHREALTIMEENABLED, ZCOACHPROMPTBUDGETPERSESSION, ZCOACHREASONPROMPTSENABLED, ZCOACHDEFAULTSNOOZEMINUTES, ZCOACHCOLLECTRAWDOMAINS, ZCOACHIDLESTARTERENABLED, ZCOACHAUTOOPENPOPOVERONSTRONGPROMPT, ZCOACHBRINGAPPTOFRONTONSTRONGPROMPT, ZCOACHALLOWSKIPACTION, ZCOACHMAXSTRONGPROMPTSPERSESSION, ZCOACHINTERVENTIONMODE FROM ZAPPSETTINGS WHERE Z_PK = 1;"
        )
        XCTAssertEqual(coachValues.realtimeEnabled, 1)
        XCTAssertEqual(coachValues.promptBudget, 4)
        XCTAssertEqual(coachValues.reasonPrompts, 1)
        XCTAssertEqual(coachValues.snoozeMinutes, 10)
        XCTAssertEqual(coachValues.collectRawDomains, 0)
        XCTAssertEqual(coachValues.idleStarterEnabled, 1)
        XCTAssertEqual(coachValues.autoOpenPopoverOnStrongPrompt, 1)
        XCTAssertEqual(coachValues.bringAppToFrontOnStrongPrompt, 1)
        XCTAssertEqual(coachValues.allowSkipAction, 1)
        XCTAssertEqual(coachValues.maxStrongPromptsPerSession, 2)
        XCTAssertEqual(coachValues.interventionMode, "balanced")

        // Verify existing data preserved
        let original = try querySingleText(db, sql: "SELECT ZCOMPLETIONSOUND FROM ZAPPSETTINGS WHERE Z_PK = 1;")
        XCTAssertEqual(original, "Glass")
    }

    private func makeTempStoreURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("FocusFlow.store")
    }

    private func openDB(_ url: URL) throws -> OpaquePointer {
        var db: OpaquePointer?
        if sqlite3_open(url.path, &db) != SQLITE_OK || db == nil {
            throw NSError(domain: "StoreMigratorTests", code: 1)
        }
        return db!
    }

    private func exec(_ db: OpaquePointer, _ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            let message = String(cString: sqlite3_errmsg(db))
            throw NSError(domain: "StoreMigratorTests", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func tableColumns(_ db: OpaquePointer, table: String) throws -> [String] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "PRAGMA table_info(\(table));"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw NSError(domain: "StoreMigratorTests", code: 3)
        }

        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1) {
                names.append(String(cString: name))
            }
        }
        return names
    }

    private func querySingleIntPair(_ db: OpaquePointer, sql: String) throws -> (Int, Int) {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw NSError(domain: "StoreMigratorTests", code: 4)
        }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw NSError(domain: "StoreMigratorTests", code: 5)
        }
        return (Int(sqlite3_column_int(statement, 0)), Int(sqlite3_column_int(statement, 1)))
    }

    private func querySingleText(_ db: OpaquePointer, sql: String) throws -> String {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw NSError(domain: "StoreMigratorTests", code: 6)
        }
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else {
            throw NSError(domain: "StoreMigratorTests", code: 7)
        }
        return String(cString: text)
    }

    private func querySingleCalendarColumns(_ db: OpaquePointer, sql: String) throws -> (Double, Int, String) {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw NSError(domain: "StoreMigratorTests", code: 8)
        }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw NSError(domain: "StoreMigratorTests", code: 9)
        }
        guard let name = sqlite3_column_text(statement, 2) else {
            throw NSError(domain: "StoreMigratorTests", code: 10)
        }
        return (
            sqlite3_column_double(statement, 0),
            Int(sqlite3_column_int(statement, 1)),
            String(cString: name)
        )
    }

    private func querySingleReminderColumns(_ db: OpaquePointer, sql: String) throws -> (Int, String) {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw NSError(domain: "StoreMigratorTests", code: 11)
        }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw NSError(domain: "StoreMigratorTests", code: 12)
        }
        guard let listId = sqlite3_column_text(statement, 1) else {
            throw NSError(domain: "StoreMigratorTests", code: 13)
        }
        return (
            Int(sqlite3_column_int(statement, 0)),
            String(cString: listId)
        )
    }

    private func querySingleCoachColumns(_ db: OpaquePointer, sql: String) throws -> (
        realtimeEnabled: Int,
        promptBudget: Int,
        reasonPrompts: Int,
        snoozeMinutes: Int,
        collectRawDomains: Int,
        idleStarterEnabled: Int,
        autoOpenPopoverOnStrongPrompt: Int,
        bringAppToFrontOnStrongPrompt: Int,
        allowSkipAction: Int,
        maxStrongPromptsPerSession: Int,
        interventionMode: String
    ) {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw NSError(domain: "StoreMigratorTests", code: 14)
        }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw NSError(domain: "StoreMigratorTests", code: 15)
        }
        guard let modeText = sqlite3_column_text(statement, 10) else {
            throw NSError(domain: "StoreMigratorTests", code: 16)
        }
        return (
            Int(sqlite3_column_int(statement, 0)),
            Int(sqlite3_column_int(statement, 1)),
            Int(sqlite3_column_int(statement, 2)),
            Int(sqlite3_column_int(statement, 3)),
            Int(sqlite3_column_int(statement, 4)),
            Int(sqlite3_column_int(statement, 5)),
            Int(sqlite3_column_int(statement, 6)),
            Int(sqlite3_column_int(statement, 7)),
            Int(sqlite3_column_int(statement, 8)),
            Int(sqlite3_column_int(statement, 9)),
            String(cString: modeText)
        )
    }
}
