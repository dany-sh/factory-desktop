import SwiftUI
import WebKit

struct RichTaskEditorView: NSViewRepresentable {
    @Binding var markdown: String
    @Binding var selectedText: String
    var isEditable = true

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "factoryEditor")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView

        if let editorURL = Bundle.module.url(forResource: "task-editor", withExtension: "html", subdirectory: "Editor") {
            webView.loadFileURL(editorURL, allowingReadAccessTo: editorURL.deletingLastPathComponent())
        } else {
            webView.loadHTMLString("<p>Factory editor resources are missing.</p>", baseURL: nil)
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(markdown: markdown, to: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "factoryEditor")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: RichTaskEditorView
        weak var webView: WKWebView?
        private var isReady = false
        private var isApplyingWebChange = false
        private var lastAppliedMarkdown: String?
        private var shouldSkipNextSwiftUpdate = false

        init(_ parent: RichTaskEditorView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            apply(markdown: parent.markdown, to: webView, force: true)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let event = body["event"] as? String else { return }

            DispatchQueue.main.async {
                if let selectedText = body["selectedText"] as? String {
                    self.parent.selectedText = selectedText
                }

                switch event {
                case "ready":
                    self.isReady = true
                    if let webView = self.webView {
                        self.apply(markdown: self.parent.markdown, to: webView, force: true)
                    }
                case "change":
                    guard let markdown = body["markdown"] as? String else { return }
                    self.isApplyingWebChange = true
                    self.lastAppliedMarkdown = markdown
                    self.shouldSkipNextSwiftUpdate = true
                    if self.parent.markdown != markdown {
                        self.parent.markdown = markdown
                    }
                    self.isApplyingWebChange = false
                default:
                    break
                }
            }
        }

        func apply(markdown: String, to webView: WKWebView, force: Bool = false) {
            guard isReady, !isApplyingWebChange else { return }
            if shouldSkipNextSwiftUpdate, !force {
                shouldSkipNextSwiftUpdate = false
                lastAppliedMarkdown = markdown
                return
            }
            guard force || markdown != lastAppliedMarkdown else { return }
            lastAppliedMarkdown = markdown
            let script = "window.FactoryEditor && window.FactoryEditor.setMarkdown(\(Self.javascriptLiteral(markdown)));"
            webView.evaluateJavaScript(script)
        }

        private static func javascriptLiteral(_ value: String) -> String {
            guard let data = try? JSONEncoder().encode(value),
                  let literal = String(data: data, encoding: .utf8) else {
                return "\"\""
            }
            return literal
        }
    }
}
