import AppKit
import Foundation

final class AppUpdateService {
    static let shared = AppUpdateService()

    struct ReleaseInfo: Identifiable {
        let id: String
        let tagName: String
        let version: String
        let htmlURL: URL
        let assetName: String
        let assetDownloadURL: URL
    }

    enum CheckResult {
        case upToDate(current: String, latest: String)
        case updateAvailable(ReleaseInfo)
    }

    private let owner = "reztrop"
    private let repo = "openclaw-hq"

    private init() {}

    func checkForUpdates(currentVersion: String) async throws -> CheckResult {
        let release = try await fetchLatestRelease()
        if Self.compareVersions(currentVersion, release.version) < 0 {
            return .updateAvailable(release)
        }
        return .upToDate(current: currentVersion, latest: release.version)
    }

    func installUpdate(_ release: ReleaseInfo) async throws {
        guard FileManager.default.isWritableFile(atPath: "/Applications") else {
            throw UpdateError.installPermissionDenied
        }

        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("openclaw-hq-update-\(UUID().uuidString)")
        let downloadPath = tempRoot.appendingPathComponent(release.assetName)
        let mountPoint = tempRoot.appendingPathComponent("mount")
        let scriptPath = tempRoot.appendingPathComponent("install_and_relaunch.sh")

        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let (tmpURL, _) = try await URLSession.shared.download(from: release.assetDownloadURL)
        try FileManager.default.moveItem(at: tmpURL, to: downloadPath)

        if downloadPath.pathExtension.lowercased() == "dmg" {
            try runProcess(
                launchPath: "/usr/bin/hdiutil",
                arguments: ["attach", downloadPath.path, "-nobrowse", "-mountpoint", mountPoint.path]
            )
        } else {
            throw UpdateError.unsupportedAsset
        }

        let mountedAppPath = mountPoint.appendingPathComponent("OpenClaw HQ.app").path
        guard FileManager.default.fileExists(atPath: mountedAppPath) else {
            throw UpdateError.appNotFoundInInstaller
        }

        let script = """
        #!/bin/bash
        set -e
        sleep 1
        APP_DST="/Applications/OpenClaw HQ.app"
        APP_SRC="\(shellEscape(mountedAppPath))"
        MOUNT_POINT="\(shellEscape(mountPoint.path))"
        TEMP_ROOT="\(shellEscape(tempRoot.path))"
        rm -rf "$APP_DST"
        ditto "$APP_SRC" "$APP_DST"
        hdiutil detach "$MOUNT_POINT" -quiet || true
        open "$APP_DST"
        rm -rf "$TEMP_ROOT"
        """

        try script.write(to: scriptPath, atomically: true, encoding: .utf8)
        try runProcess(launchPath: "/bin/chmod", arguments: ["+x", scriptPath.path])

        try runProcess(
            launchPath: "/bin/bash",
            arguments: ["-lc", "nohup '\(scriptPath.path)' >/tmp/openclaw-hq-updater.log 2>&1 &"]
        )

        await MainActor.run {
            NSApp.terminate(nil)
        }
    }

    private func fetchLatestRelease() async throws -> ReleaseInfo {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            throw UpdateError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("OpenClawHQ-Updater", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.releaseLookupFailed
        }

        let decoded = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let asset = decoded.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) ??
            decoded.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }) else {
            throw UpdateError.noSupportedAsset
        }

        let normalizedVersion = decoded.tagName.replacingOccurrences(of: "v", with: "", options: [.caseInsensitive, .anchored])
        return ReleaseInfo(
            id: decoded.id.description,
            tagName: decoded.tagName,
            version: normalizedVersion,
            htmlURL: decoded.htmlURL,
            assetName: asset.name,
            assetDownloadURL: asset.browserDownloadURL
        )
    }

    private func runProcess(launchPath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw UpdateError.processFailed(message?.isEmpty == false ? message! : "Command failed: \(launchPath)")
        }
    }

    private func shellEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\\''")
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> Int {
        let left = lhs.split(separator: ".").compactMap { Int($0) }
        let right = rhs.split(separator: ".").compactMap { Int($0) }
        let maxParts = max(left.count, right.count)

        for idx in 0..<maxParts {
            let a = idx < left.count ? left[idx] : 0
            let b = idx < right.count ? right[idx] : 0
            if a < b { return -1 }
            if a > b { return 1 }
        }
        return 0
    }
}

private extension AppUpdateService {
    struct GitHubRelease: Decodable {
        let id: Int
        let tagName: String
        let htmlURL: URL
        let assets: [GitHubAsset]

        enum CodingKeys: String, CodingKey {
            case id
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }

    struct GitHubAsset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
}

enum UpdateError: LocalizedError {
    case invalidURL
    case releaseLookupFailed
    case noSupportedAsset
    case unsupportedAsset
    case appNotFoundInInstaller
    case installPermissionDenied
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The update URL is invalid."
        case .releaseLookupFailed:
            return "Could not fetch the latest release from GitHub."
        case .noSupportedAsset:
            return "No DMG or ZIP installer was found in the latest GitHub release."
        case .unsupportedAsset:
            return "The latest release asset is not a supported installer."
        case .appNotFoundInInstaller:
            return "OpenClaw HQ.app was not found in the installer image."
        case .installPermissionDenied:
            return "OpenClaw HQ does not have permission to write to /Applications."
        case .processFailed(let message):
            return "Update command failed: \(message)"
        }
    }
}
