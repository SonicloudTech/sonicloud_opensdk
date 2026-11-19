import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'devices_page.dart';
import 'design/battery_level.dart';
import 'design/tokens.dart';
import 'device_detail_page.dart';
import 'l10n/gen/app_localizations.dart';
import 'recording_overlay_page.dart';
import 'recordings_page.dart';
import 'session.dart';

void main() {
  // 关闭 flutter_blue_plus 原生 [FBP] 日志（录音时每帧收发都会刷屏）。
  FlutterBluePlus.setLogLevel(LogLevel.none);
  runApp(const PnoteDemoApp());
}

final session = Session();

/// 语言选项：跟随系统 / English / 中文。
enum LanguageOption { system, english, chinese }

class PnoteDemoApp extends StatefulWidget {
  const PnoteDemoApp({super.key});

  @override
  State<PnoteDemoApp> createState() => _PnoteDemoAppState();
}

class _PnoteDemoAppState extends State<PnoteDemoApp> {
  LanguageOption _language = LanguageOption.system;

  Locale? get _localeOverride {
    switch (_language) {
      case LanguageOption.system:
        return null;
      case LanguageOption.english:
        return const Locale('en');
      case LanguageOption.chinese:
        return const Locale('zh');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PNote Project',
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: _localeOverride,
      // 只提供中英两种文案：系统是中文→中文，其余一律英文。
      localeResolutionCallback: (locale, supported) =>
          locale != null && locale.languageCode.startsWith('zh')
              ? const Locale('zh')
              : const Locale('en'),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
        ),
        scaffoldBackgroundColor: AppColors.bg,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: AppColors.ink,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.border),
          ),
        ),
        // iOS 式 TabBar：无胶囊指示器，选中态用近黑。
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          indicatorColor: Colors.transparent,
          elevation: 1,
          height: 64,
          iconTheme: WidgetStateProperty.resolveWith(
            (s) => IconThemeData(
              color: s.contains(WidgetState.selected)
                  ? AppColors.ink
                  : AppColors.mutedFaint,
            ),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (s) => TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: s.contains(WidgetState.selected)
                  ? AppColors.ink
                  : AppColors.mutedFaint,
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.inkSoft,
            side: const BorderSide(color: Color(0xFFD4D4D8)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      home: HomeShell(
        onLanguageChanged: (v) => setState(() => _language = v),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.onLanguageChanged});

  final ValueChanged<LanguageOption> onLanguageChanged;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  bool _recordingOverlayOpen = false;
  final _recordingsKey = GlobalKey<RecordingsPageState>();

  @override
  void initState() {
    super.initState();
    // 录音开始（App 按钮或笔身物理键）自动弹出录音全屏页。
    session.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (session.recording && !_recordingOverlayOpen && mounted) {
      _recordingOverlayOpen = true;
      Navigator.of(context)
          .push(MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => RecordingOverlayPage(session: session),
          ))
          .whenComplete(() => _recordingOverlayOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    session.l10n = l10n;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PNote Project'),
        actions: [
          _languageMenu(l10n),
          _deviceChip(l10n),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          DevicesPage(session: session),
          RecordingsPage(key: _recordingsKey, session: session),
          // ActivityPage 暂时对客户隐藏（demo 不展示事件/日志），代码保留。
          // ActivityPage(session: session),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          // 录音文件页每次进入自动重新拉取列表。
          if (i == 1) _recordingsKey.currentState?.refresh();
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.bluetooth_outlined),
            selectedIcon: const Icon(Icons.bluetooth),
            label: l10n.tabDevices,
          ),
          NavigationDestination(
            icon: const Icon(Icons.library_music_outlined),
            selectedIcon: const Icon(Icons.library_music),
            label: l10n.tabRecordings,
          ),
        ],
      ),
    );
  }

  /// AppBar 右上角的已连接设备摘要（名称 / 状态 / 电量），点击进设备信息页。
  Widget _deviceChip(AppLocalizations l10n) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final d = session.device;
        if (d == null) return const SizedBox.shrink();
        final battery = session.battery;
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => DeviceDetailPage(session: session),
              )),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    d.name.isEmpty ? l10n.voiceRecorder : d.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink),
                  ),
                ),
                if (battery != null) ...[
                  const SizedBox(width: 5),
                  BatteryLevel(percent: battery.percent),
                ],
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right,
                    size: 16, color: AppColors.borderStrong),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _languageMenu(AppLocalizations l10n) {
    return PopupMenuButton<LanguageOption>(
      tooltip: l10n.tooltipLanguage,
      icon: const Icon(Icons.language, size: 22, color: Color(0xFF64748B)),
      onSelected: widget.onLanguageChanged,
      itemBuilder: (_) => [
        PopupMenuItem(
          value: LanguageOption.system,
          child: Text(l10n.languageSystem),
        ),
        PopupMenuItem(
          value: LanguageOption.english,
          child: Text(l10n.languageEnglish),
        ),
        PopupMenuItem(
          value: LanguageOption.chinese,
          child: Text(l10n.languageChinese),
        ),
      ],
    );
  }
}
