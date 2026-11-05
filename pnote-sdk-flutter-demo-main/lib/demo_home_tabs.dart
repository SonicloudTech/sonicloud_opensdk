import 'package:flutter/material.dart';

class DemoHomeTabs extends StatefulWidget {
  final Widget device;
  final GlobalKey<ScaffoldState>? scaffoldKey;
  final PreferredSizeWidget? appBar;
  final Widget? endDrawer;

  const DemoHomeTabs({
    super.key,
    required this.device,
    this.scaffoldKey,
    this.appBar,
    this.endDrawer,
  });

  @override
  State<DemoHomeTabs> createState() => _DemoHomeTabsState();
}

class _DemoHomeTabsState extends State<DemoHomeTabs> {
  int _index = 0;

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
          children: [widget.device, const SizedBox.expand()],
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
                onTap: (index) => setState(() => _index = index),
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
