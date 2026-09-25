import 'package:flutter/material.dart';

/// A fixed-height window onto a list of rows. A short list shrinks to its
/// rows; a long one (hundreds of registrants, a full semester of events)
/// scrolls inside this box instead of stretching the whole page, so the
/// sections below it stay within reach. Same treatment as the Certificates
/// recipients list.
class OrgScrollBox extends StatefulWidget {
  final List<Widget> children;
  final double maxHeight;
  final EdgeInsetsGeometry padding;
  final CrossAxisAlignment crossAxisAlignment;

  const OrgScrollBox({
    super.key,
    required this.children,
    this.maxHeight = 420,
    this.padding = EdgeInsets.zero,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  @override
  State<OrgScrollBox> createState() => _OrgScrollBoxState();
}

class _OrgScrollBoxState extends State<OrgScrollBox> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: Scrollbar(
        controller: _scroll,
        child: SingleChildScrollView(
          controller: _scroll,
          padding: widget.padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: widget.crossAxisAlignment,
            children: widget.children,
          ),
        ),
      ),
    );
  }
}
