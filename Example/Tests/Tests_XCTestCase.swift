//
//  Tests_XCTestCase.swift
//  HLYWebViewJSBridge_Tests
//
//  Created by Lingye Han on 2020/5/9.
//  Copyright © 2020 CocoaPods. All rights reserved.
//

import XCTest
import WebKit

import HLYWebViewJSBridge
@testable import HLYWebViewJSBridge_Example

let timeout: Double = 3

class Tests_XCTestCase: XCTestCase {
    
    var wkWebView: WKWebView!
    var bridgeRefs = [HLYWebViewJSBridge]()
    
    override func setUp() {
        super.setUp()
        
        let rootVC = (UIApplication.shared.delegate as! AppDelegate).window!.rootViewController!
        wkWebView = WKWebView(frame: rootVC.view.bounds)
        wkWebView.backgroundColor = UIColor.red
        rootVC.view.addSubview(wkWebView)
        wkWebView.navigationDelegate = self
        
        HLYWebViewJSBridge.enableLogging()
    }
    
    override func tearDown() {
        super.tearDown()
        wkWebView.removeFromSuperview()
    }

    func testRegisterHandler() {
        let bridge = self.bridge()
        XCTAssertNotNil(bridge)
        
        let expectation = self.expectation(description: "Register Handler")
        bridge.registerHandler("nativeFunc") { (data, responseCallback) in
            XCTAssertEqual(data as? String, "Hello world")
            expectation.fulfill()
        }
        
        loadEchoSample()
        waitForExpectations(timeout: timeout, handler: nil)
    }

    func testCallHandler() {
        let bridge = self.bridge()
        let callbackInvoked = expectation(description: "Callback invoked")
        bridge.callHandler("echoHandler", data: "echo hello!") { (responseData) in
            XCTAssertEqual(responseData as? String, "echo hello!");
            callbackInvoked.fulfill()
        };

        loadEchoSample()
        waitForExpectations(timeout: timeout, handler: nil)
    }

    func testEchoHandlerAfterSetup() {
        let bridge = self.bridge()
        let callbackInvoked = expectation(description: "Callback invoked")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.150) {
            bridge.callHandler("echoHandler", data:"testEchoHandler") { (responseData) in
                XCTAssertEqual(responseData as! String, "testEchoHandler")
                callbackInvoked.fulfill()
            }
        }
        
        loadEchoSample()
        waitForExpectations(timeout: timeout, handler: nil)
    }

    func testObjectEncoding() {
        let bridge = self.bridge()

        func echoObject(_ object: Any) {
            let callbackInvoked = expectation(description: "Callback invoked")
            bridge.callHandler("echoHandler", data: object) { (responseData) in
                if (object is NSDictionary) {
                    XCTAssertEqual(responseData as! NSDictionary, object as! NSDictionary)
                } else if (object is NSArray) {
                    XCTAssertEqual(responseData as! NSArray, object as! NSArray)
                }
                callbackInvoked.fulfill()
            }
        }

        echoObject("A string sent over the wire");
        echoObject("A string with '\"'/\\");
        echoObject([1, 2, 3]);
        echoObject(["a": 1, "b": 2]);

        loadEchoSample()
        waitForExpectations(timeout: timeout, handler: nil)
    }

    func testJavascriptReceiveResponse() {
        let bridge = self.bridge()
        
        let callbackInvoked = expectation(description: "Callback invoked")
        bridge.registerHandler("objcEchoToJs") { (data, responseCallback) in
            XCTAssertEqual(data as! NSDictionary, ["foo": "bar"]);
            responseCallback!(data)
        }
        bridge.callHandler("jsRcvResponseTest", data: nil) { (responseData) in
            XCTAssertEqual(responseData as! String, "Response from JS");
            callbackInvoked.fulfill()
        }
        
        loadEchoSample()
        waitForExpectations(timeout: timeout, handler: nil)
    }

    func testJavascriptReceiveResponseWithoutSafetyTimeout() {
        let bridge = self.bridge()
        bridge.disableJavscriptAlertBoxSafetyTimeout()
        let callbackInvoked = expectation(description: "Callback invoked")
        bridge.registerHandler("objcEchoToJs") { (data, responseCallback) in
            XCTAssertEqual(data as! NSDictionary, ["foo": "bar"]);
            responseCallback!(data);
        }
        bridge.callHandler("jsRcvResponseTest", data:nil) { (responseData) in
            XCTAssertEqual(responseData as! String, "Response from JS");
            callbackInvoked.fulfill()
        }
        loadEchoSample()
        waitForExpectations(timeout: timeout, handler: nil)
    }

    func testRemoveHandler() {
        let bridge = self.bridge()
     
        let callbackNotInvoked = expectation(description: "Callback invoked")
        var count = 0
        bridge.registerHandler("objcEchoToJs") { (data, callback) in
            count += 1
            callback!(data)
        }
        bridge.callHandler("jsRcvResponseTest", data: nil) { (responseData) in
            XCTAssertEqual(responseData as! String, "Response from JS");
            bridge.removeHandler("objcEchoToJs")
            bridge.callHandler("jsRcvResponseTest", data: nil) { (responseData) in
                // Since we have removed the "objcEchoToJs" handler, and since the
                // echo.html javascript won't call the response callback until it has
                // received a response from "objcEchoToJs", we should never get here
                XCTAssert(false)
            }
            bridge.callHandler("echoHandler", data: nil) { (responseData) in
                XCTAssertEqual(count, 1)
                callbackNotInvoked.fulfill()
            }
        }
        
        loadEchoSample()
        waitForExpectations(timeout: timeout, handler: nil)
    }
 
    private func bridge() -> HLYWebViewJSBridge {
        let bridge = HLYWebViewJSBridge.bridge(wkWebView)
        bridgeRefs.append(bridge)
        return bridge
    }
    
    private func loadEchoSample() {
        let request = URLRequest(url: Bundle.main.url(forResource: "echo", withExtension: "html")!)
        wkWebView.load(request)
    }

}

extension Tests_XCTestCase: WKNavigationDelegate {

//    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
//        print("\(#function)")
//    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        print("\(#function)")
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        print("\(#function)")
        decisionHandler(.allow)
    }
    
}
