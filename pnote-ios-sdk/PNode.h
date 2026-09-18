//
//  PNode.h
//  PNode
//
//  Created by hMac on 2023/11/7.
//

#import <Foundation/Foundation.h>





#pragma mark -   🟧WindBleDelegate 代理


@protocol WindBleDelegate

/// 设备数据回调
- (void)deviceDataEvent:(NSString *)data;
///设备实时录音数据 opus格式
- (void)deviceRecordData:(NSData *)recordData;
///设备文件数据 opus格式
- (void)deviceFileData:(NSData *)fileData;
/// log
- (void)logInfo:(NSString *)log;
@end

#pragma mark -   🟧PNode 蓝牙工具类
@interface PNode : NSObject

+ (instancetype)Shared;

@property (nonatomic,weak) id<WindBleDelegate> delegate;///< delegate

///是否显示日志
+(void)setShowLog:(BOOL)showLog;

///是否连接设备
- (BOOL)isDeviceConnected;

///开始搜索
-(void)startSearch;

///停止搜索
-(void)stopSearch;

- (void)connectDevice:(NSString *)name;

///连接设备 参数：设备名称 地址
- (void)connectDeviceAndAddress:(NSString *)deviceName :(NSString *)address;

/// 容量大小
-(void) getDeviceCapacity;

//获取电池电量
-(void)getCBC;

///同步时间
-(void)syncTime;

///获取SN
-(void)getSn;

///断开连接
-(void)closeConnect;

///启动录音
-(void)startRecord;

///暂停录音
-(void)pauseRecord;

///继续录音
-(void)continueRecord;

///停止录音
-(void)stopRecord;

///获取文件列表
-(void)getRecordFileList;

///开始传输录音文件
-(void)startGetFile:(NSString *)fileName : (NSString*) offset;

///开始传输录音文件
-(void)startGetFileByFromToEnd:(NSString *)fileName : (NSString*) offset :(NSString*) end ;

///停止传输录音文件
-(void)stopGetFile:(NSString *)fileName;

///删除录音文件
-(void)delFileData:(NSString *)fileName;

///删除全部录音文件
-(void)delAllFileData;

///发送app当前状态 1 app进入前台  2 app进入后台
-(void)sendAppShowState:(int)state;

///返回按键开始录音
-(void)startBtnBackRecord;

///返回按键暂停录音
-(void)pauseBtnBackRecord;

///返回按键继续录音
-(void)continueBtnBackRecord;

///返回按键停止录音
-(void)stopBtnBackRecord;

///获取录音状态
-(void)getRecordState;

///获取文件名称，当录音笔设备是在录音状态的时候，调用此方法
-(void)getFileNameOnlyRecording;

///获取当前录音时长，当录音笔设备是在录音状态的时候，调用此方法
-(void)getTimeOnlyRecording;

/// 获取当前增益
-(void)getDeviceGain;

/// 设置当前增益  参数：gain 值：1：低   2：中   3：高
-(void)setDeviceGain:(int) gain;

//获取版本号
-(void)getDeviceVersion;

//获取版本Code
-(void)getDeviceVersionCode;

//请求进入升级模式
-(void)requestDeviceGotoOtaMode;

//发送文件数据
-(void)sendOtaFile:(NSData *)data;

//获取BK固件版本号
-(void)getBKHDVersion;

//下发BK升级固件URL地址
-(void)setBKUpgradeHD:(NSString *)url;

///打开WiFi
-(void)openWiFi;

///关闭WiFi
-(void)closeWiFi;

///获取设备热点连接状态，是否有手机连接上设备WiFi热点
-(void)getWiFiHotspotState;

///连接设备WiFi
-(void)connectDeviceWiFi;

///断开设备WiFi连接
-(void)disconnectDeviceWiFi;

///获取app与设备TCP/IP连接状态
-(void)getDeviceWiFiState;

/// 获取当前设备是否低功耗录音模式
-(void)getDeviceLowPowerRecordMode;

/// 设置当前设备低功耗录音模式
-(void)setDeviceLowPowerRecordMode:(int)state;

@end
