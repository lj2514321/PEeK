import 'package:embyplayer/src/core/utils/pinyin_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PinyinMatcher', () {
    test('matches exact substring', () {
      expect(PinyinMatcher.matches('周星驰', '周星'), isTrue);
      expect(PinyinMatcher.matches('赤壁', '赤壁'), isTrue);
      expect(PinyinMatcher.matches('Inception', 'incep'), isTrue);
    });

    test('matches Pinyin initials shorthand', () {
      expect(PinyinMatcher.getPinyinInitials('周星驰'), 'zxc');
      expect(PinyinMatcher.matches('周星驰', 'zxc'), isTrue);
      expect(PinyinMatcher.getPinyinInitials('赤壁'), 'cb');
      expect(PinyinMatcher.matches('赤壁', 'cb'), isTrue);
      expect(PinyinMatcher.getPinyinInitials('刘亦菲'), 'lyf');
      expect(PinyinMatcher.matches('刘亦菲', 'lyf'), isTrue);
    });

    test('returns false for non-matching queries', () {
      expect(PinyinMatcher.matches('周星驰', 'abc'), isFalse);
      expect(PinyinMatcher.matches('赤壁', 'xyz'), isFalse);
    });

    test('handles empty input gracefully', () {
      expect(PinyinMatcher.matches('周星驰', ''), isTrue);
      expect(PinyinMatcher.matches('', 'zxc'), isFalse);
    });
  });
}
