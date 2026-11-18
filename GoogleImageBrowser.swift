import SwiftUI
import AppKit
import WebKit

// No Google API key or result scraping. User interacts with the actual search page.
// The isolated script takes only the image under an explicit click.
@MainActor struct GoogleImageBrowser: NSViewRepresentable {
    let url: URL?
    let picking: Bool
    var onImage: (String) -> Void
    var onNotice: (String) -> Void
    static let world = WKContentWorld.world(name: "IconFixerSelection")
    // Coordinates are captured by the native window when pick mode is active, so
    // Google overlays and event handlers cannot consume the selection click.
    static let script = """
    (() => {
      if (window.__sifInstalled) return;
      window.__sifInstalled = true;
      window.__sifPick = false;
      function send(value) {
        window.webkit.messageHandlers.iconSelection.postMessage(typeof value === 'string' && value.length <= 11000000 ? value : '');
      }
      window.__sifPickAt = async function(x, y) {
        const under = document.elementsFromPoint(x, y);
        const candidates = [];
        function add(img) {
          if (!(img instanceof HTMLImageElement) || candidates.includes(img)) return;
          const r = img.getBoundingClientRect();
          if (r.width < 24 || r.height < 24 || x < r.left || x > r.right || y < r.top || y > r.bottom) return;
          if (!img.currentSrc && !img.src) return;
          candidates.push(img);
        }
        for (const el of under) { add(el); for (const child of el.querySelectorAll('img')) add(child); }
        if (!candidates.length) for (const img of document.images) add(img);
        if (!candidates.length) { send(''); return; }
        // Prefer the image in the actual hit stack; otherwise choose a sizeable preview.
        const direct = under.find(el => candidates.includes(el));
        const img = direct || candidates.sort((a,b) => b.getBoundingClientRect().width*b.getBoundingClientRect().height - a.getBoundingClientRect().width*a.getBoundingClientRect().height)[0];
        let src = img.currentSrc || img.src || '';
        try {
          if (src.startsWith('blob:')) {
            const blob = await (await fetch(src)).blob();
            if (blob.size > 8000000 || !blob.type.startsWith('image/')) throw Error();
            src = await new Promise((resolve, reject) => { const reader = new FileReader(); reader.onload = () => resolve(reader.result); reader.onerror = reject; reader.readAsDataURL(blob); });
          }
          send(src);
        } catch (_) { send(''); }
      };
      document.addEventListener('click', (event) => {
        if (!event.isTrusted || (!window.__sifPick && !event.altKey)) return;
        event.preventDefault(); event.stopImmediatePropagation();
        window.__sifPick = false;
        window.__sifPickAt(event.clientX, event.clientY);
      }, true);
    })();
    """
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, contentWorld: Self.world, name: "iconSelection")
        let script = WKUserScript(source: Self.script, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: Self.world)
        config.userContentController.addUserScript(script)
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        context.coordinator.view = view
        context.coordinator.installMonitor()
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        let c = context.coordinator
        c.parent = self
        if let url, c.requested != url {
            c.requested = url; view.load(URLRequest(url: url))
        }
        if c.previousPicking != picking {
            c.previousPicking = picking; c.setPicking()
        }
    }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.removeMonitor()
        view.stopLoading()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "iconSelection", contentWorld: Self.world)
        view.navigationDelegate = nil
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: GoogleImageBrowser
        var requested: URL?
        var previousPicking = false
        weak var view: WKWebView?
        private var monitor: Any?
        private var selecting = false
        func installMonitor() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, let web = self.view, (self.parent.picking || event.modifierFlags.contains(.option)), event.window === web.window, let window = web.window else { return event }
                let point = web.convert(event.locationInWindow, from: nil)
                guard web.bounds.contains(point), window.isKeyWindow, !self.selecting, let url = web.url, googlePageURL(url) else { return event }
                let x = Double(point.x - web.bounds.minX)
                let y = Double(web.isFlipped ? point.y - web.bounds.minY : web.bounds.maxY - point.y)
                let w = Double(web.bounds.width); let h = Double(web.bounds.height)
                guard w > 0, h > 0 else { return event }
                self.selecting = true
                let code = "(() => { if (typeof window.__sifPickAt !== 'function') return false; window.__sifPick = false; window.__sifPickAt(\(x) * innerWidth / \(w), \(y) * innerHeight / \(h)); return true; })()"
                web.evaluateJavaScript(code, in: nil, in: GoogleImageBrowser.world) { [weak self] result in
                    guard let self else { return }
                    self.selecting = false
                    switch result {
                    case .success(let value):
                        if (value as? Bool) != true { self.parent.onImage("") }
                    case .failure: self.parent.onImage("")
                    }
                }
                return nil
            }
        }
        func removeMonitor() { if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil } }
        init(parent: GoogleImageBrowser) { self.parent = parent }
        func setPicking() {
            let code = parent.picking ? "window.__sifPick = true;" : "window.__sifPick = false;"
            view?.evaluateJavaScript(code, in: nil, in: GoogleImageBrowser.world, completionHandler: nil)
        }
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { setPicking() }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { setPicking() }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.onNotice("Google Grafika: \(error.localizedDescription). Możesz wkleić obraz lub otworzyć przeglądarkę.")
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if navigationAction.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
            // Keep the top page on Google; arbitrary external sites cannot access the selection bridge.
            guard googlePageURL(url) || url.absoluteString == "about:blank" else {
                decisionHandler(.cancel); parent.onNotice("Wybierz grafikę w wynikach Google lub użyj zewnętrznej przeglądarki."); return
            }
            if navigationAction.targetFrame == nil { decisionHandler(.cancel); webView.load(navigationAction.request); return }
            decisionHandler(.allow)
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "iconSelection", message.frameInfo.isMainFrame, let url = view?.url, googlePageURL(url), let origin = URL(string: "https://" + message.frameInfo.securityOrigin.host), googlePageURL(origin), let value = message.body as? String, value.count <= 11_000_000 else { return }
            parent.onImage(value)
        }
    }
}

