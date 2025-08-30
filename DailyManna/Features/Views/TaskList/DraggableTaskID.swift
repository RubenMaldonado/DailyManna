import SwiftUI
import UniformTypeIdentifiers

struct DraggableTaskID: Transferable {
    let id: UUID
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .plainText, exporting: { value in
            value.id.uuidString.data(using: .utf8) ?? Data()
        }, importing: { data in
            guard let str = String(data: data, encoding: .utf8), let uuid = UUID(uuidString: str) else {
                throw URLError(.cannotDecodeContentData)
            }
            return DraggableTaskID(id: uuid)
        })
    }
}


