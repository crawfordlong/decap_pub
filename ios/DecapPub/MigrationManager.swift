import Foundation

/// Handles migration of data from UserDefaults to secure storage
final class MigrationManager {
    static let shared = MigrationManager()
    
    private let userDefaults = UserDefaults.standard
    private let migrationKey = "com.decappub.migrations.completed"
    
    private enum Migration: String, CaseIterable {
        case tokenToKeychain = "tokenToKeychain_v1"
    }
    
    private init() {}
    
    // MARK: - Public API
    
    /// Run all pending migrations
    func runMigrationsIfNeeded() {
        let completedMigrations = getCompletedMigrations()
        
        for migration in Migration.allCases {
            if !completedMigrations.contains(migration.rawValue) {
                runMigration(migration)
                markMigrationComplete(migration)
            }
        }
    }
    
    // MARK: - Individual Migrations
    
    private func runMigration(_ migration: Migration) {
        switch migration {
        case .tokenToKeychain:
            migrateTokenToKeychain()
        }
    }
    
    /// Migrate GitHub token from UserDefaults to Keychain
    private func migrateTokenToKeychain() {
        // Check if token exists in UserDefaults
        guard let token = userDefaults.string(forKey: "githubToken"),
              !token.isEmpty else {
            return
        }
        
        // Save to Keychain
        do {
            try KeychainManager.shared.save(token, for: "githubToken")
            
            // Remove from UserDefaults after successful save
            userDefaults.removeObject(forKey: "githubToken")
            userDefaults.synchronize()
            
            print("Successfully migrated GitHub token to Keychain")
        } catch {
            print("Failed to migrate token to Keychain: \(error)")
            // Don't remove from UserDefaults if migration failed
        }
    }
    
    // MARK: - Migration Tracking
    
    private func getCompletedMigrations() -> Set<String> {
        if let completed = userDefaults.array(forKey: migrationKey) as? [String] {
            return Set(completed)
        }
        return []
    }
    
    private func markMigrationComplete(_ migration: Migration) {
        var completed = getCompletedMigrations()
        completed.insert(migration.rawValue)
        userDefaults.set(Array(completed), forKey: migrationKey)
        userDefaults.synchronize()
    }
    
    // MARK: - Testing Support
    
    #if DEBUG
    /// Reset all migrations (for testing only)
    func resetMigrations() {
        userDefaults.removeObject(forKey: migrationKey)
        userDefaults.synchronize()
    }
    
    /// Check if a specific migration has been completed
    private func isMigrationComplete(_ migration: Migration) -> Bool {
        return getCompletedMigrations().contains(migration.rawValue)
    }
    #endif
}
