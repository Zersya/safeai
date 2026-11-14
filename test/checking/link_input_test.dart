import 'package:safeai/checking/link_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('url inside sentence, trailing punctuation stripped', () {
    expect(extractUrl('Cek ini ya bu https://bit.ly/abc123.'), 'https://bit.ly/abc123');
  });
  test('bare domain gets https', () {
    expect(extractUrl('s.id/promo'), 'https://s.id/promo');
  });
  test('plain text is not a link', () {
    expect(extractUrl('halo apa kabar'), isNull);
  });
  test('non-http schemes rejected', () {
    expect(extractUrl('javascript:alert(1)'), isNull);
    expect(extractUrl('intent://scan/#Intent;scheme=zxing;end'), isNull);
    expect(extractUrl('file:///sdcard/a.html'), isNull);
  });
}
