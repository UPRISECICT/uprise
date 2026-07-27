import 'package:flutter/material.dart';

/// Flutter's stock DropdownButton/DropdownButtonFormField centers its menu
/// on the selected item instead of simply dropping below the field, which
/// makes it appear anywhere on screen (above, mid-page, off to the side)
/// depending on scroll position and which item is selected. This anchors
/// the menu directly under the field instead (via CompositedTransformFollower,
/// so it tracks correctly even if the page scrolls while open) and makes
/// it scrollable when there are many items.
///
/// Drop-in replacement for DropdownButtonFormField: same `value`, `items`,
/// `onChanged`, `decoration`, `validator`, `style` parameters.
class AnchoredDropdownField<T> extends FormField<T> {
  AnchoredDropdownField({
    super.key,
    T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    InputDecoration decoration = const InputDecoration(),
    TextStyle? style,
    super.validator,
    bool enabled = true,
    double maxMenuHeight = 280,
  }) : super(
         initialValue: value,
         enabled: enabled,
         builder: (field) {
           void handleChanged(T? newValue) {
             field.didChange(newValue);
             onChanged(newValue);
           }

           return _AnchoredDropdownTrigger<T>(
             value: field.value,
             items: items,
             onChanged: handleChanged,
             decoration: decoration,
             style: style,
             errorText: field.errorText,
             maxMenuHeight: maxMenuHeight,
           );
         },
       );

  @override
  FormFieldState<T> createState() => FormFieldState<T>();
}

class _AnchoredDropdownTrigger<T> extends StatefulWidget {
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final InputDecoration decoration;
  final TextStyle? style;
  final String? errorText;
  final double maxMenuHeight;

  const _AnchoredDropdownTrigger({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.decoration,
    this.style,
    this.errorText,
    required this.maxMenuHeight,
  });

  @override
  State<_AnchoredDropdownTrigger<T>> createState() =>
      _AnchoredDropdownTriggerState<T>();
}

class _AnchoredDropdownTriggerState<T>
    extends State<_AnchoredDropdownTrigger<T>> {
  final LayerLink _link = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();
  OverlayEntry? _entry;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  void _toggle() {
    if (_entry != null) {
      _removeOverlay();
      return;
    }
    final renderBox =
        _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final width = renderBox?.size.width ?? 200.0;
    final height = renderBox?.size.height ?? 48.0;

    final overlay = Overlay.of(context);
    _entry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _removeOverlay,
            ),
          ),
          CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            offset: Offset(0, height + 4),
            child: Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(10),
                color: Colors.white,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: width,
                    maxWidth: width,
                    maxHeight: widget.maxMenuHeight,
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: widget.items.map((item) {
                      final selected = item.value == widget.value;
                      return InkWell(
                        onTap: () {
                          _removeOverlay();
                          widget.onChanged(item.value);
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          color: selected
                              ? const Color(0xFFFDF2E9)
                              : Colors.transparent,
                          child: DefaultTextStyle.merge(
                            style: TextStyle(
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                            child: item.child,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_entry!);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final matches = widget.items.where((i) => i.value == widget.value);
    final displayChild = matches.isEmpty ? null : matches.first.child;

    return CompositedTransformTarget(
      link: _link,
      child: InkWell(
        key: _fieldKey,
        onTap: _toggle,
        borderRadius: BorderRadius.circular(8),
        child: InputDecorator(
          decoration: widget.decoration.copyWith(
            errorText: widget.errorText,
            suffixIcon: Icon(
              _entry != null
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: const Color(0xFF9AA5B4),
            ),
          ),
          isEmpty: displayChild == null,
          child: displayChild == null
              ? null
              : DefaultTextStyle(
                  style:
                      widget.style ??
                      const TextStyle(fontSize: 14, color: Colors.black87),
                  child: displayChild,
                ),
        ),
      ),
    );
  }
}

/// For plain (non-Form, non-InputDecoration) dropdowns — filter pills,
/// toolbar selectors, etc. Wraps an arbitrary [trigger] widget (whatever
/// the call site already renders for its button) and shows the same
/// anchored, scrollable menu on tap.
class AnchoredMenuTrigger<T> extends StatefulWidget {
  final Widget trigger;
  final List<T> items;
  final String Function(T)? labelOf;
  // Overrides the default Text(labelOf(item)) rendering — for callers that
  // already have a fully-built child widget per item (e.g. items sourced
  // from existing DropdownMenuItem<T>.child).
  final Widget Function(T item, bool selected)? itemBuilder;
  final T? selectedValue;
  final ValueChanged<T> onSelected;
  final double maxMenuHeight;
  final double? menuWidth;

  const AnchoredMenuTrigger({
    super.key,
    required this.trigger,
    required this.items,
    this.labelOf,
    this.itemBuilder,
    required this.onSelected,
    this.selectedValue,
    this.maxMenuHeight = 280,
    this.menuWidth,
  }) : assert(
         labelOf != null || itemBuilder != null,
         'Provide either labelOf or itemBuilder',
       );

  @override
  State<AnchoredMenuTrigger<T>> createState() =>
      _AnchoredMenuTriggerState<T>();
}

class _AnchoredMenuTriggerState<T> extends State<AnchoredMenuTrigger<T>> {
  final LayerLink _link = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();
  OverlayEntry? _entry;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _entry?.remove();
    _entry = null;
  }

  double _measuredMenuWidth() {
    if (widget.menuWidth != null) return widget.menuWidth!;
    if (widget.labelOf == null) return 200.0;
    double maxTextWidth = 0;
    for (final item in widget.items) {
      final tp = TextPainter(
        text: TextSpan(
          text: widget.labelOf!(item),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (tp.width > maxTextWidth) maxTextWidth = tp.width;
    }
    return (maxTextWidth + 32).clamp(90.0, 260.0);
  }

  void _toggle() {
    if (_entry != null) {
      _removeOverlay();
      return;
    }
    final renderBox =
        _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final triggerWidth = renderBox?.size.width ?? 160.0;
    final measured = _measuredMenuWidth();
    final width = measured > triggerWidth ? measured : triggerWidth;
    final height = renderBox?.size.height ?? 36.0;

    final overlay = Overlay.of(context);
    _entry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _removeOverlay,
            ),
          ),
          CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            offset: Offset(0, height + 4),
            child: Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(10),
                color: Colors.white,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: width,
                    maxWidth: width,
                    maxHeight: widget.maxMenuHeight,
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: widget.items.map((item) {
                      final selected = item == widget.selectedValue;
                      return InkWell(
                        onTap: () {
                          _removeOverlay();
                          widget.onSelected(item);
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          color: selected
                              ? const Color(0xFFFDF2E9)
                              : Colors.transparent,
                          child: widget.itemBuilder != null
                              ? widget.itemBuilder!(item, selected)
                              : Text(
                            widget.labelOf!(item),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: selected
                                  ? const Color(0xFFB45309)
                                  : const Color(0xFF374151),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_entry!);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: GestureDetector(
        key: _fieldKey,
        onTap: _toggle,
        child: MouseRegion(cursor: SystemMouseCursors.click, child: widget.trigger),
      ),
    );
  }
}
