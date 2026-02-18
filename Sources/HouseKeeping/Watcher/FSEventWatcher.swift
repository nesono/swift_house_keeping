import CoreServices
import Foundation

public struct FileEvent: Sendable {
    public let path: String
    public let flags: FSEventStreamEventFlags
    public let eventType: FileEventType

    public var isCreated: Bool {
        flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0
    }

    public var isModified: Bool {
        flags & UInt32(kFSEventStreamEventFlagItemModified) != 0
    }

    public var isRemoved: Bool {
        flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0
    }

    public var isRenamed: Bool {
        flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0
    }
}

public final class FSEventWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let paths: [String]
    private let latency: CFTimeInterval
    private let handler: @Sendable ([FileEvent]) -> Void
    private let queue: DispatchQueue

    public init(
        paths: [String],
        latency: CFTimeInterval = 1.0,
        handler: @escaping @Sendable ([FileEvent]) -> Void,
    ) {
        self.paths = paths
        self.latency = latency
        self.handler = handler
        queue = DispatchQueue(label: "com.house-keeping.fsevents", qos: .utility)
    }

    public func start() {
        let cfPaths = paths as CFArray
        var context = FSEventStreamContext()
        let rawSelf = Unmanaged.passUnretained(self).toOpaque()
        context.info = rawSelf

        let callback: FSEventStreamCallback = {
            _, clientInfo, numEvents, eventPaths, eventFlags, _ in
            guard let clientInfo else { return }
            let watcher = Unmanaged<FSEventWatcher>.fromOpaque(clientInfo).takeUnretainedValue()

            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
            let flags = Array(UnsafeBufferPointer(start: eventFlags, count: numEvents))

            var events: [FileEvent] = []
            for i in 0 ..< numEvents {
                let flag = flags[i]
                let eventType: FileEventType = if flag & UInt32(kFSEventStreamEventFlagItemCreated) != 0 {
                    .create
                } else if flag & UInt32(kFSEventStreamEventFlagItemModified) != 0 {
                    .modify
                } else if flag & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 {
                    .delete
                } else if flag & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 {
                    .rename
                } else {
                    .modify
                }
                events.append(FileEvent(path: paths[i], flags: flag, eventType: eventType))
            }

            watcher.handler(events)
        }

        let streamFlags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)

        stream = FSEventStreamCreate(
            nil, callback, &context,
            cfPaths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency, FSEventStreamCreateFlags(streamFlags),
        )

        if let stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    public func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    deinit {
        stop()
    }
}
