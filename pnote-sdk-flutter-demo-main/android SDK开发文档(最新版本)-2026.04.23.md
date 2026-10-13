# SDK开发文档

接口说明更新：2026-10-13。

## 一、集成SDK

###1.复制pnot*.aar到项目的/libs目录下（ *表示具体的版本号）

###2.添加依赖 
    dependencies {

    implementation fileTree(dir: 'src\\main\\libs', include: ['*.aar', '*.jar'], exclude: [])
    
    //SDK 依赖的第三方库
    implementation 'com.polidea.rxandroidble2:rxandroidble:1.17.2'
    implementation 'io.reactivex.rxjava2:rxandroid:2.1.1'
    implementation 'io.reactivex.rxjava2:rxjava:2.2.8'
    
    implementation 'com.squareup.retrofit2:retrofit:2.5.0'
    implementation 'com.squareup.retrofit2:adapter-rxjava2:2.5.0'
    implementation 'com.squareup.retrofit2:converter-gson:2.5.0'
    implementation 'com.squareup.retrofit2:converter-scalars:2.5.0'
    
    implementation "io.reactivex.rxjava3:rxjava:3.1.8"
    
    implementation 'org.greenrobot:eventbus:3.3.1'
    implementation 'org.greenrobot:greendao:3.2.2'
    implementation 'com.koushikdutta.async:androidasync:3.1.0'
    
    }

## 二、SDK初始化

/*初始化 
*Context context 上下文  
*DeviceDataListener deviceDataListener  数据回调的接口对象
*/ 
public static void init(Context context, DeviceDataListener deviceDataListener);

//设备回调的接口，需要实现
public interface DeviceDataListener {
    public void onDeviceDataEvent(String data);   /// 设备数据回调
    public void onDeviceRecordData(byte[] data);  ///设备实时录音数据 opus格式
    public void onDeviceFileData(byte[] data);   ///设备文件数据 opus格式
}

## 三.方法说明

### 1、搜索、连接

    /// 开始搜索
    public static void startSearch();
    
    结果在onDeviceDataEvent接口返回，搜索json交互：
    格式：
    {
      "cmd":"cmd",
      "state":"state",
      "data":
      {
        "name":"name",
        "address":"address",
        "productType":"productType",
    
      }
    }
    说明：
    名称    描述
    cmd    标记：1
    state    标记：0 表示正常，非0表示异常
    name    蓝牙名称
    address    蓝牙地址
    productType    产品类型
    
    
    /// 停止搜索
    public static void stopSearch();
    
    ///是否连接设备
    public static void isDeviceConnected();
    
    /// 连接设备 参数：设备名称  设备mac地址
    public static void connectDevice(String name, String address);
    
    /// 断开连接
    public static void closeConnect();
    
    结果在onDeviceDataEvent接口返回，连接与断开连接的json交互：
    格式：
    {
      "cmd":"cmd",
      "state":"state",
      "data":
      {
        "connect_state":"connect_state",
        "name":"name",
        "address":"address"
      }
    }
    说明：
    名称    描述
    cmd    标记：2
    state    标记：0 表示正常，非0表示异常
    connect_state    1表示连接成功，0表示连接断开
    name    蓝牙名称
    address    蓝牙地址
    
    注：如果设备端关机等情况断开连接，SDK也会主动上报断开连接的数据；

#### AuthKey 认证（C10）

以下接口用于支持 AuthKey 的设备，调用前需完成 SDK 初始化并保持蓝牙连接。

```java
/// 蓝牙连接后进行 AuthKey 认证
public static void authkeyConnect(String authkey);
```

`authkey` 为 64 位十六进制字符，对应 32 字节密钥；允许大小写十六进制字符、可选的 `0x` / `0X` 前缀和首尾空白。前缀不计入 64 位长度，传入字符串即可，由 SDK 校验并转换为字节。

Android SDK 对无效参数抛出 `IllegalArgumentException`，不发送认证指令。

结果通过 `onDeviceDataEvent(String data)` 异步返回：

