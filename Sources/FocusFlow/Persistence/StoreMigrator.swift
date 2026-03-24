import Foundation
import SQLite3

enum StoreMigrator {
    private struct ColumnMigration {
        let table: String
        let column: String
        let sqlType: String
        let defaultSQLValue: String
    }

    private static let requiredColumnMigrations: [ColumnMigration] = [
        ColumnMigration(
            table: "ZAPPSETTINGS",
            column: "ZDAILYFOCUSGOAL",
            sqlType: "FLOAT",
            defaultSQLValue: "7200"
        ),
        ColumnMigration(
            table: "ZAPPSETTINGS",
            column: "ZCALENDARINTEGRATIONENABLED",
            sqlType: "INTEGER",
            defaultSQLValue: "0"
        ),
        ColumnMigration(
            table: "ZAPPSETTINGS",
            column: "ZCALENDARNAME",
            sqlType: "VARCHAR",
            defaultSQLValue: "'FocusFlow'"
        ),
        ColumnMigration(
            table: "ZAPPSETTINGS",
            column: "ZSELECTEDCALENDARID",
            sqlType: "VARCHAR",
            defaultSQLValue: "''"
        ),
        ColumnMigration(
            table: "ZAPPSETTINGS",
            column: "ZANTIPROCRASTINATIONENABLED",
            sqlType: "INTEGER",
            defaultSQLValue: "1"
        ),
        ColumnMigration(
            table: "ZAPPSETTINGS",
            column: "ZANTIPROCRASTINATIONTHRESHOLDMINUTES",
            sqlType: "INTEGER",
            defaultSQLValue: "5"
        ),
        ColumnMigration(
            table: "ZAPPSETTINGS",
            column: "ZREMINDERSINTEGRATIONENABLED",
            sqlType: "INTEGER",
            defaultSQLValue: "0"
        ),
        ColumnMigration(
            table: "ZAPPSETTINGS",
            column: "ZSELECTEDREMINDERLISTID",
            sqlType: "VARCHAR",
            defaultSQLValue: "''"
        ),
        ColumnMigration(
            table: "ZAPPSETTINGS",
            column: "ZCOACHREALTIMEENABLED",
            sqlType: "INTEGER",
            defaultSQLValue: "1"
        ),
        ColumnMigration(
            table: "ZAPPSETTINGS",
            column: "ZCOACHPROMPTBUDGETPERSESSION",
            sqlType: "INTEGER",
            defaultSQLValue: "4"
        ),
        ColumnMigration(
            table: "ZAPPSETTINGS",
            column: "ZCOACHREASONPROMPTSENABLED",
            sqlType: "INTEGER",
            defaultSQLValue: "1"
        ),
        ColumnMigration(
            table: "ZAPPSETTINGS",
            column: "ZCOACHDEFAULTSNOOZEMINUTES",
            sqlType: "INTEGER",
            defaultSQLValue: "10"
        ),
        ColumnMigration(
            table: "ZAPPSETTINGS",
            column: "ZCOACHCOLLECTRAWDOMAINS",
            sqlType: "INTEGER",
            defaultSQLValue: "0"
        ),
        ColumnMigration(
            table: "ZAPPSETTINGS",
            column: "ZCOACHIDLESTARTERENABLED",
            sqlType: "INTEGER",
            defaultSQLValue: "1"
        ),
        ColumnMigration(
            table: "ZAPPSETTINGS",
            column: "ZCOACHAUTOOPENPOPOVERONSTRONGPROMPT",
            sqlType: "INTEGER",
            defaultSQLValue: "1"
        ),
        ColumnMigration(
            table: "ZAPPSETTINGS",
            column: "ZCOACHBRINGAPPTOFRONTONSTRONGPROMPT",
            sqlType: "INTEGER",
            defaultSQLValue: "1"
        ),
        ColumnMigration(
            table: "ZAPPSETTINGS",
            column: "ZCOACHALLOWSKIPACTION",
            sqlType: "INTEGER",
            defaultSQLValue: "1"
        ),
        ColumnMigration(
            table: "ZAPPSETTINGS",
            column: "ZCOACHMAXSTRONGPROMPTSPERSESSION",
            sqlType: "INTEGER",
            defaultSQLValue: "2"
        ),
        ColumnMigration(
            table: "ZAPPSETTINGS",
            column: "ZCOACHINTERVENTIONMODE",
            sqlType: "VARCHAR",
            defaultSQLValue: "'balanced'"
        ),
        ColumnMigration(
            table: "ZPROJECT",
            column: "ZWORKMODE",
            sqlType: "VARCHAR",
            defaultSQLValue: "'deep_work'"
        ),
        ColumnMigration(
            table: "ZPROJECT",
            column: "ZGUARDIANSENSITIVITY",
            sqlType: "VARCHAR",
            defaultSQLValue: "'normal'"
        ),
        ColumnMigration(
            table: "ZPROJECT",
            column: "ZDIFFICULTYBIAS",
            sqlType: "VARCHAR",
            defaultSQLValue: "'moderate'"
        )
    ]

    static func migrateStoreIfNeeded(at storeURL: URL) throws {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return
        }

        let db = try openDatabase(at: storeURL)
        defer { sqlite3_close(db) }

        for migration in requiredColumnMigrations {
            let columns = try loadColumns(for: migration.table, in: db)
            guard columns.contains(migration.column) == false else {
                continue
            }

            let sql = """
            ALTER TABLE \(migration.table)
            ADD COLUMN \(migration.column) \(migration.sqlType) NOT NULL DEFAULT \(migration.defaultSQLValue);
            """
            try execute(sql: sql, in: db)
        }
    }

    private static func openDatabase(at storeURL: URL) throws -> OpaquePointer {
        var db: OpaquePointer?
        guard sqlite3_open(storeURL.path, &db) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Failed to open SQLite database."
            if let db {
                sqlite3_close(db)
            }
            throw NSError(domain: "StoreMigrator", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return db
    }

    private static func loadColumns(for table: String, in db: OpaquePointer) throws -> Set<String> {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        let query = "PRAGMA table_info(\(table));"
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError(in: db, code: 2)
        }

        var columns = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1) {
                columns.insert(String(cString: name))
            }
        }
        return columns
    }

    private static func execute(sql: String, in db: OpaquePointer) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw sqliteError(in: db, code: 3)
        }
    }

    private static func sqliteError(in db: OpaquePointer, code: Int) -> NSError {
        NSError(
            domain: "StoreMigrator",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))]
        )
    }
}
