import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        
        if let controller = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.windows.first })
            .first?.rootViewController as? FlutterViewController {
            
            let eventChannel = FlutterEventChannel(
                name: "com.soni.soni_sdk_demo/eventChannel",
                binaryMessenger: controller.binaryMessenger
            )
            eventChannel.setStreamHandler(self)
        }
        
        
        
        let channel = FlutterMethodChannel(name: "com.soni.soni_sdk_demo/recordPen", binaryMessenger: self.window?.rootViewController as! FlutterBinaryMessenger)
        channel.setMethodCallHandler { (call: FlutterMethodCall, result: FlutterResult) -> Void in
            print("iOS原生收到指令\(call.method)    参数：\(call.arguments)");
            switch(call.method) {
            case "connect": // 链接蓝牙
                if let args = call.arguments as? [String: Any],
                   let name = args["name"] as? String {
                    
                    if let address = args["address"] as? String, !address.isEmpty {
                        print("蓝牙 name: \(name), address: \(address)")
                        PNode.shared().connectDeviceAndAddress(name, address)
                    } else {
                        PNode.shared().connectDevice(name)
                        print("address为空，使用connectDevice方法")
                    }
                    
                } else {
                    print("参数错误，name缺失")
                }
                
                result(nil)
            case "authkeyConnect":
                guard let args = call.arguments as? [String: Any],
                      let authkey = args["authkey"] as? String else {
                    result(FlutterError(code: "INVALID_AUTHKEY", message: "AuthKey 需为十六进制字符串", details: nil))
                    return
                }
                PNode.shared().authkeyConnect(authkey)
                result(nil)
            /* 新版 SDK 已移除 AuthKey 修改和解绑接口。
            case "resetAuthkey":
                guard let args = call.arguments as? [String: Any],
                      let authkey = args["authkey"] as? String else {
                    result(FlutterError(code: "INVALID_AUTHKEY", message: "AuthKey 需为十六进制字符串", details: nil))
                    return
                }
                PNode.shared().resetAuthkey(authkey)
                result(nil)
            case "unbondAuthkey":
                PNode.shared().unbondAuthkey()
                result(nil)
            */
            case "setWifiPassword":
                guard let args = call.arguments as? [String: Any],
                      let password = args["password"] as? String,
                      (8...16).contains(password.utf16.count) else {
                    result(FlutterError(code: "INVALID_PASSWORD", message: "热点密码需为 8-16 个字符", details: nil))
                    return
                }
                PNode.shared().setWifiPassword(password)
                result(nil)
            case "close"://断开链接
                PNode.shared().closeConnect()
                result(nil)
            case "startRecord"://开始录音
                PNode.shared().startRecord()
                result(nil)
            case "pauseRecord"://暂停录音
                PNode.shared().pauseRecord()
                result(nil)
            case "stopRecord"://停止录音
                PNode.shared().stopRecord()
                result(nil)
            case "deleteReordFile"://删除录音
                if let args = call.arguments as? [String: Any], let fileName = args["fileName"] as? String {
                    print("删除文件 name: \(fileName)")
                    PNode.shared().delFileData(fileName)
                }
                result(nil)
            case "continueRecord"://继续录音
                PNode.shared().continueRecord()
                result(nil)
            case "startSearch"://开始扫描
                PNode.shared().startSearch()
                PNode.setShowLog(true)
                result(nil)
            case "stopSearch"://停止扫描
                PNode.shared().stopSearch()
                result(nil)
            case "syncTime"://同步时间
                PNode.shared().syncTime()
                result(nil)
            case "getRecordFileList"://文件列表
                PNode.shared().getRecordFileList();
                result(nil)
            case "getCBC"://电量
                PNode.shared().getCBC()
                result(nil)
                
                
            case "getSN":
                PNode.shared().getSn()
                result(nil)
            case "startGetFile"://传输文件
                
                
                
                if let args = call.arguments as? [String: Any],let fileName = args["fileName"] as? String {
                    PNode.shared().startGetFile(fileName,"0")
                } else {
                    print("文件名为空")
                }
                
                result(nil)
            case "stopGetFile"://停止传输
                if let args = call.arguments as? [String: Any], let fileName = args["fileName"] as? String {
                    print("Received message from Flutter: \(fileName)")
                    PNode.shared().stopGetFile(fileName)
                } else {
                    print("文件名为空")
                }
                result(nil)
                
            case "startBtnBackRecord":
                print("开始了吗")
                PNode.shared().startBtnBackRecord()
                print("开始了")
                result(nil)
            case "pauseBtnBackRecord":
                PNode.shared().pauseBtnBackRecord()
                result(nil)
            case "continueBtnBackRecord":
                PNode.shared().continueBtnBackRecord()
                result(nil)
            case "stopBtnBackRecord":
                PNode.shared().stopBtnBackRecord()
                result(nil)
            case "sendAppShowState":
                if let stateInt = call.arguments as? Int {
                    let state = Int32(stateInt)
                    print("发送App状态: \(state)")
                    PNode.shared().sendAppShowState(state)
                    result(nil)
                }
            case "recordState":
                PNode.shared().getRecordState()
                result(nil)
            case "getFileName":
                PNode.shared().getFileNameOnlyRecording()
                result(nil)
            case "getTimeOnlyRecording":
                PNode.shared().getTimeOnlyRecording()
                result(nil)
            case "getDeviceCapacity":
                PNode.shared().getDeviceCapacity()
                result(nil)
            case "isDeviceConnected":
                PNode.shared().isDeviceConnected()
                result(nil)
            case "deleteAllReordFile":
                PNode.shared().delAllFileData()
                result(nil)
            case "getDeviceGain":
                PNode.shared().getDeviceGain()
                result(nil)
            case "setDeviceGain":
                if let args = call.arguments as? [String: Any],
                   let gain = args["gain"] as? Int32 {
                    PNode.shared().setDeviceGain(gain)
                    result(nil)
                }
                
            case "startGetFileByFromToEnd":
                if let args = call.arguments as? [String: Any],
                   let fileName = args["fileName"] as? String,
                   let end = args["end"] as? String {
                    print("startGetFileByFrom，fileName \(fileName) isNew \(end)")
                    
                    PNode.shared().startGetFileByFrom(toEnd: fileName, "0", end)
                } else {
                    print("参数错误，fileName 或 end 缺失")
                }
                result(nil)
            case "getDeviceVersion":
                PNode.shared().getDeviceVersion()
                result(nil)
            case "getDeviceVersion":
          
                PNode.shared().getDeviceVersion()
             
                result(nil)
            case "getDeviceVersionCode":
          
                PNode.shared().getDeviceVersionCode()
             
                result(nil)
            case "getDeviceWiFiState":
                PNode.shared().getDeviceWiFiState()
                result(nil)
            case "openWiFi":
          
                PNode.shared().openWiFi()
             
                result(nil)
            case "closeWiFi":
          
                PNode.shared().closeWiFi()
             
                result(nil)
            case "connectDeviceWiFi":
          
                PNode.shared().connectDeviceWiFi()
             
                result(nil)
            case "quickConnectDeviceWiFi":

                PNode.shared().quickConnectDeviceWiFi(withWiFiTimeout: 30, tcpTimeout: 10)

                result(nil)
            case "disconnectDeviceWiFi":

                PNode.shared().disconnectDeviceWiFi()
             
                result(nil)
            case "getWiFiHotspotState":
                PNode.shared().getWiFiHotspotState()
                result(nil)
            /* 新版 SDK 已移除设备名称及 Wi-Fi 直传接口。
            case "setDeviceName":
                guard let args = call.arguments as? [String: Any],
                      let name = args["name"] as? String else {
                    result(FlutterError(code: "INVALID_ARGUMENT", message: "设备名称不能为空", details: nil))
                    return
                }
                PNode.shared().setDeviceName(name)
                result(nil)
            case "resetDeviceName":
                PNode.shared().resetDeviceName()
                result(nil)
            case "setWifiDirect":
                guard let args = call.arguments as? [String: Any],
                      let ssid = args["ssid"] as? String,
                      let password = args["password"] as? String else {
                    result(FlutterError(code: "INVALID_ARGUMENT", message: "Wi-Fi 名称和密码不能为空", details: nil))
                    return
                }
                PNode.shared().setWiFiDirectSSID(ssid, password: password)
                result(nil)
            case "setRemoteUrl":
                guard let args = call.arguments as? [String: Any],
                      let url = args["url"] as? String else {
                    result(FlutterError(code: "INVALID_ARGUMENT", message: "上传 URL 不能为空", details: nil))
                    return
                }
                PNode.shared().setRemoteURL(url)
                result(nil)
            case "resetWifiDirect":
                PNode.shared().resetWiFiDirect()
                result(nil)
            case "getWifiDirect":
                PNode.shared().getWiFiDirect()
                result(nil)
            */
            case "requestDeviceGotoOtaMode":
                PNode.shared().requestDeviceGotoOtaMode()
                result(nil)
            case "sendOtaFile":
                guard let args = call.arguments as? [String: Any],
                      let filePath = args["filePath"] as? String else {
                    result(FlutterError(code: "INVALID_ARGUMENT", message: "文件路径不能为空", details: nil))
                    return
                }
                do {
                    let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
                    PNode.shared().sendOtaFile(data)
                    result(nil)
                } catch {
                    result(FlutterError(code: "FILE_ERROR", message: "读取固件文件失败: \(error.localizedDescription)", details: nil))
                }
            case "getDeviceLowPowerRecordMode":
                PNode.shared().getDeviceLowPowerRecordMode()
                result(nil)
            case "setDeviceLowPowerRecordMode":
                if let args = call.arguments as? [String: Any],
                   let state = args["state"] as? Int {
                    print("setDeviceLowPowerRecordMode, state \(state)")
                    PNode.shared().setDeviceLowPowerRecordMode(Int32(state))
                } else {
                    print("参数错误，state 缺失")
                }
                result(nil)
            case "getBKHDVersion":
                PNode.shared().getBKHDVersion()
                result(nil)
            case "setBK_UPGRADEHD":
                guard let args = call.arguments as? [String: Any],
                      let url = args["url"] as? String,
                      !url.isEmpty else {
                    result(FlutterError(code: "INVALID_ARGUMENT", message: "BK 升级 URL 不能为空", details: nil))
                    return
                }
                PNode.shared().setBKUpgradeHD(url)
                result(nil)
            default:
                result(nil)
            }
        }
        
        
        
        PNode.shared().delegate = self
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    var eventSink: FlutterEventSink?
}

extension AppDelegate: WindBleDelegate {
    func deviceDataEvent(_ data: String) {
        print("设备数据回调:\(data)")
        if let eventSink = eventSink {
            eventSink(data)
        }
    }
    
    func deviceRecord(_ recordData: Data) {
        print("设备实时录音数据 opus格式:\(recordData.count)")
        if let eventSink = eventSink {
            eventSink([
                "audioType": "record",
                "audio": [UInt8](recordData),
            ])
        }
    }
    
    func deviceFileData(_ fileData: Data) {
        print("备文件数据 opus格式\(fileData.count)")
        if let eventSink = eventSink {
            eventSink([
                "audioType": "file",
                "audio": [UInt8](fileData),
            ])
        }
    }
    
    func logInfo(_ log: String!) {
        if let eventSink = eventSink {
            eventSink(["sdkLog":log])
        }
    }
    
}
extension AppDelegate: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
