/// 书源选项的宽松 JSON 解析：legado 用 GSON lenient 模式，允许单引号、
/// 无引号键名、尾逗号与 `//` 注释；Dart 的 `jsonDecode` 全部拒绝。
///
/// 只用于 URL 选项 / 请求头 / `@put` 这些书源作者手写的片段，不用于网络返回的
/// 严格 JSON。
library;

/// 宽松 JSON 解码；无法解析时返回 null。
Object? lenientJsonDecode(String text) {
  final parser = _Parser(text);
  try {
    final value = parser.parseValue();
    parser.skipSpace();
    if (parser.index < parser.text.length) return null;
    return value;
  } on Object {
    return null;
  }
}

Map<String, Object?>? lenientJsonObject(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  final value = lenientJsonDecode(text);
  if (value is Map) return Map<String, Object?>.from(value);
  return null;
}

class _Parser {
  _Parser(this.text);

  final String text;
  int index = 0;

  Object? parseValue() {
    skipSpace();
    if (index >= text.length) return null;
    final char = text[index];
    if (char == '{') return parseObject();
    if (char == '[') return parseArray();
    if (char == '"' || char == "'") return parseString();
    return parseBare();
  }

  Map<String, Object?> parseObject() {
    final map = <String, Object?>{};
    index++; // {
    skipSpace();
    if (peek == '}') {
      index++;
      return map;
    }
    while (index < text.length) {
      skipSpace();
      if (peek == '}') {
        index++;
        break;
      }
      final key = peek == '"' || peek == "'"
          ? parseString()
          : parseBare().toString();
      skipSpace();
      if (peek != ':') {
        // 允许 `{a,b}` 这种把键当值的写法，值为 null。
        map[key.toString()] = null;
      } else {
        index++;
        map[key.toString()] = parseValue();
      }
      skipSpace();
      if (peek == ',') {
        index++;
        skipSpace();
        continue;
      }
      if (peek == '}') {
        index++;
        break;
      }
      break;
    }
    return map;
  }

  List<Object?> parseArray() {
    final list = <Object?>[];
    index++; // [
    skipSpace();
    if (peek == ']') {
      index++;
      return list;
    }
    while (index < text.length) {
      list.add(parseValue());
      skipSpace();
      if (peek == ',') {
        index++;
        skipSpace();
        continue;
      }
      if (peek == ']') {
        index++;
        break;
      }
      break;
    }
    return list;
  }

  String parseString() {
    final quote = text[index++];
    final buffer = StringBuffer();
    while (index < text.length) {
      final char = text[index++];
      if (char == quote) break;
      if (char == r'\' && index < text.length) {
        final next = text[index++];
        switch (next) {
          case 'n':
            buffer.write('\n');
          case 'r':
            buffer.write('\r');
          case 't':
            buffer.write('\t');
          case 'b':
            buffer.write('\b');
          case 'f':
            buffer.write('\f');
          case 'u':
            if (index + 4 <= text.length) {
              final code = int.tryParse(
                text.substring(index, index + 4),
                radix: 16,
              );
              if (code != null) {
                buffer.write(String.fromCharCode(code));
                index += 4;
              }
            }
          default:
            buffer.write(next);
        }
        continue;
      }
      buffer.write(char);
    }
    return buffer.toString();
  }

  Object? parseBare() {
    skipSpace();
    final start = index;
    while (index < text.length) {
      final char = text[index];
      if (char == ',' ||
          char == '}' ||
          char == ']' ||
          char == ':' ||
          char == ' ' ||
          char == '\t' ||
          char == '\n' ||
          char == '\r') {
        break;
      }
      index++;
    }
    final token = text.substring(start, index).trim();
    if (token.isEmpty) return '';
    if (token == 'true') return true;
    if (token == 'false') return false;
    if (token == 'null' || token == 'undefined') return null;
    final integer = int.tryParse(token);
    if (integer != null) return integer;
    final decimal = double.tryParse(token);
    if (decimal != null) return decimal;
    return token;
  }

  String get peek => index < text.length ? text[index] : '';

  void skipSpace() {
    while (index < text.length) {
      final char = text[index];
      if (char == ' ' || char == '\t' || char == '\n' || char == '\r') {
        index++;
        continue;
      }
      if (text.startsWith('//', index)) {
        final end = text.indexOf('\n', index);
        index = end < 0 ? text.length : end + 1;
        continue;
      }
      if (text.startsWith('/*', index)) {
        final end = text.indexOf('*/', index + 2);
        index = end < 0 ? text.length : end + 2;
        continue;
      }
      break;
    }
  }
}
