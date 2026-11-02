import 'package:flutter_test/flutter_test.dart';
import 'package:herapp/voice.dart';

void main() {
  test('a reply reads aloud without its code, markup or addresses', () {
    expect(
      speakable('# Done\n\n- **Fixed** the [login page](https://x.test/a)\n- see https://x.test\n\n```dart\nmain() {}\n```\n\nAll `good`.'),
      'Done\nFixed the login page\nsee\nAll good.',
    );
  });
}
