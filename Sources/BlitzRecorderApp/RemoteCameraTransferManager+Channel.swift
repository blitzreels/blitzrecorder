import BlitzRecorderCore
import BlitzRecorderTransport
import Foundation
import Network

struct RemoteCameraChannelRequest {
    let takeID: UUID
    let host: NWEndpoint.Host?
    let port: UInt16
    let token: String
    let offset: Int64
    let byteCount: Int64
}

extension RemoteCameraTransferManager {
    /// Reads the clip from the iPhone's raw-byte channel into the partial file. The import finishes once both the
    /// bytes and the iPhone's `transferComplete` checksum are in, in whichever order they arrive.
    func receiveChannel(_ request: RemoteCameraChannelRequest) {
        guard let partialURL = partialURL(takeID: request.takeID) else { return }
        guard let host = request.host else {
            failChannel(.init(takeID: request.takeID,
                              error: RecorderError.remoteCameraTransferFailed("The iPhone address is unknown.")))
            return
        }
        noteChannelProgress(.init(takeID: request.takeID, receivedByteCount: request.offset))
        let takeID = request.takeID
        channelTasks[takeID] = Task { [weak self] in
            do {
                let total = try await RawFileTransferClient.receive(.init(
                    host: host, port: request.port, token: request.token, destinationURL: partialURL,
                    offset: request.offset, byteCount: request.byteCount,
                    onProgress: { total in
                        Task { @MainActor in self?.noteChannelProgress(.init(takeID: takeID, receivedByteCount: total)) }
                    }
                ))
                await self?.finishChannel(.init(takeID: takeID, receivedByteCount: total))
            } catch {
                self?.failChannel(.init(takeID: takeID, error: error))
            }
        }
    }

    struct ChannelProgress {
        let takeID: UUID
        let receivedByteCount: Int64
    }

    private func noteChannelProgress(_ progress: ChannelProgress) {
        updateReceivedByteCount(progress)
        scheduleTimeout(takeID: progress.takeID, reason: "Timed out while receiving iPhone recording data.")
    }

    private func finishChannel(_ progress: ChannelProgress) async {
        channelTasks.removeValue(forKey: progress.takeID)
        updateReceivedByteCount(progress)
        guard let completion = pendingChannelCompletions.removeValue(forKey: progress.takeID) else { return }
        await completeTransfer(takeID: progress.takeID, byteCount: completion.byteCount, sha256: completion.sha256,
                               settings: completion.settings)
    }

    struct ChannelFailure {
        let takeID: UUID
        let error: Error
    }

    private func failChannel(_ failure: ChannelFailure) {
        onMessage("iPhone transfer channel failed: \(failure.error.localizedDescription)")
        channelTasks.removeValue(forKey: failure.takeID)
        pendingChannelCompletions.removeValue(forKey: failure.takeID)
        failInFlightTransfer(takeID: failure.takeID, reason: failure.error.localizedDescription)
    }
}
