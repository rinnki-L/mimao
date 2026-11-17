/// HTML DOM 桥：把 Venera 源脚本的 `HtmlDocument` / `HtmlElement` / `HtmlNode`
/// 调用（method: 'html'）映射到 `package:html` 的 DOM。
///
/// 源脚本拿到的不是 Dart 对象，而是整数 key（句柄）；每次 query 返回一个新
/// key，注册到 [_nodes] 里。这样和 Venera `js_engine.dart` 的 key 语义一致，
/// `dispose` 也能释放整棵文档。
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' show parse;

/// `method: 'html'` 分派器。
class HtmlDomBridge {
  final Map<int, dom.Node> _nodes = <int, dom.Node>{};
  int _nextKey = 1;

  /// 处理一条 html 消息；返回值原样交回 JS（JSInvokable 会自动转 JS 类型）。
  Object? dispatch(Map<dynamic, dynamic> message) {
    final function = message['function'] as String? ?? '';
    switch (function) {
      case 'parse':
        final raw = message['data']?.toString() ?? '';
        final document = parse(raw);
        final key = _register(document);
        return key;
      case 'dispose':
        final key = _asInt(message['key']);
        // Venera 的 dispose 传文档 key；清掉该文档根即可。节点句柄仍可查，
        // 但 JS 侧已不再持有它们；下次 parse 会从新的 key 段开始。
        _documents.remove(key);
        _nodes.remove(key);
        return null;
      case 'querySelector':
        final root = _node(message['key']);
        final query = message['query']?.toString() ?? '';
        if (root == null) return null;
        final found = _queryOne(root, query);
        return found == null
            ? null
            : _register(found, doc: _asInt(message['key']));
      case 'querySelectorAll':
        final root = _node(message['key']);
        final query = message['query']?.toString() ?? '';
        if (root == null) return <int>[];
        return _queryAll(
          root,
          query,
        ).map((node) => _register(node, doc: _asInt(message['key']))).toList();
      case 'getElementById':
        final root = _node(message['key']);
        if (root == null) return null;
        final id = message['id']?.toString() ?? '';
        final found = _queryOne(root, '#$id');
        return found == null
            ? null
            : _register(found, doc: _asInt(message['key']));
      case 'dom_querySelector':
        final node = _node(message['key']);
        final query = message['query']?.toString() ?? '';
        if (node == null) return null;
        final found = _queryOne(node, query);
        return found == null
            ? null
            : _register(found, doc: _asInt(message['doc']));
      case 'dom_querySelectorAll':
        final node = _node(message['key']);
        final query = message['query']?.toString() ?? '';
        if (node == null) return <int>[];
        return _queryAll(
          node,
          query,
        ).map((n) => _register(n, doc: _asInt(message['doc']))).toList();
      case 'getText':
        final node = _node(message['key']);
        return node?.text ?? '';
      case 'getAttributes':
        final node = _node(message['key']);
        if (node is! dom.Element) return <String, String>{};
        return <String, String>{
          for (final entry in node.attributes.entries)
            '${entry.key}': entry.value,
        };
      case 'getChildren':
        final node = _node(message['key']);
        final docKey = _asInt(message['doc']);
        if (node == null) return <int>[];
        return node.nodes
            .whereType<dom.Element>()
            .map((n) => _register(n, doc: docKey))
            .toList();
      case 'getNodes':
        final node = _node(message['key']);
        final docKey = _asInt(message['doc']);
        if (node == null) return <int>[];
        return node.nodes.map((n) => _register(n, doc: docKey)).toList();
      case 'getInnerHTML':
        final node = _node(message['key']);
        if (node is dom.Element) return node.innerHtml;
        return node?.text ?? '';
      case 'getParent':
        final node = _node(message['key']);
        final parent = node?.parent;
        return parent == null
            ? null
            : _register(parent, doc: _asInt(message['doc']));
      case 'getClassNames':
        final node = _node(message['key']);
        if (node is! dom.Element) return <String>[];
        return node.classes.toList();
      case 'getId':
        final node = _node(message['key']);
        return node is dom.Element ? node.id : null;
      case 'getLocalName':
        final node = _node(message['key']);
        return node is dom.Element ? node.localName : null;
      case 'getPreviousSibling':
        final node = _node(message['key']);
        final sibling = node is dom.Element
            ? node.previousElementSibling
            : null;
        return sibling == null
            ? null
            : _register(sibling, doc: _asInt(message['doc']));
      case 'getNextSibling':
        final node = _node(message['key']);
        final sibling = node is dom.Element ? node.nextElementSibling : null;
        return sibling == null
            ? null
            : _register(sibling, doc: _asInt(message['doc']));
      case 'node_text':
        return _node(message['key'])?.text ?? '';
      case 'node_type':
        return _nodeType(_node(message['key']));
      case 'node_toElement':
        final node = _node(message['key']);
        return node is dom.Element
            ? _register(node, doc: _asInt(message['doc']))
            : null;
      default:
        return null;
    }
  }

  /// 已解析的根文档 key——`dispose` 用来做归属清理。
  final Set<int> _documents = <int>{};

  int _register(dom.Node node, {int? doc}) {
    final key = _nextKey++;
    _nodes[key] = node;
    if (doc == null) _documents.add(key);
    return key;
  }

  dom.Node? _node(dynamic key) {
    if (key == null) return null;
    return _nodes[_asInt(key)];
  }

  dom.Element? _queryOne(dom.Node root, String query) {
    if (query.isEmpty) return null;
    try {
      // Document 与 Element 都带 querySelector（_ParentNode mixin）。
      return switch (root) {
        dom.Element() => root.querySelector(query),
        dom.Document() => root.querySelector(query),
        dom.DocumentFragment() => root.querySelector(query),
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  List<dom.Element> _queryAll(dom.Node root, String query) {
    if (query.isEmpty) return <dom.Element>[];
    try {
      return switch (root) {
        dom.Element() => root.querySelectorAll(query),
        dom.Document() => root.querySelectorAll(query),
        dom.DocumentFragment() => root.querySelectorAll(query),
        _ => <dom.Element>[],
      };
    } catch (_) {
      return <dom.Element>[];
    }
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _nodeType(dom.Node? node) => switch (node) {
    dom.Text() => 'text',
    dom.Element() => 'element',
    dom.Comment() => 'comment',
    dom.Document() => 'document',
    _ => 'unknown',
  };
}
