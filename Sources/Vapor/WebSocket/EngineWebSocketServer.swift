/// Vapor's default `WebSocketServer` implementation. Includes conformance to `WebSocketServer`
/// that is backed by a `TrieRouter` for registering multiple different websocket handlers.
///
/// A `WebSocketServer` determines whether HTTP requests requesting upgrade to the websocket protocol should
/// be approved or denied. If approved, additional headers can be returned in the 101 switching protocols response.
///
/// When HTTP upgrade requests are approved, the `WebSocketServer` will handle the newly connected websocket clients.
///
/// HTTP upgrade requests will be handled by the `WebSocketServer` before invoking Vapor's normal HTTP request pipeline
/// (including middleware). Should an HTTP upgrade request be accepted, no other parts of Vapor's pipeline will be invoked.
/// Should the HTTP upgrade request be denied, the request will continue through Vapor's HTTP pipeline normally.
///
/// Note: The `WebSocketServer` _always_ runs behind an HTTP server and will only be invoked when HTTP requests request an uprade.
public final class EngineWebSocketServer: WebSocketServer, Service {
    /// The internal trie-node router backing this server.
    /// This will be used to register and retreive all websocket responding routes.
    private let router: TrieRouter<WebSocketResponder>

    /// All websocket responder routes that have been added to this `EngineWebSocketServer`.
    public var routes: [Route<WebSocketResponder>]

    /// Creates a new `EngineWebSocketServer` with default settings.
    public static func `default`() -> EngineWebSocketServer {
        return .init()
    }

    /// Creates a new `EngineWebSocketServer`. Use the `.default()` static method to do this publicly.
    internal init() {
        router = .init()
        routes = .init()
    }

    /// Registers a new `Route<WebSocketResponder>` to this `EngineWebSocketServer`.
    ///
    /// This is normally done using the convenience `.get(...)` methods. However, this method is
    /// useful for registering custom routes.
    ///
    /// - parameters:
    ///     - route: The websocket responder route to add to this websocket server.
    public func register(route: Route<WebSocketResponder>) {
        routes.append(route)
        router.register(route: route)
    }

    /// Determines whether the HTTP request should be upgraded or not.
    /// Only HTTP requests that have requested websocket protocol upgrade will be supplied to this method.
    ///
    /// - parameters:
    ///     - request: The HTTP request requesting upgrade to websocket protocol.
    /// - returns: HTTPHeaders to include in the 101 switching protocols HTTP response.
    ///            If `nil`, the HTTP upgrade request will be denied.
    public func webSocketShouldUpgrade(for request: Request) -> HTTPHeaders? {
        guard let route = router.route(
            path: request.http.urlString.split(separator: "/").map { .init(substring: $0) },
            parameters: request
        ) else {
            return nil
        }
        return route.shouldUpgrade(request)
    }

    /// Handles newly connected websocket clients. This method will only be called if `webSocketShouldUpgrade(for:)` returned
    /// non-nil HTTP headers.
    ///
    /// - parameters:
    ///     - webSocket: The newly connected websocket client. Use this to send and receive messages from the client.
    ///     - request: The HTTP request that initiated the websocket protocol upgrade.
    public func webSocketOnUpgrade(_ webSocket: WebSocket, for request: Request) {
        do {
            guard let route = router.route(
                path: request.http.urlString.split(separator: "/").map { .init(substring: $0) },
                parameters: request
                ) else {
                    throw VaporError(identifier: "websocketOnUpgrade", reason: "Could not find route for upgraded WebSocket", source: .capture())
            }
            try route.onUpgrade(webSocket, request)
        } catch {
            ERROR("WebSocket: \(error)")
            webSocket.close()
        }
    }
}

/// MARK: Convenience `get`

extension EngineWebSocketServer {
    /// Registers a new websocket handling route at the supplied dynamic path.
    ///
    /// - parameters:
    ///     - path: Dynamic path to associate with this websocket upgrade closure.
    ///             HTTP upgrade requests that contain a matching path will invoke the supplied on upgrade
    ///             closure when the websocket client connects.
    ///             Any parameterized values can be retreived from the HTTP request supplied to the closure.
    ///     - closure: Websocket on upgrade closure. Accepts newly upgraded websocket connections.
    ///
    /// - returns: Discardable websocket responder route. Use this route reference to append metadata to the route.
    @discardableResult
    public func get(at path: [DynamicPathComponent], use closure: @escaping (WebSocket, Request) throws -> ()) -> Route<WebSocketResponder> {
        let responder = WebSocketResponder(
            shouldUpgrade: { _ in [:] },
            onUpgrade: closure
        )
        let route: Route<WebSocketResponder> = .init(path: path, output: responder)
        register(route: route)
        return route
    }

    /// Registers a new websocket handling route at the supplied dynamic path.
    ///
    /// - parameters:
    ///     - path: Dynamic path to associate with this websocket upgrade closure.
    ///             HTTP upgrade requests that contain a matching path will invoke the supplied on upgrade
    ///             closure when the websocket client connects.
    ///             Any parameterized values can be retreived from the HTTP request supplied to the closure.
    ///     - closure: Websocket on upgrade closure. Accepts newly upgraded websocket connections.
    ///
    /// - returns: Discardable websocket responder route. Use this route reference to append metadata to the route.
    @discardableResult
    public func get(_ path: DynamicPathComponent..., use closure: @escaping (WebSocket, Request) throws -> ()) -> Route<WebSocketResponder> {
        return self.get(at: path, use: closure)
    }

    /// Registers a new websocket handling route at the supplied dynamic path.
    ///
    /// - parameters:
    ///     - path: Dynamic path to associate with this websocket upgrade closure.
    ///             HTTP upgrade requests that contain a matching path will invoke the supplied on upgrade
    ///             closure when the websocket client connects.
    ///             Any parameterized values can be retreived from the HTTP request supplied to the closure.
    ///     - closure: Websocket on upgrade closure. Accepts newly upgraded websocket connections.
    ///
    /// - returns: Discardable websocket responder route. Use this route reference to append metadata to the route.
    @discardableResult
    public func get(_ path: DynamicPathComponentRepresentable..., use closure: @escaping (WebSocket, Request) throws -> ()) -> Route<WebSocketResponder> {
        return self.get(at: path.makeDynamicPathComponents(), use: closure)
    }
}
