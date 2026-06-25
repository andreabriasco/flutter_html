import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

void main() {
  testWidgets('measures paragraph text', (tester) async {
    late HtmlMeasurement measurement;

    await tester.pumpWidget(
      _TestHost(
        builder: (context) {
          measurement = const HtmlTextMeasurer().measure(
            context: context,
            data: '<p>Short title</p>',
            style: _textStyles,
            maxWidth: 240,
            textDirection: TextDirection.ltr,
          );
          return const SizedBox.shrink();
        },
      ),
    );

    expect(measurement.supported, isTrue);
    expect(measurement.lineCount, 1);
  });

  testWidgets('counts short list items as separate lines', (tester) async {
    late HtmlMeasurement measurement;

    await tester.pumpWidget(
      _TestHost(
        builder: (context) {
          measurement = const HtmlTextMeasurer().measure(
            context: context,
            data: '<ul><li>Short item</li><li>Also short</li></ul>',
            style: _textStyles,
            maxWidth: 240,
            textDirection: TextDirection.ltr,
          );
          return const SizedBox.shrink();
        },
      ),
    );

    expect(measurement.supported, isTrue);
    expect(measurement.lineCount, 2);
  });

  testWidgets('counts wrapped list items across multiple lines',
      (tester) async {
    late HtmlMeasurement measurement;

    await tester.pumpWidget(
      _TestHost(
        builder: (context) {
          measurement = const HtmlTextMeasurer().measure(
            context: context,
            data:
                '<ul><li>This first item is long enough to wrap</li><li>Short</li></ul>',
            style: _textStyles,
            maxWidth: 120,
            textDirection: TextDirection.ltr,
          );
          return const SizedBox.shrink();
        },
      ),
    );

    expect(measurement.supported, isTrue);
    expect(measurement.lineCount, greaterThan(2));
  });

  testWidgets('returns unsupported for non-text html', (tester) async {
    late HtmlMeasurement measurement;

    await tester.pumpWidget(
      _TestHost(
        builder: (context) {
          measurement = const HtmlTextMeasurer().measure(
            context: context,
            data: '<img src="https://example.com/image.png" />',
            style: _textStyles,
            maxWidth: 240,
            textDirection: TextDirection.ltr,
          );
          return const SizedBox.shrink();
        },
      ),
    );

    expect(measurement.supported, isFalse);
  });

  testWidgets('measures a pre-parsed html element', (tester) async {
    late HtmlMeasurement measurement;

    await tester.pumpWidget(
      _TestHost(
        builder: (context) {
          measurement = const HtmlTextMeasurer().measure(
            context: context,
            element: html_parser.parse('<p>Short title</p>').documentElement!,
            style: _textStyles,
            maxWidth: 240,
            textDirection: TextDirection.ltr,
          );
          return const SizedBox.shrink();
        },
      ),
    );

    expect(measurement.supported, isTrue);
    expect(measurement.lineCount, 1);
  });

  testWidgets('returns unsupported for widget-based html', (tester) async {
    late HtmlMeasurement measurement;

    await tester.pumpWidget(
      _TestHost(
        builder: (context) {
          measurement = const HtmlTextMeasurer().measure(
            context: context,
            data: '<details><summary>Title</summary><p>Body</p></details>',
            style: _textStyles,
            maxWidth: 240,
            textDirection: TextDirection.ltr,
          );
          return const SizedBox.shrink();
        },
      ),
    );

    expect(measurement.supported, isFalse);
  });
}

final _textStyles = {
  'body': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
  'html': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
  'p': Style(
    margin: Margins.zero,
    fontSize: FontSize(16),
    lineHeight: LineHeight(1.2),
  ),
  'ul': Style(margin: Margins.zero),
  'li': Style(fontSize: FontSize(16), lineHeight: LineHeight(1.2)),
};

class _TestHost extends StatelessWidget {
  final WidgetBuilder builder;

  const _TestHost({required this.builder});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(builder: builder),
      ),
    );
  }
}
