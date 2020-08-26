//
//  HLYWebViewJSBridge.swift
//  HLYWebViewJSBridge
//
//  Created by LingyeHan on 2020/5/7.
//  Copyright (c) 2020 LingyeHan. All rights reserved.
//

import Foundation
import WebKit

public typealias WVJBResponseCallback = (_ responseData: Any?) -> Void
public typealias WVJBHandler = (_ data: Any?, _ responseCallback: WVJBResponseCallback?) -> Void
//public typealias WVJBMessage = [String: Any]

struct WVJBMessage {
    var handlerName: String
    var data: Any?
    var callbackId: String?
    
//    var responseMessage: WVJBResponseMessage?
    
    init(handlerName: String) {
        self.handlerName = handlerName
    }
    

    var toDictionary: [String: Any] {
        var dict: [String: Any] = ["handlerName": handlerName]
        if data != nil {
            dict["data"] = data
        }
        if callbackId != nil {
            dict["callbackId"] = callbackId
        }
        return dict
    }
}

struct WVJBResponseMessage {

    var responseId: String
    var responseData: Any?
    
    init(responseId: String) {
        self.responseId = responseId
    }
}

open class HLYWebViewJSBridge: NSObject {
    
    private static var logging = false
    private static var logMaxLength = 500
    
    fileprivate var callbackUniqueId = 0
    
    fileprivate lazy var messageHandlers = [String: WVJBHandler]()
    fileprivate lazy var responseCallbacks = [String: WVJBResponseCallback]()
    fileprivate lazy var messageQueue: [WVJBMessage]? = { [WVJBMessage]() }()
    fileprivate weak var webView: WKWebView?
    public weak var webViewDelegate: WKNavigationDelegate?
    
    public class func enableLogging() { logging = true }
    public class func setLogMaxLength(_ length: Int) { logMaxLength = length }
    
