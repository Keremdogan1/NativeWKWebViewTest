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

    // 2. Navigation Response & Security Header Inspection
    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let httpResponse = navigationResponse.response as? HTTPURLResponse {
            let statusCode = httpResponse.statusCode
            let mimeType = httpResponse.mimeType ?? "unknown"
            let xFrameOptions = httpResponse.value(forHTTPHeaderField: "X-Frame-Options") ?? "none"
            let csp = httpResponse.value(forHTTPHeaderField: "Content-Security-Policy") != nil ? "present" : "none"
            let setCookie = httpResponse.value(forHTTPHeaderField: "Set-Cookie") != nil ? "present" : "none"

            BrowserLogger.shared.log(.resp, "HTTP \(statusCode) [\(mimeType)] X-Frame: \(xFrameOptions) CSP: \(csp) Set-Cookie: \(setCookie)")
            BrowserLogger.shared.log(.resp, " ↳ URL: \(httpResponse.url?.absoluteString ?? "")")
        }
        decisionHandler(.allow)
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
