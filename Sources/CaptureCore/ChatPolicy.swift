import Foundation
import CoreGraphics
import UniformTypeIdentifiers

public enum LaunchMode: Equatable, Sendable {
    case chat
    case chatPreview
    case lab(session: String?, web: Bool)
    public static func parse(_ arguments: [String]) throws -> LaunchMode {
        var lab = false, web = false
        var preview = false
        var session: String?
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--lab": lab = true
            case "--web-test": lab = true; web = true
            case "--chat-preview": preview = true
            case "--session":
                index += 1
                guard index < arguments.count, arguments[index].hasPrefix("/"), session == nil else {
                    throw LaunchError.invalidArguments
                }
                lab = true; session = arguments[index]
            default: throw LaunchError.invalidArguments
            }
            index += 1
        }
        guard !preview || !lab else { throw LaunchError.invalidArguments }
        return preview ? .chatPreview : (lab ? .lab(session: session, web: web) : .chat)
    }
}

public enum LaunchError: Error { case invalidArguments }

public enum ChatInteraction {
    public static func pendingRestore<T: Equatable>(previous: [T], visible: [T]) -> [T] {
        visible.reduce(previous) { result, value in result.contains(value) ? result : result + [value] }
    }
    public static func pasteText(_ text: String?, representations: [String]) -> String? {
        guard !representations.contains(where: { name in
            guard let type = UTType(name) else { return name == "NSFilenamesPboardType" }
            return type.conforms(to: .image) || type.conforms(to: .fileURL) || type.conforms(to: .pdf)
        }) else { return nil }
        return text
    }
}

public enum WebNavigationPolicy {
    public static func allows(_ url: URL?) -> Bool {
        guard let url else { return false }
        if url.absoluteString == "about:blank" { return true }
        return url.scheme?.lowercased() == "https" && url.host?.isEmpty == false
            && url.user == nil && url.password == nil
    }
}

public enum WindowPlacement {
    public static func restore(_ saved: CGRect?, screens: [CGRect]) -> CGRect {
        let fallback = CGRect(x: 0, y: 0, width: 1280, height: 800)
        let screens = screens.filter { !$0.isEmpty && !$0.isInfinite && !$0.isNull }
        let valid = saved.flatMap { rect -> CGRect? in
            [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite) && !rect.isEmpty ? rect : nil
        }
        let screen = valid.flatMap { rect in
            screens.max { a, b in
                let first = a.intersection(rect), second = b.intersection(rect)
                return (first.isNull ? 0 : first.width * first.height) < (second.isNull ? 0 : second.width * second.height)
            }.flatMap { $0.intersects(rect) ? $0 : nil }
        } ?? screens.first ?? fallback
        let size = CGSize(width: min(screen.width, max(640, valid?.width ?? 900)),
                          height: min(screen.height, max(480, valid?.height ?? 700)))
        let origin = valid.flatMap { screen.intersects($0) ? $0.origin : nil }
            ?? CGPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
        return CGRect(x: min(max(origin.x, screen.minX), screen.maxX - size.width),
                      y: min(max(origin.y, screen.minY), screen.maxY - size.height),
                      width: size.width, height: size.height)
    }
}
