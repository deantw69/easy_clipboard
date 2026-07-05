//
//  ShareViewController.swift
//  Share Extension
//
//  自包含的原生分享擴充:不依賴 Flutter 也不依賴 receive_sharing_intent pod
//  (避免擴充編譯 plugin module 時找不到 Flutter/Flutter.h)。
//
//  資料契約與 receive_sharing_intent 1.8.1 完全一致:把分享內容寫進 App Group
//  的 UserDefaults("ShareKey" = JSON([SharedMediaFile]))後,以 URL scheme
//  「ShareMedia-<主App bundleId>:share」喚醒主 App;主 App(Runner,內含 Flutter)
//  端的外掛照常讀取。只接受圖片 / 文字 / 網址。
//

import UIKit
import Social
import MobileCoreServices

private let kSchemePrefix = "ShareMedia"
private let kUserDefaultsKey = "ShareKey"
private let kUserDefaultsMessageKey = "ShareMessageKey"
private let kAppGroupIdKey = "AppGroupId"

// 與外掛端 SharedMediaType 對應(僅用到 image/text/url)。
private enum ShareType: String, Codable {
    case image, video, text, file, url

    var uti: String {
        switch self {
        case .image: return "public.image"
        case .video: return "public.movie"
        case .text: return "public.text"
        case .file: return "public.file-url"
        case .url: return "public.url"
        }
    }
}

// 必須與 receive_sharing_intent 的 SharedMediaFile(Codable)欄位完全一致,
// 主 App 端才能用 JSONDecoder 正確解析。
private final class SharedMediaFile: Codable {
    let path: String
    let mimeType: String?
    let thumbnail: String?
    let duration: Double?
    let message: String?
    let type: ShareType

    init(path: String,
         mimeType: String? = nil,
         thumbnail: String? = nil,
         duration: Double? = nil,
         message: String? = nil,
         type: ShareType) {
        self.path = path
        self.mimeType = mimeType
        self.thumbnail = thumbnail
        self.duration = duration
        self.message = message
        self.type = type
    }
}

