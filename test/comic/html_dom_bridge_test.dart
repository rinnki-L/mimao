/// HtmlDomBridge 单测：CSS 选择器、text/attributes、父子兄弟、节点类型。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:mimao/comic/engine/engine.dart';

void main() {
  const html = '''
<html><body>
  <div id="one" class="item active"><a href="/a" data-id="1">First</a></div>
  <div id="two" class="item"><a href="/b">Second</a></div>
  <p id="text">hello <b>world</b></p>
</body></html>
''';

  Object? call(HtmlDomBridge dom, String fn, Map<dynamic, dynamic> extra) => dom
      .dispatch(<dynamic, dynamic>{'method': 'html', 'function': fn, ...extra});

  test('parse + querySelectorAll + text + attributes', () {
    final dom = HtmlDomBridge();
    final doc = call(dom, 'parse', <dynamic, dynamic>{'data': html}) as int;

    final items =
        call(dom, 'querySelectorAll', <dynamic, dynamic>{
              'key': doc,
              'query': '.item',
            })
            as List;
    expect(items.length, 2);

    final first = items.first as int;
    final id = call(dom, 'getId', <dynamic, dynamic>{'key': first, 'doc': doc});
    expect(id, 'one');

    final classes =
        call(dom, 'getClassNames', <dynamic, dynamic>{'key': first, 'doc': doc})
            as List;
    expect(classes, contains('active'));

    final anchor = call(dom, 'dom_querySelector', <dynamic, dynamic>{
      'key': first,
      'query': 'a',
      'doc': doc,
    });
    final attributes =
        call(dom, 'getAttributes', <dynamic, dynamic>{
              'key': anchor,
              'doc': doc,
            })
            as Map;
    expect(attributes['href'], '/a');
    expect(attributes['data-id'], '1');

    final text = call(dom, 'getText', <dynamic, dynamic>{
      'key': anchor,
      'doc': doc,
    });
    expect(text, 'First');
  });

  test('getElementById + children + nextElementSibling + innerHTML', () {
    final dom = HtmlDomBridge();
    final doc = call(dom, 'parse', <dynamic, dynamic>{'data': html}) as int;

    final p = call(dom, 'getElementById', <dynamic, dynamic>{
      'key': doc,
      'id': 'text',
    });
    final inner = call(dom, 'getInnerHTML', <dynamic, dynamic>{
      'key': p,
      'doc': doc,
    });
    expect(inner, contains('<b>world</b>'));

    final first = call(dom, 'querySelector', <dynamic, dynamic>{
      'key': doc,
      'query': '#one',
    });
    final sibling = call(dom, 'getNextSibling', <dynamic, dynamic>{
      'key': first,
      'doc': doc,
    });
    final siblingId = call(dom, 'getId', <dynamic, dynamic>{
      'key': sibling,
      'doc': doc,
    });
    expect(siblingId, 'two');
  });

  test('nodes + node_type + node_text', () {
    final dom = HtmlDomBridge();
    final doc = call(dom, 'parse', <dynamic, dynamic>{'data': html}) as int;
    final p = call(dom, 'getElementById', <dynamic, dynamic>{
      'key': doc,
      'id': 'text',
    });
    final nodes =
        call(dom, 'getNodes', <dynamic, dynamic>{'key': p, 'doc': doc}) as List;
    expect(nodes.isNotEmpty, isTrue);
    final types = nodes
        .map(
          (n) =>
              call(dom, 'node_type', <dynamic, dynamic>{'key': n, 'doc': doc}),
        )
        .toList();
    expect(types, contains('text'));
  });
}
