// 阅读器纯模型单测（无副作用、无 IO）。
//
// closure-02：payload/文案统一收敛到 C′（comicProgressText），B′ 的
// readerProgressPayload / readerProgressText 已删除。

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_models.dart';
import 'package:mimao/comic/reader/reader_page.dart';

void main() {
  test('pinchZoom：以基准倍率叠加手势 scale 并钳制到 [1,4]', () {
    expect(pinchZoom(1.0, 1.5), 1.5);
    expect(pinchZoom(2.0, 0.5), 1.0);
    expect(pinchZoom(2.0, 4.0), 4.0);
  });

  test('ComicChapter.pageCount 反映图片数；chapterId 默认空串', () {
    const chapter = ComicChapter(
      title: 'x',
      images: <ReaderImage>[ReaderImage('a'), ReaderImage('b')],
    );
    expect(chapter.pageCount, 2);
    expect(chapter.chapterId, '');

    const stable = ComicChapter(
      title: 'y',
      chapterId: 'ep-7',
      images: <ReaderImage>[ReaderImage('c')],
    );
    expect(stable.chapterId, 'ep-7');
    expect(stable.pageCount, 1);
  });

  test('ReaderImage：headers 参与相等性；plain 无头', () {
    const a = ReaderImage('u', headers: <String, String>{'Referer': 'r'});
    expect(a, ReaderImage('u', headers: <String, String>{'Referer': 'r'}));
    expect(a, isNot(const ReaderImage('u')));
    expect(
      a.hashCode,
      ReaderImage('u', headers: <String, String>{'Referer': 'r'}).hashCode,
    );
    expect(ReaderImage.plain('u').headers, isEmpty);
    expect(a.toString(), contains('headers: 1 项'));
    expect(ReaderImage.plain('u').toString(), 'ReaderImage(u)');
  });

  test('ReaderMode 六种模式枚举齐全，方向布尔自洽', () {
    expect(ReaderMode.values, <ReaderMode>[
      ReaderMode.pagedLtr,
      ReaderMode.pagedRtl,
      ReaderMode.pagedTtb,
      ReaderMode.continuousTtb,
      ReaderMode.continuousLtr,
      ReaderMode.continuousRtl,
    ]);

    expect(ReaderMode.pagedLtr.isPaged, isTrue);
    expect(ReaderMode.pagedLtr.isVertical, isFalse);
    expect(ReaderMode.pagedLtr.isRtl, isFalse);
    expect(ReaderMode.pagedRtl.isPaged, isTrue);
    expect(ReaderMode.pagedRtl.isRtl, isTrue);
    expect(ReaderMode.pagedTtb.isPaged, isTrue);
    expect(ReaderMode.pagedTtb.isVertical, isTrue);
    expect(ReaderMode.continuousTtb.isContinuous, isTrue);
    expect(ReaderMode.continuousTtb.isVertical, isTrue);
    expect(ReaderMode.continuousRtl.isContinuous, isTrue);
    expect(ReaderMode.continuousRtl.isRtl, isTrue);
    expect(ReaderMode.continuousLtr.isVertical, isFalse);
  });

  test('ReaderSettings：normalized 钳制预加载区间，copyWith 覆盖单字段', () {
    const settings = ReaderSettings();
    expect(settings.mode, ReaderMode.pagedLtr);
    expect(settings.preloadCount, 4);
    expect(settings.tapToTurn, isTrue);
    expect(settings.doubleTapZoom, isTrue);

    expect(
      const ReaderSettings(preloadCount: 99).normalized().preloadCount,
      ReaderSettings.maxPreloadCount,
    );
    expect(
      const ReaderSettings(preloadCount: -1).normalized().preloadCount,
      ReaderSettings.minPreloadCount,
    );

    final updated = settings.copyWith(
      mode: ReaderMode.continuousTtb,
      tapToTurn: false,
    );
    expect(updated.mode, ReaderMode.continuousTtb);
    expect(updated.tapToTurn, isFalse);
    expect(updated.preloadCount, 4, reason: '未指定字段保持原值');
    expect(updated, isNot(settings));
  });
}