| 方法 | cmd | data 字段 | 功能 |
| --- | --- | --- | --- |
| authkeyConnect | 31 | authkey_state | 使用设备当前 AuthKey 认证 |

认证结果格式示例：

```json
{
  "cmd": "31",
  "state": "0",
  "data": {
    "authkey_state": "0"
  }
}
```

调用示例：

```java
// 在蓝牙连接成功回调后调用，示例值需替换成设备当前 AuthKey。
String authkey = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff";
PNote.authkeyConnect(authkey);
```

AuthKey 调用流程：蓝牙连接成功 → 调用 `authkeyConnect` 使用设备当前 AuthKey 认证 → 等待 `cmd=31` 回调并确认认证成功 → 执行需要认证的设备操作。

### 2、录音

    /// 获取录音笔录音状态
    public static void getRecordState();
    
    结果在onDeviceDataEvent接口返回，json格式：
    {
      "cmd":"cmd",
      "state":"state",
      "data":
      {
        "recordState":" recordState"
      }
    }
    说明：
    名称    描述
    cmd    标记：9
    state    标记：0 表示正常，非0表示异常
    recordState    1  小机在录音状态 2小机不在录音状态
    
    
    /// 获取录音笔正在录音中时候的录音文件名称
    public static void getFileNameOnlyRecording();
    
    结果在onDeviceDataEvent接口返回，json格式：
    {
      "cmd":"cmd",
      "state":"state",
      "data":
      {
        "recordName":" recordName"
      }
    }
    说明：
    名称    描述
    cmd    标记：11
    state    标记：0 表示正常，非0表示异常
    recordName    文件名称
    
    
    ///获取当前录音时长，当录音笔设备是在录音状态的时候
    public static void getTimeOnlyRecording();
    
    结果在onDeviceDataEvent接口返回，json格式：
    {
      "cmd":"cmd",
      "state":"state",
      "data":
      {
        "recordTime":" recordTime"
      }
    }
    说明：
    名称    描述
    cmd    标记：10
    state    标记：0 表示正常，非0表示异常
    recordTime    当前录音时长，按秒为单位
    
    
    ** 由app端发起
    
    /// 启动录音
    public static void startRecord();
    
    /// 暂停录音
    public static void pauseRecord();
    
    /// 继续录音
    public static void continueRecord() ;
    
    /// 停止录音
    public static void stopRecord();
    
    结果在onDeviceDataEvent接口返回，录音json交互：
    格式：
    {
      "cmd":"cmd",
      "state":"state",
      "data":
      {
        "record_state":"record_state",
        "fileName":"fileName"
      }
    }
    说明：
    名称    描述
    cmd    标记：3
    state    标记：0 表示正常，非0表示异常
    record_state    0表示没有在录音或者停止录音，1表示正在录音， 2 暂停
    fileName  文件名
    
    录音数据在onDeviceRecordData接口返回，数据是opus格式，16k，单声道，40字节一帧；
    
    ** 由录音笔点击按键发起
    
    当录音笔连接上app的时候，用户点击录音笔的录音按键进行录音，暂停录音、继续录音、保存录音等操作的时候，app端需要返回对应响应，录音笔才会进入对应的操作；
    
    //为了区别app后台及前台，发送app当前状态给录音笔； 1 app进入前台  2 app进入后台，此方法需实现
    public static void sendAppShowState(int state);
    
    /// 返回按键开始录音
    public static void startBtnBackRecord();
    
    /// 返回按键暂停录音
    public static void pauseBtnBackRecord();
    
    /// 返回按键继续录音
    public static void continueBtnBackRecord();
    
    /// 返回按键停止录音
    public static void stopBtnBackRecord() ;
    
    
    录音笔按钮按键json数据：
     格式：
    {
      "cmd":"cmd",
      "state":"state",
      "data":
      {
        "event":"event"
      }
    }
    说明：
    名称    描述
    cmd    标记：8
    state    标记：0 表示正常，非0表示异常
    event    开始录音  1  保存录音 3  暂停录音 5  继续录音 7
    
    当app收到event为1的时候，表示录音笔请求进入录音，app做完成UI及逻辑处理后，调用startBtnBackRecord函数，录音笔进入开始录音操作；
    当app收到event为3的时候，表示录音笔请求停止录音，app做完成UI及逻辑处理后，调用stopBtnBackRecord函数，录音笔进入停止录音操作；
    当app收到event为5的时候，表示录音笔请求暂停录音，app做完成UI及逻辑处理后，调用pauseBtnBackRecord函数，录音笔进入暂停录音操作；
    当app收到event为7的时候，表示录音笔请求继续录音，app做完成UI及逻辑处理后，调用continueBtnBackRecord函数，录音笔进入继续录音操作；

