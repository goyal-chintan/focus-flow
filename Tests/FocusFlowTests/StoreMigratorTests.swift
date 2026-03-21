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
        XCTAssertTrue(columns.contains("ZANTIPROCRASTINATIONENABLED"))
        XCTAssertTrue(columns.contains("ZANTIPROCRASTINATIONTHRESHOLDMINUTES"))

        let calendarValues = try querySingleCalendarColumns(
            db,
            sql: "SELECT ZDAILYFOCUSGOAL, ZCALENDARINTEGRATIONENABLED, ZCALENDARNAME FROM ZAPPSETTINGS WHERE Z_PK = 1;"
        )
        XCTAssertEqual(calendarValues.0, 7200.0, accuracy: 0.001)
        XCTAssertEqual(calendarValues.1, 0)
        XCTAssertEqual(calendarValues.2, "FocusFlow")

        let values = try querySingleIntPair(
            db,
            sql: "SELECT ZANTIPROCRASTINATIONENABLED, ZANTIPROCRASTINATIONTHRESHOLDMINUTES FROM ZAPPSETTINGS WHERE Z_PK = 1;"
        )
        XCTAssertEqual(values.0, 1)
        XCTAssertEqual(values.1, 5)

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
        XCTAssertEqual(columns.filter { $0 == "ZANTIPROCRASTINATIONENABLED" }.count, 1)
        XCTAssertEqual(columns.filter { $0 == "ZANTIPROCRASTINATIONTHRESHOLDMINUTES" }.count, 1)
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
}
