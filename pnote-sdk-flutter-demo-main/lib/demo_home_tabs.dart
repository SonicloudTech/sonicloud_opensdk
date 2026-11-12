import 'package:flutter/material.dart';

class DemoHomeTabs extends StatefulWidget {
  final Widget device;
  final Widget testPage;
  final Future<bool> Function()? onLeaveTest;
  final GlobalKey<ScaffoldState>? scaffoldKey;
  final PreferredSizeWidget? appBar;
  final Widget? endDrawer;

  const DemoHomeTabs({
    super.key,
    required this.device,
    this.testPage = const SizedBox.expand(),
    this.onLeaveTest,
    this.scaffoldKey,
    this.appBar,
    this.endDrawer,
  });

  @override
  State<DemoHomeTabs> createState() => _DemoHomeTabsState();
}

class _DemoHomeTabsState extends State<DemoHomeTabs> {
  int _index = 0;
  final _tabBarKey = GlobalKey();
  bool _switchPending = false;

  Future<void> _selectTab(int index) async {
    final controller = DefaultTabController.of(_tabBarKey.currentContext!);
    if (_switchPending) {
      controller.index = _index;
      return;
    }
    if (_index == 1 && index == 0 && widget.onLeaveTest != null) {
      controller.index = _index;
      _switchPending = true;
      try {
        if (!await widget.onLeaveTest!()) return;
      } finally {
        _switchPending = false;
      }
    }
    if (!mounted) return;
    setState(() => _index = index);
    controller.index = index;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        key: widget.scaffoldKey,
        appBar: widget.appBar,
        endDrawer: widget.endDrawer,
        endDrawerEnableOpenDragGesture: false,
        body: IndexedStack(
          index: _index,
          children: [widget.device, widget.testPage],
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE8EDF5))),
            boxShadow: [
              BoxShadow(
                color: Color(0x080F2345),
                blurRadius: 12,
                offset: Offset(0, -3),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            maintainBottomViewPadding: true,
            minimum: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F4FA),
                borderRadius: BorderRadius.circular(16),
              ),
              child: TabBar(
                key: _tabBarKey,
                onTap: _selectTab,
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFF718096),
                labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                tabs: [
                  _tab('设备', Icons.devices_outlined),
                  _tab('测试', Icons.science_outlined),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(String label, IconData icon) => Tab(
    height: 40,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 8,
      children: [Icon(icon, size: 18), Text(label)],
    ),
  );
}
