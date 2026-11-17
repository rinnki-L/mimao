/// 漫画源引擎测试的离线夹具：一份自写的 Venera 风格源脚本 + HTML/JSON 数据。
///
/// 脚本按 `_template_.js` 的 API 形状写（class extends ComicSource，
/// search.load / comic.loadInfo / comic.loadEp），只用 Network.* / HtmlDocument /
/// Comic / ComicDetails / JSON 这些 js_bridge 已对齐的 API——它是"测试用源数据"，
/// 不是我们维护的真实社区源。
library;

/// 测试用源脚本文本（真实 QuickJS 执行 / fake 宿主都能跑）。
const String fixtureSourceScript = r'''
class FixtureSource extends ComicSource {
  name = "Fixture Manga";
  key = "fixture";
  version = "1.2.0";
  minAppVersion = "1.6.0";
  url = "https://example.test/fixture.js";

  baseUrl = "https://fixture.test";
  headers = {"User-Agent": "fixture-UA", "Referer": "https://fixture.test/"};

  fixUrl(path) {
    if (!path) return "";
    if (path.startsWith("http")) return path;
    return this.baseUrl + (path.startsWith("/") ? path : "/" + path);
  }

  search = {
    load: async (keyword, options, page) => {
      let res = await Network.get(
        this.baseUrl + "/search?q=" + encodeURIComponent(keyword) + "&page=" + page,
        this.headers
      );
      if (res.status !== 200) throw "search failed: " + res.status;
      let doc = new HtmlDocument(res.body);
      let comics = [];
      for (let el of doc.querySelectorAll(".result-item")) {
        let a = el.querySelector("a.title");
        let img = el.querySelector("img.cover");
        if (!a) continue;
        comics.push(new Comic({
          id: a.attributes["href"].split("/").pop(),
          title: a.text,
          cover: this.fixUrl(img ? (img.attributes["data-src"] || img.attributes["src"]) : ""),
          tags: ["测试"]
        }));
      }
      doc.dispose();
      return { comics: comics, maxPage: 3 };
    }
  };

  comic = {
    loadInfo: async (id) => {
      let res = await Network.get(this.baseUrl + "/comic/" + id, this.headers);
      if (res.status !== 200) throw "detail failed";
      let doc = new HtmlDocument(res.body);
      let chapters = {};
      for (let a of doc.querySelectorAll(".chapter-list a")) {
        chapters[a.attributes["data-id"]] = a.text;
      }
      let titleEl = doc.querySelector("h1.title");
      let detail = new ComicDetails({
        title: titleEl ? titleEl.text : "未知",
        cover: this.fixUrl("cover.jpg"),
        description: "测试漫画",
        chapters: chapters,
        tags: { "作者": ["测试作者"] }
      });
      doc.dispose();
      return detail;
    },
    loadEp: async (comicId, epId) => {
      let res = await Network.get(
        this.baseUrl + "/comic/" + comicId + "/" + epId, this.headers
      );
      if (res.status !== 200) throw "ep failed";
      let doc = new HtmlDocument(res.body);
      let images = [];
      for (let img of doc.querySelectorAll(".reader img")) {
        let src = img.attributes["data-src"] || img.attributes["src"];
        if (src) images.push(this.fixUrl(src));
      }
      doc.dispose();
      return { images: images };
    }
  };
}
''';

/// 语法错误的源脚本（验证容错）。
const String fixtureBrokenScript = r'''
class Broken extends ComicSource {
  search = {
    load: async (keyword) => { this is not valid javascript !!!
  };
}
''';

/// 不含 ComicSource 类的文本（验证导入拒绝）。
const String fixtureNotASource = 'console.log("hello");';

/// 搜索结果页 HTML。
const String fixtureSearchHtml = '''
<html><body>
  <div class="result-item">
    <a class="title" href="/comic/one">海贼王</a>
    <img class="cover" data-src="/cover/one.jpg" />
  </div>
  <div class="result-item">
    <a class="title" href="/comic/two">咒术回战</a>
    <img class="cover" src="/cover/two.jpg" />
  </div>
</body></html>
''';

/// 详情页 HTML。
const String fixtureDetailHtml = '''
<html><body>
  <h1 class="title">海贼王</h1>
  <div class="chapter-list">
    <a data-id="ch-1">第1话 启程</a>
    <a data-id="ch-2">第2话 伙伴</a>
    <a data-id="ch-3">第3话 航海</a>
  </div>
</body></html>
''';

/// 章节图片页 HTML。
const String fixtureImagesHtml = '''
<html><body>
  <div class="reader">
    <img data-src="/img/1.jpg" />
    <img src="/img/2.jpg" />
    <img data-src="https://cdn.test/3.jpg" />
  </div>
</body></html>
''';

/// 按 URL 返回夹具正文的假 HTTP 客户端（供纯 Dart js_bridge / 宿主测试用）。
class FixtureHttpClient {
  FixtureHttpClient(this._responses);

  final Map<String, String> _responses;
  final List<Map<String, String>> requestedHeaders = <Map<String, String>>[];
  final List<String> requestedUrls = <String>[];

  String? responseFor(String url) {
    for (final entry in _responses.entries) {
      if (url.contains(entry.key)) return entry.value;
    }
    return null;
  }
}

