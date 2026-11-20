/// 内嵌的 Venera 兼容 JS 初始化库（`init.js`）。
///
/// 这是用 Dart 自写的、语义对齐上游 `assets/init.js` 的最小实现：社区源脚本
/// 依赖的全局 API（`Network` / `fetch` / `HtmlDocument` / `HtmlElement` /
/// `Convert` / `Cookie` / `console` / `Comic` / `ComicDetails` / `ComicSource`
/// / `setTimeout` 等）都在这里定义；它们统一走 `sendMessage(...)`，由
/// [ComicJsBridge] 分派到我们的实现。
///
/// 不照抄上游源码（规则数据不维护），只维持 API 形状；`init.js` 本身是引擎
/// 代码、纳入自写代码门禁。
library;

/// 注入 QuickJS 后必须实现的全局宿主函数（与上游同名）。
const String comicInitGlobalSetter = '(key, value) => { this[key] = value; }';

/// Venera 源脚本兼容层。字符串直接 `FlutterQjs.evaluate()` 即可。
const String comicInitJs = r'''
// ---- Venera-compatible source runtime (self-written, API-aligned) ----

// 源设置默认值快照：宿主在实例化源、调用 init() 之前从 `source.settings`
// 拍一份 `{settingKey: default}`（对齐 Venera 在注册期解析 settings 定义）。
// 之后 loadSetting 读不到用户保存值时回落到这里；脚本再改 settings 定义也
// 不影响已拍下的默认值。
let __sourceSettingDefaults = {};

function setTimeout(callback, delay) {
    sendMessage({ method: 'delay', time: delay || 0 }).then(callback);
}
function setInterval(callback, delay) {
    const timer = {
        active: true,
        stop() { this.active = false; }
    };
    const loop = () => {
        if (!timer.active) return;
        sendMessage({ method: 'delay', time: delay || 0 }).then(() => {
            if (!timer.active) return;
            callback();
            loop();
        });
    };
    loop();
    return timer;
}

function Cookie(opts) {
    opts = opts || {};
    this.name = opts.name || '';
    this.value = opts.value || '';
    this.domain = opts.domain || '';
}

let Convert = {
    encodeUtf8: (s) => sendMessage({method:'convert', type:'utf8', value:String(s), isEncode:true}),
    decodeUtf8: (v) => sendMessage({method:'convert', type:'utf8', value:v, isEncode:false}),
    encodeGbk: (s) => sendMessage({method:'convert', type:'gbk', value:String(s), isEncode:true}),
    decodeGbk: (v) => sendMessage({method:'convert', type:'gbk', value:v, isEncode:false}),
    encodeBase64: (v) => sendMessage({method:'convert', type:'base64', value:v, isEncode:true}),
    decodeBase64: (v) => sendMessage({method:'convert', type:'base64', value:v, isEncode:false}),
    md5: (v) => sendMessage({method:'convert', type:'md5', value:v, isEncode:true}),
    sha1: (v) => sendMessage({method:'convert', type:'sha1', value:v, isEncode:true}),
    sha256: (v) => sendMessage({method:'convert', type:'sha256', value:v, isEncode:true}),
    sha512: (v) => sendMessage({method:'convert', type:'sha512', value:v, isEncode:true}),
    hmac: (k, v, h) => sendMessage({method:'convert', type:'hmac', key:k, value:v, hash:h, isEncode:true}),
    hmacString: (k, v, h) => sendMessage({method:'convert', type:'hmac', key:k, value:v, hash:h, isEncode:true, isString:true}),
    hexEncode: (bytes) => {
        const view = new Uint8Array(bytes);
        let out = '';
        for (let i = 0; i < view.length; i++) out += ('0' + view[i].toString(16)).slice(-2);
        return out;
    }
};

function createUuid() { return sendMessage({method:'uuid'}); }
function randomInt(min, max) { return sendMessage({method:'random', type:'int', min:min, max:max}); }
function randomDouble(min, max) { return sendMessage({method:'random', type:'double', min:min, max:max}); }

let Network = {
    async fetchBytes(method, url, headers, data, extra) {
        const result = await sendMessage({
            method:'http', http_method:method, bytes:true,
            url:url, headers:headers || {}, data:data === undefined ? null : data, extra:extra
        });
        if (result && result.error) throw result.error;
        return result;
    },
    async sendRequest(method, url, headers, data, extra) {
        const result = await sendMessage({
            method:'http', http_method:method,
            url:url, headers:headers || {}, data:data === undefined ? null : data, extra:extra
        });
        if (result && result.error) throw result.error;
        return result;
    },
    get(url, headers, extra) { return this.sendRequest('GET', url, headers, null, extra); },
    post(url, headers, data, extra) { return this.sendRequest('POST', url, headers, data, extra); },
    put(url, headers, data, extra) { return this.sendRequest('PUT', url, headers, data, extra); },
    patch(url, headers, data, extra) { return this.sendRequest('PATCH', url, headers, data, extra); },
    delete(url, headers, extra) { return this.sendRequest('DELETE', url, headers, null, extra); },
    setCookies(url, cookies) { return sendMessage({method:'cookie', function:'set', url:url, cookies:cookies}); },
    getCookies(url) { return sendMessage({method:'cookie', function:'get', url:url}); },
    deleteCookies(url) { return sendMessage({method:'cookie', function:'delete', url:url}); }
};

async function fetch(url, options) {
    let method = 'GET', headers = {}, data = null;
    if (options) {
        method = options.method || method;
        headers = options.headers || headers;
        data = options.body === undefined ? null : options.body;
    }
    const result = await Network.fetchBytes(method, url, headers, data);
    const text = async () => await Convert.decodeUtf8(result.body);
    return {
        ok: result.status >= 200 && result.status < 300,
        status: result.status,
        statusText: '',
        headers: result.headers,
        arrayBuffer: async () => result.body,
        text: text,
        json: async () => JSON.parse(await text())
    };
}

class HtmlDocument {
    constructor(html) {
        this.key = sendMessage({method:'html', function:'parse', data:String(html)});
    }
    querySelector(query) {
        const k = sendMessage({method:'html', function:'querySelector', key:this.key, query:query});
        return k == null ? null : new HtmlElement(k, this.key);
    }
    querySelectorAll(query) {
        const ks = sendMessage({method:'html', function:'querySelectorAll', key:this.key, query:query}) || [];
        return ks.map(k => new HtmlElement(k, this.key));
    }
    getElementById(id) {
        const k = sendMessage({method:'html', function:'getElementById', key:this.key, id:id});
        return k == null ? null : new HtmlElement(k, this.key);
    }
    dispose() { sendMessage({method:'html', function:'dispose', key:this.key}); }
}

class HtmlElement {
    constructor(k, doc) { this.key = k; this.doc = doc; }
    get text() { return sendMessage({method:'html', function:'getText', key:this.key, doc:this.doc}); }
    get attributes() { return sendMessage({method:'html', function:'getAttributes', key:this.key, doc:this.doc}); }
    get children() {
        return (sendMessage({method:'html', function:'getChildren', key:this.key, doc:this.doc}) || [])
            .map(k => new HtmlElement(k, this.doc));
    }
    get nodes() {
        return (sendMessage({method:'html', function:'getNodes', key:this.key, doc:this.doc}) || [])
            .map(k => new HtmlNode(k, this.doc));
    }
    get innerHTML() { return sendMessage({method:'html', function:'getInnerHTML', key:this.key, doc:this.doc}); }
    get parent() {
        const k = sendMessage({method:'html', function:'getParent', key:this.key, doc:this.doc});
        return k == null ? null : new HtmlElement(k, this.doc);
    }
    get classNames() { return sendMessage({method:'html', function:'getClassNames', key:this.key, doc:this.doc}); }
    get id() { return sendMessage({method:'html', function:'getId', key:this.key, doc:this.doc}); }
    get localName() { return sendMessage({method:'html', function:'getLocalName', key:this.key, doc:this.doc}); }
    get previousElementSibling() {
        const k = sendMessage({method:'html', function:'getPreviousSibling', key:this.key, doc:this.doc});
        return k == null ? null : new HtmlElement(k, this.doc);
    }
    get nextElementSibling() {
        const k = sendMessage({method:'html', function:'getNextSibling', key:this.key, doc:this.doc});
        return k == null ? null : new HtmlElement(k, this.doc);
    }
    querySelector(q) {
        const k = sendMessage({method:'html', function:'dom_querySelector', key:this.key, query:q, doc:this.doc});
        return k == null ? null : new HtmlElement(k, this.doc);
    }
    querySelectorAll(q) {
        const ks = sendMessage({method:'html', function:'dom_querySelectorAll', key:this.key, query:q, doc:this.doc}) || [];
        return ks.map(k => new HtmlElement(k, this.doc));
    }
}

class HtmlNode {
    constructor(k, doc) { this.key = k; this.doc = doc; }
    get text() { return sendMessage({method:'html', function:'node_text', key:this.key, doc:this.doc}); }
    get type() { return sendMessage({method:'html', function:'node_type', key:this.key, doc:this.doc}); }
    toElement() {
        const k = sendMessage({method:'html', function:'node_toElement', key:this.key, doc:this.doc});
        return k == null ? null : new HtmlElement(k, this.doc);
    }
}

function log(level, title, content) {
    sendMessage({method:'log', level:level, title:title, content:String(content)});
}
let console = {
    log: (c) => log('info', 'JS Console', c),
    warn: (c) => log('warning', 'JS Console', c),
    error: (c) => log('error', 'JS Console', c)
};

function Comic(o) {
    o = o || {};
    this.id = o.id; this.title = o.title;
    this.subtitle = o.subtitle; this.subTitle = o.subTitle === undefined ? o.subtitle : o.subTitle;
    this.cover = o.cover; this.tags = o.tags; this.description = o.description;
    this.maxPage = o.maxPage; this.language = o.language;
    this.favoriteId = o.favoriteId; this.stars = o.stars;
}
function ComicDetails(o) {
    o = o || {};
    this.title = o.title;
    this.subtitle = o.subtitle === undefined ? o.subTitle : o.subtitle;
    this.cover = o.cover; this.description = o.description;
    this.tags = o.tags; this.chapters = o.chapters;
    this.isFavorite = o.isFavorite; this.subId = o.subId;
    this.thumbnails = o.thumbnails; this.recommend = o.recommend;
    this.commentCount = o.commentCount; this.likesCount = o.likesCount;
    this.isLiked = o.isLiked; this.uploader = o.uploader;
    this.updateTime = o.updateTime; this.uploadTime = o.uploadTime;
    this.url = o.url; this.stars = o.stars; this.maxPage = o.maxPage;
    this.comments = o.comments;
}
function Comment(o) { Object.assign(this, o || {}); }
function ImageLoadingConfig(o) { Object.assign(this, o || {}); }

let APP = {
    locale: 'zh_CN',
    version: '1.0.0',
    platform: 'windows'
};
let UI = {};

class ComicSource {
    static sources = {};
    constructor() {}
    loadData(k) { return sendMessage({method:'load_data', key:this.key, data_key:k}); }
    // 对齐 Venera：先取用户保存值，再回落到脚本 settings 定义的 default。
    // 缺失时返回 null（上游会 throw，但源脚本普遍按 null/假值写兜底，返回
    // null 更不易把可选设置读崩）。
    loadSetting(k) {
        const stored = sendMessage({method:'load_setting', key:this.key, setting_key:k});
        if (stored !== null && stored !== undefined) return stored;
        if (Object.prototype.hasOwnProperty.call(__sourceSettingDefaults, k)) {
            return __sourceSettingDefaults[k];
        }
        return null;
    }
    saveData(k, d) { return sendMessage({method:'save_data', key:this.key, data_key:k, data:d}); }
    deleteData(k) { return sendMessage({method:'delete_data', key:this.key, data_key:k}); }
    get isLogged() { return sendMessage({method:'isLogged', key:this.key}); }
    translate(k) { return (this.translation && this.translation[APP.locale] && this.translation[APP.locale][k]) || k; }
    init() {}
}
''';
