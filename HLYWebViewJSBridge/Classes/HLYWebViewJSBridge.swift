//
//  HLYWebViewJSBridge.swift
//  HLYWebViewJSBridge
//
//  Created by LingyeHan on 2020/5/7.
//  Copyright (c) 2020 LingyeHan. All rights reserved.
//

import Foundation
import WebKit

private let kOldProtocolScheme = "wvjbscheme"
private let kNewProtocolScheme = "https"
private let kQueueHasMessage = "__wvjb_queue_message__"
private let kBridgeLoaded = "__bridge_loaded__"

public typealias WVJBResponseCallback = (_ responseData: Any?) -> Void
public typealias WVJBHandler = (_ data: Any?, _ responseCallback: WVJBResponseCallback?) -> Void
public typealias WVJBMessage = [String: Any]

protocol WebViewJavascriptBridgeBaseDelegate {
    func evaluateJavascript(_ javascriptCommand: String) -> String
}

open class HLYWebViewJSBridge: NSObject {
    
    private static var logging = false
    private static var logMaxLength = 500
    
    fileprivate var responseCallbackUniqueId = 0
    
    fileprivate lazy var messageHandlers = [String: WVJBHandler]()
    fileprivate lazy var responseCallbacks = [String: WVJBResponseCallback]()
    fileprivate lazy var startupMessageQueue: [WVJBMessage]? = { [WVJBMessage]() }()
    fileprivate weak var webView: WKWebView?
    public weak var webViewDelegate: WKNavigationDelegate?
    
    public class func enableLogging() { logging = true }
    public class func setLogMaxLength(_ length: Int) { logMaxLength = length }
    
    deinit {
//        self.webViewDelegate = nil
    }
    
    fileprivate override init() {
        super.init()
    }
    
    fileprivate convenience init(webView: WKWebView) {
        self.init()
        self.webView = webView
        self.webViewDelegate = webView.navigationDelegate // keep ref to original deleagate
        self.webView!.navigationDelegate = self
    }
    
    public class func bridge(_ webView: WKWebView) -> HLYWebViewJSBridge {
        let bridge = HLYWebViewJSBridge(webView: webView)
        return bridge
    }
    
}

// MARK: - Public

extension HLYWebViewJSBridge {
    
    public func registerHandler(_ handlerName: String, handler: @escaping WVJBHandler) {
        self.messageHandlers[handlerName] = handler
    }

    public func removeHandler(_ handlerName: String) {
        self.messageHandlers.removeValue(forKey: handlerName)
    }
    
    public func removeAllHandlers() {
        self.messageHandlers.removeAll()
    }
    
    public func callHandler(_ handlerName: String, data: Any?, responseCallback: WVJBResponseCallback?) {
        var message = WVJBMessage()

        if let data = data {
            message["data"] = data
        }
        if let callback = responseCallback {
            responseCallbackUniqueId += 1
            let callbackId = "objc_cb_\(responseCallbackUniqueId)"
            self.responseCallbacks[callbackId] = callback
            message["callbackId"] = callbackId
        }
        message["handlerName"] = handlerName
        
        self.queueMessage(message)
    }

    public func disableJavscriptAlertBoxSafetyTimeout() {
        callHandler("_disableJavascriptAlertBoxSafetyTimeout", data: nil, responseCallback: nil)
    }
}

// MARK: - WKNavigationDelegate

extension HLYWebViewJSBridge: WKNavigationDelegate {
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if webView != self.webView { return }
        
        guard let url = navigationAction.request.url else {
            return
        }
        //print("==> decidePolicyFor: \(url)")
        if isJavascriptBridgeURL(url) {
            if isBridgeLoadedURL(url) {
                //print("==> injectJavascriptFile: \(url)")
                injectJavascriptFile()
            } else if isQueueMessageURL(url) {
                //print("==> flushMessageQueue: \(url)")
                flushMessageQueue()
            } else {
                // Unkown Message
                NSLog("WVJB WARNING: Received unknown WebViewJavascriptBridge command \(url.absoluteString)")
            }
            decisionHandler(WKNavigationActionPolicy.cancel)
            return
        }

