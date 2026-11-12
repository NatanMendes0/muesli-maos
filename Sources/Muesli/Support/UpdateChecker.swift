import Foundation
import AppKit

struct UpdateReleaseInfo: Equatable {
    let currentVersion: String
    let latestVersion: String
    let releaseName: String
    let releaseNotes: String
    let htmlURL: String
    let zipURL: String
    let zipName: String
}

/// Checks GitHub Releases (`NatanMendes0/muesli-maos`) for new versions and downloads updates.
@MainActor
final class UpdateChecker: NSObject, ObservableObject {
    @Published var availableUpdate: UpdateReleaseInfo?
    @Published var bannerDismissed = false
    @Published var checking = false
    @Published var upToDateMessage: String?
    @Published var errorMessage: String?
    @Published var downloading = false
    @Published var downloadProgress: Double = 0
    @Published var downloadedFileURL: URL?

    private var downloadTask: URLSessionDownloadTask?
    private nonisolated let targetFilename = Atomic<String>(AppVersion.macZipName)

    func checkOnLaunch() {
        Task { await check(interactive: false) }
    }

    func check(interactive: Bool) async {
        guard !checking else { return }
        checking = true
        if interactive {
            upToDateMessage = nil
            errorMessage = nil
        }
        defer { checking = false }

        do {
            if let info = try await fetchLatestRelease() {
                if Self.isNewerVersion(info.latestVersion, than: AppVersion.current) {
                    availableUpdate = info
                    bannerDismissed = false
                } else {
                    availableUpdate = nil
                    if interactive {
                        upToDateMessage = "Você já está utilizando a versão mais recente (v\(AppVersion.current))."
                    }
                }
            } else if interactive {
                errorMessage = "Não foi possível obter informações da release."
            }
        } catch {
            if interactive {
                errorMessage = error.localizedDescription
            }
        }
    }

    func downloadUpdate() {
        guard let info = availableUpdate, !downloading, let url = URL(string: info.zipURL) else { return }
        downloading = true
        downloadProgress = 0
        errorMessage = nil
        downloadedFileURL = nil
        targetFilename.value = info.zipName.isEmpty ? AppVersion.macZipName : info.zipName

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        downloadTask = task
        task.resume()
    }

    func openReleasePage() {
        let str = availableUpdate?.htmlURL ?? "https://github.com/\(AppVersion.githubRepo)/releases"
        if let url = URL(string: str) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Helpers

    nonisolated static func isNewerVersion(_ candidate: String, than current: String) -> Bool {
        let parse: (String) -> [Int] = { s in
            s.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                .split(separator: ".")
                .map { Int($0.filter(\.isNumber)) ?? 0 }
        }
        var a = parse(candidate)
        var b = parse(current)
        let n = max(a.count, b.count)
        while a.count < n { a.append(0) }
        while b.count < n { b.append(0) }
        for i in 0..<n {
            if a[i] != b[i] { return a[i] > b[i] }
        }
        return false
    }

    private func fetchLatestRelease() async throws -> UpdateReleaseInfo? {
        let apiURL = URL(string: "https://api.github.com/repos/\(AppVersion.githubRepo)/releases/latest")!
        var req = URLRequest(url: apiURL)
        req.timeoutInterval = 10
        req.setValue("Muesli-macOS/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 200,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let tag = (json["tag_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !tag.isEmpty {
            let assets = json["assets"] as? [[String: Any]] ?? []
            var zipURL = ""
            var zipName = AppVersion.macZipName
            for a in assets {
                if let name = a["name"] as? String, name.hasSuffix(".zip"),
                   let dl = a["browser_download_url"] as? String {
                    zipURL = dl
                    zipName = name
                    break
                }
            }
            let htmlURL = (json["html_url"] as? String) ?? "https://github.com/\(AppVersion.githubRepo)/releases"
            return UpdateReleaseInfo(
                currentVersion: AppVersion.current,
                latestVersion: tag,
                releaseName: (json["name"] as? String) ?? tag,
                releaseNotes: (json["body"] as? String) ?? "Atualizações e correções de estabilidade.",
                htmlURL: htmlURL,
                zipURL: zipURL.isEmpty ? htmlURL : zipURL,
                zipName: zipName
            )
        }

        // Fallback via HTML redirect if GitHub API returns 403 rate limit
        let webURL = URL(string: "https://github.com/\(AppVersion.githubRepo)/releases/latest")!
        var wReq = URLRequest(url: webURL)
        wReq.timeoutInterval = 10
        wReq.setValue("Muesli-macOS/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
        let (_, wResp) = try await URLSession.shared.data(for: wReq)
        if let finalURL = wResp.url?.absoluteString, finalURL.contains("/releases/tag/") {
            let tag = finalURL.components(separatedBy: "/releases/tag/").last?.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) ?? ""
            if !tag.isEmpty {
                return UpdateReleaseInfo(
                    currentVersion: AppVersion.current,
                    latestVersion: tag,
                    releaseName: tag,
                    releaseNotes: "Nova versão disponível no GitHub Releases.",
                    htmlURL: finalURL,
                    zipURL: "https://github.com/\(AppVersion.githubRepo)/releases/download/\(tag)/\(AppVersion.macZipName)",
                    zipName: AppVersion.macZipName
                )
            }
        }
        return nil
    }
}

extension UpdateChecker: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in self.downloadProgress = p }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let dest = downloads.appendingPathComponent(targetFilename.value)
        let result: Result<URL, Error>
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: location, to: dest)
            result = .success(dest)
        } catch {
            result = .failure(error)
        }
        Task { @MainActor in
            self.downloading = false
            self.downloadProgress = 1.0
            self.downloadTask = nil
            switch result {
            case .success(let url):
                self.downloadedFileURL = url
                NSWorkspace.shared.activateFileViewerSelecting([url])
            case .failure(let err):
                self.errorMessage = err.localizedDescription
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, (error as NSError).code != NSURLErrorCancelled else { return }
        Task { @MainActor in
            self.downloading = false
            self.downloadProgress = 0
            self.errorMessage = error.localizedDescription
        }
    }
}
