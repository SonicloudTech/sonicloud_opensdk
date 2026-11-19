import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_mind_map/adapter/i_link_adapter.dart';
import 'package:flutter_mind_map/adapter/i_node_adapter.dart';
import 'package:flutter_mind_map/adapter/i_theme_adapter.dart';
import 'package:flutter_mind_map/i_mind_map_node.dart';
import 'package:flutter_mind_map/link/beerse_line_link.dart';
import 'package:flutter_mind_map/link/i_link.dart';
import 'package:flutter_mind_map/link/line_link.dart';
import 'package:flutter_mind_map/link/poly_line_link.dart';
import 'package:flutter_mind_map/mind_map_node.dart';
import 'package:flutter_mind_map/theme/i_mind_map_theme.dart';
import 'package:flutter_mind_map/theme/mind_map_theme_compact.dart';
import 'package:flutter_mind_map/theme/mind_map_theme_large.dart';
import 'package:flutter_mind_map/theme/mind_map_theme_normal.dart';
import 'package:path_drawing/path_drawing.dart';
import 'package:flutter/rendering.dart';

// ignore: must_be_immutable
class MindMap extends StatefulWidget {
  final GlobalKey repaintKey;

  MindMap({super.key, required this.repaintKey});

  void loadData(Map<String, dynamic> json) {
    if (json.containsKey("id") &&
        json.containsKey("content") &&
        json.containsKey("nodes")) {
      MindMapNode rootNode = MindMapNode();
      setRootNode(rootNode);
      rootNode.loadData(json);
    }
  }

  Map<String, dynamic> getData() {
    return getRootNode().getData();
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {
      "RootNode": getRootNode().toJson(),
      "Zoom": getZoom().toString(),
      "BackgroundColor": colorToString(getBackgroundColor()),
    };
    if (getOffset() != null) {
      json["x"] = getOffset()!.dx.toString();
      json["y"] = getOffset()!.dy.toString();
    }
    return json;
  }

  bool _isLoading = false;

  void fromJson(Map<String, dynamic> json) {
    _isLoading = true;
    if (json.containsKey("Zoom")) {
      setZoom(double.tryParse(json["Zoom"].toString()) ?? 1.0);
    }
    if (json.containsKey("BackgroundColor")) {
      setBackgroundColor(stringToColor(json["BackgroundColor"].toString()));
    }
    if (json.containsKey("x") && json.containsKey("y")) {
      double x = double.tryParse(json["x"].toString()) ?? 0;
      double y = double.tryParse(json["y"].toString()) ?? 0;
      setOffset(Offset(x, y));
    }
    if (json.containsKey("RootNode")) {
      Map<String, dynamic> map = json["RootNode"];
      if (map.isNotEmpty) {
        IMindMapNode? node = createNode(map.keys.first);
        if (node != null) {
          setRootNode(node);
          node.fromJson(map);
        }
      }
    }
    _isLoading = false;
  }

  double buttonWidth = 16;
  Color buttonColor = Colors.black;
  Color buttonBackground = Colors.white;
  Color dragInBorderColor = Colors.cyan;
  double dragInBorderWidth = 3;
  double mindMapPadding = 80;

  //Adapter
  final List<INodeAdapter> _nodeAdapter = [MindMapNodeAdapter()];

  void registerNodeAdapter(INodeAdapter value) {
    if (!_nodeAdapter.contains(value)) {
      _nodeAdapter.add(value);
    }
  }

  List<INodeAdapter> getNodeAdapter() {
    return _nodeAdapter;
  }

  IMindMapNode? createNode(String name) {
    for (INodeAdapter na in _nodeAdapter) {
      if (na.getName() == name) {
        return na.createNode();
      }
    }
    return null;
  }

  final List<ILinkAdapter> _linkAdapter = [
    BeerseLinkLinkAdapter(),
    LineLinkAdapter(),
    PolyLineLinkAdapter(),
  ];

  void registerLinkAdapter(ILinkAdapter value) {
    if (!_linkAdapter.contains(value)) {
      _linkAdapter.add(value);
    }
  }

  List<ILinkAdapter> getLinkAdapter() {
    return _linkAdapter;
  }

  ILink? createLink(String name) {
    for (ILinkAdapter na in _linkAdapter) {
      if (na.getName() == name) {
        return na.createLink();
      }
    }
    return null;
  }

