// SingletonManager - Ensures only one instance of RemoteJuggler tray runs

import Foundation

final class SingletonManager: @unchecked Sendable {
    @MainActor static let shared = SingletonManager()

    private let socketPath = "/tmp/remote-juggler-tray.sock"
    private var serverSocket: Int32 = -1

    private init() {}

    /// Returns true if this is the primary instance, false if another instance is running
    func acquireLock() -> Bool {
        // Remove stale socket
        unlink(socketPath)

        // Create Unix domain socket
        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            print("Failed to create socket")
            return false
        }

        // Bind to socket path
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path.0) { dest in
                _ = strcpy(dest, ptr)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.bind(serverSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        if bindResult < 0 {
            // Another instance is running
            close(serverSocket)
            serverSocket = -1

            // Try to activate the existing instance
            activateExistingInstance()
            return false
        }

        // Listen for connections (for activation signals)
        listen(serverSocket, 1)

        // Start listening for activation in background
        startListening()

        return true
    }

    func releaseLock() {
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
        unlink(socketPath)
    }

    private func activateExistingInstance() {
        // Connect to existing instance to bring it to front
        let clientSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard clientSocket >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path.0) { dest in
                _ = strcpy(dest, ptr)
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(clientSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        if connectResult >= 0 {
            // Send activation message
            let msg = "ACTIVATE\n"
            _ = msg.withCString { Darwin.send(clientSocket, $0, msg.count, 0) }
        }

        close(clientSocket)
    }

    private func startListening() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }

            while self.serverSocket >= 0 {
                let clientSocket = accept(self.serverSocket, nil, nil)
                if clientSocket >= 0 {
                    // Read activation message
                    var buffer = [CChar](repeating: 0, count: 256)
                    let bytesRead = recv(clientSocket, &buffer, buffer.count - 1, 0)

                    if bytesRead > 0 {
                        let data = Data(bytes: buffer, count: Int(bytesRead))
                        if let message = String(data: data, encoding: .utf8),
                           message.hasPrefix("ACTIVATE") {
                            DispatchQueue.main.async {
                                self.handleActivation()
                            }
                        }
                    }

                    close(clientSocket)
                }
            }
        }
    }

    private func handleActivation() {
        // Bring menu bar app to front / show menu
        // In a real implementation, this would trigger the menu bar extra to show
        print("Activation received from another instance")
    }

    deinit {
        releaseLock()
    }
}
