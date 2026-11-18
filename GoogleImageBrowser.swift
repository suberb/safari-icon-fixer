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
    static let script = """
    (() => {
      if (window.__sifInstalled) return;
      window.__sifInstalled = true;
      window.__sifPick = false;
      document.addEventListener('click', async (event) => {
        if (!event.isTrusted || (!window.__sifPick && !event.altKey)) return;
        const img = event.composedPath().find(x => x instanceof HTMLImageElement) || document.elementsFromPoint(event.clientX, event.clientY).find(x => x instanceof HTMLImageElement);
        if (!img) return;
        event.preventDefault(); event.stopImmediatePropagation();
        window.__sifPick = false;
        let src = img.currentSrc || img.src || '';
        try {
          if (src.startsWith('blob:')) {
            const blob = await (await fetch(src)).blob();
            if (blob.size > 8000000 || !blob.type.startsWith('image/')) throw Error();
            src = await new Promise((resolve, reject) => { const reader = new FileReader(); reader.onload = () => resolve(reader.result); reader.onerror = reject; reader.readAsDataURL(blob); });
          }
          if (typeof src === 'string' && src.length <= 11000000) window.webkit.messageHandlers.iconSelection.postMessage(src);
        } catch (_) { window.webkit.messageHandlers.iconSelection.postMessage(''); }
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
        view.stopLoading()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "iconSelection", contentWorld: Self.world)
        view.navigationDelegate = nil
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: GoogleImageBrowser
        var requested: URL?
        var previousPicking = false
        weak var view: WKWebView?
        init(parent: GoogleImageBrowser) { self.parent = parent }
        func setPicking() {
            let code = parent.picking ? "window.__sifPick = true;" : "window.__sifPick = false;"
            view?.evaluateJavaScript(code, in: nil, in: GoogleImageBrowser.world, completionHandler: nil)
        }
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
            guard message.name == "iconSelection", message.frameInfo.isMainFrame, let url = message.frameInfo.request.url, googlePageURL(url), let value = message.body as? String, value.count <= 11_000_000 else { return }
            parent.onImage(value)
        }
    }
}

private final class GoogleDownloadPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Avoid silently following a selected image to an unrelated server.
        let oldHost = response.url?.host?.lowercased()
        let next = request.url
        completionHandler(next.map(publicImageURL) == true && next?.host?.lowercased() == oldHost ? request : nil)
    }
}
func selectedGoogleImage(_ value: String) async throws -> (Data, String) {
    if value.hasPrefix("data:image/"), let comma = value.firstIndex(of: ",") {
        guard value[..<comma].lowercased().hasSuffix(";base64"), let data = Data(base64Encoded: String(value[value.index(after: comma)...])), data.count <= 8_000_000 else { throw fail("Nieobsługiwany lub zbyt duży obraz. Spróbuj wkleić grafikę.") }
        return (data, "Google Grafika — obraz z wyników")
    }
    guard let url = URL(string: value), publicImageURL(url) else { throw fail("Nie można pobrać tego obrazu. Wybierz inny albo użyj Kopiuj/Wklej obraz.") }
    let cfg = URLSessionConfiguration.ephemeral
    cfg.httpShouldSetCookies = false; cfg.urlCredentialStorage = nil; cfg.timeoutIntervalForRequest = 12; cfg.timeoutIntervalForResource = 25
    let session = URLSession(configuration: cfg, delegate: GoogleDownloadPolicy(), delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    let (bytes, response) = try await session.bytes(from: url)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let final = http.url, publicImageURL(final), http.expectedContentLength <= 8_000_000 else { throw fail("Serwer nie udostępnił obrazu. Spróbuj skopiować obraz z podglądu.") }
    var data = Data()
    for try await byte in bytes { guard data.count < 8_000_000 else { throw fail("Obraz przekracza 8 MB.") }; data.append(byte) }
    return (data, final.absoluteString)
}
