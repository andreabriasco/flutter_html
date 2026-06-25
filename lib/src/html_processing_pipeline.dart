import 'package:flutter/widgets.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html/src/css_parser.dart';
import 'package:flutter_html/src/extension/extension_context.dart';
import 'package:flutter_html/src/processing/befores_afters.dart';
import 'package:flutter_html/src/processing/lists.dart';
import 'package:flutter_html/src/processing/margins.dart';
import 'package:flutter_html/src/processing/relative_sizes.dart';
import 'package:flutter_html/src/processing/whitespace.dart';
import 'package:flutter_html/src/tree/replaced_element.dart';
import 'package:html/dom.dart' as html;

class HtmlProcessingPipeline {
  HtmlProcessingPipeline({
    required this.parser,
    required this.buildContext,
  });

  final HtmlParser parser;
  final BuildContext buildContext;

  StyledElement prepareTree() {
    // Preparing Step
    var tree = _prepareHtmlTree();

    // Styling Step
    _beforeStyleTree(tree);
    _styleTree(tree);

    // Processing Step
    _beforeProcessTree(tree);
    tree = _processTree(tree);

    return tree;
  }

  /// Converts the tree of Html nodes into a simplified StyledElement tree
  StyledElement _prepareHtmlTree() {
    final tree = StyledElement(
      name: '[Tree Root]',
      children: [],
      node: parser.htmlData,
      style: Style.fromTextStyle(DefaultTextStyle.of(buildContext).style),
    );

    for (final node in parser.htmlData.nodes) {
      tree.children.add(_prepareHtmlTreeRecursive(node));
    }

    return tree;
  }

  /// Recursive helper method for [_prepareHtmlTree].
  StyledElement _prepareHtmlTreeRecursive(html.Node node) {
    // Set the extension context for this node.
    final extensionContext = ExtensionContext(
      parser: parser,
      buildContext: buildContext,
      node: node,
      currentStep: CurrentStep.preparing,
    );

    // Block the tag from rendering if it is restricted.
    if (_isTagRestricted(extensionContext)) {
      return EmptyContentElement(node: node);
    }

    // Lex this element's children
    final children = node.nodes.map(_prepareHtmlTreeRecursive).toList();

    // Prepare the element from one of the extensions
    return parser.prepareFromExtension(extensionContext, children);
  }

  /// Called before any styling is cascaded on the tree
  void _beforeStyleTree(StyledElement tree) {
    final extensionContext = ExtensionContext(
      node: tree.node,
      parser: parser,
      styledElement: tree,
      buildContext: buildContext,
      currentStep: CurrentStep.preStyling,
    );

    // Prevent restricted tags from getting sent to extensions.
    if (_isTagRestricted(extensionContext)) {
      return;
    }

    // Loop through every extension and see if it wants to process this element
    for (final extension in parser.extensions) {
      if (extension.matches(extensionContext)) {
        extension.beforeStyle(extensionContext);
      }
    }

    // Loop through built in elements and see if they want to process this element.
    for (final builtIn in HtmlParser.builtIns) {
      if (builtIn.matches(extensionContext)) {
        builtIn.beforeStyle(extensionContext);
      }
    }

    // Do the same recursively
    tree.children.forEach(_beforeStyleTree);
  }

  /// [_styleTree] takes the lexed [StyleElement] tree and applies external,
  /// inline, and custom CSS/Flutter styles, and then cascades the styles down the tree.
  void _styleTree(StyledElement tree) {
    final styleTagContents = parser.htmlData
        .getElementsByTagName('style')
        .map((e) => e.innerHtml)
        .join();
    final styleTagDeclarations =
        parseExternalCss(styleTagContents, parser.onCssParseError);

    _styleTreeRecursive(tree, styleTagDeclarations);
  }

  /// Recursive helper method for [_styleTree].
  void _styleTreeRecursive(StyledElement tree, styleTagDeclarations) {
    // Apply external CSS
    styleTagDeclarations.forEach((selector, style) {
      if (tree.matchesSelector(selector)) {
        tree.style = tree.style.merge(declarationsToStyle(style));
      }
    });

    // Apply inline styles
    if (tree.attributes.containsKey('style')) {
      final newStyle =
          inlineCssToStyle(tree.attributes['style'], parser.onCssParseError);
      if (newStyle != null) {
        tree.style = tree.style.merge(newStyle);
      }
    }

    // Apply custom styles
    parser.style.forEach((selector, style) {
      if (tree.matchesSelector(selector)) {
        tree.style = tree.style.merge(style);
      }
    });

    // Cascade applicable styles down the tree. Recurse for all children
    for (final child in tree.children) {
      child.style = tree.style.copyOnlyInherited(child.style);
      _styleTreeRecursive(child, styleTagDeclarations);
    }
  }

  /// Called before any processing is done on the tree
  void _beforeProcessTree(StyledElement tree) {
    final extensionContext = ExtensionContext(
      node: tree.node,
      parser: parser,
      styledElement: tree,
      buildContext: buildContext,
      currentStep: CurrentStep.preProcessing,
    );

    // Prevent restricted tags from getting sent to extensions
    if (_isTagRestricted(extensionContext)) {
      return;
    }

    // Loop through every extension and see if it can process this element
    for (final extension in parser.extensions) {
      if (extension.matches(extensionContext)) {
        extension.beforeProcessing(extensionContext);
      }
    }

    // Loop through built in elements and see if they can process this element.
    for (final builtIn in HtmlParser.builtIns) {
      if (builtIn.matches(extensionContext)) {
        builtIn.beforeProcessing(extensionContext);
      }
    }

    // Do the same recursively
    tree.children.forEach(_beforeProcessTree);
  }

  /// [_processTree] takes the now-styled [StyleElement] tree and does some final
  /// processing steps: removing unnecessary whitespace and empty elements,
  /// calculating relative values, processing list markers and counters,
  /// processing `before`/`after` generated elements, and collapsing margins
  /// according to CSS rules.
  StyledElement _processTree(StyledElement tree) {
    tree = WhitespaceProcessing.processWhitespace(tree);
    tree = RelativeSizesProcessing.processRelativeValues(tree);
    tree = ListProcessing.processLists(tree);
    tree = BeforesAftersProcessing.processBeforesAfters(tree);
    tree = MarginProcessing.processMargins(tree);
    return tree;
  }

  bool _isTagRestricted(ExtensionContext context) {
    if (context.node is! html.Element) {
      return false;
    }

    if (parser.doNotRenderTheseTags != null &&
        parser.doNotRenderTheseTags!.contains(context.elementName)) {
      return true;
    }

    if (parser.onlyRenderTheseTags != null &&
        !parser.onlyRenderTheseTags!.contains(context.elementName)) {
      return true;
    }

    return false;
  }
}