/// 真实社区源：weihanlong267-spec/Venera-Next-sources 的 bilimanga.js
/// （逐字保存，规则数据不维护；仅用于验证 js_bridge API 对齐）。
const String realBilimangaSource = r'''
/** @type {import('./_venera_.js')} */
class Bilimanga extends ComicSource {
  name = "哔哩哔哩漫画";
  key = "bilimanga";
  version = "1.0.0";
  minAppVersion = "1.6.0";
  url = "https://cdn.jsdelivr.net/gh/Wjavan/venera-next-sources@main/bilimanga.js";

  settings = {
    domains: {
      title: "选择域名",
      type: "select",
      options: [
        { value: "https://www.bilimanga.net", text: "https://www.bilimanga.net (主站)" }
      ],
      default: "https://www.bilimanga.net"
    }
  };

  get baseUrl() {
    return this.loadSetting("domains") || "https://www.bilimanga.net";
  }

  get headers() {
    return {
      "User-Agent": "Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36",
      "Referer": this.baseUrl + "/"
    };
  }

  parseComic(item) {
    const link = item.querySelector("a");
    if (!link) return null;
    const href = link.attributes.href;
    const id = href.split("/").pop().replace(".html", "");
    const title = item.querySelector(".title, h3, h4, .book-title")?.text?.trim() || link.text.trim();
    const cover = item.querySelector("img")?.attributes?.src || item.querySelector("img")?.attributes?.["data-src"];
    const author = item.querySelector(".author, .book-author")?.text?.trim() || "";
    const update = item.querySelector(".update, .chapter, .latest")?.text?.trim() || "";
    if (!id || !title) return null;
    return new Comic({
      id, title,
      subTitle: author,
      cover: this.fixUrl(cover),
      tags: [],
      description: update
    });
  }

  fixUrl(u) {
    if (!u) return "";
    if (u.startsWith("http")) return u;
    if (u.startsWith("//")) return "https:" + u;
    return this.baseUrl.replace(/\/$/, "") + "/" + u.replace(/^\//, "");
  }

  explore = [{
    title: "哔哩哔哩漫画",
    type: "multiPartPage",
    load: async (page) => {
      let url = page === 1 ? this.baseUrl : `${this.baseUrl}/page/${page}/`;
      let res = await Network.get(url, this.headers);
      if (res.status !== 200) throw `加载失败: ${res.status}`;
      let doc = new HtmlDocument(res.body);
      const result = {};
      let items = doc.querySelectorAll(".comic-list li, .book-list li, .comic-item, .list-item, .recommend-item, .cell.comic-item, .manga-1-list-item, .manga-i-list-item, .comics li, article");
      if (items.length > 0) {
        result["推荐漫画"] = items.map(e => this.parseComic(e)).filter(Boolean);
      }
      return result;
    }
  }];

  category = null;

  search = {
    load: async (keyword, options, page) => {
      let url = `${this.baseUrl}/search/${encodeURIComponent(keyword)}/${page}/`;
      let res = await Network.get(url, this.headers);
      if (res.status !== 200) throw `搜索失败: ${res.status}`;
      let doc = new HtmlDocument(res.body);
      let items = doc.querySelectorAll(".comic-list li, .book-list li, .comic-item, .list-item, .cell.comic-item, .manga-1-list-item, .manga-i-list-item, .search-result li, .comics li, article");
      return {
        comics: items.map(e => this.parseComic(e)).filter(Boolean),
        maxPage: page + 1
      };
    }
  };

  comic = {
    loadInfo: async (id) => {
      let url = `${this.baseUrl}/comic/${id}/`;
      let res = await Network.get(url, this.headers);
      if (res.status !== 200) throw `详情加载失败: ${res.status}`;
      let doc = new HtmlDocument(res.body);
      
      let title = doc.querySelector(".book-title, h1, .detail-title, .comic-title, .metas-title")?.text?.trim() || id;
      let cover = doc.querySelector(".book-cover img, .detail-cover img, .comic-cover img, .metas-image img, .manga-1-cover img")?.attributes?.src || "";
      let author = doc.querySelector(".book-author, .author, .comic-author, .metas-body .author")?.text?.trim() || "";
      let description = doc.querySelector(".book-intro, .intro, .description, .comic-desc, .metas-desc p")?.text?.trim() || "";
      let update = doc.querySelector(".last-chapter, .update-chapter, .latest-chapter, .manga-1-list-subtitle, .newchapter a")?.text?.trim() || "";
      let status = doc.querySelector(".book-status, .status, .comic-status, .has-text-success")?.text?.trim() || "";
      
      let chapters = new Map();
      let chapterLinks = doc.querySelectorAll("#chapter-list a, .chapter-list a, .catalog a, .comic-chapters a, .book-chapters a, .detail-list a");
      let i = 0;
      for (let link of chapterLinks) {
        let href = link.attributes.href;
        let cid = href.split("/").pop().replace(".html", "");
        let ctitle = link.text.trim();
        if (cid && ctitle) {
          chapters.set(i.toString(), ctitle);
          i++;
        }
      }

      return new ComicDetails({
        title, cover: this.fixUrl(cover),
        description, tags: { 作者: [author], 状态: [status], 更新: [update] },
        chapters, updateTime: update
      });
    },

    loadEp: async (comicId, epId) => {
      let url = `${this.baseUrl}/comic/${comicId}/${epId}.html`;
      let res = await Network.get(url, this.headers);
      if (res.status !== 200) throw `章节加载失败: ${res.status}`;
      let doc = new HtmlDocument(res.body);
      
      let images = [];
      let imgNodes = doc.querySelectorAll("#chapter-images img, .chapter-content img, .read-content img, .comic-page img, .manga-1-cover img, .manga-i-cover img, .chapter-images img");
      for (let img of imgNodes) {
        let src = img.attributes["data-src"] || img.attributes["data-original"] || img.attributes["src"] || "";
        if (src) images.push(this.fixUrl(src));
      }
      return { images };
    }
  };
}
''';