        typealias WKNavigationActionMethodType = (WKWebView, WKNavigationAction, @escaping (WKNavigationActionPolicy) -> Void) -> Void
        if let webViewDelegate = self.webViewDelegate, webViewDelegate.responds(to: #selector(webView(_:decidePolicyFor:decisionHandler:) as WKNavigationActionMethodType)) {
            webViewDelegate.webView?(webView, decidePolicyFor: navigationAction, decisionHandler: decisionHandler)
        } else {
            decisionHandler(WKNavigationActionPolicy.allow)
        }
    }
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if webView != self.webView { return }
        //print("==> navigationResponse: \(navigationResponse.response.url)")
        if self.webViewDelegate?.webView?(webView, decidePolicyFor: navigationResponse, decisionHandler: decisionHandler) == nil {
            decisionHandler(WKNavigationResponsePolicy.allow)
        }
    }
    
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if webView != self.webView { return }

        self.webViewDelegate?.webView?(webView, didStartProvisionalNavigation: navigation)
    }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if webView != self.webView { return }

        self.webViewDelegate?.webView?(webView, didFailProvisionalNavigation: navigation, withError: error)
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView != self.webView { return }

        self.webViewDelegate?.webView?(webView, didFinish: navigation)
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if webView != self.webView { return }

        self.webViewDelegate?.webView?(webView, didFail: navigation, withError: error)
    }

    public func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if webView != self.webView { return }

        if let webViewDelegate = self.webViewDelegate, webViewDelegate.webView?(webView, didReceive: challenge, completionHandler: completionHandler) != nil {
            webViewDelegate.webView?(webView, didReceive: challenge, completionHandler: completionHandler)
        } else {
            completionHandler(URLSession.AuthChallengeDisposition.performDefaultHandling, nil)
        }
    }
    
}

// MARK: - Private

extension HLYWebViewJSBridge {
    
    private func queueMessage(_ message: WVJBMessage) {
        if self.startupMessageQueue != nil {
            self.startupMessageQueue!.append(message)
        } else {
            self.dispatchMessage(message)
        }
    }
    
    private func dispatchMessage(_ message: WVJBMessage) {
        guard let jsonMsg = escapeMessage(message), let webView = self.webView else {
            return
        }
        
        let jsCommand = "WebViewJavascriptBridge._handleMessageFromObjC('\(jsonMsg)');"
        if Thread.current.isMainThread {
            webView.evaluateJavaScript(jsCommand, completionHandler: nil)
        } else {
            DispatchQueue.main.sync {
                webView.evaluateJavaScript(jsCommand, completionHandler: nil)
            }
        }
    }
    
    private func flushMessageQueue() {
        self.webView?.evaluateJavaScript("WebViewJavascriptBridge._fetchQueue();", completionHandler: { (result, error) in
            if error != nil {
                NSLog("WVJB WARNING: Error when trying to fetch data from WKWebView: \(error!.localizedDescription)")
            }
            if let message = result as? String {
                self.handleQueueMessage(message)
            }
        })
    }
    