  final List<IThemeAdapter> _themeAdapter = [
    MindMapThemeCompactAdapter(),
    MindMapThemeNormalAdapter(),
    MindMapThemeLargeAdapter(),
  ];

  void registerThemeAdapter(IThemeAdapter value) {
    if (!_themeAdapter.contains(value)) {
      _themeAdapter.add(value);
    }
  }

  List<IThemeAdapter> getThemeAdapter() {
    return _themeAdapter;
  }

  IMindMapTheme? createTheme(String name) {
    for (IThemeAdapter na in _themeAdapter) {
      if (na.getName() == name) {
        return na.createTheme();
      }
    }
    return null;
  }

  //End Adapter

  bool _showRecycle = true;

  bool getShowRecycle() {
    return _showRecycle;
  }

  void setShowRecycle(bool value) {
    if (_showRecycle != value) {
      _showRecycle = value;
      _state?.refresh();
    }
  }

  String _recycleTitle = "Drag here to delete";

  String getRecycleTitle() {
    return _recycleTitle;
  }

  void setRecycleTitle(String value) {
    if (_recycleTitle != value) {
      _recycleTitle = value;
      _state?.refresh();
    }
  }

  bool _canMove = true;

  bool getCanMove() {
    return _canMove;
  }

  void setCanMove(bool value) {
    if (_canMove != value) {
      _canMove = value;
      _state?.refresh();
    }
  }

  bool _showZoom = true;

  bool getShowZoom() {
    return _showZoom;
  }

  void setShowZoom(bool value) {
    if (_showZoom != value) {
      _showZoom = value;
      _state?.refresh();
    }
  }

  void refresh() {
    _state?.refresh();
  }

  double _zoom = 1;

  double getZoom() {
    return _zoom;
  }

  void setZoom(double value) {
    if (value > 0) {
      _zoom = value;
      List<Function()> list = [];
      list.addAll(_onZoomChangedListeners);
      for (Function() call in list) {
        call();
      }
      onChanged();
    }
  }

  final List<Function()> _onChangedListeners = [];

  void addOnChangedListeners(Function() value) {
    _onChangedListeners.add(value);
  }

  void removeOnChangedListeners(Function() value) {
    _onChangedListeners.remove(value);
  }

  void onChanged() {
    if (!_isLoading) {
      List<Function()> list = [];
      list.addAll(_onChangedListeners);
      for (Function() call in list) {
        call();
      }
    }
  }

  IMindMapTheme? _theme;

  IMindMapTheme? getTheme() {
    return _theme;
  }

  void setTheme(IMindMapTheme? value) {
    _theme = value;
    refresh();
    onChanged();
  }

  final List<Function()> _onZoomChangedListeners = [];

  void addOnZoomChangedListeners(Function() value) {
    _onZoomChangedListeners.add(value);
  }

  void removeOnZoomChangedListeners(Function() value) {
    _onZoomChangedListeners.remove(value);
  }

  IMindMapNode? _selectedNode;

  IMindMapNode? getSelectedNode() {
    return _selectedNode;
  }

  void setSelectedNode(IMindMapNode? node) {
    _selectedNode = node;
    notifySelectedNodeChanged();
  }

  final List<Function()> _onTapListeners = [];

  void addOnTapListeners(Function() callback) {
    _onTapListeners.add(callback);
  }

  void removeOnTapListeners(Function() callback) {
    _onTapListeners.remove(callback);
  }

  void onTap() {
    List<Function()> list = [];
    list.addAll(_onTapListeners);
    for (Function() call in list) {
      call();
    }
  }

  final List<Function()> _onSelectedNodeChangedListeners = [];

  void addOnSelectedNodeChangedListeners(Function() callback) {
    _onSelectedNodeChangedListeners.add(callback);
  }

  void removeOnSelectedNodeChangedListeners(Function() callback) {
    _onSelectedNodeChangedListeners.remove(callback);
  }

  void notifySelectedNodeChanged() {
    for (var listener in _onSelectedNodeChangedListeners) {
      listener();
    }
  }

  final List<Function(IMindMapNode)> _onDoubleTapListeners = [];

  void addOnDoubleTapListeners(Function(IMindMapNode) value) {
    _onDoubleTapListeners.add(value);
  }

