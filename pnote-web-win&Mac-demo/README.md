# 声云 录音卡 / CB08 录音笔处理程序

**Language / 语言:** The Web console supports `中文` and `English`; switch languages from the selector in the top-right corner.

基于《CB08 通讯协议 V1.0》（`docs/协议.md`）实现的录音笔 BLE 桌面处理程序：
Python + [bleak](https://github.com/hbldh/bleak)，提供**命令行 REPL** 和 **Web 控制台**两套界面，
覆盖协议全部 4 个命令类型，并集成本地离线语音转文字（FunASR SenseVoiceSmall）。

已在真机（声云 录音卡，广播名 CB08）上完整验证：扫描 → 连接 → 巡检 → 列表 → 下载 → 转文字。

## 功能一览

| 分类 | 功能 |
| --- | --- |
| 设备信息 | 电量 / 存储容量 / 固件版本 / 授权码 / 时间同步（连接后自动） |
| 文件操作 | 文件列表、WAV/OPUS 下载（候选名自动回退）、断点续传、2-12 分段下载、单个/全部删除（二次确认） |
| 实时转写 | 实时音频推流（OPUS 码流落盘）、暂停 / 继续 / 停止 |
| 录音控制 | 远程开始 / 保存 / 暂停 / 继续，状态 / 时长 / 文件名查询，增益查询与设置 |
| 语音转文字 | 本地离线识别（SenseVoiceSmall + VAD），结果存同名 `.txt` |
| 调试 | 只读安全巡检（smoke）、任意命令封包直发（raw / rawframe）、机身按键事件监听 |
| Web 界面 | 以上全部功能的浏览器版，附下载进度条、WAV 在线试听、实时事件推送 |

## 目录结构

```
record/
├── main.py                  # 程序入口（REPL / --web）
├── requirements.txt         # 核心依赖（仅 bleak）
├── requirements-asr.txt     # 转文字可选依赖（funasr/torch 等）
├── requirements-web.txt     # Web 界面可选依赖（fastapi/uvicorn）
├── recorder/
│   ├── protocol.py          # 协议层：帧构造/流式解析/CRC/文件列表解码/WAV 检查
│   ├── crc16.py             # CRC-16/XMODEM
│   ├── ble.py               # BLE 传输层（bleak 封装，MTU 分片/整帧单写）
│   ├── device.py            # 设备高层逻辑（请求应答匹配、下载/实时/录音会话）
│   ├── asr.py               # 本地离线语音转文字（可选功能）
│   ├── web.py               # Web 后端（FastAPI + WebSocket，可选功能）
│   └── cli.py               # 命令行 REPL
├── web/                     # Web 前端静态页面（无构建工具链）
├── tests/                   # 单元测试（协议 + 设备层模拟 + asr + web）
├── tools/fetch_vendor_page.py  # 抓取厂家测试页源码的临时脚本
└── docs/
    ├── 协议.md              # 通讯协议文档（本项目实现依据）
    └── vendor_page/         # 厂家测试页 https://sinicloud.com 源码存档
```

## 安装

需要 Python 3.10+，Windows / macOS / Linux 均可（依赖系统蓝牙适配器支持 BLE）。

```bash
# 核心功能（连接/下载/录音控制等）
pip install -r requirements.txt

# 可选：语音转文字功能
pip install -r requirements-asr.txt

# 可选：Web 界面
pip install -r requirements-web.txt
```

> 转文字依赖注意：torchaudio 大版本必须与已安装的 torch 配对
> （如 torch 2.9.x ↔ torchaudio 2.9.x），否则导入时报 WinError 127。
> 首次执行 `transcribe` 会从 ModelScope 自动下载 SenseVoiceSmall 模型
> （约 900MB，缓存于 `~/.cache/modelscope`），之后完全离线。

## 快速开始

```bash
python main.py            # 启动 REPL（下载保存到 ./downloads）
python main.py -o out     # 指定下载目录
python main.py -v         # 输出调试日志（含收发帧 hex）
python main.py --web      # 启动 Web 界面（默认 http://127.0.0.1:8000）
python main.py --web --port 9000   # 指定端口
```

Web 界面在浏览器中提供与 REPL 等价的全部功能：扫描连接、巡检、文件
列表/下载（带进度条）/删除、转写、WAV 在线试听、实时推流、录音控制、
增益、raw 调试；下载进度与机身按键事件通过 WebSocket 实时推送。

真机典型流程（REPL）：

```
record> scan              # 扫描（找不到时试 scan compat）
record> connect 0
record> smoke             # 只读巡检，安全无写入
record> list
record> download 0        # 下载为 WAV，自动校验 RIFF 声明长度
record> transcribe 0      # 语音转文字（未下载会先自动下载）
```

## 命令参考

```
连接管理
  scan [秒] [compat]      扫描录音笔（compat 列出全部有名设备，
                          兼容广播不带服务 UUID 的固件）
  connect <序号|地址>      连接扫描结果中的设备
  disconnect / status     断开 / 查看连接状态与 MTU

设备信息
  smoke                   只读项巡检（电量/容量/固件/授权码/录音状态/
                          时长/文件名/增益/文件列表）
  info | battery | capacity | version | auth | synctime

文件操作
  list                    拉取文件列表
  download <序号|all> [offset] [文件名]
                          下载（WAV 优先自动候选名；offset 续传时
                          不换候选名；下载中 Ctrl+C 发送 2-7 终止）
  seg <序号> <start> <end>  2-12 分段下载指定字节范围
  transcribe <序号|all|本地文件> [auto|zh|en|yue|ja|ko]
                          语音转文字，结果存同名 .txt
  delete <序号> / deleteall  删除（输入 yes 确认，不可恢复）

实时转写
  rt start|stop|pause|resume   实时音频推流（OPUS 码流保存到本地）

录音控制
  rec start|save|pause|resume|state|time|name
  gain [1|2|3]            查询或设置增益（1低 2中 3高）

调试
  raw <type> <cmd> [参数hex]    按协议封包发送任意命令
  rawframe <完整帧hex>          直接发送完整帧（抓包复现）
```

## 协议实现要点

- **帧格式**：`[0x5A][SEQ][CRC:2B LE][LEN:2B LE][DATA=TYPE+CMD+PARAMS]`；
  CRC-16/XMODEM，计算范围 = LEN 原始 2 字节 + DATA
- **GATT**：Service `0xAE20`；AE21 写（无应答）、AE22 主通知（先订阅）、AE23 按键通知；
  AE22/AE23 各自独立的流式解析缓存，支持半帧/多帧/噪声重同步，LEN>8192 视为假帧头
- **下载（2-2）**：`offset:4B LE + filename:24B NUL 填充`，共 36B **必须一次 GATT 写入**（拆包设备返回 code=1）；
  候选名顺序 `base.wav → base.opus → 原始截断名`，仅 code=1 且未收到数据时换名
- **文件列表**：`count:4B BE + N×28B(time:4B BE + size:4B BE + name:20B)`；
  个别固件 time 字段为 Unix 时间戳，按启发式区分显示
- **超时策略**：普通命令 5s；列表无 CMD=18 收尾帧时空闲 1.2s 返回；下载空闲 12s；
  删除应答 3s（旧固件可能不回，按已发送处理）
- **落盘安全**：同名文件自动加 `_时长s_大小` 后缀，不覆盖已有文件

实现与厂家官方测试页（<https://sinicloud.com>，源码存档于 `docs/vendor_page/`）
逐段比对过，核心协议逻辑互相印证。

## 测试

```bash
python -m unittest discover tests -v
```

40 项测试，无需真机、无需蓝牙：

- `test_protocol.py` — 帧构造/解析、CRC 校验向量、协议 7.3 节真机 36B 帧逐字节复现、
  文件列表大端解码、WAV 检查、时间戳启发式
- `test_device.py` — FakeTransport 模拟设备端到端：请求应答匹配、多帧列表组装、
  下载会话与候选名回退、续传不换名、分段下载、删除兼容
- `test_asr.py` — 转文字模块的依赖缺失兜底
- `test_web.py` — Web 层 REST 接口（状态/参数校验/目录穿越防护/静态文件）
  与模拟设备调用链

## 常见问题

- **扫不到设备**：确认录音笔未被手机 App 占用；试 `scan compat` 列出全部设备手动选择
- **`transcribe` 报未安装 funasr**：执行 `pip install -r requirements-asr.txt`
- **torchaudio 导入报 WinError 127**：torch 与 torchaudio 版本不配对，
  安装与 torch 同号的 torchaudio（如 `pip install torchaudio==2.9.1`）
- **REPL 中输入 Windows 路径**：反斜杠、正斜杠均可；含空格的路径用引号包住
