import Foundation
import WebKit

/// Dedicated WKNavigationDelegate implementing deep network and security inspection
public final class BrowserNavigationDelegate: NSObject, WKNavigationDelegate {
    private weak var browser: NativeBrowser?

    public init(browser: NativeBrowser) {
        self.browser = browser
        super.init()
    }

    // 1. Navigation Action Policy Decision
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let browser = browser else {
            decisionHandler(.allow)
            return
        }

        let url = navigationAction.request.url
        let urlStr = url?.absoluteString ?? "unknown"
        let scheme = url?.scheme?.lowercased() ?? "none"

        let navTypeStr: String
        switch navigationAction.navigationType {
        case .linkActivated: navTypeStr = "linkActivated"
        case .formSubmitted: navTypeStr = "formSubmitted"
        case .backForward: navTypeStr = "backForward"
        case .reload: navTypeStr = "reload"
        case .formResubmitted: navTypeStr = "formResubmitted"
        case .other: navTypeStr = "other"
        @unknown default: navTypeStr = "unknown"
        }

        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? false
        let isTargetNil = (navigationAction.targetFrame == nil)
        let method = navigationAction.request.httpMethod ?? "GET"

        BrowserLogger.shared.log(.nav, "ACTION: type=\(navTypeStr) method=\(method) scheme=\(scheme) mainFrame=\(isMainFrame) targetNil=\(isTargetNil)")
        BrowserLogger.shared.log(.nav, " ↳ URL: \(urlStr)")

        // Local Test Fixtures Interceptor (local-suite.poc)
        if url?.host == "local-suite.poc" && isMainFrame && !isTargetNil {
            let path = (url?.path.isEmpty == false && url?.path != "/") ? url!.path : "index.html"
            let html = WebFixturesProvider.shared.html(for: path)
            BrowserLogger.shared.log(.test, "Serving offline test fixture for: \(path) (Method: \(method))")
            webView.loadHTMLString(html, baseURL: WebFixturesProvider.baseSuiteURL)
            decisionHandler(.cancel)
            return
        }

        // Custom App Schemes Check
        if scheme != "http" && scheme != "https" && scheme != "about" && scheme != "data" {
            BrowserLogger.shared.log(.scheme, "Non-HTTP Scheme intercepted: \(scheme) (URL: \(urlStr))")

            let knownAppSchemes = ["vnd.youtube", "googlesearch", "googlechrome", "reddit", "twitter", "fb"]
            if browser.state.customSchemePolicy == .blockExternal && knownAppSchemes.contains(scheme) {
                BrowserLogger.shared.log(.scheme, "Policy BLOCK: External app scheme denied: \(scheme)")
                browser.emitEvent(.schemeRequested(scheme: scheme, url: url, allowed: false))
                decisionHandler(.cancel)
                return
            } else {
                browser.emitEvent(.schemeRequested(scheme: scheme, url: url, allowed: true))
            }
        }

        browser.emitEvent(.navigationStarted(url: url))
        decisionHandler(.allow)
    }

    // 2. Navigation Response, Security Header Inspection & Download Decision
    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let response = navigationResponse.response
        let mimeType = response.mimeType ?? "unknown"
        let urlStr = response.url?.absoluteString ?? ""
        var isAttachment = false

        if let httpResponse = response as? HTTPURLResponse {
            let statusCode = httpResponse.statusCode
            let xFrameOptions = httpResponse.value(forHTTPHeaderField: "X-Frame-Options") ?? "none"
            let csp = httpResponse.value(forHTTPHeaderField: "Content-Security-Policy") != nil ? "present" : "none"
            let setCookie = httpResponse.value(forHTTPHeaderField: "Set-Cookie") != nil ? "present" : "none"
            let contentDisposition = httpResponse.value(forHTTPHeaderField: "Content-Disposition") ?? ""

            if contentDisposition.lowercased().contains("attachment") {
                isAttachment = true
            }

            BrowserLogger.shared.log(.resp, "HTTP \(statusCode) [\(mimeType)] X-Frame: \(xFrameOptions) CSP: \(csp) Set-Cookie: \(setCookie)")
            if !contentDisposition.isEmpty {
                BrowserLogger.shared.log(.resp, " ↳ Content-Disposition: \(contentDisposition)")
            }
            BrowserLogger.shared.log(.resp, " ↳ URL: \(urlStr)")
        }

        // Check if response qualifies for WKDownload
        let cannotShow = !navigationResponse.canShowMIMEType
        let ext = response.url?.pathExtension.lowercased() ?? ""
        let binaryExtensions = ["zip", "tar", "gz", "tgz", "7z", "rar", "dmg", "pkg", "exe", "iso", "bin", "apk", "ipa"]
        let isBinaryExtension = binaryExtensions.contains(ext)

        if cannotShow || isAttachment || isBinaryExtension {
            BrowserLogger.shared.log(.nav, "[DOWNLOAD] Triggering WKDownload (canShowMIME=\(!cannotShow), attachment=\(isAttachment), ext=\(ext))")
            decisionHandler(.download)
            return
        }

        decisionHandler(.allow)
    }

    // Modern WKDownload lifecycle hooks (iOS 14.5+)
    public func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        BrowserLogger.shared.log(.nav, "[DOWNLOAD] navigationResponse didBecome WKDownload.")
        browser?.downloadManager.registerDownload(download, from: navigationResponse.response)
    }

    public func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        BrowserLogger.shared.log(.nav, "[DOWNLOAD] navigationAction didBecome WKDownload.")
        browser?.downloadManager.registerDownload(download, from: nil)
    }

    // 3. Provisional & Finished Events
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        BrowserLogger.shared.log(.nav, "EVENT: didStartProvisionalNavigation")
        browser?.updateLoadingState(isLoading: true)
        browser?.emitEvent(.loadingChanged(true))
    }

    public func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        let redirectUrl = webView.url
        BrowserLogger.shared.log(.nav, "REDIRECT: Server redirected to: \(redirectUrl?.absoluteString ?? "")")
        browser?.emitEvent(.serverRedirect(url: redirectUrl))
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let finalUrl = webView.url?.absoluteString ?? ""
        BrowserLogger.shared.log(.nav, "EVENT: didFinish -> \(finalUrl)")
        browser?.updateStateFromWebView()
        browser?.emitEvent(.navigationFinished(url: webView.url, title: webView.title))
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        BrowserLogger.shared.log(.error, "didFail: \(error.localizedDescription)")
        browser?.updateError(error.localizedDescription)
        browser?.emitEvent(.navigationFailed(error: error))
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        BrowserLogger.shared.log(.error, "didFailProvisional: \(error.localizedDescription)")
        browser?.updateError(error.localizedDescription)
        browser?.emitEvent(.navigationFailed(error: error))
    }

    // 4. SSL Authentication Challenges
    public func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let authMethod = challenge.protectionSpace.authenticationMethod
        let host = challenge.protectionSpace.host
        BrowserLogger.shared.log(.nav, "SSL/Auth Challenge: host=\(host) method=\(authMethod)")
        completionHandler(.performDefaultHandling, nil)
    }

    // 5. Crash Resiliency (WebContent Process Termination)
    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        browser?.handleProcessTermination()
    }
}