### 3、文件操作

    /// 获取文件列表
    public static void getRecordFileList();
    录音文件名列表json交互：
    格式：
    {
      "cmd":"cmd",
      "state":"state",
      "data":
      [
        {
          "size":"size",
          "time":"time",
          "name":"name"
        }
      ]
    }
    说明：
    名称    描述
    cmd    标记：4
    state    标记：0 表示正常，非0表示异常
    finish    标记：0 表示正在传输，1表示传输完成
    size    文件大小，字节
    time    文件时长，秒
    name    文件名
    
    
    /// 开始传输录音文件，参数fileName  文件名，非空， 参数offset，偏移量，从哪里开始传递，如果整个文件传输，可以传递为0
    public static void startGetFile(String fileName, int offset);
    
    /// 开始传输录音文件  参数fileName  文件名，非空， 参数offset，偏移量，从哪里开始传递，参数end，传递到哪里截止，end 要比offset 大
    public static void startGetFileByFromToEnd(String fileName, int offset, int end);
    
    结果在onDeviceDataEvent接口返回，文件传输数据json格式：
    {
      "cmd":"cmd",
      "state":"state",
      "data":
      {
        "record_file_state":"record_file_state",
        "name":"name"
      }
    }
    说明：
    名称    描述
    cmd    标记：5
    state    标记：0 表示正常，非0表示异常
    record_file_state    0：传输完成； 1：文件不存在； 2：offset过大（预留）； 3：其他停止 4 : 传输中
    name    文件名称
    
    /// 停止传输录音文件  参数fileName  文件名，非空，
    public static void stopGetFile(String fileName);
    
    
    ///删除录音笔文件   参数文件名，文件名非空
    public static void deleteReordFile(String fileName);
    
    ///删除全部录音笔文件
    public static void deleteAllReordFile();
    
    结果在onDeviceDataEvent接口返回，删除单个和删除全部文件json格式：
    {
      "cmd":"cmd",
      "state":"state",
      "data":
      {
        "delete_state":"delete_state"
      }
    }
    说明：
    名称    描述
    cmd    标记：14
    state    标记：0 表示正常，非0表示异常
    delete_state    0：成功； 1：失败；

### 4、WIFI操作管理

    /// 获取是否连接上设备WiFi
    public static void getDeviceWiFiState();
    操作成功后，会在cmd 12的接口返回WiFi状态；
    /// 获取WiFi热点是否被手机连接上
    public static void getWiFiHotspotState();
    操作成功后，会在cmd 12的接口返回WiFi状态:4 有手机连接设备WiFi热点   5当前没有手机连接设备WiFi热点
    /// 打开WiFi
    public static void openWiFi();
    操作成功后，会在cmd 12的接口返回WiFi状态:0表示WiFi热点打开 1 表示WiFi热点关闭
    /// 关闭WiFi
    public static void closeWiFi();
    操作成功后，会在cmd 12的接口返回WiFi状态:0表示WiFi热点打开 1 表示WiFi热点关闭
    /// 连接WiFi
    public static void connectDeviceWiFi();
    操作成功后，会在cmd 12的接口返回WiFi状态：2表示WiFi连接成功，3表示WiFi断开连接
    /// 断开WiFi
    public static void disconnectDeviceWiFi();
    操作成功后，会在cmd 12的接口返回WiFi状态：2表示WiFi连接成功，3表示WiFi断开连接
    
    结果在onDeviceDataEvent接口返回，格式：
    {
        "cmd":"cmd",
        "state":"state",
        "data":
        {
            "wifi_state":" wifi_state",
            "wifiName":" wifiName"
        }
    }
    说明：
    名称    描述
    cmd    标记：12
    state    标记：0 表示正常，非0表示异常
    wifi_state    WiFi状态，0表示WiFi热点打开 1 表示WiFi热点关闭 2表示WiFi连接成功，3表示WiFi断开连接  4 有手机WiFi连接  5当前没有手机连接设备WiFi热点
    wifiName    Wifi名称
    
    当手机连接上设备WiFi热点的时候，设备也会主动推送cmd为12的json数据:4 有手机连接设备WiFi热点；

