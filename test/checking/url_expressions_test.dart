import 'package:safeai/checking/url_expressions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('expressionsFor', () {
    test('query and nested path', () {
      expect(expressionsFor('http://a.b.com/1/2.html?param=1').toSet(), {
        'a.b.com/1/2.html?param=1',
        'a.b.com/1/2.html',
        'a.b.com/',
        'a.b.com/1/',
        'b.com/1/2.html?param=1',
        'b.com/1/2.html',
        'b.com/',
        'b.com/1/',
      });
    });

    test('last five host components', () {
      expect(expressionsFor('http://a.b.c.d.e.f.com/1.html').toSet(), {
        'a.b.c.d.e.f.com/1.html',
        'a.b.c.d.e.f.com/',
        'c.d.e.f.com/1.html',
        'c.d.e.f.com/',
        'd.e.f.com/1.html',
        'd.e.f.com/',
        'e.f.com/1.html',
        'e.f.com/',
        'f.com/1.html',
        'f.com/',
      });
    });

    test('IP host has no suffixes', () {
      expect(expressionsFor('http://1.2.3.4/1/').toSet(), {'1.2.3.4/1/', '1.2.3.4/'});
    });

    test('multi-part TLD', () {
      expect(expressionsFor('http://example.co.uk/1'), containsAll(['example.co.uk/1', 'example.co.uk/']));
    });

    test('at most 4 path prefixes plus exact', () {
      final e = expressionsFor('http://x.com/a/b/c/d/e/f.html?q=1');
      expect(e.where((x) => x.startsWith('x.com/')).toSet(), {
        'x.com/a/b/c/d/e/f.html?q=1',
        'x.com/a/b/c/d/e/f.html',
        'x.com/',
        'x.com/a/',
        'x.com/a/b/',
        'x.com/a/b/c/',
      });
    });
  });

  group('canonicalize', () {
    test('decimal IP host', () {
      expect(canonicalize('http://3279880203/blah').host, '195.127.0.11');
    });
    test('host lowercased', () {
      expect(canonicalize('http://www.GOOgle.com/').toString(), 'www.google.com/');
    });
    test('dot segments', () {
      expect(canonicalize('http://www.google.com/foo/./bar/../baz').path, '/foo/baz');
    });
    test('escaped host and path', () {
      expect(
        canonicalize('http://%31%36%38%2e%31%38%38%2e%39%39%2e%32%36/%2E%73%65%63%75%72%65/%77%77%77%2E%65%62%61%79%2E%63%6F%6D/').toString(),
        '168.188.99.26/.secure/www.ebay.com/',
      );
    });
    test('query untouched', () {
      expect(canonicalize('http://www.google.com/q?r?s').toString(), 'www.google.com/q?r?s');
    });
    test('fragment, userinfo, port, whitespace dropped', () {
      expect(canonicalize('http://user:pw@www.google.com:8080/a\t/b#frag').toString(), 'www.google.com/a/b');
    });
    test('hex and octal IP, repeated dots', () {
      expect(canonicalize('http://0x7f.0.0.01/').host, '127.0.0.1');
      expect(canonicalize('http://...www.google.com.../').host, 'www.google.com');
    });
    test('percent and space escaped on output', () {
      expect(canonicalize('http://host.com/%25%32%35 x').path, '/%25%20x');
    });
    test('missing scheme', () {
      expect(canonicalize('www.google.com/a').toString(), 'www.google.com/a');
    });
  });
}
