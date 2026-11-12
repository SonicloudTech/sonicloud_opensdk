package com.soni.soni_sdk_demo

import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.content.ClipData
import androidx.core.content.FileProvider
import com.soni.soni_sdk_demo.util.AES256GCMUtil
import com.wind.pnote.ui.DeviceDataListener
import com.wind.pnote.ui.LogDataListener
import com.wind.pnote.ui.PNote
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.reactivex.plugins.RxJavaPlugins
import java.io.File

class MainActivity : FlutterFragmentActivity(), DeviceDataListener {
    private val channel = "com.soni.soni_sdk_demo/recordPen"
    private val eventChannelName = "com.soni.soni_sdk_demo/eventChannel";
    private var eventSink: EventChannel.EventSink? = null;
    /** B 款 AES 会话 IV，后续 packet 共用；A 款不使用 */
    private var sessionIv: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channel
        ).setMethodCallHandler { call, result ->
            when (call.method) {

                "shareFile" -> {
                    val source = call.argument<String>("path")?.let { File(it) }
                    if (source == null || !source.isFile) {
                        result.error("INVALID_SHARE_FILE", "分享文件不存在", null)
                    } else {
                        try {
                            val uri = FileProvider.getUriForFile(
                                this, "$packageName.shared_files", source
                            )
                            val intent = Intent(Intent.ACTION_SEND).apply {
                                type = call.argument<String>("mimeType") ?: "application/octet-stream"
                                putExtra(Intent.EXTRA_STREAM, uri)
                                clipData = ClipData.newUri(contentResolver, source.name, uri)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(Intent.createChooser(intent, "分享文件"))
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("FILE_SHARE_FAILED", "无法打开系统分享界面", error.message)
                        }
                    }
                }

                "init" -> {
                    // 初始化PNote
                    PNote.init(this,this)
                    // 显示日志
                    PNote.setShowLog(true)
//                    PNote.setLogDataListener { data ->
////                        Log.i("PNote", "🤔：$data")
//                        runOnUiThread {
//                            try {
//                                eventSink?.success("SDK：$data")
//                            } catch (e: Exception) {
//                                Log.e("MainActivity", "Error sending data to Flutter: ${e.message}")
//                            }
//                        }
//                    }
                    PNote.setDevicesLogDataListener { logInfo ->
                        Log.d(
                            "DevicesLogDataListener",
                            "收到设备日志信息: ${logInfo?.take(100)}..."
                        )
                    }

                    PNote.setLogDataListener { p0 ->
                        Log.d(
                            "LogDataListener",
                            "收到设备日志信息: ${p0}"
                        )
                    }
                    result.success(null)
                }


                "startRecord" -> {
                    Log.d("开始调用", "  PNote.startRecord() ")
                    sessionIv = null
                    PNote.startRecord()
                    result.success(null)
                }

                "startRecordWithBoneMic" -> {
                    val enabled = call.argument<Boolean>("enabled")
                    if (enabled == null) {
                        result.error("INVALID_BONE_MIC", "骨麦开关需为布尔值", null)
                    } else {
                        sessionIv = null
                        PNote.startRecord(if (enabled) 1 else 0)
                        result.success(null)
                    }
                }

                "pauseRecord" -> {
                    PNote.pauseRecord()
                    result.success(null)
                }

                "continueRecord" -> {
                    PNote.continueRecord()
                    result.success(null)
                }

                "stopRecord" -> {
                    Log.d("开始调用", "  PNote.stopRecord() ")
                    PNote.stopRecord()
                    sessionIv = null
                    result.success(null)
                }

                "stopSearch" -> {
                    PNote.stopSearch()
                    result.success(true)
                }

                "startSearch" -> {
                    PNote.startSearch()
                    result.success(true)
                }

                "connect" -> {
                    //  FF:FE:53:12:1B:13
                    val arguments = call.arguments as? Map<*, *>
                    val name = arguments?.get("name") as? String ?: ""
                    val address = arguments?.get("address") as? String ?: ""

                    PNote.connectDevice(name, address)

                    result.success("connect success")
                }

                "authkeyConnect" -> {
                    val authkey = call.argument<String>("authkey")
                    if (authkey == null) {
                        result.error("INVALID_AUTHKEY", "AuthKey 需为十六进制字符串", null)
                    } else {
                        PNote.authkeyConnect(authkey)
                        result.success(null)
                    }
                }

                "resetAuthkey" -> {
                    val authkey = call.argument<String>("authkey")
                    if (authkey == null) {
                        result.error("INVALID_AUTHKEY", "AuthKey 需为十六进制字符串", null)
                    } else {
                        PNote.ResetAuthkey(authkey)
                        result.success(null)
                    }
                }

                "unbondAuthkey" -> {
                    PNote.UnbondAuthkey()
                    result.success(null)
                }

                "setWifiPassword" -> {
                    val password = call.argument<String>("password")
                    if (password == null || password.length !in 8..16) {
                        result.error("INVALID_PASSWORD", "热点密码需为 8-16 个字符", null)
                    } else {
                        PNote.SetWifiPassword(password)
                        result.success(null)
                    }
                }

                "close" -> {
                    PNote.closeConnect()
                    result.success("close success")
                }

                "destroyListen" -> {
                    result.success(null)
                }

                "getRecordFileList" -> {
                    PNote.getRecordFileList()
                    result.success(null)
                }

                "startGetFile" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val fileName = arguments?.get("fileName") as? String ?: ""
                    val offset = arguments?.get("offset") as? Int ?: 0
                    // 🔹 打印接收到的值
                    Log.d("PNote_Debug", "startGetFile -> fileName: $fileName, offset: $offset")
                    PNote.startGetFile(fileName,offset)
                    result.success(null)
                }

                "stopGetFile" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val fileName = arguments?.get("fileName") as? String ?: ""
                    PNote.stopGetFile(fileName)
                    result.success(null)
                }

                "deleteReordFile" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val fileName = arguments?.get("fileName") as? String ?: ""
                    Log.d("删除录音文件", "deleteReordFile -> fileName: $fileName")

                    PNote.deleteReordFile(fileName)
                    result.success(null)
                }

                "deleteAllReordFile" -> {
                    PNote.deleteAllReordFile()
                }

                "getDeviceGain" -> {
                    PNote.getDeviceGain()
                }

                "setDeviceGain" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val gain = arguments?.get("gain") as? Int ?: 1
                    Log.d("设置设备增益", "setDeviceGain -> gain: $gain--${gain::class.simpleName}")
                    PNote.setDeviceGain(gain)
                }

                "getCBC" -> {
                    PNote.getCBC()
                    result.success(null)
                }


                "getSN" -> {
                    PNote.getSn()
                    result.success(null)
                }

                "syncTime" -> {
                    PNote.syncTime()
                    result.success(null)
                }

                "startBtnBackRecord" -> {
                    Log.d("开始调用", " PNote.startBtnBackRecord() ")
                    sessionIv = null
                    PNote.startBtnBackRecord()
                    result.success(null)
                }
                "pauseBtnBackRecord" -> {
                    PNote.pauseBtnBackRecord()
                    result.success(null)
                }
                "continueBtnBackRecord" -> {
                    PNote.continueBtnBackRecord()
                    result.success(null)
                }
                "stopBtnBackRecord" -> {
                    PNote.stopBtnBackRecord()
                    sessionIv = null
                    result.success(null)
                }
                "sendAppShowState" -> {
                    val arguments = call.arguments as? Int?: 1
                    PNote.sendAppShowState(arguments)
                    result.success(null)
                }
                "recordState" -> {
                    Log.d("开始调用", " PNote.getRecordState()")

                    PNote.getRecordState()
                    result.success(null)
                }
                "getFileName" -> {
                    Log.d("开始调用", " PNote.getFileNameOnlyRecordimg()")

                    PNote.getFileNameOnlyRecording()
                    result.success(null)
                }

                "getRecordTime" -> {
                    Log.d("开始调用", " PNote.getTimeOnlyRecordimg()")


                    PNote.getTimeOnlyRecording()
                    result.success(null)
                }

                "startGetFileByFromToEnd" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val fileName = arguments?.get("fileName") as? String ?: ""
                    val end = arguments?.get("end") as? Int ?: 0
                    // 🔹 打印接收到的值
                    Log.d("开始调用", "PNote.startGetFileByFromToEnd() -> fileName: $fileName, end: $end")
                    PNote.startGetFileByFromToEnd(fileName,0,end)
                    result.success(null)
                }

                "isDeviceConnected" -> {
                    Log.d("开始调用", "PNote.isDeviceConnected()")
                    PNote.isDeviceConnected()
                    result.success(true)
                }

                "getDeviceCapacity" -> {
                    Log.d("开始调用", "PNote.getDeviceCapacity()")
                    PNote.getDeviceCapacity()
                    result.success(null)
                }

                "getTimeOnlyRecording" -> {
                    Log.d("开始调用", "PNote.getTimeOnlyRecording()")
                    PNote.getTimeOnlyRecording()
                }
                "getDeviceVersion" -> {
                    Log.d("开始调用", "PNote.getDeviceVersion()")
                    PNote.getDeviceVersion()
                    result.success(null)
                }
                "getDeviceVersion" -> {
                    Log.d("开始调用", " PNote.getDeviceVersion()")


                    PNote.getDeviceVersion()
                    result.success(null)
                }
                "getDeviceVersionCode" -> {
                    Log.d("开始调用", " PNote.getDeviceVersionCode()")


                    PNote.getDeviceVersionCode()
                    result.success(null)
                }
                "getDeviceWiFiState" -> {
                    Log.d("开始调用", " PNote.getDeviceWiFiState()")
                    PNote.getDeviceWiFiState()
                    result.success(null)
                }
                "getWiFiHotspotState" -> {
                    Log.d("开始调用", " PNote.getWiFiHotspotState()")
                    PNote.getWiFiHotspotState()
                    result.success(null)
                }
                "openWiFi" -> {
                    Log.d("开始调用", " PNote.openWiFi()")


                    PNote.openWiFi()
                    result.success(null)
                }
                "closeWiFi" -> {
                    Log.d("开始调用", " PNote.closeWiFi()")


                    PNote.closeWiFi()
                    result.success(null)
                }
                ///连接设备WiFi
                "connectDeviceWiFi" -> {
                    Log.d("开始调用", " PNote.connectDeviceWiFi()")


                    PNote.connectDeviceWiFi()
                    result.success(null)
                }
                "quickConnectDeviceWiFi" -> {
                    val password = call.argument<String>("password") ?: ""
                    PNote.quickConnectDeviceWiFi(password, 30, 10)
                    result.success(null)
                }
                ///断开设备WiFi连接
                "disconnectDeviceWiFi" -> {
                    Log.d("开始调用", " PNote.disconnectDeviceWiFi()")


                    PNote.disconnectDeviceWiFi()
                    result.success(null)
                }
                "setDeviceName" -> {
                    val name = call.argument<String>("name") ?: ""
                    PNote.SetDeviceName(name)
                    result.success(null)
                }
                "resetDevice" -> {
                    PNote.RestDevice()
                    result.success(null)
                }
                "resetDeviceName" -> {
                    PNote.ResetDeviceName()
                    result.success(null)
                }
                "setWifiDirect" -> {
                    val ssid = call.argument<String>("ssid") ?: ""
                    val password = call.argument<String>("password") ?: ""
                    PNote.SetWifi(ssid, password)
                    result.success(null)
                }
                "setRemoteUrl" -> {
                    val url = call.argument<String>("url") ?: ""
                    PNote.SetRemoteURL(url)
                    result.success(null)
                }
                "resetWifiDirect" -> {
                    PNote.ResetWifi()
                    result.success(null)
                }
                "getWifiDirect" -> {
                    PNote.GetWifi()
                    result.success(null)
                }
                ///请求设备进入OTA升级模式
                "requestDeviceGotoOtaMode" -> {
                    Log.d("开始调用", " PNote.requestDeviceGotoOtaMode()")
                    PNote.requestDeviceGotoOtaMode()
                    result.success(null)
                }
                ///发送OTA固件文件
                "sendOtaFile" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        try {
                            val file = java.io.File(filePath)
                            if (file.exists()) {
                                val data = file.readBytes()
                                Log.d("OTA传输", "文件大小: ${data.size} bytes")
                                PNote.sendOtaFile(data)
                                result.success(null)
                            } else {
                                result.error("FILE_NOT_FOUND", "固件文件不存在", null)
                            }
                        } catch (e: Exception) {
                            Log.e("OTA传输", "发送失败: ${e.message}")
                            result.error("ERROR", "发送OTA文件失败", e.message)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "文件路径不能为空", null)
                    }
                }
                ///获取低功耗录音模式状态
                "getDeviceLowPowerRecordMode" -> {
                    Log.d("开始调用", "PNote.getDeviceLowPowerRecordMode()")
                    PNote.getDeviceLowPowerRecordMode()
                    result.success(null)
                }
                ///设置低功耗录音模式状态
                "setDeviceLowPowerRecordMode" -> {
                    val state = call.argument<Int>("state") ?: 0
                    Log.d("开始调用", "PNote.setDeviceLowPowerRecordMode() state=$state")
                    PNote.setDeviceLowPowerRecordMode(state)
                    result.success(null)
                }

                /// 设置离线文件传输间隔
                "sendFileTimeInterval" -> {
                    val interval = call.argument<Int>("interval")
                    if (interval == null || interval !in 13..255) {
                        result.error("INVALID_ARGUMENT", "传输间隔须为 13–255 毫秒", null)
                    } else {
                        PNote.sendFileTimeInterval(interval.toByte())
                        result.success(null)
                    }
                }
                "setHeartbeatDataState" -> {
                    val state = call.argument<Int>("state")
                    if (state == null || state !in 0..1) {
                        result.error("INVALID_ARGUMENT", "心跳开关仅支持 0 或 1", null)
                    } else {
                        PNote.setHeartbeatDataState(state)
                        result.success(null)
                    }
                }
                "sendBackHeartbeatData" -> {
                    PNote.sendBackHeartbeatData()
                    result.success(null)
                }

                /// 获取 BK 版本号
                "getBKHDVersion" -> {
                    Log.d("开始调用", "PNote.getBKHDVersion()")
                    PNote.getBKHDVersion()
                    result.success(null)
                }
                /// 发送 BK 升级 URL
                "setBK_UPGRADEHD" -> {
                    val url = call.argument<String>("url") ?: ""
                    Log.d("开始调用", "PNote.setBK_UPGRADEHD() url=$url")
                    PNote.setBK_UPGRADEHD(url)
                    result.success(null)
                }

                else -> {
                    result.notImplemented()
                }

            }

        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        RxJavaPlugins.setErrorHandler { throwable ->
            Log.e("error", throwable.localizedMessage)
        }
    }


    override fun onDeviceDataEvent(p0: String?) {
        /// 设备数据回调
        runOnUiThread {
            try {
                eventSink?.success(p0)
            } catch (e: Exception) {
                Log.e("MainActivity", "Error sending data to Flutter: ${e.message}")
            }
        }
    }

    override fun onDeviceRecordData(p0: ByteArray?) {
        ///设备实时录音数据 opus格式
        if (p0 == null) return

        if (BluetoothConstants.DEVICE_AES256GCM) {
            when (p0.size) {
                36 -> {
                    // Session Record：解析并保存 sessionIv，后续 packet 共用
                    val tmpSessionIv = AES256GCMUtil.parseSessionIv(p0)
                    sessionIv = tmpSessionIv.copyOf()
                    Log.d("MainActivity", "AES sessionIv updated, len=${sessionIv?.size}")
                }
                420 -> {
                    // AES Packet：解密后得到 Opus plaintext
                    val iv = sessionIv
                    if (iv != null) {
                        try {
                            val plaintext = AES256GCMUtil.decryptPacket(iv, p0)
                            sendRecordDataToFlutter(plaintext)
                        } catch (e: Exception) {
                            Log.e("MainActivity", "AES decrypt failed: ${e.message}")
                        }
                    } else {
                        Log.e("MainActivity", "sessionIv 为空")
                    }
                }
                else -> Log.e("MainActivity", "opusdata 长度不对: ${p0.size}")
            }
        } else {
            sendRecordDataToFlutter(p0)
        }
    }

    private fun sendRecordDataToFlutter(opusData: ByteArray) {
        runOnUiThread {
            try {
                eventSink?.success(
                    mapOf(
                        "audioType" to "record",
                        "audio" to opusData.toList(),
                    )
                )
            } catch (e: Exception) {
                Log.e("MainActivity", "Error sending record data to Flutter: ${e.message}")
            }
        }
    }

    override fun onDeviceFileData(p0: ByteArray?) {
        ///设备文件数据 opus格式
        if (p0 == null) return
        runOnUiThread {
            try {
                eventSink?.success(
                    mapOf(
                        "audioType" to "file",
                        "audio" to p0.toList(),
                    )
                )
            } catch (e: Exception) {
                Log.e("MainActivity", "Error sending file data to Flutter: ${e.message}")
            }
        }
    }
}