#### 快速连接设备 Wi-Fi

调用前保持蓝牙连接；需要认证的设备先完成 AuthKey 认证。SDK 打开设备热点、连接热点并建立 TCP，结果通过现有 `cmd=12` 回调返回。只有 `data.wifi_state=2` 才表示 TCP 连接成功，热点打开或手机加入热点的回调不能作为文件传输就绪条件。

```java
/// 打开设备热点并自动连接，默认总超时 30 秒、单次 TCP 超时 10 秒
public static void quickConnectDeviceWiFi();

/// 自定义快速连接超时时间，单位：秒
public static void quickConnectDeviceWiFi(int wifiTimeout, int tcpTimeout);
```

`wifiTimeout` 为快速连接总超时，`tcpTimeout` 为单次 TCP 连接超时。两个参数必须大于 0 且不超过 2147483 秒，并且 `wifiTimeout > tcpTimeout`；否则 SDK 抛出 `IllegalArgumentException`。

宿主 App 需完成对应 Android 版本要求的蓝牙、定位及附近 Wi-Fi 权限授权，并处理系统可能弹出的网络连接确认。

```java
PNote.quickConnectDeviceWiFi(30, 10);
```

当前快速连接接口未提供热点密码入参。已设置密码的热点请使用手动流程：调用 `openWiFi`，从 `cmd=12` 获取 `wifiName`，通过手机系统或 App 的 Wi-Fi 连接能力使用密码加入该热点，加入成功后再调用 `connectDeviceWiFi` 建立 TCP。

#### 设置设备热点密码（C10 新增）

```java
public static void SetWifiPassword(String password);
```

`password` 为 8-16 个字符。调用前保持蓝牙连接；热点已经开启时，新密码在下次开启热点时生效。Android SDK 对无效密码抛出 `IllegalArgumentException`。

结果通过 `onDeviceDataEvent(String data)` 返回：

```json
{
  "cmd": "34",
  "state": "0",
  "data": {
    "wifi_password_state": "0"
  }
}
```

`wifi_password_state` 为设备返回的操作结果 Code，以十进制字符串上报，具体含义以设备固件协议为准；`state=0` 不等同于密码设置成功。收到设备结果并确认成功后，下次连接热点时使用新密码。

此接口修改的是设备自身热点密码。

