import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'provider_record_pen.dart';

// 编号及行顺序对应 Demo功能列表.md，新增型号只需维护此配置。
const _commonRows = [
  [7, 8, 9, 10],
  [12, 14, 15, 16, 11],
  [20, 21, 22, 24, 27],
  [28, 31, 32, 29, 30],
  [17, 33, 34, 23, 25],
];
const _wifiRow = [39, 40, 42, 41, 43];
const _otaRows = [
  _wifiRow,
  [44, 45, 52],
  [55, 56],
];
const _cb08OtaRows = [
  _wifiRow,
  [44, 45, 52, 53, 54],
  [55, 56],
];
const _deviceLayouts = <int, ({String name, List<List<int>> rows})>{
  1: (
    name: 'CB08',
    rows: [
      [35, 36, 37, 38, 26],
      [18, 19, 53, 54],
    ],
  ),
  3: (name: 'CB08', rows: _cb08OtaRows),
  4: (name: 'CB08', rows: _cb08OtaRows),
  5: (
    name: 'D10',
    rows: [
      [48, 51, 50, 49],
      [5, 47],
    ],
  ),
  8: (name: 'CB08', rows: _cb08OtaRows),
  198: (
    name: 'C08-FB',
    rows: [
      _wifiRow,
      [5, 47, 57],
    ],
  ),
  199: (
    name: 'C08-DX',
    rows: [
      _wifiRow,
      [44, 45, 5, 47],
      [6, 57],
    ],
  ),
  200: (
    name: 'C08-AI',
    rows: [
      _wifiRow,
      [44, 45, 57],
    ],
  ),
  201: (
    name: 'L09',
    rows: [
      [2],
      _wifiRow,
      [44, 45, 5, 47, 46],
      [13, 3, 4, 57],
    ],
  ),
  202: (
    name: 'C10',
    rows: [
      [2],
      _wifiRow,
      [44, 45, 5, 47, 46],
      [57, 3, 4],
    ],
  ),
};

class DemoFunctionPanel extends StatelessWidget {
  final Widget fileSelector;
  final Widget deviceSelector;
  final Widget Function(int id) functionBuilder;

  const DemoFunctionPanel({
    super.key,
    required this.fileSelector,
    required this.deviceSelector,
    required this.functionBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RecordPenProvider>();
    final layout = provider.isConnected && provider.deviceInfo != null
        ? _deviceLayouts[provider.deviceType] ?? (name: '其他', rows: _otaRows)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 5,
      children: [
        fileSelector,
        deviceSelector,
        ..._commonRows.map(_buildRow),
        if (layout != null) ...[
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 24,
              runSpacing: 4,
              children: [
                for (final label in [
                  provider.deviceType?.toString() ?? '未知',
                  layout.name,
                  provider.deviceInfo?['name']?.toString() ?? '',
                ])
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontStyle: FontStyle.normal,
                    ),
                  ),
              ],
            ),
          ),
          ...layout.rows.map(_buildRow),
        ],
      ],
    );
  }

  Widget _buildRow(List<int> ids) {
    if (ids.length == 1) return functionBuilder(ids.single);
    if (ids.first == 55) {
      return Row(
        spacing: 5,
        children: [
          Expanded(flex: 3, child: functionBuilder(55)),
          Expanded(flex: 2, child: functionBuilder(56)),
        ],
      );
    }
    return Row(
      spacing: 5,
      children: [
        for (var index = 0; index < 5; index++)
          Expanded(
            child: SizedBox(
              height: 32,
              child: index < ids.length ? functionBuilder(ids[index]) : null,
            ),
          ),
      ],
    );
  }
}