    private func handleQueueMessage(_ jsonMessage: String) {
        if jsonMessage.isEmpty {
            NSLog("WVJB WARNING: Native got nil while fetching the message queue JSON from webview. This can happen if the WebViewJavascriptBridge JS is not currently present in the webview, e.g if the webview just loaded a new page.");
            return
        }

        guard let messages = deserializeMessage(jsonMessage) as? Array<Any> else {
            NSLog("WVJB Handle Message Error: message is not array")
            return
        }

        for item in messages {
            guard let message = item as? WVJBMessage else {
                NSLog("WVJB WARNING: Invalid message received: \(item)")
                continue
            }
            log(action: "Received Message", message: message)
            
            // Native callback(JS完成Native调用后)
            if let responseId = message["responseId"] as? String {
                if let responseCallback = self.responseCallbacks[responseId] {
                    responseCallback(message["responseData"] ?? NSNull())
                } else {
                    NSLog("WVJB Handle Message Error: no matching callback closure for: \(message)")
                }
                self.responseCallbacks.removeValue(forKey: responseId)
            } else { // JS call Native Handler
                guard let handlerName = message["handlerName"] as? String,
                    let messageHandler = self.messageHandlers[handlerName] else {
                    NSLog("WVJB Handle Message Error: no handler for message from JS: %@", message);
                    continue
                }
                
                let responseCallback: WVJBResponseCallback = {
                    if let callbackId = message["callbackId"] as? String {
                        return { [unowned self] (responseData: Any?) -> Void in
                            let respData: Any = responseData ?? NSNull()
                            let respMessage: WVJBMessage = ["responseId": callbackId as Any, "responseData": respData]
                            self.queueMessage(respMessage)
                        }
                    } else {
                        return { (responseData: Any?) -> Void in
                            // emtpy closure, make sure callback closure param is non-optional
                        }
                    }
                }()
                messageHandler(message["data"], responseCallback)
            }
        }
    }
    
    private func injectJavascriptFile() {
        guard let bundleURL = Bundle(for: HLYWebViewJSBridge.self).url(forResource: "HLYWebViewJSBridge", withExtension: "bundle"),
            let path = Bundle(url: bundleURL)?.path(forResource: "HLYWebViewJSBridge", ofType: "js") else {
            fatalError("The `HLYWebViewJSBridge.js` file could not be found")
        }
        
        do {
            let jsContext = try String(contentsOfFile: path, encoding: .utf8)
            self.webView?.evaluateJavaScript(jsContext, completionHandler: nil)
            if let queuedMessage = self.startupMessageQueue {
                for message in queuedMessage {
                    dispatchMessage(message)
                }
                self.startupMessageQueue = nil // TODO 仅为了添加一个默认 Message
            }
        } catch let error as NSError {
            NSLog("WVJB Inject Javascript File Error: \(error.localizedDescription)")
        }
    }

    private func isJavascriptBridgeURL(_ url: URL) -> Bool {
        if isSchemeMatch(url) == false {
            return false
        }
        return isBridgeLoadedURL(url) || isQueueMessageURL(url)
    }

    private func isSchemeMatch(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == kNewProtocolScheme || scheme == kOldProtocolScheme
    }

    private func isQueueMessageURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased()
        return isSchemeMatch(url) && host == kQueueHasMessage
    }

    private func isBridgeLoadedURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased()
        return isSchemeMatch(url) && host == kBridgeLoaded
    }

    // MARK: - SwiftWebViewBridge & JSON Serilization
    
    private func escapeMessage(_ message: Any) -> String? {
        guard let jsonMsg = self.serializeMessage(message) else {
            return nil
        }
        
        return jsonMsg
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\'", with: "\\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028") // 行分隔符
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029") // 段分隔符
    }
    
    private func serializeMessage(_ message: Any, pretty: Bool = false) -> String? {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message, options: JSONSerialization.WritingOptions())
            return String(data: jsonData, encoding: String.Encoding.utf8)
        } catch let error as NSError {
            NSLog("WVJB Serialize Message Error: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func deserializeMessage(_ message: String) -> Any? {
        guard let serializedData = message.data(using: String.Encoding.utf8) else {
            return nil
        }
        
        do {
            let jsonObj = try JSONSerialization.jsonObject(with: serializedData, options: .allowFragments)
            return jsonObj
        } catch let error as NSError {
            NSLog("WVJB Deserialize Message Error: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func log(action: String, message: Any) {
        if (HLYWebViewJSBridge.logging == false) { return }
        let json = (message is String) ? (message as! String) : (serializeMessage(message, pretty: true) ?? "")
        if (json.lengthOfBytes(using: .utf8) > HLYWebViewJSBridge.logMaxLength) {
            NSLog("WVJB \(action): \(json.prefix(HLYWebViewJSBridge.logMaxLength))...")
        } else {
            NSLog("WVJB \(action): \(json)")
        }
    }
    
}
