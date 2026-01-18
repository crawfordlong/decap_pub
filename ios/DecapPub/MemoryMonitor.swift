import Foundation
import UIKit
import os.log

/// Monitors memory usage and handles memory warnings
@MainActor
final class MemoryMonitor: ObservableObject {
    static let shared = MemoryMonitor()
    
    @Published private(set) var currentMemoryUsageMB: Float = 0
    @Published private(set) var memoryWarningCount: Int = 0
    
    private var timer: Timer?
    private let updateInterval: TimeInterval = 5.0 // Update every 5 seconds
    
    private init() {
        startMonitoring()
    }
    
    // MARK: - Monitoring
    
    func startMonitoring() {
        // Listen for memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        
        // Start periodic memory usage monitoring
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMemoryUsage()
            }
        }
        
        // Initial update
        updateMemoryUsage()
    }
    
    func stopMonitoring() {
        NotificationCenter.default.removeObserver(self)
        timer?.invalidate()
        timer = nil
    }
    
    @objc nonisolated private func handleMemoryWarning() {
        Task { @MainActor in
            memoryWarningCount += 1
            Logger.performance.warning("Memory warning received (count: \(self.memoryWarningCount))")
            Logger.performance.info("Current memory usage: \(self.currentMemoryUsageMB) MB")
            
            // Clear image caches
            ImageCache.shared.clearAll()
            Logger.performance.info("Cleared image caches in response to memory warning")
            
            // Update memory usage after clearing
            updateMemoryUsage()
        }
    }
    
    private func updateMemoryUsage() {
        currentMemoryUsageMB = getMemoryUsageMB()
        
        // Log if memory usage is high
        if currentMemoryUsageMB > 200 {
            Logger.performance.warning("High memory usage: \(self.currentMemoryUsageMB) MB")
        }
    }
    
    // MARK: - Memory Calculation
    
    private func getMemoryUsageMB() -> Float {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        guard kerr == KERN_SUCCESS else {
            return 0
        }
        
        return Float(info.resident_size) / (1024 * 1024)
    }
    
    // MARK: - Cache Stats
    
    var cacheStats: String {
        ImageCache.shared.stats
    }
    
    // MARK: - Manual Memory Management
    
    func clearImageCaches() {
        ImageCache.shared.clearAll()
        Logger.performance.info("Manually cleared image caches")
        updateMemoryUsage()
    }
    
    func clearFullImageCache() {
        ImageCache.shared.clearFullImages()
        Logger.performance.info("Manually cleared full image cache")
        updateMemoryUsage()
    }
}

// MARK: - Mach Imports

import Darwin.Mach