### 5、OTA部分

    ///获取版本号code
    public static void getDeviceVersionCode();
    结果在onDeviceDataEvent接口返回，格式：
    {
      "cmd":"cmd",
      "state":"state",
      "data":
      {
        "versionCode":"versionCode"
      }
    }
    说明：
    名称    描述
    cmd    标记：18
    state    标记：0 表示正常，非0表示异常
    versionCode    版本code，字符串类似0001这样，主要用于判断比较版本
    
    //请求进入升级模式
    public static void requestDeviceGotoOtaMode();
    结果在onDeviceDataEvent接口返回，格式：
    {
      "cmd":"cmd",
      "state":"state",
      "data":
      {
          "prepareState":"prepareState"
      }
    }
    说明：
    名称    描述
    cmd    标记：19
    state    标记：0 表示正常，非0表示异常
    prepareState    返回状态，0表示已经进入升级状态，
    1 表示不能进入升级状态，主要原因是可能是SD卡或者内存不足；
    2 表示WiFi的TCP/IP未连接，升级模式需要在WiFi连接的状态下才能进行升级；
    
    //发送升级文件数据
    public static void sendOtaFile(byte[] data);
    
    把整个update.ufw文件的数据一次性传递给SDK，由SDK来做分包发送；SDK会返回发送的数据进度
    
    结果在onDeviceDataEvent接口返回，格式：
    {
      "cmd":"cmd",
      "state":"state",
      "data":
      {
        "progress":"progress",
        "total":"total"
    
      }
    }
    说明：
    名称    描述
    cmd    标记：20
    state    标记：0 表示正常，非0表示异常
    progress    当前进度字节；
    total    总字节数
    
    当设备接收完成文件后设备会进入自动升级流程，结果会在下面json返回：
    格式：
    {
      "cmd":"cmd",
      "state":"state",
      "data":
      {
        "receiveState":" receiveState"
      }
    }
    说明：
    名称    描述
    cmd    标记：21
    state    标记：0 表示正常，非0表示异常
    receiveState  0：文件接收完成，准备重启（重启表示不代表升级成功，需要重启完成后建议连接完成蓝牙后获取一次版本code进行比较是否一致
    1：文件接收错误，升级失败；如果WiFi连接或者蓝牙连接断开的时候，设备端会直接退出升级模式；
    
    OTA升级流程，目前这边的升级流程，供参考：
    判断电池电量是否大于 20%
    否 → 提示 “电池电量不足，不能升级” → 流程结束
    是 → 进入下一步
    判断是否连接设备 WiFi
    否 → 提示 “需要先连接设备 WiFi” → 流程结束
    是 → 进入下一步
    APP 调用getDeviceVersionCode获取设备版本 code
    对比 APP 版本 code 和设备版本 code
    APP 版本 code ≤ 设备版本 code → 提示 “无需升级，版本已是最新” → 流程结束
    APP 版本 code > 设备版本 code → 进入下一步
    APP 调用requestDeviceGotoOtaMode让设备进入升级模式
    接收设备回复码
    回复 1 → 提示 “不能进入升级状态（SD 卡 / 内存不足）” → 流程结束
    回复 2 → 提示 “WiFi 的 TCP/IP 未连接，需确保 WiFi 连接” → 流程结束
    回复 0 → 设备正常进入升级模式，进入下一步
    APP 通过sendotaFile函数一次性传输升级数据给 SDK
    监控升级过程中 WiFi / 蓝牙连接状态
    连接断开 → 设备退出升级模式 → 流程结束
    连接正常 → 接收 SDK / 设备回复结果
    处理回复结果
    回复 1 → 提示 “文件接收错误，升级失败” → 流程结束
    回复 0 → 提示 “文件接收完成，设备准备重启” → 进入下一步
    设备重启完成后，重新连接蓝牙
    再次获取设备版本 code 并与 APP 版本 code 对比
    版本 code 一致 → 提示 “升级成功” → 流程结束
    版本 code 不一致 → 提示 “升级失败（版本未更新）” → 流程结束
    
    //获取BK固件版本号
    public static void getBKHDVersion();
    
    //下发BK升级固件URL地址
    public static void setBK_UPGRADEHD(String url);
    
    BK OTA相关结果在onDeviceDataEvent接口返回，格式：
    {
      "cmd":"40",
      "state":"0",
      "data":
      {
        "type":"type",
        "value":"value"
      }
    }
    说明：
    名称    描述
    cmd    标记：40
    state    标记：0 表示正常，非0表示异常

    type    
    01    返回BK固件版本号 
    08    返回升级URL设置结果，0：成功；1：失败
    09    返回固件下载进度 0-100
    0A    返回固件文件校验结果，0：成功；1：失败
    
    BK OTA升级说明：
    APP需要提供设备可访问的HTTP或HTTPS固件下载地址，并在HTTP响应头中返回文件长度Content-Length；
    调用setBK_UPGRADEHD时传入未对完整地址进行URIEncode的URL；如果文件名包含特殊字符，仅对URL路径中的文件名进行编码；
    调用getBKHDVersion获取当前BK固件版本号；
    对比版本后调用setBK_UPGRADEHD下发升级地址；
    通过cmd 40依次处理升级URL设置结果、下载进度和文件校验结果；