private final class GoogleDownloadPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Avoid silently following a selected image to an unrelated server.
        let oldHost = response.url?.host?.lowercased()
        let next = request.url
        let newHost = next?.host?.lowercased()
        let allowed = next.map(publicImageURL) == true && (newHost == oldHost || (isGoogleImageHost(oldHost) && isGoogleImageHost(newHost)))
        completionHandler(allowed ? request : nil)
    }
}
func selectedGoogleImage(_ value: String) async throws -> (Data, String) {
    if value.hasPrefix("data:image/"), let comma = value.firstIndex(of: ",") {
        guard value[..<comma].lowercased().hasSuffix(";base64"), let data = Data(base64Encoded: String(value[value.index(after: comma)...])), data.count <= 8_000_000 else { throw fail("Nieobsługiwany lub zbyt duży obraz. Spróbuj wkleić grafikę.") }
        return (data, "Google Grafika — obraz z wyników")
    }
    guard let url = URL(string: value), publicImageURL(url) else { throw fail("Nie można pobrać tego obrazu. Wybierz inny albo użyj Kopiuj/Wklej obraz.") }
    let cfg = URLSessionConfiguration.ephemeral
    cfg.httpAdditionalHeaders = ["Accept": "image/*,*/*;q=0.8", "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15"]
    cfg.httpShouldSetCookies = false; cfg.urlCredentialStorage = nil; cfg.timeoutIntervalForRequest = 12; cfg.timeoutIntervalForResource = 25
    let session = URLSession(configuration: cfg, delegate: GoogleDownloadPolicy(), delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    let (bytes, response) = try await session.bytes(from: url)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let final = http.url, publicImageURL(final), http.expectedContentLength <= 8_000_000 else { throw fail("Serwer nie udostępnił obrazu. Spróbuj skopiować obraz z podglądu.") }
    var data = Data()
    for try await byte in bytes { guard data.count < 8_000_000 else { throw fail("Obraz przekracza 8 MB.") }; data.append(byte) }
    return (data, final.absoluteString)
}
