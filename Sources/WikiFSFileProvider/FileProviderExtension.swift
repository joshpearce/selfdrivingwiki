import FileProvider

/// The replicated File Provider extension principal class. Read-only: it serves
/// metadata, enumerates containers, and materializes file content on demand;
/// every mutating operation is rejected.
///
/// `@objc(FileProviderExtension)` pins the Objective-C runtime name so it
/// matches `NSExtensionPrincipalClass` in the appex Info.plist (otherwise Swift
/// would mangle it to `WikiFSFileProvider.FileProviderExtension`).
@objc(FileProviderExtension)
final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    required init(domain: NSFileProviderDomain) {
        super.init()
    }

    func invalidate() {}

    func item(for identifier: NSFileProviderItemIdentifier,
              request: NSFileProviderRequest,
              completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        if let item = Catalog.item(for: identifier) {
            completionHandler(item, nil)
        } else {
            completionHandler(nil, noSuchItem)
        }
        return Progress()
    }

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier,
                       version requestedVersion: NSFileProviderItemVersion?,
                       request: NSFileProviderRequest,
                       completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        guard let data = Catalog.content(for: itemIdentifier),
              let item = Catalog.item(for: itemIdentifier) else {
            completionHandler(nil, nil, noSuchItem)
            return Progress()
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try data.write(to: url)
            completionHandler(url, item, nil)
        } catch {
            completionHandler(nil, nil, error)
        }
        return Progress()
    }

    // MARK: Read-only — reject all mutations.

    func createItem(basedOn itemTemplate: NSFileProviderItem,
                    fields: NSFileProviderItemFields,
                    contents url: URL?,
                    options: NSFileProviderCreateItemOptions,
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        completionHandler(nil, [], false, readOnly)
        return Progress()
    }

    func modifyItem(_ item: NSFileProviderItem,
                    baseVersion version: NSFileProviderItemVersion,
                    changedFields: NSFileProviderItemFields,
                    contents newContents: URL?,
                    options: NSFileProviderModifyItemOptions,
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        completionHandler(nil, [], false, readOnly)
        return Progress()
    }

    func deleteItem(identifier: NSFileProviderItemIdentifier,
                    baseVersion version: NSFileProviderItemVersion,
                    options: NSFileProviderDeleteItemOptions,
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (Error?) -> Void) -> Progress {
        completionHandler(readOnly)
        return Progress()
    }

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier,
                    request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        WikiFSEnumerator(container: containerItemIdentifier)
    }

    private var noSuchItem: NSError {
        NSError(domain: NSFileProviderErrorDomain, code: NSFileProviderError.noSuchItem.rawValue)
    }

    private var readOnly: NSError {
        NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError,
                userInfo: [NSLocalizedDescriptionKey: "WikiFS is read-only"])
    }
}
