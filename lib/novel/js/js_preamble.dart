/// legado 书源 JS 的兼容层（注入 QuickJS 的全局 API）。
///
/// 书源规则里 `@js:` 片段按 Rhino 语义写：同步调用 `java.ajax` / `java.getString`
/// / `source.getVariable` / `book.name` / `cookie.getCookie` 等。QuickJS 里没有
/// Rhino 的 Java 桥，这里用 `__native(name, args)` 统一转给 Dart 侧
/// [LegadoJsBridge]；需要网络的调用由 Dart 返回 `{__mimaofetch:[...]}` 哨兵，
/// JS 侧抛 `__MIMAO_FETCH__`，宿主预取后重放整段脚本（同步语义得以保留）。
library;

/// 必须由 Dart 注入的宿主函数。
const String legadoInitGlobalSetter = '(key, value) => { this[key] = value; }';

/// 注入一次的全局兼容层。
const String legadoInitJs = r'''
function __call(name, args) {
  const r = __native(name, args || []);
  if (r && typeof r === 'object') {
    if (r.__mimaofetch !== undefined) {
      throw new Error('__MIMAO_FETCH__' + JSON.stringify(r.__mimaofetch));
    }
    if (r.__mimaothrow !== undefined) {
      throw new Error(String(r.__mimaothrow));
    }
  }
  return r;
}

function __element(html) {
  if (html === null || html === undefined) return null;
  if (typeof html !== 'string') return html;
  return {
    __html: html,
    toString() { return __call('dom.text', [html]) || ''; },
    text() { return __call('dom.text', [html]) || ''; },
    ownText() { return __call('dom.ownText', [html]) || ''; },
    html() { return __call('dom.html', [html]) || ''; },
    outerHtml() { return html; },
    attr(name) { return __call('dom.attr', [html, name]) || ''; },
    select(selector) {
      const list = __call('dom.select', [html, selector]) || [];
      return list.map(__element);
    },
    getElementsByTag(tag) { return this.select(tag); },
    getElementsByClass(cls) { return this.select('.' + cls); },
    getElementsByTagName(tag) { return this.select(tag); }
  };
}

const java = {
  ruleUrl: '',
  ajax(url, timeout) { return __call('ajax', [url, timeout]); },
  ajaxAll(urls, skipRateLimit) { return __call('ajaxAll', [urls, skipRateLimit]); },
  connect(url, header, timeout) { return __call('connect', [url, header, timeout]); },
  get(url, headers, timeout) { return __call('connect', [url, headers, timeout]); },
  post(url, body, headers, timeout) { return __call('post', [url, body, headers, timeout]); },
  head(url, headers, timeout) { return __call('head', [url, headers, timeout]); },
  getString(rule, content) { return __call('getString', [rule, content]); },
  getStringList(rule, content) { return __call('getStringList', [rule, content]) || []; },
  getElement(rule, content) { return __element(__call('getElement', [rule, content])); },
  getElements(rule, content) {
    const list = __call('getElements', [rule, content]) || [];
    return list.map(__element);
  },
  setContent(content) { __call('setContent', [content]); return content; },
  put(key, value) { return __call('put', [key, value]); },
  get(key) { return __call('get', [key]) || ''; },
  log(message) { __call('log', [String(message)]); return message; },
  logType(value) { __call('log', [typeof value]); },
  toast(message) { return message; },
  longToast(message) { return message; },

  md5Encode(s) { return __call('md5Encode', [String(s)]) || ''; },
  md5Encode16(s) { return __call('md5Encode16', [String(s)]) || ''; },
  base64Encode(s, flags) { return __call('base64Encode', [String(s), flags]) || ''; },
  base64Decode(s, charset) { return __call('base64Decode', [s, charset]) || ''; },
  base64DecodeToByteArray(s, flags) { return __call('base64DecodeToByteArray', [s, flags]) || []; },
  hexEncodeToString(s) { return __call('hexEncodeToString', [String(s)]) || ''; },
  hexDecodeToString(s) { return __call('hexDecodeToString', [String(s)]) || ''; },
  strToBytes(s, charset) { return __call('strToBytes', [String(s), charset]) || []; },
  bytesToStr(bytes, charset) { return __call('bytesToStr', [bytes, charset]) || ''; },
  encodeURI(s, enc) { return __call('encodeURI', [String(s), enc]) || ''; },
  digestHex(data, algorithm) { return __call('digestHex', [String(data), algorithm]) || ''; },
  digestBase64Str(data, algorithm) { return __call('digestBase64Str', [String(data), algorithm]) || ''; },
  HMacHex(data, algorithm, key) { return __call('hmacHex', [String(data), algorithm, String(key)]) || ''; },
  HMacBase64(data, algorithm, key) { return __call('hmacBase64', [String(data), algorithm, String(key)]) || ''; },

  timeFormat(time) { return __call('timeFormat', [time]) || ''; },
  timeFormatUTC(time, format, sh) { return __call('timeFormatUTC', [time, format, sh]) || ''; },
  t2s(text) { return __call('t2s', [String(text)]) || String(text); },
  s2t(text) { return __call('s2t', [String(text)]) || String(text); },
  toNumChapter(title) { return __call('toNumChapter', [String(title)]) || String(title); },
  getWebViewUA() { return __call('getWebViewUA', []) || ''; },
  randomUUID() { return __call('randomUUID', []) || ''; },
  androidId() { return 'mimao'; },
  getCookie(tag, key) { return __call('cookie.get', [tag, key]) || ''; },
  getVerificationCode(imageUrl) { return ''; },
  importScript(path) { return __call('importScript', [path]) || ''; },
  cacheFile(url, saveTime) { return __call('cacheFile', [url, saveTime]) || ''; },
  readTxtFile(path, charset) { return ''; },
  downloadFile(url) { return ''; },
  webView(html, url, js, cacheFirst) { return __call('webView', [url, js]) || ''; },
  webViewGetSource(html, url, js, regex) { return __call('webView', [url, js]) || ''; },
  webViewGetOverrideUrl(html, url, js, regex) { return __call('webView', [url, js]) || ''; },
  startBrowser(url, title, html) { __call('log', ['startBrowser(unsupported): ' + url]); },
  startBrowserAwait(url, title) { return { body: '', url: url }; },
  openUrl(url) { __call('log', ['openUrl: ' + url]); },
  queryTTF(data, useCache) { return null; },
  replaceFont(text) { return text; },
  getReadBookConfig() { return '{}'; },
  getReadBookConfigMap() { return {}; },
  getThemeMode() { return 'system'; },
  getThemeConfig() { return '{}'; },
  getThemeConfigMap() { return {}; },
  refreshTocUrl() {},
  refreshBookUrl() {},
  reGetBook() {},
  toURL(url, base) { return String(url); },

  createSymmetricCrypto(transformation, key, iv) {
    return {
      decrypt(data) { return __call('crypto.decryptBytes', [transformation, key, iv, data]) || []; },
      decryptStr(data) { return __call('crypto.decrypt', [transformation, key, iv, data]) || ''; },
      encrypt(data) { return __call('crypto.encryptBytes', [transformation, key, iv, data]) || []; },
      encryptBase64(data) { return __call('crypto.encryptBase64', [transformation, key, iv, data]) || ''; },
      encryptHex(data) { return __call('crypto.encryptHex', [transformation, key, iv, data]) || ''; }
    };
  },
  createAsymmetricCrypto(transformation) {
    return {
      decrypt() { return []; },
      decryptStr() { return ''; },
      encryptBase64(data) { return ''; }
    };
  },
  createSign(algorithm) { return { sign: () => '' }; },
  aesDecodeToString(data, key, transformation, iv) {
    return __call('crypto.decrypt', [transformation, key, iv, data]) || '';
  },
  aesBase64DecodeToString(data, key, transformation, iv) {
    return __call('crypto.decrypt', [transformation, key, iv, data]) || '';
  },
  aesEncodeToBase64String(data, key, transformation, iv) {
    return __call('crypto.encryptBase64', [transformation, key, iv, data]) || '';
  },
  desEncodeToBase64String(data, key, transformation, iv) {
    return __call('crypto.encryptBase64', [transformation, key, iv, data]) || '';
  },
  desDecodeToString(data, key, transformation, iv) {
    return __call('crypto.decrypt', [transformation, key, iv, data]) || '';
  }
};
java.get = java.get;
Object.defineProperty(java, 'ruleUrl', { get() { return __baseUrlInternal || ''; } });

const source = {
  get bookSourceUrl() { return __sourceInfo.bookSourceUrl || ''; },
  get bookSourceName() { return __sourceInfo.bookSourceName || ''; },
  get bookSourceComment() { return __sourceInfo.bookSourceComment || ''; },
  get bookSourceGroup() { return __sourceInfo.bookSourceGroup || ''; },
  get bookSourceType() { return Number(__sourceInfo.bookSourceType || 0); },
  getKey() { return this.bookSourceUrl; },
  getTag() { return this.bookSourceName; },
  getVariable() { return __call('source.getVariable', []) || ''; },
  setVariable(value) { __call('source.setVariable', [value]); },
  getLoginInfoMap() { return {}; },
  getLoginHeaderMap() { return {}; },
  putLoginHeader() {},
  getLoginHeader() { return ''; }
};

const book = {
  get name() { return __bookInfo.name || ''; },
  get author() { return __bookInfo.author || ''; },
  get bookUrl() { return __bookInfo.bookUrl || ''; },
  get tocUrl() { return __bookInfo.tocUrl || ''; },
  get origin() { return __bookInfo.origin || ''; },
  get originName() { return __bookInfo.originName || ''; },
  get kind() { return __bookInfo.kind || ''; },
  get intro() { return __bookInfo.intro || ''; },
  get type() { return Number(__bookInfo.type || 0); },
  get durChapterIndex() { return Number(__bookInfo.durChapterIndex || 0); },
  get durChapterTitle() { return __bookInfo.durChapterTitle || ''; },
  get variable() { return this.getVariable(); },
  getVariable(key) { return __call('book.getVariable', [key]) || ''; },
  putVariable(key, value) { __call('book.putVariable', [key, value]); },
  setReverseToc(value) { __call('book.setReverseToc', [value]); },
  getReverseToc() { return false; },
  get canUpdate() { return true; }
};

const cookie = {
  getCookie(tag, key) { return __call('cookie.get', [tag, key]) || ''; },
  getKey(tag, key) { return __call('cookie.get', [tag, key]) || ''; },
  setCookie(tag, value) { __call('cookie.set', [tag, value]); },
  removeCookie(tag) { __call('cookie.remove', [tag]); },
  replaceCookie(tag, value) { __call('cookie.set', [tag, value]); }
};

const cache = {
  getFromMemory(key) { return __call('cache.get', [key]); },
  putMemory(key, value) { __call('cache.put', [key, value]); },
  deleteMemory(key) { __call('cache.remove', [key]); }
};

const console = {
  log(...args) { __call('log', [args.join(' ')]); },
  error(...args) { __call('log', ['[error] ' + args.join(' ')]); },
  warn(...args) { __call('log', ['[warn] ' + args.join(' ')]); }
};

const Packages = {
  java: {
    lang: {
      Thread: {
        sleep() {},
        currentThread() { return { getName() { return 'mimao'; } }; }
      },
      System: {
        currentTimeMillis() { return Date.now(); },
        err: { println(s) { __call('log', [String(s)]); } },
        out: { println(s) { __call('log', [String(s)]); } }
      },
      String: {
        valueOf: (v) => String(v)
      }
    },
    util: {
      Base64: { getEncoder() { return { encodeToString(bytes) { return java.base64Encode(String(bytes)); } }; } }
    }
  },
  android: {
    util: {
      Base64: {
        NO_WRAP: 2,
        DEFAULT: 0,
        encodeToString(bytes, flags) { return java.base64Encode(String(bytes), flags); },
        decode(str, flags) { return java.base64DecodeToByteArray(str); }
      }
    }
  },
  org: {
    jsoup: {
      Jsoup: {
        parse(html) { return __element(html); },
        connect(url) { return { get() { return __call('ajax', [url]); } }; }
      }
    }
  }
};

if (typeof globalThis !== 'undefined') {
  globalThis.java = java;
  globalThis.source = source;
  globalThis.book = book;
  globalThis.cookie = cookie;
  globalThis.cache = cache;
  globalThis.console = console;
  globalThis.Packages = Packages;
  globalThis.org = Packages.org;
  globalThis.javax = Packages.javax || {};
  globalThis.android = Packages.android;
  globalThis.HtmlDocument = { parse: (html) => __element(html) };
  globalThis.HtmlElement = { parse: (html) => __element(html) };
  globalThis.setTimeout = (fn, delay) => { fn(); };
  globalThis.setInterval = () => 0;
  globalThis.clearTimeout = () => {};
  globalThis.clearInterval = () => {};
}
''';
