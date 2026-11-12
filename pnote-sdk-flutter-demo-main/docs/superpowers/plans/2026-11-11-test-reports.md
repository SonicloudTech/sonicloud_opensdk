# Test Reports Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 持续保存自动化测试 txt 报告，并统一音频和报告的系统分享。
**Architecture:** runner 通过可注入的 onReport 文本回调输出统计；TestReportStore 串行追加并保留失败写入；FileSharer 提供缓存快照和通用原生分享通道。
**Tech Stack:** Flutter/Dart、Android FileProvider/ACTION_SEND、iOS UIActivityViewController。
**Spec:** ../specs/2026-11-11-test-reports-design.md

## Global Constraints
- 同一个 txt 持续追加，使用实际换行、手机本地开始时间和 HH:mm:ss 耗时。
- 原生分享只打开系统选择面板，由用户选择接收应用。
- 不改变现有测试调度和音频编码，不作无关格式变更。
- 当前工作区有未提交用户改动，直接增量修改，不创建工作树或提交。

## Review Focus
- 取消、断连与失败都写入报告，写盘失败不改变设备测试结果。
- 多次测试和应用重启不会覆盖旧报告，分享等待待写内容完成。
- 共享文件被微信/QQ 延迟读取时仍保持稳定，限制 FileProvider 可共享目录。
- 设备断开后仍可分享报告，窄屏下设备信息和分享按钮同排。
- 实际字节/秒计算包含不足一秒、无速度样本和零字节情况。

### Task 1: Report storage and generic sharing
- [x] Add test/test_report_test.dart: ordered append, reopen persistence, failed-write retry, duration/rate formatting.
- [x] Update test/audio_export_test.dart: generic shareFile payload, stable snapshots and failure cleanup; watch failures.
- [x] Implement lib/test_report.dart and lib/service_file_share.dart; replace audio export save API with generic share.
- [x] Run targeted tests, then update native handlers and Android FileProvider configuration; validate native builds.

### Task 2: Runner statistics
- [x] Add report assertions in file_transfer_test_runner_test.dart and ota_automation_runner_test.dart for success/failure/interruption.
- [x] Add optional void Function(String)? onReport to both runner constructors; emit headers, each attempt and totals.
- [x] Read provider numeric rate bounds through a public snapshot API; use measured elapsed time and actual bytes.
- [x] Run runner tests and verify all result paths.

### Task 3: Test page and integration
- [x] Update demo_home_tabs_test.dart for the new title, top header and report share button; watch failure.
- [x] Connect one shared TestReportStore in main.dart and DemoTestPage; move device identity out of OTA card.
- [x] Run full Flutter suite, scoped analysis and Android/iOS compile checks; report the pre-existing widget_test.dart Opus failure separately.
- [x] Request final review of only this task's changes, address important findings, record validation.


## Validation ledger
- Task 1: storage/share tests passed (10 tests after review fixes). Existing audio validation still passes.
- Task 2: transfer and OTA runner tests passed (20 tests), including success/failure/interrupt report rows.
- Task 3: narrow-screen header/layout and OTA tests passed. Final full Flutter suite: 105 passed, 1 pre-existing failure (`test/widget_test.dart`, Counter increments smoke test, Opus not initialized).
- Scoped Dart analysis: no errors/warnings; 8 existing informational findings.
- Android `:app:compileNormalDebugKotlin`: BUILD SUCCESSFUL, 137 tasks. iOS `flutter build ios --debug --no-codesign`: built Runner.app.
- Final independent review identified two P2 findings: concurrent report append/copy and duplicate rows after partial write/flush/close failure. Both fixed with queued snapshot creation and original-offset recovery; new regression tests passed.
- Native system share panels compiled; WeChat/QQ receiving must be checked on a phone with those apps installed.
- No commits made because the checkout contains user-owned changes (including pubspec version changes).