    deinit {
        //self.webViewDelegate = nil
        #if DEBUG
        print("<\(NSStringFromClass(type(of: self))) is deinit>")
        #endif
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
        var message = WVJBMessage(handlerName: handlerName)
        message.data = data
        if let callback = responseCallback {
            callbackUniqueId += 1
            let callbackId = "objc_cb_\(callbackUniqueId)"
            self.responseCallbacks[callbackId] = callback
            message.callbackId = callbackId
        }
        
//        self.queueMessage(message.toDictionary)

            startupMessage(message)
        
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

        if isJSBridgeURL(url) {
            if isBridgeLoadedURL(url) {
                injectJavascriptFile()
            } else if isQueueMessageURL(url) {
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
    
    private func injectJavascriptFile() {
        guard let bundleURL = Bundle(for: HLYWebViewJSBridge.self).url(forResource: "HLYWebViewJSBridge", withExtension: "bundle"),
            let path = Bundle(url: bundleURL)?.path(forResource: "HLYWebViewJSBridge", ofType: "js") else {
            fatalError("The `HLYWebViewJSBridge.js` file could not be found")
        }
        
        do {
            let jsContext = try String(contentsOfFile: path, encoding: .utf8)
            self.webView?.evaluateJavaScript(jsContext, completionHandler: nil)
            
            log(action: "injectJavascriptFile", message: jsContext)
            
            // js注入完成后，开启发送本地消息
            startupMessage(nil)
        } catch let error as NSError {
            NSLog("WVJB Inject Javascript File Error: \(error.localizedDescription)")
        }
    }
    
    /// 开启发送本地暂存的 callHandler 消息
    private func startupMessage(_ message: WVJBMessage?) {
        guard let messageQueue = self.messageQueue else {
            if let message = message {
                dispatchMessage(message.toDictionary)
            }
            return
        }
        
        // 发送所有暂存消息
        guard let message = message else {
            messageQueue.forEach({ message in
                dispatchMessage(message.toDictionary)
            })
            self.messageQueue = nil // 完成后置空消息队列(只在启动过程中用一次)
            return
        }
        
        // js未注入Web页面前，先暂存本地 callHandler 消息
        self.messageQueue!.append(message)
    }
    
//    private func queueMessage(_ message: [String: Any]) {
//        if self.messageQueue != nil {
//            var msg = WVJBMessage(handlerName: message["handlerName"] as! String)
//            if let data = message["data"] {
//                msg.data = data
//            }
//            if let callbackId = message["callbackId"] as? String {
//                msg.callbackId = callbackId
//            }
//            self.messageQueue!.append(msg)
//        } else {
//            self.dispatchMessage(message)
//        }
//    }
    
    // add Native callHandler
    private func dispatchMessage(_ message: [String: Any]) {
        log(action: "dispatchMessage", message: message)
        
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
    
    /// Add H5 callHandler
    private func flushMessageQueue() {
        self.webView?.evaluateJavaScript("WebViewJavascriptBridge._fetchQueue();", completionHandler: { (result, error) in
            if error != nil {
                NSLog("WVJB WARNING: Error when trying to fetch data from WKWebView: \(error!.localizedDescription)")
            }
            self.log(action: "fetchMessageQueue", message: result as Any)
            if let jsonMessageString = result as? String {
                self.handleQueueMessage(jsonMessageString)
            }
        })
    }
    
    private func handleQueueMessage(_ jsonString: String) {
        if jsonString.isEmpty {
            NSLog("WVJB WARNING: Native got nil while fetching the message queue JSON from webview. This can happen if the WebViewJavascriptBridge JS is not currently present in the webview, e.g if the webview just loaded a new page.");
            return
        }

        guard let messages = deserializeMessage(jsonString) as? Array<Any> else {
            NSLog("WVJB Handle Message Error: message is not array")
            return
        }

        /// 数据格式:
        /// [
        ///     {"handlerName":"nativeFunc","data":"Hello world"},
        ///     {"handlerName":"callHandler_1","data":{"foo":"bar"},"callbackId":"cb_1_1589540375410"}
        /// ]
        for item in messages {
            guard let message = item as? [String: Any] else {
                NSLog("WVJB WARNING: Invalid message received: \(item)")
                continue
            }
            //log(action: "Received Message", message: message)
            
            // Native callback(JS完成Native调用后)
            if let responseId = message["responseId"] as? String {
                if let responseCallback = self.responseCallbacks[responseId] {
                    log(action: "messageHandler.responseCallback", message: "\(message)")
                    responseCallback(message["responseData"] ?? NSNull())
                } else {
                    NSLog("WVJB Handle Message Error: no matching callback closure for: \(message)")
                }
                self.responseCallbacks.removeValue(forKey: responseId)
            } else {
                // JS 端调用 Native --> dispatchMessage()
                guard let handlerName = message["handlerName"] as? String,
                    let messageHandler = self.messageHandlers[handlerName] else {
                    NSLog("WVJB Error: Unregistered native handler for JS: %@", message);
                    continue
                }
                
                let responseCallback: WVJBResponseCallback? = {
                    if let callbackId = message["callbackId"] as? String {
                        return { [unowned self] (responseData: Any?) -> Void in
                            let respData: Any = responseData ?? NSNull()
                            let respMessage: [String: Any] = ["responseId": callbackId as Any, "responseData": respData]
//                            self.queueMessage(respMessage)
                            self.dispatchMessage(respMessage)
                        }
                    }
                    return nil
                }()
                
                log(action: "messageHandler", message: "\(message)")
                messageHandler(message["data"], responseCallback)
            }
        }
    }

    private func isJSBridgeURL(_ url: URL) -> Bool {
        if isSchemeMatchURL(url) == false {
            return false
        }
        return isBridgeLoadedURL(url) || isQueueMessageURL(url)
    }
    
    private func isBridgeLoadedURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased()
        return isSchemeMatchURL(url) && host == "__bridge_loaded__"
    }

    private func isQueueMessageURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased()
        return isSchemeMatchURL(url) && host == "__wvjb_queue_message__"
    }
    
    private func isSchemeMatchURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "https" || scheme == "wvjbscheme"
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
