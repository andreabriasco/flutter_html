import 'package:csslib/parser.dart' as css_parser;
import 'package:csslib/visitor.dart' as css;
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html/src/builtins/details_element_builtin.dart';
import 'package:flutter_html/src/builtins/image_builtin.dart';
import 'package:flutter_html/src/builtins/interactive_element_builtin.dart';
import 'package:flutter_html/src/builtins/ruby_builtin.dart';
import 'package:flutter_html/src/builtins/styled_element_builtin.dart';
import 'package:flutter_html/src/builtins/text_builtin.dart';
import 'package:flutter_html/src/builtins/vertical_align_builtin.dart';
import 'package:flutter_html/src/html_processing_pipeline.dart';
import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' as html_parser;

typedef OnTap = void Function(
  String? url,
  Map<String, String> attributes,
  html.Element? element,
);

typedef OnCssParseError = String? Function(
  String css,
  List<css_parser.Message> errors,
);

class HtmlParser extends StatefulWidget {
  final html.Element htmlData;
  final OnTap? onLinkTap;
  final OnTap? onAnchorTap;
  final OnCssParseError? onCssParseError;
  final bool shrinkWrap;
  final Map<String, Style> style;
  final List<HtmlExtension> extensions;
  final Set<String>? doNotRenderTheseTags;
  final Set<String>? onlyRenderTheseTags;
  final OnTap? internalOnAnchorTap;
  final Html? root;

  HtmlParser({
    required super.key,
    required this.htmlData,
    required this.onLinkTap,
    required this.onAnchorTap,
    required this.onCssParseError,
    required this.shrinkWrap,
    required this.style,
    required this.extensions,
    required this.doNotRenderTheseTags,
    required this.onlyRenderTheseTags,
    this.root,
  }) : internalOnAnchorTap = onAnchorTap ??
            (key != null ? _handleAnchorTap(key, onLinkTap) : onLinkTap);

  @override
  State<HtmlParser> createState() => _HtmlParserState();

  static final builtIns = [
    const ImageBuiltIn(),
    const VerticalAlignBuiltIn(),
    const InteractiveElementBuiltIn(),
    const RubyBuiltIn(),
    const DetailsElementBuiltIn(),
    const StyledElementBuiltIn(),
    const TextBuiltIn(),
  ];

  /// [parseHTML] converts a string of HTML to a DOM element using the dart `html` library.
  static html.Element parseHTML(String data) {
    return html_parser.parse(data).documentElement!;
  }

  /// [parseCss] converts a string of CSS to a CSS stylesheet using the dart `csslib` library.
  static css.StyleSheet parseCss(String data) {
    return css_parser.parse(data);
  }

  static OnTap _handleAnchorTap(Key key, OnTap? onLinkTap) =>
      (String? url, Map<String, String> attributes, html.Element? element) {
        if (url?.startsWith("#") == true) {
          final anchorContext =
              AnchorKey.forId(key, url!.substring(1))?.currentContext;
          if (anchorContext != null) {
            Scrollable.ensureVisible(anchorContext);
          }
          return;
        }
        onLinkTap?.call(url, attributes, element);
      };

  /// Prepares the html node using one of the built-ins or HtmlExtensions
  /// available. If none of the extensions matches, returns an
  /// EmptyContentElement
  StyledElement prepareFromExtension(
    ExtensionContext extensionContext,
    List<StyledElement> children, {
    Set<HtmlExtension> extensionsToIgnore = const {},
  }) {
    // Loop through every extension and see if it can handle this node
    for (final extension in extensions) {
      if (!extensionsToIgnore.contains(extension) &&
          extension.matches(extensionContext)) {
        return extension.prepare(extensionContext, children);
      }
    }

    // Loop through built in elements and see if they can handle this node.
    for (final builtIn in builtIns) {
      if (!extensionsToIgnore.contains(builtIn) &&
          builtIn.matches(extensionContext)) {
        return builtIn.prepare(extensionContext, children);
      }
    }

    // If no extension or built-in matches, then return an empty content element.
    return EmptyContentElement(node: extensionContext.node);
  }

  /// Builds the StyledElement into an InlineSpan using one of the built-ins
  /// or HtmlExtensions available. If none of the extensions matches, returns
  /// an empty TextSpan.
  InlineSpan buildFromExtension(
    ExtensionContext extensionContext, {
    Set<HtmlExtension> extensionsToIgnore = const {},
  }) {
    // Loop through every extension and see if it can handle this node
    for (final extension in extensions) {
      if (!extensionsToIgnore.contains(extension) &&
          extension.matches(extensionContext)) {
        return extension.build(extensionContext);
      }
    }

    // Loop through built in elements and see if they can handle this node.
    for (final builtIn in builtIns) {
      if (!extensionsToIgnore.contains(builtIn) &&
          builtIn.matches(extensionContext)) {
        return builtIn.build(extensionContext);
      }
    }

    return const TextSpan(text: "");
  }
}

class _HtmlParserState extends State<HtmlParser> {
  late StyledElement tree;

  @override
  void didChangeDependencies() {
    tree = HtmlProcessingPipeline(
      parser: widget,
      buildContext: context,
    ).prepareTree();
    super.didChangeDependencies();
  }

  /// As the widget [build]s, the HTML data is processed into a tree of [StyledElement]s,
  /// which are then parsed into an [InlineSpan] tree that is then rendered to the screen by Flutter
  @override
  Widget build(BuildContext context) {
    //Rendering Step
    return CssBoxWidget.withInlineSpanChildren(
      style: tree.style,
      //TODO can we have buildTree return a list of InlineSpans rather than a single one.
      children: [buildTree()],
      shrinkWrap: widget.shrinkWrap,
      top: true,
    );
  }

  @override
  void dispose() {
    for (var e in widget.extensions) {
      e.onDispose();
    }
    super.dispose();
  }

  bool _isTagRestricted(ExtensionContext context) {
    // Block the tag from rendering if it is restricted.
    if (context.node is! html.Element) {
      return false;
    }

    if (widget.doNotRenderTheseTags != null &&
        widget.doNotRenderTheseTags!.contains(context.elementName)) {
      return true;
    }

    if (widget.onlyRenderTheseTags != null &&
        !widget.onlyRenderTheseTags!.contains(context.elementName)) {
      return true;
    }

    return false;
  }

  /// [buildTree] converts a tree of [StyledElement]s to an [InlineSpan] tree.
  InlineSpan buildTree() {
    //TODO, can't we just break tree out from parent element created in lexHtmlTree?
    return _buildTreeRecursive(tree);
  }

  InlineSpan _buildTreeRecursive(StyledElement tree) {
    // Generate a function that allows children to be built lazily
    Map<StyledElement, InlineSpan> buildChildren() {
      return Map.fromEntries(tree.children.map((child) {
        return MapEntry(child, _buildTreeRecursive(child));
      }));
    }

    // Set the extension context for this node.
    final extensionContext = ExtensionContext(
      parser: widget,
      buildContext: context,
      node: tree.node,
      styledElement: tree,
      currentStep: CurrentStep.building,
      buildChildrenCallback: buildChildren,
    );

    // Block restricted tags from getting sent to extensions
    if (_isTagRestricted(extensionContext)) {
      return const TextSpan(text: "");
    }

    return widget.buildFromExtension(extensionContext);
  }
}
