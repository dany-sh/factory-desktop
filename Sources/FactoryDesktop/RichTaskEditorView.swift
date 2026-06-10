import FactoryDesktopCore
import SwiftUI
import WebKit

struct RichTaskEditorView: NSViewRepresentable {
    @Binding var markdown: String
    @Binding var selectionState: TaskEditorSelectionState
    @ObservedObject var bridge: RichTaskEditorBridge
    var isEditable = true

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView: WKWebView
        if let persistedWebView = bridge.webView {
            webView = persistedWebView
        } else {
            let configuration = WKWebViewConfiguration()
            let createdWebView = WKWebView(frame: .zero, configuration: configuration)
            createdWebView.setValue(false, forKey: "drawsBackground")
            bridge.webView = createdWebView
            bridge.isReady = false
            context.coordinator.attach(to: createdWebView)
            if let editorURL = Bundle.module.url(forResource: "task-editor", withExtension: "html", subdirectory: "Editor") {
                createdWebView.loadFileURL(editorURL, allowingReadAccessTo: editorURL.deletingLastPathComponent())
            } else {
                createdWebView.loadHTMLString("<p>Factory editor resources are missing.</p>", baseURL: nil)
            }
            webView = createdWebView
        }

        context.coordinator.attach(to: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.attach(to: webView)
        context.coordinator.registerBridge(bridge)
        context.coordinator.apply(markdown: markdown, to: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "factoryEditor")
        webView.navigationDelegate = nil
        coordinator.unregisterBridge()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: RichTaskEditorView
        weak var webView: WKWebView?
        private var isApplyingWebChange = false
        private var shouldSkipNextSwiftUpdate = false

        init(_ parent: RichTaskEditorView) {
            self.parent = parent
        }

        func attach(to webView: WKWebView) {
            self.webView = webView
            webView.navigationDelegate = self
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "factoryEditor")
            webView.configuration.userContentController.add(self, name: "factoryEditor")
        }

        func registerBridge(_ bridge: RichTaskEditorBridge) {
            bridge.requestLatestMarkdown = { [weak self] completion in
                self?.readMarkdown(completion: completion)
            }
        }

        func unregisterBridge() {
            parent.bridge.requestLatestMarkdown = nil
            parent.bridge.dismissInlineAI = nil
            parent.bridge.openInlineAI = nil
            parent.bridge.runInlineAction = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.bridge.isReady = true
            apply(markdown: parent.markdown, to: webView, force: true)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let event = body["event"] as? String else { return }

            DispatchQueue.main.async {
                if let selectedText = body["selectedText"] as? String {
                    var selectionState = self.parent.selectionState
                    selectionState.selectedText = selectedText
                    if let isFocused = body["isFocused"] as? Bool {
                        selectionState.isFocused = isFocused
                    }
                    if let activeSection = body["activeSection"] as? String {
                        selectionState.activeSection = EditorAssistSection(rawValue: activeSection)
                    } else {
                        selectionState.activeSection = nil
                    }
                    if let cursorAtInsertionPoint = body["cursorAtInsertionPoint"] as? Bool {
                        selectionState.cursorAtInsertionPoint = cursorAtInsertionPoint
                    }
                    if let changeToken = body["changeToken"] as? Int {
                        selectionState.changeToken = changeToken
                    }
                    self.parent.selectionState = selectionState
                }

                if event == "dismissInlineAI" {
                    self.parent.bridge.dismissInlineAI?()
                } else if event == "openInlineAI" {
                    self.parent.bridge.openInlineAI?()
                } else if event == "inlineAIAction",
                          let actionRawValue = body["action"] as? String,
                          let action = EditorAssistAction(rawValue: actionRawValue) {
                    self.parent.bridge.runInlineAction?(action)
                }

                switch event {
                case "ready":
                    self.parent.bridge.isReady = true
                    if let webView = self.webView {
                        self.apply(markdown: self.parent.markdown, to: webView, force: true)
                    }
                case "change":
                    guard let markdown = body["markdown"] as? String else { return }
                    self.isApplyingWebChange = true
                    self.parent.bridge.lastAppliedMarkdown = markdown
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
            guard parent.bridge.isReady, !isApplyingWebChange else { return }
            if shouldSkipNextSwiftUpdate, !force {
                shouldSkipNextSwiftUpdate = false
                parent.bridge.lastAppliedMarkdown = markdown
                return
            }
            guard force || markdown != parent.bridge.lastAppliedMarkdown else { return }
            parent.bridge.lastAppliedMarkdown = markdown
            let script = "window.FactoryEditor && window.FactoryEditor.setMarkdown(\(Self.javascriptLiteral(markdown)));"
            webView.evaluateJavaScript(script)
        }

        private func readMarkdown(completion: @escaping (String) -> Void) {
            guard let webView, parent.bridge.isReady else {
                completion(parent.markdown)
                return
            }
            webView.evaluateJavaScript("window.FactoryEditor && window.FactoryEditor.getMarkdown();") { result, _ in
                let markdown = (result as? String) ?? self.parent.markdown
                DispatchQueue.main.async {
                    self.parent.markdown = markdown
                    self.parent.bridge.lastAppliedMarkdown = markdown
                    completion(markdown)
                }
            }
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

final class RichTaskEditorBridge: ObservableObject {
    @Published var isReady = false
    var requestLatestMarkdown: (((@escaping (String) -> Void) -> Void))?
    var dismissInlineAI: (() -> Void)?
    var openInlineAI: (() -> Void)?
    var runInlineAction: ((EditorAssistAction) -> Void)?
    fileprivate var webView: WKWebView?
    fileprivate var lastAppliedMarkdown: String?
}
