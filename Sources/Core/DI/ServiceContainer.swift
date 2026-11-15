import Foundation

/// Explicit dependency injection container. Not a global mutable singleton.
public final class ServiceContainer: @unchecked Sendable {
    private let lock = NSLock()
    private var factories: [ObjectIdentifier: () -> Any] = [:]
    private var singletons: [ObjectIdentifier: Any] = [:]

    public init() {}

    public func register<T>(_ type: T.Type = T.self, factory: @escaping () -> T) {
        lock.lock(); defer { lock.unlock() }
        factories[ObjectIdentifier(type)] = factory
    }

    public func registerSingleton<T>(_ type: T.Type = T.self, instance: T) {
        lock.lock(); defer { lock.unlock() }
        singletons[ObjectIdentifier(type)] = instance
        factories[ObjectIdentifier(type)] = { instance }
    }

    public func registerSingleton<T>(_ instance: T) {
        registerSingleton(T.self, instance: instance)
    }

    public func resolve<T>(_ type: T.Type = T.self) throws -> T {
        lock.lock()
        if let existing = singletons[ObjectIdentifier(type)] as? T {
            lock.unlock()
            return existing
        }
        guard let factory = factories[ObjectIdentifier(type)] else {
            lock.unlock()
            throw AppError.configuration("No registration for \(type)")
        }
        lock.unlock()
        guard let value = factory() as? T else {
            throw AppError.configuration("Factory returned wrong type for \(type)")
        }
        return value
    }
}
