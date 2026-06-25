import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html/src/html_processing_pipeline.dart';
import 'package:flutter_html/src/tree/replaced_element.dart';
import 'package:flutter_html/src/utils.dart';
import 'package:html/dom.dart' as html;

class HtmlMeasurement {
  final bool supported;
  final int lineCount;
  final Size size;

  const HtmlMeasurement({
    required this.supported,
    required this.lineCount,
    required this.size,
  });

  const HtmlMeasurement.unsupported()
      : supported = false,
        lineCount = 0,
        size = Size.zero;
}

class HtmlTextMeasurer {
  const HtmlTextMeasurer();

  static const _supportedTextMeasurementTags = {
    'a',
    'abbr',
    'acronym',
    'address',
    'article',
    'aside',
    'b',
    'bdi',
    'bdo',
    'big',
    'blockquote',
    'body',
    'center',
    'cite',
    'code',
    'data',
    'dd',
    'del',
    'dfn',
    'div',
    'dl',
    'dt',
    'em',
    'figcaption',
    'figure',
    'font',
    'footer',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'header',
    'html',
    'i',
    'ins',
    'kbd',
    'li',
    'main',
    'mark',
    'nav',
    'noscript',
    'ol',
    'p',
    'pre',
    'q',
    's',
    'samp',
    'section',
    'small',
    'span',
    'strike',
    'strong',
    'summary',
    'time',
    'tt',
    'u',
    'ul',
    'var',
    'wbr',
  };

  HtmlMeasurement measure({
    required BuildContext context,
    required Map<String, Style> style,
    required double maxWidth,
    required TextDirection textDirection,
    String? data,
    html.Element? element,
    TextScaler textScaler = TextScaler.noScaling,
    Locale? locale,
    List<HtmlExtension> extensions = const [],
    bool shrinkWrap = false,
    Set<String>? doNotRenderTheseTags,
    Set<String>? onlyRenderTheseTags,
    OnCssParseError? onCssParseError,
  }) {
    if (maxWidth <= 0 || !maxWidth.isFinite) {
      return const HtmlMeasurement.unsupported();
    }

    // Start from the same DOM input used by the Html widget. Raw data is parsed
    // first; pre-parsed elements can be measured directly.
    final htmlData = data != null ? HtmlParser.parseHTML(data) : element;
    if (htmlData == null) {
      return const HtmlMeasurement.unsupported();
    }

    // Build an HtmlParser configured with the same options that affect render
    // output: styles, extensions, tag filters, shrinkWrap, and CSS error hooks.
    final parser = HtmlParser(
      key: GlobalKey(),
      htmlData: htmlData,
      onLinkTap: null,
      onAnchorTap: null,
      onCssParseError: onCssParseError,
      shrinkWrap: shrinkWrap,
      style: style,
      extensions: extensions,
      doNotRenderTheseTags: doNotRenderTheseTags,
      onlyRenderTheseTags: onlyRenderTheseTags,
    );

    // Reuse flutter_html's own processing pipeline so style resolution,
    // whitespace, list markers, generated content, and margins match render.
    final tree = HtmlProcessingPipeline(
      parser: parser,
      buildContext: context,
    ).prepareTree();

    // The render path turns this tree into widgets/spans. The measurer walks the
    // same processed tree and calculates text metrics instead.
    final result = _measureFlow(
      tree.children,
      tree.style,
      maxWidth,
      textDirection,
      textScaler,
      locale,
      shrinkWrap,
    );

    if (result == null) {
      return const HtmlMeasurement.unsupported();
    }

    return HtmlMeasurement(
      supported: true,
      lineCount: result.lineCount,
      size: result.size,
    );
  }

  // Measures a flow of sibling elements. Inline siblings are kept together,
  // while block siblings split the flow and are measured separately.
  _MeasureResult? _measureFlow(
    List<StyledElement> children,
    Style currentStyle,
    double maxWidth,
    TextDirection textDirection,
    TextScaler textScaler,
    Locale? locale,
    bool shrinkWrap, [
    List<InlineSpan> initialInlineSpans = const [],
  ]) {
    var lineCount = 0;
    var width = 0.0;
    var height = 0.0;
    final inlineSpans = List<InlineSpan>.of(initialInlineSpans);

    // Closes the current inline run. If there is no pending inline content, a
    // zero-sized result lets the caller continue measuring the surrounding flow.
    _MeasureResult? flushInlineSpans() {
      if (inlineSpans.isEmpty) {
        return const _MeasureResult(lineCount: 0, size: Size.zero);
      }

      final result = _measureSpan(
        TextSpan(
          style: currentStyle.generateTextStyle(),
          children: List<InlineSpan>.of(inlineSpans),
        ),
        maxWidth,
        textDirection,
        textScaler,
        locale,
        currentStyle.maxLines,
      );
      inlineSpans.clear();
      return result;
    }

    for (final child in children) {
      final display = child.style.display ?? Display.inline;
      if (display == Display.none || child is EmptyContentElement) {
        continue;
      }

      if (display.isBlock || display.displayListItem) {
        // A block breaks the inline run. Measure any inline content that came
        // before it, then measure the block as its own vertical segment.
        final inlineResult = flushInlineSpans();
        if (inlineResult == null) return null;
        lineCount += inlineResult.lineCount;
        width = math.max(width, inlineResult.size.width);
        height += inlineResult.size.height;

        final blockResult = _measureBlock(
          child,
          maxWidth,
          textDirection,
          textScaler,
          locale,
          shrinkWrap,
        );
        if (blockResult == null) return null;
        lineCount += blockResult.lineCount;
        width = math.max(width, blockResult.size.width);
        height += blockResult.size.height;
      } else {
        // Inline elements stay in the same run so wrapping is calculated across
        // the full inline sequence, just like Flutter's text layout does.
        final span = _buildInlineSpan(child);
        if (span == null) return null;
        inlineSpans.add(span);
      }
    }

    // Measure the final inline run, if the flow ended with inline content.
    final inlineResult = flushInlineSpans();
    if (inlineResult == null) return null;
    lineCount += inlineResult.lineCount;
    width = math.max(width, inlineResult.size.width);
    height += inlineResult.size.height;

    return _MeasureResult(
      lineCount: lineCount,
      size: Size(width, height),
    );
  }

