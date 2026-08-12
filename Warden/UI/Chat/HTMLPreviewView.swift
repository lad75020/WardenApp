
import SwiftUI
@preconcurrency
import WebKit
import os

enum HTMLPreviewSecurity {
    static let contentSecurityPolicy = "default-src 'none'; img-src data: blob:; media-src data: blob:; style-src 'unsafe-inline'; font-src data:; script-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"

    static func securedHTMLDocument(_ html: String) -> String {
        let csp = "<meta http-equiv=\"Content-Security-Policy\" content=\"\(contentSecurityPolicy)\">"
        // Wrapping rather than trusting an author-provided CSP ensures our policy
        // is always present. Multiple CSPs are intersected by WebKit.
        return """
        <!DOCTYPE html>
        <html>
        <head>
            \(csp)
        </head>
        <body>
            \(html)
        </body>
        </html>
        """
    }

    static func allowsNavigation(url: URL?, navigationType: WKNavigationType) -> Bool {
        // loadHTMLString's initial document has no request URL. Every URL-backed
        // navigation, including about:, file:, data:, and external links, is denied.
        url == nil && navigationType == .other
    }
}

struct HTMLPreviewView: View {
    let htmlContent: String
    let zoomLevel: Double
    let refreshTrigger: Int
    let userAgent: String?
    @State private var isLoading = true
    @Environment(\.colorScheme) var colorScheme
    
    // Default initializer for backward compatibility
    init(htmlContent: String) {
        self.htmlContent = htmlContent
        self.zoomLevel = 1.0
        self.refreshTrigger = 0
        self.userAgent = nil
    }
    
    // Enhanced initializer with zoom and refresh
    init(htmlContent: String, zoomLevel: Double, refreshTrigger: Int) {
        self.htmlContent = htmlContent
        self.zoomLevel = zoomLevel
        self.refreshTrigger = refreshTrigger
        self.userAgent = nil
    }
    
    // Full initializer with user agent support
    init(htmlContent: String, zoomLevel: Double, refreshTrigger: Int, userAgent: String?) {
        self.htmlContent = htmlContent
        self.zoomLevel = zoomLevel
        self.refreshTrigger = refreshTrigger
        self.userAgent = userAgent
    }
    
    var body: some View {
        ZStack {
            WebViewWrapper(
                htmlContent: htmlContent, 
                zoomLevel: zoomLevel,
                refreshTrigger: refreshTrigger,
                userAgent: userAgent,
                isLoading: $isLoading
            )
            
            if isLoading {
                modernLoadingView
            }
        }
    }
    
    private var modernLoadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                .scaleEffect(1.2)
            
            Text("Loading Preview...")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            colorScheme == .dark ? 
                Color(red: 0.1, green: 0.1, blue: 0.12).opacity(0.95) : 
                Color.white.opacity(0.95)
        )
        .transition(.opacity)
    }
}

struct WebViewWrapper: NSViewRepresentable {
    let htmlContent: String
    let zoomLevel: Double
    let refreshTrigger: Int
    let userAgent: String?
    @Binding var isLoading: Bool
    
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        
        // Set custom user agent if provided
        if let userAgent = userAgent {
            configuration.applicationNameForUserAgent = userAgent
        }
        
        // Disable context menu for cleaner experience
        configuration.preferences.setValue(false, forKey: "developerExtrasEnabled")
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground") // Transparent background
        
        // Set custom user agent directly on webView if provided
        if let userAgent = userAgent {
            webView.customUserAgent = userAgent
        }
        
        // Apply modern styling
        webView.wantsLayer = true
        webView.layer?.cornerRadius = 8
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        // Update user agent if it changed
        if let userAgent = userAgent, webView.customUserAgent != userAgent {
            webView.customUserAgent = userAgent
        }
        
        // Check if content changed or refresh was triggered
        let shouldReload = context.coordinator.lastContent != htmlContent || 
                          context.coordinator.lastRefreshTrigger != refreshTrigger ||
                          context.coordinator.lastUserAgent != userAgent
        
        if shouldReload {
            context.coordinator.lastContent = htmlContent
            context.coordinator.lastRefreshTrigger = refreshTrigger
            context.coordinator.lastUserAgent = userAgent
            isLoading = true
            webView.loadHTMLString(HTMLPreviewSecurity.securedHTMLDocument(htmlContent), baseURL: nil)
        }
        
        // Apply zoom level
        if abs(webView.magnification - zoomLevel) > 0.01 {
            webView.setMagnification(zoomLevel, centeredAt: CGPoint(x: webView.bounds.midX, y: webView.bounds.midY))
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewWrapper
        var lastContent: String = ""
        var lastRefreshTrigger: Int = 0
        var lastUserAgent: String? = nil
        
        init(parent: WebViewWrapper) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.parent.isLoading = false
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            WardenLog.app.error("HTML preview navigation failed")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            WardenLog.app.error("HTML preview provisional navigation failed")
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(
                HTMLPreviewSecurity.allowsNavigation(
                    url: navigationAction.request.url,
                    navigationType: navigationAction.navigationType
                ) ? .allow : .cancel
            )
        }
    }
}
