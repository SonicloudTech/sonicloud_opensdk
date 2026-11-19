# flutter_mind_map

[![Dart SDK Version](https://badgen.net/pub/sdk-version/flutter_mind_map)](https://pub.dev/packages/flutter_mind_map)
[![Pub Version](https://img.shields.io/pub/v/flutter_mind_map)](https://pub.dev/packages/flutter_mind_map)
[![Pub Likes](https://img.shields.io/pub/likes/flutter_mind_map)](https://pub.dev/packages/flutter_mind_map)

Flutter's highly customizable and interactive mind map package features custom themes, custom line formats, and custom content.

---

### Contents

-   [Load nodes from JSON](#load-nodes-from-json)
-   [Create nodes and customize node styles through code](#create-nodes-and-customize-node-styles-through-code)
-   [Set theme](#set-theme)
-   [Custom Theme](#custom-theme)
-   [Register custom theme](#register-custom-theme)
-   [Use custom theme](#use-custom-theme)
-   [Set the type of line](#set-the-type-of-line)
-   [Save or read data and styles](#save-or-read-data-and-styles)

---

## Load nodes from JSON

```dart
Map<String, dynamic> json = {
  "id": "os_classification",
  "content": "OS Types",
  "nodes": [
    {
      "id": "by_domain",
      "content": "By Domain",
      "nodes": [
        {"id": "desktop", "content": "Desktop", "nodes": []},
        {"id": "server", "content": "Server", "nodes": []},
        {"id": "mobile", "content": "Mobile", "nodes": []},
        {"id": "embedded", "content": "Embedded", "nodes": []},
        {"id": "hypervisor", "content": "Hypervisor", "nodes": []}
      ]
    },
    {
      "id": "by_user",
      "content": "By User",
      "nodes": [
        {"id": "single_user", "content": "Single-User", "nodes": []},
        {"id": "multi_user", "content": "Multi-User", "nodes": []}
      ]
    },
    {
      "id": "by_license",
      "content": "By License",
      "nodes": [
        {"id": "proprietary", "content": "Proprietary", "nodes": []},
        {"id": "open_source", "content": "Open Source", "nodes": []}
      ]
    },
    {
      "id": "by_kernel",
      "content": "By Kernel",
      "nodes": [
        {"id": "monolithic", "content": "Monolithic", "nodes": []},
        {"id": "microkernel", "content": "Microkernel", "nodes": []},
        {"id": "hybrid", "content": "Hybrid", "nodes": []},
        {"id": "exokernel", "content": "Exokernel", "nodes": []}
      ]
    },
    {
      "id": "by_time",
      "content": "By Time",
      "nodes": [
        {"id": "time_sharing", "content": "Time-Sharing", "nodes": []},
        {"id": "real_time", "content": "Real-Time", "nodes": []}
      ]
    }
  ]
};

mindMap.loadData(json);
```

## Create nodes and customize node styles through code

```dart
          mindMap.getRootNode().getLeftItems().clear();
          mindMap.getRootNode().getRightItems().clear();
          mindMap.getRootNode().setTitle("OS Types");
          mindMap.getRootNode().setLinkColor(Colors.blue);

          (mindMap.getRootNode() as MindMapNode).setBorderRadius(
            BorderRadiusGeometry.circular(100),
          );
          (mindMap.getRootNode() as MindMapNode).setPadding(
            EdgeInsets.fromLTRB(30, 6, 30, 6),
          );

          MindMapNode node1 = MindMapNode();
          node1.setTitle("By Domain");
          node1.setBackgroundColor(Colors.yellow);
          node1.setTextStyle(TextStyle(fontSize: 12.0, color: Colors.black));
          mindMap.getRootNode().addLeftItem(node1);

          MindMapNode node11 = MindMapNode();
          node11.setTitle("Desktop");
          node11.setBackgroundColor(Colors.white);
          node11.setTextStyle(TextStyle(fontSize: 10.0, color: Colors.black));
          node11.setPadding(EdgeInsets.fromLTRB(20, 2, 20, 2));
          node1.addLeftItem(node11);

          MindMapNode node12 = MindMapNode();
          node12.setTitle("Server");
          node12.setBackgroundColor(Colors.white);
          node12.setTextStyle(TextStyle(fontSize: 10.0, color: Colors.black));
          node12.setPadding(EdgeInsets.fromLTRB(20, 2, 20, 2));
          node1.addLeftItem(node12);

          MindMapNode node13 = MindMapNode();
          node13.setTitle("Mobile");
          node13.setBackgroundColor(Colors.white);
          node13.setTextStyle(TextStyle(fontSize: 10.0, color: Colors.black));
          node13.setPadding(EdgeInsets.fromLTRB(20, 2, 20, 2));
          node1.addLeftItem(node13);

          MindMapNode node14 = MindMapNode();
          node14.setTitle("Enbedded");
          node14.setBackgroundColor(Colors.white);
          node14.setTextStyle(TextStyle(fontSize: 10.0, color: Colors.black));
          node14.setPadding(EdgeInsets.fromLTRB(20, 2, 20, 2));
          node1.addLeftItem(node14);

          MindMapNode node15 = MindMapNode();
          node15.setTitle("Hypervisor");
          node15.setBackgroundColor(Colors.white);
          node15.setTextStyle(TextStyle(fontSize: 10.0, color: Colors.black));
          node15.setPadding(EdgeInsets.fromLTRB(20, 2, 20, 2));
          node1.addLeftItem(node15);

          MindMapNode node2 = MindMapNode();
          node2.setTitle("By User");
          node2.setBackgroundColor(Colors.yellow);
          node2.setTextStyle(TextStyle(fontSize: 12.0, color: Colors.black));
          mindMap.getRootNode().addLeftItem(node2);

          MindMapNode node21 = MindMapNode();
          node21.setTitle("Single-User");
          node21.setBackgroundColor(Colors.white);
          node21.setTextStyle(TextStyle(fontSize: 10.0, color: Colors.black));
          node21.setPadding(EdgeInsets.fromLTRB(20, 2, 20, 2));
          node2.addLeftItem(node21);

          MindMapNode node22 = MindMapNode();
          node22.setTitle("Multi-User");
          node22.setBackgroundColor(Colors.white);
          node22.setTextStyle(TextStyle(fontSize: 10.0, color: Colors.black));
          node22.setPadding(EdgeInsets.fromLTRB(20, 2, 20, 2));
          node2.addLeftItem(node22);

          MindMapNode node3 = MindMapNode();
          node3.setTitle("By License");
          node3.setTextStyle(
            TextStyle(
              fontSize: 12.0,
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          );
          node3.setBorder(
            BoxBorder.fromLTRB(
              bottom: BorderSide(
                color: Colors.black,
                width: 2.0,
                style: BorderStyle.solid,
              ),
            ),
          );
          node3.setPadding(EdgeInsets.fromLTRB(20, 2, 20, 2));
          node3.setBorderRadius(BorderRadius.circular(0));
          node3.setLinkColor(Colors.deepOrange);
          node3.setLinkInOffsetMode(MindMapNodeLinkOffsetMode.bottom);
          node3.setLinkOutOffsetMode(MindMapNodeLinkOffsetMode.bottom);
          mindMap.getRootNode().addLeftItem(node3);

          MindMapNode node31 = MindMapNode();
          node31.setTitle("Proprietary");
          node31.setBackgroundColor(Colors.white);
          node31.setTextStyle(TextStyle(fontSize: 10.0, color: Colors.black));
          node31.setPadding(EdgeInsets.fromLTRB(20, 2, 20, 2));
          node3.addLeftItem(node31);

          MindMapNode node32 = MindMapNode();
          node32.setTitle("Open Source");
          node32.setBackgroundColor(Colors.white);
          node32.setTextStyle(TextStyle(fontSize: 10.0, color: Colors.black));
          node32.setPadding(EdgeInsets.fromLTRB(20, 2, 20, 2));
          node3.addLeftItem(node32);

          MindMapNode node4 = MindMapNode();
          node4.setLinkColor(Colors.red);
          node4.setLinkInOffsetMode(MindMapNodeLinkOffsetMode.top);
          node4.setLinkOutOffsetMode(MindMapNodeLinkOffsetMode.bottom);
          node4.setBorderRadius(BorderRadiusGeometry.circular(5));
          node4.setTitle("By Kernel");
          node4.setLink(PolyLineLink());
          mindMap.getRootNode().addRightItem(node4);

          MindMapNode node41 = MindMapNode();
          node41.setTitle("Monolithic");
          node4.addRightItem(node41);
          MindMapNode node42 = MindMapNode();
          node42.setTitle("Microkernel");
          node4.addRightItem(node42);
          MindMapNode node43 = MindMapNode();
          node43.setTitle("Hybrid");
          node4.addRightItem(node43);
          MindMapNode node44 = MindMapNode();
          node44.setTitle("Exokernel");
          node4.addRightItem(node44);

          MindMapNode node5 = MindMapNode();
          node5.setTitle("By Time");
          node5.setLinkColor(Colors.cyan);
          node5.setBorder(
            BoxBorder.all(
              color: Colors.cyan,
              width: 2.0,
              style: BorderStyle.solid,
              strokeAlign: BorderSide.strokeAlignOutside,
            ),
          );
          node5.setChild(
            Row(
              children: [
                Icon(
                  Icons.account_circle_outlined,
                  size: 16,
                  color: Colors.cyan,
                ),
                SizedBox(width: 10),
                Text(
                  node5.getTitle(),
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ),
          );
          mindMap.getRootNode().addRightItem(node5);

          MindMapNode node51 = MindMapNode();
          node51.setTitle("Time-Sharing");
          node5.addRightItem(node51);
          MindMapNode node52 = MindMapNode();
          node52.setTitle("Real-Time");
          node5.addRightItem(node52);

```

## Set theme

```dart
mindMap.setTheme(MindMapThemeCompact());

```

## Custom Theme

```dart
import 'package:flutter/material.dart';
import 'package:flutter_mind_map/adapter/i_theme_adapter.dart';
import 'package:flutter_mind_map/link/beerse_line_link.dart';
import 'package:flutter_mind_map/link/poly_line_link.dart';
import 'package:flutter_mind_map/theme/i_mind_map_theme.dart';

class MyTheme implements IMindMapTheme {
  @override
  String getName() {
    return "MyTheme";
  }

  @override
  Map<String, dynamic>? getThemeByLevel(int level) {
    switch (level) {
      case 0:
        return {
          "BackgroundColor": Colors.white,
          "TextColor": Colors.black,
          "FontSize": 16.0,
          "Bold": true,
          "LinkColor": Colors.deepPurpleAccent,
          "LinkWidth": 1.5,
          "HSpace": 50,
          "VSpace": 20,
          "Border": Border.all(
            color: Colors.deepPurpleAccent,
            width: 2,
            style: BorderStyle.solid,
            strokeAlign: BorderSide.strokeAlignOutside,
          ),
          "BorderRadius": BorderRadius.circular(100),
          "Padding": EdgeInsets.fromLTRB(20, 10, 20, 10),
          "Link": PolyLineLink(),
        };
      case 1:
        return {
          "BackgroundColor": Colors.transparent,
          "TextColor": Colors.black,
          "FontSize": 14.0,
          "HSpace": 50,
          "VSpace": 20,
          "Border": Border.all(color: Colors.deepOrangeAccent, width: 1.5),
          "BorderRadius": BorderRadius.circular(6),
          "Padding": EdgeInsets.fromLTRB(12, 6, 12, 6),
          "LinkWidth": 1.5,
          "LinkColors": [
            Colors.deepPurpleAccent,
            Colors.blueAccent,
            Colors.green,
            Colors.deepOrangeAccent,
            Colors.cyan,
            Colors.redAccent,
            Colors.brown,
          ],
          "BorderColors": [
            Colors.deepPurpleAccent,
            Colors.blueAccent,
            Colors.green,
            Colors.deepOrangeAccent,
            Colors.cyan,
            Colors.redAccent,
            Colors.brown,
          ],
          "Link": BeerseLineLink(),
        };
      case 2:
        return {
          "BackgroundColor": Colors.transparent,
          "TextColor": Colors.black,
          "FontSize": 12.0,
          "HSpace": 40,
          "VSpace": 10,
          "Border": Border.all(color: Colors.transparent, width: 0),
          "BorderRadius": BorderRadius.circular(0),
          "Padding": EdgeInsets.fromLTRB(6, 0, 6, 0),
          "LinkWidth": 1.0,
        };
    }
    return null;
  }

  @override
  Color getBackgroundColor() {
    return Colors.white;
  }
}

class MyThemeAdapter implements IThemeAdapter {
  @override
  IMindMapTheme createTheme() {
    return MyTheme();
  }

  @override
  String getName() {
    return "MyTheme";
  }
}

```

## Register custom theme

```dart
mindMap.registerThemeAdapter(MyThemeAdapter());
```

## Use custom theme

```dart
mindMap.setTheme(MindMapThemeCompact());
```

or

```dart
mindMap.setTheme(mindMap.createTheme("MyTheme")!);
```

## Set the type of line

```dart
node1.setLink(PolyLineLink());
node2.setLink(BeerseLineLink());
node3.setLink(LineLink());

```

## Save or read data and styles

```dart
Map<String, dynamic> data = mindMap.toJson();
mindMap.fromJson(data);

```
