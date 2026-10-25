import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:indicators_work/focus_rotation.dart';
import 'package:indicators_work/focus_theme.dart';

class CatalogueBundle extends CachingAssetBundle {
  final Map<String, Object> data;
  CatalogueBundle(this.data);
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode(jsonEncode(data))));
}

final empty = CatalogueBundle({
  'artists': <String, String>{},
  'artworks': <Object>[],
});

void main() {
  tearDown(() => loadPersonalFocusArt(bundle: empty));
  test(
    'personal art participates in picker and rotation without duplicate loads',
    () async {
      final bundle = CatalogueBundle({
        'artists': {'atelier': 'Ателье'},
        'artworks': [
          for (var i = 0; i < 5; i++)
            {
              'id': 'atelier-$i',
              'artist': 'atelier',
              'label': 'Композиция $i',
              'file': 'atelier-$i.jpg',
              'source': 'https://example.org/art/$i',
            },
        ],
      });
      await loadPersonalFocusArt(bundle: bundle);
      await loadPersonalFocusArt(bundle: bundle);
      expect(focusArtworks.length, 40);
      expect(focusArtists['atelier'], 'Ателье');
      expect(focusArt['atelier-0'], 'atelier-0.jpg');
      expect(focusThemes['atelier-0'], 'Композиция 0');
      expect(
        rotationPool({
          'pool': ['atelier-0', 'monet', 'missing'],
        }),
        ['atelier-0', 'monet'],
      );
      expect(
        focusThemeAt('atelier-0', {
          'enabled': true,
          'pool': ['atelier-0', 'atelier-1'],
          'anchorMs': 0,
          'minutes': 10,
        }, 600000),
        'atelier-1',
      );
    },
  );
  test(
    'invalid paths and collisions leave the existing catalogue intact',
    () async {
      for (final file in ['../secret.jpg', 'monet-water-lilies-1906.jpg']) {
        final bundle = CatalogueBundle({
          'artists': {'atelier': 'Ателье'},
          'artworks': [
            {
              'id': 'atelier-one',
              'artist': 'atelier',
              'label': 'Композиция',
              'file': file,
              'source': 'https://example.org/art',
            },
          ],
        });
        await expectLater(
          loadPersonalFocusArt(bundle: bundle),
          throwsFormatException,
        );
        expect(focusArtworks.length, 35);
        expect(focusArtists.containsKey('atelier'), isFalse);
      }
    },
  );
}
