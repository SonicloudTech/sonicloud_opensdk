(() => {
  "use strict";

  const $ = (id) => document.getElementById(id);
  let connected = false;
  let currentFiles = [];
  const messages = {
    "zh-CN": { pageTitle: "QS668 录音笔 Web 控制台", brandTitle: "声云录音卡 控制台", brandEyebrow: "BLE 控制台 · AE20", language: "语言", disconnected: "未连接", connected: "已连接", connection: "连接管理", scan: "扫描", compatScan: "兼容扫描（列出全部设备）", disconnect: "断开", deviceInfo: "设备信息", batteryCapacityFirmware: "电量/容量/固件", readOnlyCheck: "只读巡检", syncTime: "同步时间", deviceFiles: "设备文件", refreshList: "刷新列表", abortTransfer: "终止传输(2-7)", deleteAll: "删除全部", transcriptionLanguage: "转写语言", durationTime: "时长/时间", size: "大小", fileName: "文件名", actions: "操作", advanced: "高级：", index: "序号", resumeDownload: "续传下载", segmentDownload: "分段下载(2-12)", localFiles: "本地文件", refreshLocal: "刷新本地列表", transcriptionResult: "转写结果", liveTranscription: "实时转写", start: "开始", pause: "暂停", resume: "继续", stop: "停止", recordingControl: "录音控制", startRecording: "开始录音", save: "保存", state: "状态", duration: "时长", gain: "增益", low: "1 低", medium: "2 中", high: "3 高", set: "设置", get: "查询", debug: "调试", paramsHex: "参数 hex", paramsPlaceholder: "如 01ff，可空", fullFrameHex: "完整帧 hex", framePlaceholder: "5a 03 9e 20 1e 00 02 02 ...", sendCommand: "发送命令", sendFrame: "直发帧", logs: "日志", clear: "清空", scanProgress: "扫描中（6 秒）...", noDevice: "未发现录音笔；可勾选兼容扫描重试", connecting: "连接中...", connectedAndSynced: "已连接并同步时间", connectedNoSync: "已连接（时间同步失败）", download: "下载", transcribe: "转写", delete: "删除", noLocalFiles: "（无本地文件）", confirmDelete: "确认删除设备上的 {name}？此操作不可恢复", confirmDeleteAll: "确认删除设备上的全部录音？此操作不可恢复", pageLoaded: "页面已加载。请先扫描并连接录音笔。" },
    "en-US": { pageTitle: "QS668 Recorder Web Console", brandTitle: "SoniCloud Recorder Console", brandEyebrow: "BLE Console · AE20", language: "Language", disconnected: "Disconnected", connected: "Connected", connection: "Connection", scan: "Scan", compatScan: "Compatibility scan (show all devices)", disconnect: "Disconnect", deviceInfo: "Device information", batteryCapacityFirmware: "Battery / capacity / firmware", readOnlyCheck: "Read-only check", syncTime: "Sync time", deviceFiles: "Device files", refreshList: "Refresh list", abortTransfer: "Abort transfer (2-7)", deleteAll: "Delete all", transcriptionLanguage: "Transcription language", durationTime: "Duration / time", size: "Size", fileName: "File name", actions: "Actions", advanced: "Advanced:", index: "Index", resumeDownload: "Resume download", segmentDownload: "Segment download (2-12)", localFiles: "Local files", refreshLocal: "Refresh local list", transcriptionResult: "Transcription result", liveTranscription: "Live transcription", start: "Start", pause: "Pause", resume: "Resume", stop: "Stop", recordingControl: "Recording control", startRecording: "Start recording", save: "Save", state: "State", duration: "Duration", gain: "Gain", low: "1 Low", medium: "2 Medium", high: "3 High", set: "Set", get: "Get", debug: "Debug", paramsHex: "Params hex", paramsPlaceholder: "e.g. 01ff, optional", fullFrameHex: "Full frame hex", framePlaceholder: "5a 03 9e 20 1e 00 02 02 ...", sendCommand: "Send command", sendFrame: "Send frame", logs: "Logs", clear: "Clear", scanProgress: "Scanning (6 seconds)...", noDevice: "No recorder found; enable compatibility scan and try again", connecting: "Connecting...", connectedAndSynced: "Connected and time synchronized", connectedNoSync: "Connected (time sync failed)", download: "Download", transcribe: "Transcribe", delete: "Delete", noLocalFiles: "(No local files)", confirmDelete: "Delete {name} from the device? This cannot be undone", confirmDeleteAll: "Delete all recordings from the device? This cannot be undone", pageLoaded: "Page loaded. Scan and connect a recorder to begin." }
  };
  let locale = localStorage.getItem("sonicloud-locale") || (navigator.language.toLowerCase().startsWith("zh") ? "zh-CN" : "en-US");
  const t = (key, vars = {}) => Object.keys(vars).reduce((s, k) => s.replace(`{${k}}`, vars[k]), (messages[locale] || messages["en-US"])[key] || key);
  function applyI18n() {
    document.documentElement.lang = locale;
    document.title = t("pageTitle");
    document.querySelectorAll("[data-i18n]").forEach((el) => { el.textContent = t(el.dataset.i18n) || el.textContent; });
    document.querySelectorAll("[data-i18n-placeholder]").forEach((el) => { el.placeholder = t(el.dataset.i18nPlaceholder) || el.placeholder; });
    if ($("uiLang")) $("uiLang").value = locale;
    if ($("connBadge")) $("connBadge").textContent = connected ? t("connected") : t("disconnected");
  }

  // ------------------------------------------------ 基础工具

  function log(level, text) {
    const div = document.createElement("div");
    div.className = `line ${level.toLowerCase()}`;
    const ts = new Date().toLocaleTimeString(locale, { hour12: false });
    div.textContent = `[${ts}] [${level}] ${text}`;
    $("log").appendChild(div);
    $("log").scrollTop = $("log").scrollHeight;
  }

  async function api(path, body, method) {
    const opts = { method: method || (body === undefined ? "GET" : "POST") };
    if (body !== undefined) {
      opts.headers = { "Content-Type": "application/json" };
      opts.body = JSON.stringify(body);
    }
    const resp = await fetch(path, opts);
    let data = null;
    try { data = await resp.json(); } catch (e) { /* 空响应 */ }
    if (!resp.ok) {
      throw new Error((data && data.error) || `HTTP ${resp.status}`);
    }
    return data;
  }

  // 按钮防重入：执行期间禁用并显示等待样式
  async function run(btn, fn) {
    if (btn) { btn.disabled = true; btn.classList.add("busy"); }
    try {
      await fn();
    } catch (err) {
      log("ERR", err.message);
    } finally {
      if (btn) { btn.disabled = false; btn.classList.remove("busy"); }
      refreshNeedConn();
    }
  }

  function setConnected(on, mtu, payload) {
    connected = on;
    $("connBadge").textContent = on ? t("connected") : t("disconnected");
    $("connBadge").className = `badge ${on ? "on" : "off"}`;
    $("disconnectBtn").disabled = !on;
    $("mtuText").textContent = on ? `MTU=${mtu}，单写上限=${payload}B` : "";
    refreshNeedConn();
  }

  function refreshNeedConn() {
    document.querySelectorAll("[data-need-conn]").forEach((b) => {
      if (!b.classList.contains("busy")) b.disabled = !connected;
    });
  }

  // ------------------------------------------------ WebSocket 推送

  function openWs() {
    const proto = location.protocol === "https:" ? "wss" : "ws";
    const ws = new WebSocket(`${proto}://${location.host}/ws`);
    ws.onmessage = (ev) => {
      const msg = JSON.parse(ev.data);
      if (msg.type === "log") {
        log(msg.level, msg.text);
      } else if (msg.type === "progress") {
        showProgress(msg.received, msg.expected);
      } else if (msg.type === "realtime") {
        if (msg.event === "bytes") $("rtInfo").textContent = `已接收码流 ${msg.text}`;
        if (msg.event === "filename") log("INFO", `实时录音文件名：${msg.value}`);
        if (msg.event === "state") log("INFO", `实时状态：${msg.value}`);
      } else if (msg.type === "device_event") {
        log("EVENT", `设备事件：${msg.desc} body=${msg.body}`);
      }
    };
    ws.onclose = () => setTimeout(openWs, 2000);   // 断线自动重连
  }

  function showProgress(received, expected) {
    $("progressWrap").classList.remove("hidden");
    const pct = expected > 0 ? Math.min(received / expected * 100, 100) : 0;
    $("progressBar").style.width = `${pct}%`;
    $("progressText").textContent = expected > 0
      ? `${fmtSize(received)} / ~${fmtSize(expected)} (${pct.toFixed(0)}%)`
      : fmtSize(received);
  }

  function fmtSize(n) {
    if (n >= 1048576) return `${(n / 1048576).toFixed(1)} MB`;
    if (n >= 1024) return `${(n / 1024).toFixed(1)} KB`;
    return `${n} B`;
  }

  // ------------------------------------------------ 连接管理

  $("scanBtn").onclick = () => run($("scanBtn"), async () => {
    log("INFO", t("scanProgress"));
    const devices = await api("/api/scan",
      { timeout: 6, compat: $("compatChk").checked });
    const list = $("deviceList");
    list.innerHTML = "";
    if (!devices.length) {
      log("WARN", t("noDevice"));
      return;
    }
    devices.forEach((d) => {
      const btn = document.createElement("button");
      btn.textContent = `${d.name}  ${d.address}`;
      btn.onclick = () => run(btn, async () => {
        log("INFO", t("connecting"));
        const r = await api("/api/connect", { target: d.index });
        setConnected(true, r.mtu, r.payload);
        log("OK", r.time_synced ? t("connectedAndSynced") : t("connectedNoSync"));
      });
      list.appendChild(btn);
    });
  });

  $("disconnectBtn").onclick = () => run($("disconnectBtn"), async () => {
    await api("/api/disconnect", {});
    setConnected(false);
  });

  // ------------------------------------------------ 设备信息

  $("infoBtn").onclick = () => run($("infoBtn"), async () => {
    const r = await api("/api/info");
    renderKv([["电量", r.battery], ["容量", r.capacity], ["固件", r.version], ["授权码", r.auth]]);
  });

  $("smokeBtn").onclick = () => run($("smokeBtn"), async () => {
    log("INFO", "开始只读巡检...");
    const rows = await api("/api/smoke", {});
    renderKv(rows.map((r) => [r.label, r.value, r.ok]));
    rows.forEach((r) => log(r.ok ? "OK" : "WARN", `${r.label}：${r.value}`));
    await loadFiles();   // 巡检里已拉过列表，同步到表格
  });

  $("synctimeBtn").onclick = () => run($("synctimeBtn"), async () => {
    const r = await api("/api/synctime", {});
    log("OK", r.message);
  });

  function renderKv(rows) {
    const panel = $("infoPanel");
    panel.innerHTML = "";
    rows.forEach(([k, v, ok]) => {
      const div = document.createElement("div");
      div.className = ok === false ? "bad" : "";
      const b = document.createElement("b");
      b.textContent = k;
      div.append(b, document.createTextNode(String(v)));
      panel.appendChild(div);
    });
  }

  // ------------------------------------------------ 设备文件

  async function loadFiles() {
    const files = await api("/api/status").then((s) => s.files);
    renderFiles(files);
  }

  function renderFiles(files) {
    currentFiles = files || [];
    $("fileTable").classList.toggle("hidden", !files.length);
    const tbody = $("fileRows");
    tbody.innerHTML = "";
    files.forEach((f) => {
      const tr = document.createElement("tr");
      // 文件名来自设备，用 textContent 防注入
      [String(f.index), f.time_text, f.size_text, f.name].forEach((v, i) => {
        const cell = document.createElement("td");
        cell.textContent = v;
        if (i === 3) cell.className = "mono";
        tr.appendChild(cell);
      });
      const td = document.createElement("td");
      td.append(
        mkBtn(t("download"), (btn) => run(btn, () => download(f.index, 0))),
        mkBtn(t("transcribe"), (btn) => run(btn, () => transcribe({ index: f.index }))),
        mkBtn(t("delete"), (btn) => run(btn, () => deleteOne(f)), "danger"));
      tr.appendChild(td);
      tbody.appendChild(tr);
    });
  }

  function mkBtn(text, onclick, cls) {
    const b = document.createElement("button");
    b.textContent = text;
    b.className = `mini ${cls || ""}`;
    b.onclick = () => onclick(b);
    return b;
  }

  $("filesBtn").onclick = () => run($("filesBtn"), async () => {
    log("INFO", "拉取文件列表...");
    const files = await api("/api/files");
    renderFiles(files);
    log("OK", `共 ${files.length} 个文件`);
  });

  async function download(index, offset) {
    showProgress(0, 0);
    const r = await api("/api/download", { index, offset: offset || 0 });
    let kind = "原始码流";
    if (r.is_wav && r.wav) {
      kind = `WAV ${r.wav.sample_rate}Hz ${r.wav.bits}bit ${r.wav.channels}ch` +
        (r.wav.ok ? "（声明长度一致）" : "（声明长度不一致！）");
    }
    log("OK", `下载完成：${r.local_name}  ${r.size_text}  ${kind}`);
    await loadLocal();
  }

  $("advDownloadBtn").onclick = () => run($("advDownloadBtn"), () =>
    download(Number($("advIndex").value), Number($("advOffset").value)));

  $("segBtn").onclick = () => run($("segBtn"), async () => {
    const r = await api("/api/segment", {
      index: Number($("advIndex").value),
      start: Number($("segStart").value),
      end: Number($("segEnd").value),
    });
    log("OK", `分段下载完成：${r.local_name}  ${r.size_text}`);
    await loadLocal();
  });

  $("abortBtn").onclick = () => run($("abortBtn"), async () => {
    const r = await api("/api/abort", {});
    log("OK", r.message);
  });

  async function deleteOne(f) {
    if (!confirm(t("confirmDelete", { name: f.name }))) return;
    const r = await api("/api/delete", { index: f.index });
    log("OK", r.message);
    const files = await api("/api/files");
    renderFiles(files);
  }

  $("deleteAllBtn").onclick = () => run($("deleteAllBtn"), async () => {
    if (!confirm(t("confirmDeleteAll"))) return;
    const r = await api("/api/deleteall", {});
    log("OK", r.message);
    renderFiles([]);
  });

  // ------------------------------------------------ 转写 / 本地文件

  async function transcribe(target) {
    log("INFO", "转写中（首次使用需下载并加载模型，请耐心等待）...");
    const r = await api("/api/transcribe",
      Object.assign({ language: $("langSel").value }, target));
    $("transcribeOut").classList.remove("hidden");
    $("transcribeText").textContent =
      `【${r.source}】\n${r.text || "（未识别到语音）"}`;
    log("OK", `转写完成，文本已保存：${r.txt}`);
    await loadLocal();
  }

  async function loadLocal() {
    const files = await api("/api/local");
    const list = $("localList");
    list.innerHTML = "";
    files.forEach((f) => {
      const div = document.createElement("div");
      div.className = "local-item";
      const url = `/downloads/${encodeURIComponent(f.name)}`;
      const a = document.createElement("a");
      a.href = url;
      a.target = "_blank";
      a.className = "mono";
      a.textContent = f.name;
      const size = document.createElement("span");
      size.className = "muted";
      size.textContent = ` ${f.size_text}`;
      div.append(a, size);
      if (f.kind === "wav") {
        const audio = document.createElement("audio");
        audio.controls = true;
        audio.preload = "none";
        audio.src = url;
        div.appendChild(audio);
        div.appendChild(mkBtn("转写", (btn) =>
          run(btn, () => transcribe({ name: f.name }))));
      }
      list.appendChild(div);
    });
    if (!files.length) {
      const empty = document.createElement("span");
      empty.className = "muted";
      empty.textContent = t("noLocalFiles");
      list.appendChild(empty);
    }
  }

  $("localBtn").onclick = () => run($("localBtn"), loadLocal);

  // ------------------------------------------------ 实时 / 录音 / 增益

  document.querySelectorAll("[data-rt]").forEach((btn) => {
    btn.onclick = () => run(btn, async () => {
      if (btn.dataset.rt === "start") $("rtInfo").textContent = "";
      const r = await api("/api/rt", { action: btn.dataset.rt });
      log("OK", r.message);
      if (btn.dataset.rt === "stop") await loadLocal();
    });
  });

  document.querySelectorAll("[data-rec]").forEach((btn) => {
    btn.onclick = () => run(btn, async () => {
      const r = await api("/api/rec", { action: btn.dataset.rec });
      log("OK", r.message);
    });
  });

  $("gainSetBtn").onclick = () => run($("gainSetBtn"), async () => {
    const r = await api("/api/gain", { level: Number($("gainSel").value) });
    log("OK", r.message);
  });

  $("gainGetBtn").onclick = () => run($("gainGetBtn"), async () => {
    const r = await api("/api/gain");
    log("OK", `当前增益：${r.text}`);
  });

  // ------------------------------------------------ 调试

  $("rawBtn").onclick = () => run($("rawBtn"), async () => {
    const r = await api("/api/raw", {
      type: Number($("rawType").value),
      cmd: Number($("rawCmd").value),
      params: $("rawParams").value.trim(),
    });
    log("OK", r.message);
  });

  $("rawFrameBtn").onclick = () => run($("rawFrameBtn"), async () => {
    const r = await api("/api/rawframe", { hex: $("rawFrame").value.trim() });
    log("OK", r.message);
  });

  $("clearLogBtn").onclick = () => { $("log").innerHTML = ""; };

  // ------------------------------------------------ 启动

  $("uiLang").addEventListener("change", (event) => {
    locale = event.target.value;
    localStorage.setItem("sonicloud-locale", locale);
    applyI18n();
    renderFiles(currentFiles);
    loadLocal().catch((err) => log("ERR", err.message));
  });
  applyI18n();
  openWs();
  api("/api/status").then((s) => {
    setConnected(s.connected, s.mtu, s.payload);
    renderFiles(s.files || []);
    return loadLocal();
  }).catch((err) => log("ERR", err.message));
  log("INFO", t("pageLoaded"));
})();