### 6、其它

    ///同步时间, 连接上设备后，需要先调用此方法把app时间同步给录音笔设备
    public static void syncTime();
    
    ///获取电池电量
    public static void getCBC();
    
    结果在onDeviceDataEvent接口返回，格式：
    {
      "cmd":"cmd",
      "state":"state",
      "data":
      {
        "cbc":"cbc"
      }
    }
    说明：
    名称    描述
    cmd    标记：6
    state    标记：0 表示正常，非0表示异常
    cbc    电量百分比  0~100 电量百分比   110   充电中
    
    
    ///获取SN码
    public static void getSn();
    格式：
    {
      "cmd":"cmd",
      "state":"state",
      "data":
      {
        "sn":"sn"
      }
    }
    说明：
    名称    描述
    cmd    标记：7
    state    标记：0 表示正常，非0表示异常
    sn    sn码
    
    
    /// 获取容量大小
    public static void getDeviceCapacity();
    
    结果在onDeviceDataEvent接口返回，容量数据返回
    格式：
    {
      "cmd":"cmd",
      "state":"state",
      "data":
      {
        "residueSpace":"residueSpace",
        "totalSpace":"totalSpace"
      }
    }
    说明：
    名称    描述
    cmd    标记：13
    state    标记：0 表示正常，非0表示异常
    residueSpace    剩余空间，KB
    totalSpace    总空间，KB
    
    
    /// 获取当前增益
    public static void getDeviceGain();
    结果在onDeviceDataEvent接口返回，格式：
    {
      "cmd":"cmd",
      "state":"state",
      "data":
      {
        "gain":"gain"
      }
    }
    说明：
    名称    描述
    cmd    标记：15
    state    标记：0 表示正常，非0表示异常
    gain    1：低   2：中   3：高
    
    /// 设置当前增益  参数：gain 值：1：低   2：中   3：高
    public static void setDeviceGain(int gain);
    结果在onDeviceDataEvent接口返回，格式：
    {
      "cmd":"cmd",
      "state":"state",
      "data":
      {
        "gain_state":"gain_state "
      }
    }
    说明：
    名称    描述
    cmd    标记：16
    state    标记：0 表示正常，非0表示异常
    gain_state    0：成功； 1：失败；
    
    ///获取版本号
    public static void getDeviceVersion();
    结果在onDeviceDataEvent接口返回，格式：
    {
      "cmd":"cmd",
      "state":"state",
      "data":
      {
        "version":"version"
      }
    }
    说明：
    名称    描述
    cmd    标记：17
    state    标记：0 表示正常，非0表示异常
    version    版本号，字符串
    
    
    /// 获取当前设备是否低功耗录音模式，此函数主要是用于长时间续航
    public static void getDeviceLowPowerRecordMode();
    结果在onDeviceDataEvent接口返回，格式：
    {
      "cmd":"cmd",
      "state":"state",
      "data":
      {
         "low_power_state":"low_power_state"
      }
    }
    说明：
    名称    描述
    cmd    标记：22
    state    标记：0 表示正常，非0表示异常
    low_power_state    0 不是  1是
    
    
    /// 设置当前设备低功耗录音模式  1是进入低功耗，0 是退出低功耗
    public static void setDeviceLowPowerRecordMode(int state);
    
    结果在onDeviceDataEvent接口返回，格式：
    {
      "cmd":"cmd",
      "state":"state",
      "data":
      {
          "low_power_state":" low_power_state "
      }
    }
    说明：
    名称    描述
    cmd    标记：23
    state    标记：0 表示正常，非0表示异常
    low_power_state    0：设置成功； 1：设置失败；