  void removeOnDoubleTapListeners(Function(IMindMapNode) value) {
    _onDoubleTapListeners.remove(value);
  }

  void onDoubleTap(IMindMapNode node) {
    List<Function(IMindMapNode)> list = [];
    list.addAll(_onDoubleTapListeners);
    for (Function(IMindMapNode) call in list) {
      call(node);
    }
  }

  bool _readOnly = false;

  void setReadOnly(bool value) {
    if (_readOnly != value) {
      _readOnly = value;
      setSelectedNode(null);
      _state?.refresh();
    }
  }

  bool getReadOnly() => _readOnly;

  bool _hasTextField = true;

  void setHasTextField(bool value) {
    if (_hasTextField != value) {
      _hasTextField = value;
      setSelectedNode(null);
      _state?.refresh();
    }
  }

  bool hasTextField() => _hasTextField;

  Color? _backgroundColor;

  Color getBackgroundColor() =>
      _backgroundColor ??
      (getTheme() != null
          ? getTheme()!.getBackgroundColor()
          : Colors.transparent);

  void setBackgroundColor(Color color) {
    _backgroundColor = color;
    _state?.refresh();
    onChanged();
  }

  IMindMapNode _rootNode = MindMapNode();

  IMindMapNode getRootNode() {
    if (_rootNode.getMindMap() == null) {
      _rootNode.setMindMap(this);
    }
    return _rootNode;
  }

  void setRootNode(IMindMapNode rootNode) {
    _rootNode = rootNode;
    _rootNode.setMindMap(this);
    onRootNodeChanged();
    onChanged();
  }

  final List<Function()> _onRootNodeChangeListeners = [];

  void addOnRootNodeChangeListener(Function() listener) {
    _onRootNodeChangeListeners.add(listener);
  }

  void removeOnRootNodeChangeListener(Function() listener) {
    _onRootNodeChangeListeners.remove(listener);
  }

  void onRootNodeChanged() {
    for (var listener in _onRootNodeChangeListeners) {
      listener();
    }
  }

  final List<Function()> _onMoveListeners = [];

  void addOnMoveListeners(Function() callback) {
    _onMoveListeners.add(callback);
  }

  void removeOnMoveListeners(Function() callback) {
    _onMoveListeners.remove(callback);
  }

  void onMove() {
    for (var listener in _onMoveListeners) {
      listener();
    }
  }

  @override
  State<StatefulWidget> createState() => MindMapState();

  MindMapState? _state;

  Offset? _offset;

  void setOffset(Offset? value) {
    _offset = value;
    _state?.refresh();
    onChanged();
  }

  Offset? getOffset() => _offset;

  Offset moveOffset = Offset.zero;

  void setMoveOffset(Offset value) {
    if (moveOffset.dx != value.dx || moveOffset.dy != value.dy) {
      moveOffset = value;
      onMove();
    }
  }

  Offset getMoveOffset() => moveOffset;

  Size? _size;

  void setSize(Size? value) {
    if (_size == null ||
        (value != null &&
            (value.width != _size!.width || value.height != _size!.height))) {
      _size = value;
      _state?.refresh();
    }
  }

  Size? getSize() => _size;

  RenderObject? _renderObject;

  RenderObject? getRenderObject() {
    return _renderObject;
  }

  IMindMapNode? _dragInNode;
  IMindMapNode? _dragNode;
  Offset? _dragOffset;
  bool _leftDrag = true;
  bool _inRecycle = false;

  Future<ByteData?> exportToImage({double pixelRatio = 3}) async {
    await WidgetsBinding.instance.endOfFrame;

    final originZoom = getZoom();
    final originOffset = getMoveOffset();

    final bounds = _calcBounds(getRootNode());
    final targetSize = Size(
      bounds.width + mindMapPadding * 2,
      bounds.height + mindMapPadding * 2,
    );

    setZoom(1);
    setMoveOffset(
      Offset(-bounds.left + mindMapPadding, -bounds.top + mindMapPadding),
    );
    refresh();

    await WidgetsBinding.instance.endOfFrame;

    // 检查repaintKey对应的context是否存在
    if (repaintKey.currentContext == null) {
      throw Exception("Mind map widget is not rendered yet");
    }

    // 检查RenderObject是否为RenderRepaintBoundary类型
    final renderObject = repaintKey.currentContext?.findRenderObject();
    if (renderObject == null || !(renderObject is RenderRepaintBoundary)) {
      throw Exception("Mind map render boundary not found");
    }

    final boundary = renderObject as RenderRepaintBoundary;

    final image = await boundary.toImage(pixelRatio: pixelRatio);

    setZoom(originZoom);
    setMoveOffset(originOffset);

    //返回字节
    ByteData? byteData = await image.toByteData(format: ImageByteFormat.png);
    refresh();
    return byteData;
  }

