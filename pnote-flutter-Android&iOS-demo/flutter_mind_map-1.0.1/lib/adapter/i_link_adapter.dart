import 'package:flutter_mind_map/link/i_link.dart';

abstract class ILinkAdapter {
  String getName();
  ILink createLink();
}