class ShareViewController: UIViewController {
    private var hostAppBundleIdentifier = ""
    private var appGroupId = ""
    private var sharedMedia: [SharedMediaFile] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        loadIds()
        // 不顯示任何 UI(不繼承 SLComposeServiceViewController 的發佈輸入框),
        // 直接處理分享內容後跳轉主 App,避免閃出系統 compose 畫面。
        view.backgroundColor = .clear
        processAndRedirect()
    }

    private func processAndRedirect() {
        guard let content = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = content.attachments else {
            dismissWithError()
            return
        }
        let total = attachments.count
        for (index, attachment) in attachments.enumerated() {
            // 順序:先網址、再圖片、最後文字(網頁連結同時符合 url 與 text,優先當 url)。
            for type in [ShareType.url, .image, .text] {
                if attachment.hasItemConformingToTypeIdentifier(type.uti) {
                    attachment.loadItem(forTypeIdentifier: type.uti, options: nil) { [weak self] data, error in
                        guard let self = self, error == nil else {
                            self?.dismissWithError()
                            return
                        }
                        switch type {
                        case .text:
                            if let text = data as? String {
                                self.appendLiteral(text, type: .text, index: index, total: total)
                            }
                        case .url:
                            if let url = data as? URL {
                                self.appendLiteral(url.absoluteString, type: .url, index: index, total: total)
                            } else if let text = data as? String {
                                self.appendLiteral(text, type: .url, index: index, total: total)
                            }
                        default: // image
                            if let url = data as? URL {
                                self.appendImage(fromFile: url, index: index, total: total)
                            } else if let image = data as? UIImage {
                                self.appendImage(fromUIImage: image, index: index, total: total)
                            } else if let imageData = data as? Data, let image = UIImage(data: imageData) {
                                // 截圖編輯器分享時直接給原始 Data(非檔案 URL/UIImage),需自行轉圖
                                self.appendImage(fromUIImage: image, index: index, total: total)
                            } else if index == total - 1 {
                                self.saveAndRedirect()
                            }
                        }
                    }
                    break
                }
            }
        }
    }

    private func loadIds() {
        let extId = Bundle.main.bundleIdentifier ?? ""
        if let dot = extId.lastIndex(of: ".") {
            hostAppBundleIdentifier = String(extId[..<dot])
        } else {
            hostAppBundleIdentifier = extId
        }
        let custom = Bundle.main.object(forInfoDictionaryKey: kAppGroupIdKey) as? String
        appGroupId = custom ?? "group.\(hostAppBundleIdentifier)"
    }

    private func appendLiteral(_ value: String, type: ShareType, index: Int, total: Int) {
        sharedMedia.append(SharedMediaFile(
            path: value,
            mimeType: type == .text ? "text/plain" : nil,
            type: type))
        if index == total - 1 { saveAndRedirect() }
    }

    private func appendImage(fromFile url: URL, index: Int, total: Int) {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else { return }
        let name = url.lastPathComponent.isEmpty ? "\(UUID().uuidString).png" : url.lastPathComponent
        let dst = container.appendingPathComponent(name)
        if copyFile(at: url, to: dst), let decoded = dst.absoluteString.removingPercentEncoding {
            sharedMedia.append(SharedMediaFile(path: decoded, mimeType: mimeForImage(url), type: .image))
        }
        if index == total - 1 { saveAndRedirect() }
    }

    private func appendImage(fromUIImage image: UIImage, index: Int, total: Int) {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else { return }
        let dst = container.appendingPathComponent("TempImage.png")
        if writeTempFile(image, to: dst), let decoded = dst.absoluteString.removingPercentEncoding {
            sharedMedia.append(SharedMediaFile(path: decoded, mimeType: "image/png", type: .image))
        }
        if index == total - 1 { saveAndRedirect() }
    }

    private func saveAndRedirect(message: String? = nil) {
        let userDefaults = UserDefaults(suiteName: appGroupId)
        userDefaults?.set(try? JSONEncoder().encode(sharedMedia), forKey: kUserDefaultsKey)
        userDefaults?.set(message, forKey: kUserDefaultsMessageKey)
        userDefaults?.synchronize()
        redirectToHostApp()
    }

    private func redirectToHostApp() {
        loadIds()
        guard let url = URL(string: "\(kSchemePrefix)-\(hostAppBundleIdentifier):share") else {
            completeRequest()
            return
        }
        if #available(iOS 18.0, *) {
            // 從 responder chain 找到 UIApplication,檢查 open 成敗;失敗才有回饋。
            var responder = self as UIResponder?
            var application: UIApplication?
            while responder != nil {
                if let app = responder as? UIApplication {
                    application = app
                    break
                }
                responder = responder?.next
            }
            guard let application = application else {
                showOpenFailedAlert()
                return
            }
            application.open(url, options: [:]) { [weak self] success in
                if success {
                    self?.completeRequest()
                } else {
                    self?.showOpenFailedAlert()
                }
            }
        } else {
            // iOS 18 以下走 selector,無成敗回呼;維持原行為直接結束。
            let selector = sel_registerName("openURL:")
            var responder = self as UIResponder?
            while responder != nil {
                if responder?.responds(to: selector) == true {
                    _ = responder?.perform(selector, with: url)
                }
                responder = responder?.next
            }
            completeRequest()
        }
    }

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    /// 喚醒主 App 失敗時的提示,關閉後才結束分享流程。
    private func showOpenFailedAlert() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let alert = UIAlertController(
                title: "無法開啟 SyncNest",
                message: "請確認 SyncNest 已安裝,或稍後再試。",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "關閉", style: .default) { [weak self] _ in
                self?.completeRequest()
            })
            self.present(alert, animated: true)
        }
    }

    private func dismissWithError() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func writeTempFile(_ image: UIImage, to dst: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: dst.path) {
                try FileManager.default.removeItem(at: dst)
            }
            try image.pngData()?.write(to: dst)
            return true
        } catch {
            return false
        }
    }

    private func copyFile(at src: URL, to dst: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: dst.path) {
                try FileManager.default.removeItem(at: dst)
            }
            try FileManager.default.copyItem(at: src, to: dst)
            return true
        } catch {
            return false
        }
    }

    private func mimeForImage(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "heic": return "image/heic"
        case "heif": return "image/heif"
        case "webp": return "image/webp"
        default: return "image/jpeg"
        }
    }
}