  Rect _calcBounds(IMindMapNode node) {
    final offset = node.getOffset() ?? Offset.zero;
    final size = node.getSize() ?? Size.zero;
    Rect rect = Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height);

    for (final child in [...node.getLeftItems(), ...node.getRightItems()]) {
      rect = rect.expandToInclude(_calcBounds(child));
    }
    return rect;
  }
}

class MindMapState extends State<MindMap> {
  @override
  void initState() {
    super.initState();
    widget.addOnRootNodeChangeListener(onRootNodeChanged);
    widget.addOnSelectedNodeChangedListeners(onSelectedNodeChanged);
  }

  @override
  void dispose() {
    widget.removeOnRootNodeChangeListener(onRootNodeChanged);
    widget.removeOnSelectedNodeChangedListeners(onSelectedNodeChanged);
    super.dispose();
  }

  void onRootNodeChanged() {
    setState(() {});
  }

  void onSelectedNodeChanged() {
    setState(() {});
  }

  Size s = Size.zero;

  Offset _focalPoint = Offset.zero;
  Offset _lastFocalPoint = Offset.zero;
  double _lastScale = 1.0;
  final GlobalKey _key = GlobalKey();
  final GlobalKey _pkey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    widget._state = this;
    WidgetsBinding.instance.addPostFrameCallback((c) {
      if (mounted) {
        RenderObject? ro = context.findRenderObject();
        if (ro != null && ro is RenderBox) {
          if (s.width != ro.size.width || s.height != ro.size.height) {
            setState(() {
              s = ro.size;
            });
          }
        }
      }
    });
    double x = widget.getOffset()?.dx ?? 0;
    double y = widget.getOffset()?.dy ?? 0;
    Size? size = widget.getSize();
    if (s.isEmpty) {
      s = MediaQuery.of(context).size;
    }
    if (widget.getOffset() == null &&
        size != null &&
        size.width > 0 &&
        size.height > 0) {
      x = (s.width - size.width * widget.getZoom()) / 2;
      y = (s.height - size.height * widget.getZoom()) / 2;
      //set RooetNode Center
      Size? rs = widget.getRootNode().getSize();
      Offset? ro = widget.getRootNode().getOffset();
      if (rs != null && ro != null) {
        if (widget.getRootNode().getLeftItems().isNotEmpty &&
            widget.getRootNode().getRightItems().isNotEmpty) {
          x =
              s.width / 2 -
              ro.dx -
              rs.width / 2 +
              (ro.dx - size.width / 2 + rs.width / 2) -
              (ro.dx - size.width / 2 + rs.width / 2) * widget.getZoom();
          y =
              s.height / 2 -
              ro.dy -
              rs.height / 2 +
              (ro.dy - size.height / 2 + rs.height / 2) -
              (ro.dy - size.height / 2 + rs.height / 2) * widget.getZoom();
        } else {
          if (widget.getRootNode().getLeftItems().isNotEmpty) {
            x = s.width - size.width - 30;
            y =
                s.height / 2 -
                ro.dy -
                rs.height / 2 +
                (ro.dy - size.height / 2 + rs.height / 2) -
                (ro.dy - size.height / 2 + rs.height / 2) * widget.getZoom();
          } else {
            x = 30;
            y =
                s.height / 2 -
                ro.dy -
                rs.height / 2 +
                (ro.dy - size.height / 2 + rs.height / 2) -
                (ro.dy - size.height / 2 + rs.height / 2) * widget.getZoom();
          }
        }
      }
    }
    return Container(
      color: widget.getBackgroundColor(),
      width: double.infinity,
      height: double.infinity,
      child: GestureDetector(
        onTap: () {
          widget.setSelectedNode(null);
          widget.onTap();
        },
        //Scale
        onScaleStart: (details) {
          if (widget.getCanMove()) {
            setState(() {
              _focalPoint = widget.getMoveOffset();
              _lastFocalPoint = details.focalPoint;
              _lastScale = widget.getZoom();
            });
          }
        },
        onScaleUpdate: (details) {
          if (widget.getCanMove()) {
            setState(() {
              double scale = _lastScale * details.scale;
              widget.setZoom(scale < 0.1 ? 0.1 : scale);
              widget.setMoveOffset(
                Offset(
                  _focalPoint.dx + details.focalPoint.dx - _lastFocalPoint.dx,
                  _focalPoint.dy + details.focalPoint.dy - _lastFocalPoint.dy,
                ),
              );
            });
          }
        },
        child: DragTarget(
          key: _pkey,
          builder: (context, candidateData, rejectedData) {
            return Container(
              color: widget.getBackgroundColor(),
              width: double.infinity,
              height: double.infinity,
              child: Stack(
                children: [
                  Positioned(
                    left:
                        x +
                        widget.getMoveOffset().dx -
                        widget.mindMapPadding * widget.getZoom(),
                    top:
                        y +
                        widget.getMoveOffset().dy -
                        widget.mindMapPadding * widget.getZoom(),
                    child: Transform.scale(
                      scale: widget.getZoom(),
                      child: Container(
                        key: _key,
                        child: RepaintBoundary(
                          key: widget.repaintKey,
                          child: CustomPaint(
                            painter: MindMapPainter(mindMap: widget),
                            child: Container(
                              //color: Colors.grey,
                              padding: EdgeInsets.all(
                                widget.mindMapPadding * widget.getZoom(),
                              ),
                              child: widget.getRootNode() as Widget,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  Container(
                    padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
                    height: 52,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        MediaQuery.of(context).size.width > 600
                            ? Container()
                            : Spacer(),
                        //Recycle
                        widget.getReadOnly() || !widget.getShowRecycle()
                            ? Container()
                            : DragTarget(
                                onWillAcceptWithDetails: (details) {
                                  if (details.data is IMindMapNode) {
                                    setState(() {
                                      widget._inRecycle = true;
                                      widget._dragNode =
                                          details.data as IMindMapNode;
                                    });
                                    return true;
                                  }
                                  return false;
                                },
                                onAcceptWithDetails: (details) {
                                  if (widget._dragNode != null) {
                                    setState(() {
                                      if (widget._dragNode!.getNodeType() ==
                                          NodeType.left) {
                                        widget._dragNode!
                                            .getParentNode()
                                            ?.removeLeftItem(widget._dragNode!);
                                      } else {
                                        widget._dragNode!
                                            .getParentNode()
                                            ?.removeRightItem(
                                              widget._dragNode!,
                                            );
                                      }
                                      widget._inRecycle = false;
                                      widget._dragNode = null;
                                    });
                                  }
                                },
                                onLeave: (data) {
                                  setState(() {
                                    widget._inRecycle = false;
                                  });
                                },
                                builder:
                                    (context, candidateData, rejectedData) {
                                      return Container(
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: widget._inRecycle
                                                ? Colors.red
                                                : Theme.of(
                                                    context,
                                                  ).colorScheme.outline,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        constraints: BoxConstraints(
                                          minWidth: 32,
                                          minHeight: 32,
                                        ),
                                        padding: EdgeInsets.fromLTRB(
                                          8,
                                          0,
                                          8,
                                          0,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.delete_outline_outlined,
                                              size: 20,
                                              color: widget._inRecycle
                                                  ? Colors.red
                                                  : Theme.of(
                                                      context,
                                                    ).colorScheme.outline,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              widget.getRecycleTitle(),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: widget._inRecycle
                                                    ? Colors.red
                                                    : Theme.of(
                                                        context,
                                                      ).colorScheme.outline,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                              ),
                        MediaQuery.of(context).size.width > 600
                            ? Container()
                            : Spacer(),
                        (widget.getShowZoom()
                            ? SizedBox(width: 20)
                            : Container()),
                        //Zoom
                        widget.getShowZoom()
                            ? Container(
                                constraints: const BoxConstraints(
                                  minHeight: 32,
                                  maxHeight: 32,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: ToggleButtons(
                                  constraints: const BoxConstraints.tightFor(
                                    height: 32,
                                    width: 32,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                  borderColor: Theme.of(
                                    context,
                                  ).colorScheme.outline,
                                  isSelected: const [false, false, false],
                                  onPressed: (index) {
                                    switch (index) {
                                      case 0:
                                        if (widget.getZoom() > 0.2 && mounted) {
                                          setState(() {
                                            widget.setZoom(
                                              widget.getZoom() - 0.1,
                                            );
                                          });
                                        }
                                        break;
                                      case 1:
                                        setState(() {
                                          widget.setMoveOffset(Offset.zero);
                                          widget.setZoom(1);
                                        });
                                      case 2:
                                        if (widget.getZoom() < 2 && mounted) {
                                          setState(() {
                                            widget.setZoom(
                                              widget.getZoom() + 0.1,
                                            );
                                          });
                                        }
                                        break;
                                    }
                                  },
                                  children: [
                                    Icon(
                                      Icons.remove,
                                      size: 16,
                                      shadows: [
                                        BoxShadow(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.surface,
                                          blurRadius: 4.0,
                                          blurStyle: BlurStyle.outer,
                                        ),
                                      ],
                                    ),
                                    Text(
                                      "${(widget.getZoom() * 100).round()}%",
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall!
                                          .copyWith(
                                            fontSize: 8,
                                            shadows: [
                                              BoxShadow(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.surface,
                                                blurRadius: 4.0,
                                                blurStyle: BlurStyle.outer,
                                              ),
                                            ],
                                          ),
                                    ),
                                    Icon(
                                      Icons.add,
                                      size: 16,
                                      shadows: [
                                        BoxShadow(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.surface,
                                          blurRadius: 4.0,
                                          blurStyle: BlurStyle.outer,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              )
                            : Container(),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
          onWillAcceptWithDetails: (details) {
            if (details.data is IMindMapNode) {
              setState(() {
                widget._dragNode = details.data as IMindMapNode;
              });
              return true;
            }
            setState(() {
              widget._dragNode = null;
            });
            return false;
          },
          onAcceptWithDetails: (details) {
            if (details.data is IMindMapNode) {
              setState(() {
                if (widget._dragInNode != null) {
                  if ((details.data as IMindMapNode).getNodeType() ==
                      NodeType.left) {
                    (details.data as IMindMapNode)
                        .getParentNode()
                        ?.removeLeftItem((details.data as IMindMapNode));
                  } else {
                    (details.data as IMindMapNode)
                        .getParentNode()
                        ?.removeRightItem((details.data as IMindMapNode));
                  }
                  if (widget._leftDrag) {
                    widget._dragInNode!.insertLeftItem(
                      (details.data as IMindMapNode),
                      _dragIndex,
                    );
                  } else {
                    widget._dragInNode!.insertRightItem(
                      (details.data as IMindMapNode),
                      _dragIndex,
                    );
                  }
                  widget.getRootNode().refresh();
                }
                widget._dragInNode = null;
              });
            }
            setState(() {
              widget._dragNode = null;
            });
          },
          onLeave: (data) {
            setState(() {
              widget._dragInNode = null;
              widget._dragNode = null;
            });
          },
          onMove: (details) {
            if (details.data is IMindMapNode) {
              widget._dragInNode = details.data as IMindMapNode;
              Size dataSize =
                  (details.data as IMindMapNode).getSize() ?? Size.zero;
              RenderObject? ro = _key.currentContext?.findRenderObject();
              widget._renderObject = ro;
              if (ro != null && ro is RenderBox) {
                Offset r = ro.localToGlobal(Offset.zero);
                Offset offset = Offset(
                  details.offset.dx -
                      r.dx +
                      dataSize.width +
                      (dataSize.width * widget.getZoom() / 2) -
                      dataSize.width / 2,
                  details.offset.dy - r.dy + dataSize.height / 2,
                );

                IMindMapNode? leftDragNode = inLeftDrag(
                  details.data as IMindMapNode,
                  offset,
                );
                if (leftDragNode != null &&
                    !isParent(details.data as IMindMapNode, leftDragNode)) {
                  setState(() {
                    widget._leftDrag = true;
                    widget._dragInNode = leftDragNode;
                    widget._dragOffset = offset;
                  });
                  return;
                }

                offset = Offset(
                  details.offset.dx -
                      r.dx -
                      (dataSize.width * widget.getZoom() / 2) +
                      dataSize.width / 2,
                  details.offset.dy - r.dy + dataSize.height / 2,
                );
                debugPrint(
                  "${offset.dx} :${offset.dy}  dx:${details.offset.dx} rdx:${r.dx} rowidth:${ro.size.width}  :${size!.width}",
                );

                IMindMapNode? rightDragNode = inRightDrag(
                  details.data as IMindMapNode,
                  offset,
                );
                if (rightDragNode != null &&
                    !isParent(details.data as IMindMapNode, rightDragNode)) {
                  setState(() {
                    widget._leftDrag = false;
                    widget._dragInNode = rightDragNode;
                    widget._dragOffset = offset;
                  });
                  return;
                }

                setState(() {
                  widget._dragInNode = null;
                });
              }
            }
          },
        ),
      ),
    );
  }

  IMindMapNode? inLeftDrag(IMindMapNode node, Offset offset) {
    return inLeftDragByParentNode(node, offset, widget.getRootNode());
  }

  int _dragIndex = 0;

  IMindMapNode? inLeftDragByParentNode(
    IMindMapNode node,
    Offset offset,
    IMindMapNode parentNode,
  ) {
    Rect? rect = parentNode.getLeftArea();

    if (rect != null) {
      if (rect.top * widget.getZoom() <= offset.dy &&
          rect.left * widget.getZoom() <= offset.dx &&
          rect.bottom * widget.getZoom() >= offset.dy &&
          rect.right * widget.getZoom() >= offset.dx) {
        _dragIndex = 0;
        if (parentNode.getLeftItems().isNotEmpty) {
          _dragIndex = parentNode.getLeftItems().length;
          int index = 0;

          for (IMindMapNode n in parentNode.getLeftItems()) {
            Size? size = n.getSize();
            Offset o = n.getOffset() ?? Offset.zero;
            if (n.getRenderObject() is RenderBox) {
              Offset po = (n.getRenderObject() as RenderBox).localToGlobal(
                Offset.zero,
                ancestor: widget._renderObject,
              );
              o = Offset(o.dx + po.dx, o.dy + po.dy);
            }
            if (o.dy * widget.getZoom() +
                    (size?.height ?? 0) * widget.getZoom() / 2 >
                offset.dy) {
              _dragIndex = index;
              break;
            }
            index++;
          }
        }
        if (node.getParentNode() == parentNode &&
            node.getNodeType() == NodeType.left) {
          int i = parentNode.getLeftItems().indexOf(node);
          if (i < _dragIndex && _dragIndex > 0) {
            _dragIndex--;
          }
        }
        return parentNode;
      }
      for (IMindMapNode cn in parentNode.getLeftItems()) {
        IMindMapNode? n = inLeftDragByParentNode(node, offset, cn);
        if (n != null) {
          return n;
        }
      }
    }
    return null;
  }

  IMindMapNode? inRightDrag(IMindMapNode node, Offset offset) {
    return inRightDragByParentNode(node, offset, widget.getRootNode());
  }

  IMindMapNode? inRightDragByParentNode(
    IMindMapNode node,
    Offset offset,
    IMindMapNode parentNode,
  ) {
    Rect? rect = parentNode.getRightArea();

    if (rect != null) {
      if (rect.top * widget.getZoom() <= offset.dy &&
          rect.left * widget.getZoom() <= offset.dx &&
          rect.bottom * widget.getZoom() >= offset.dy &&
          rect.right * widget.getZoom() >= offset.dx) {
        _dragIndex = 0;
        if (parentNode.getRightItems().isNotEmpty) {
          _dragIndex = parentNode.getRightItems().length;
          int index = 0;

          for (IMindMapNode n in parentNode.getRightItems()) {
            Size? size = n.getSize();
            Offset o = n.getOffset() ?? Offset.zero;
            if (n.getRenderObject() is RenderBox) {
              Offset po = (n.getRenderObject() as RenderBox).localToGlobal(
                Offset.zero,
                ancestor: widget._renderObject,
              );
              o = Offset(o.dx + po.dx, o.dy + po.dy);
            }
            if (o.dy * widget.getZoom() +
                    (size?.height ?? 0) * widget.getZoom() / 2 >
                offset.dy) {
              _dragIndex = index;
              break;
            }
            index++;
          }
        }
        if (node.getParentNode() == parentNode &&
            node.getNodeType() == NodeType.right) {
          int i = parentNode.getRightItems().indexOf(node);
          if (i < _dragIndex && _dragIndex > 0) {
            _dragIndex--;
          }
        }
        return parentNode;
      }
      for (IMindMapNode cn in parentNode.getRightItems()) {
        IMindMapNode? n = inRightDragByParentNode(node, offset, cn);
        if (n != null) {
          return n;
        }
      }
    }
    return null;
  }

  bool isParent(IMindMapNode node, IMindMapNode dragNode) {
    IMindMapNode? parent = dragNode;
    while (parent != null) {
      if (parent == node) {
        return true;
      }
      parent = parent.getParentNode();
    }
    return false;
  }

  void refresh() {
    if (mounted) {
      setState(() {
        widget.getRootNode().setOffset(null);
        widget.getRootNode().setSize(null);
      });
    }
  }
}

class MindMapPainter extends CustomPainter {
  MindMapPainter({required this.mindMap});

  MindMap mindMap;

  @override
  void paint(Canvas canvas, Size size) {
    /// 添加导出后的背景色
    final Paint bg = Paint()
      ..style = PaintingStyle.fill
      ..color = mindMap.getBackgroundColor();
    canvas.drawRect(Offset.zero & size, bg);

    Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = mindMap.dragInBorderWidth
      ..color = mindMap.dragInBorderColor;
    if (mindMap._dragInNode != null) {
      //canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
      RenderObject? ro = mindMap._dragInNode!.getRenderObject();
      if (ro != null && mindMap._renderObject != null) {
        Offset o = (ro as RenderBox).localToGlobal(
          Offset.zero,
          ancestor: mindMap._renderObject,
        );
        Path path = Path();
        path.addRRect(
          RRect.fromLTRBR(
            o.dx +
                (mindMap._dragInNode!.getOffset()?.dx ?? 0) -
                3 -
                mindMap.dragInBorderWidth,
            o.dy +
                (mindMap._dragInNode!.getOffset()?.dy ?? 0) -
                3 -
                mindMap.dragInBorderWidth,
            o.dx +
                (mindMap._dragInNode!.getOffset()?.dx ?? 0) +
                (mindMap._dragInNode!.getSize()?.width ?? 0) +
                3 +
                mindMap.dragInBorderWidth,
            o.dy +
                (mindMap._dragInNode!.getOffset()?.dy ?? 0) +
                (mindMap._dragInNode!.getSize()?.height ?? 0) +
                3 +
                mindMap.dragInBorderWidth,
            Radius.circular(6),
          ),
        );
        canvas.drawPath(
          dashPath(
            path,
            dashArray: CircularIntervalList<double>(<double>[10, 10]),
          ),
          paint,
        );
        if (mindMap._dragOffset != null) {
          Path pathline = Path();
          double x1 = mindMap._dragOffset!.dx / mindMap.getZoom();
          double y1 = mindMap._dragOffset!.dy / mindMap.getZoom();
          double x2 =
              o.dx +
              (mindMap._dragInNode!.getOffset()?.dx ?? 0) +
              (mindMap._leftDrag
                  ? 0
                  : (mindMap._dragInNode!.getSize()?.width ?? 0));
          double y2 =
              o.dy +
              (mindMap._dragInNode!.getOffset()?.dy ?? 0) +
              (mindMap._dragInNode!.getSize()?.height ?? 0) / 2 +
              (mindMap._dragInNode!.getLinkOutOffset());
          pathline.moveTo(
            mindMap._dragOffset!.dx / mindMap.getZoom(),
            mindMap._dragOffset!.dy / mindMap.getZoom(),
          );
          pathline.cubicTo(
            x1 + (x2 - x1) / 2,
            y1,
            x2 - (x2 - x1) / 2,
            y2,
            x2,
            y2,
          );
          canvas.drawPath(
            dashPath(
              pathline,
              dashArray: CircularIntervalList<double>(<double>[10, 10]),
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
