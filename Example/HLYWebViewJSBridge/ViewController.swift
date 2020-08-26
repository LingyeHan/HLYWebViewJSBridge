//
//  ViewController.swift
//  HLYWebViewJSBridge
//
//  Created by LingyeHan on 05/07/2020.
//  Copyright (c) 2020 LingyeHan. All rights reserved.
//

import UIKit
import WebKit
import HLYWebViewJSBridge

class ViewController: UIViewController {

    var wkWebView: WKWebView!
    var bridge: HLYWebViewJSBridge?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        wkWebView = WKWebView(frame: view.bounds)
        wkWebView.backgroundColor = UIColor.red
        view.addSubview(wkWebView)
        //wkWebView.navigationDelegate = self
        
        HLYWebViewJSBridge.enableLogging()
        bridge = HLYWebViewJSBridge.bridge(wkWebView)
        
        loadExampleHTML()
        
        bridge?.registerHandler("jsCallNativeHandler", handler: { (data, responseCallback) in
            responseCallback?(data)
        })
        bridge?.registerHandler("jsCallNativeHandler_1", handler: { (data, responseCallback) in
            responseCallback?(data)
        })
        
        self.bridge?.callHandler("nativeCallJSHandler", data: "echo hello!") { (responseData) in
             NSLog("nativeCallJSHandler: \(responseData as? String ?? "")")
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.bridge?.callHandler("nativeCallJSHandler_1", data: "echo hello!") { (responseData) in
                 NSLog("nativeCallJSHandler_1: \(responseData as? String ?? "")")
            }
        }
    }
    
    private func loadExampleHTML() {
        let request = URLRequest(url: Bundle.main.url(forResource: "JSBridgeExample", withExtension: "html")!)
        wkWebView.load(request)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

}

