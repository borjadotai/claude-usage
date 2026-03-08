import WebKit

@MainActor
final class SessionMonitor: NSObject, WKNavigationDelegate {
    var onLoginSuccess: ((String) -> Void)?

    // Allow all navigations (Google OAuth, SSO, captcha, etc.)
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        let host = url.host ?? ""
        let path = url.path

        // Check for cookies when we've landed on claude.ai (any path after login)
        guard host.hasSuffix("claude.ai") && !path.contains("/login") && !path.contains("/oauth") else { return }

        // Small delay to ensure cookies are persisted after the final redirect
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self, weak webView] in
            guard let self, let webView else { return }
            self.extractSessionKey(from: webView)
        }
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        // Also check after redirects — login completion often involves multiple redirects
        guard let url = webView.url, let host = url.host else { return }
        guard host.hasSuffix("claude.ai") && !url.path.contains("/login") else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self, weak webView] in
            guard let self, let webView else { return }
            self.extractSessionKey(from: webView)
        }
    }

    private func extractSessionKey(from webView: WKWebView) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            let sessionCookie = cookies.first { cookie in
                (cookie.name == "sessionKey" || cookie.name == "__Secure-next-auth.session-token")
                    && (cookie.value.hasPrefix("sk-ant-sid") || cookie.value.count > 40)
            }
            // Also check for lastActiveOrg cookie as a signal that login succeeded
            let orgCookie = cookies.first { $0.name == "lastActiveOrg" }
            if let cookie = sessionCookie {
                self.onLoginSuccess?(cookie.value)
            } else if orgCookie != nil {
                // Login succeeded but cookie name might have changed — try all cookies from claude.ai
                let claudeCookies = cookies.filter { $0.domain.contains("claude.ai") }
                for c in claudeCookies {
                    print("Claude cookie: \(c.name) = \(c.value.prefix(20))...")
                }
            }
        }
    }
}