  // Measures block-like elements as containers. Box spacing is applied first,
  // then children are measured recursively inside the remaining content width.
  _MeasureResult? _measureBlock(
    StyledElement element,
    double maxWidth,
    TextDirection textDirection,
    TextScaler textScaler,
    Locale? locale,
    bool shrinkWrap,
  ) {
    if (!_supportsElement(element)) return null;

    final padding =
        element.style.padding?.resolve(textDirection) ?? EdgeInsets.zero;
    final margin = element.style.margin ?? Margins.zero;
    final borderSize =
        element.style.border?.dimensions.collapsedSize ?? Size.zero;
    final horizontalSpace =
        padding.horizontal + margin.horizontal + borderSize.width;
    final verticalSpace =
        padding.vertical + margin.vertical + borderSize.height;
    final childMaxWidth = math.max(0.0, maxWidth - horizontalSpace);

    // Empty blocks can still render box spacing and width, so keep measuring
    // the container even when there is no text child.
    //
    // List items can render markers inside the content box. Seed the child flow
    // with the marker span so it contributes to line wrapping and width.
    final childResult = element.children.isEmpty
        ? const _MeasureResult(lineCount: 0, size: Size.zero)
        : _measureFlow(
            element.children,
            element.style,
            childMaxWidth,
            textDirection,
            textScaler,
            locale,
            shrinkWrap,
            _listMarkerSpans(element),
          );

    if (childResult == null) return null;

    final display = element.style.display ?? Display.inline;
    // Non-shrink-wrapped blocks occupy the full available width in flutter_html,
    // even when the text inside is shorter.
    final blockWidth = display.isBlock && !shrinkWrap
        ? maxWidth
        : math.min(maxWidth, childResult.size.width + horizontalSpace);

    return _MeasureResult(
      lineCount: childResult.lineCount,
      size: Size(
        blockWidth,
        childResult.size.height + verticalSpace,
      ),
    );
  }

  // Converts a supported inline element subtree into spans that TextPainter can
  // measure. Widget-like or unsupported content makes the measurement fail.
  InlineSpan? _buildInlineSpan(StyledElement element) {
    if (!_supportsElement(element)) return null;

    if (element is TextContentElement) {
      return TextSpan(
        text: element.text.transformed(element.style.textTransform),
        style: element.style.generateTextStyle(),
      );
    }

    if (element is LinebreakContentElement) {
      return TextSpan(
        text: '\n',
        style: element.style.generateTextStyle(),
      );
    }

    final display = element.style.display ?? Display.inline;
    if (display.isBlock || display.displayListItem) {
      return null;
    }

    final children = <InlineSpan>[];
    for (final child in element.children) {
      final childSpan = _buildInlineSpan(child);
      if (childSpan == null) return null;
      children.add(childSpan);
    }

    return TextSpan(
      style: element.style.generateTextStyle(),
      children: children,
    );
  }

  List<InlineSpan> _listMarkerSpans(StyledElement element) {
    if (element.style.listStylePosition != ListStylePosition.inside ||
        element.style.display?.displayListItem != true) {
      return const [];
    }

    final marker = element.style.marker?.content.replacementContent;
    if (marker == null || marker.isEmpty) {
      return const [];
    }

    return [
      TextSpan(
        text: marker,
        style: element.style.marker?.style?.generateTextStyle(),
      ),
    ];
  }

  _MeasureResult _measureSpan(
    InlineSpan span,
    double maxWidth,
    TextDirection textDirection,
    TextScaler textScaler,
    Locale? locale,
    int? maxLines,
  ) {
    final painter = TextPainter(
      text: span,
      textDirection: textDirection,
      textScaler: textScaler,
      locale: locale,
      maxLines: maxLines,
    )..layout(maxWidth: maxWidth);

    final result = _MeasureResult(
      lineCount: painter.computeLineMetrics().length,
      size: painter.size,
    );
    painter.dispose();
    return result;
  }

  bool _supportsElement(StyledElement element) {
    // Be conservative: unsupported content falls back to the safer layout path
    // instead of pretending we can measure it accurately.
    if (element is EmptyContentElement) return true;
    if (element is TextContentElement) return true;
    if (element is LinebreakContentElement) return true;
    if (element is ReplacedElement) return false;
    if (!_supportedTextMeasurementTags.contains(element.name)) return false;

    final display = element.style.display ?? Display.inline;
    if (display == Display.none) return true;
    return display == Display.inline ||
        display == Display.block ||
        display == Display.listItem;
  }
}

class _MeasureResult {
  final int lineCount;
  final Size size;

  const _MeasureResult({
    required this.lineCount,
    required this.size,
  });
}
