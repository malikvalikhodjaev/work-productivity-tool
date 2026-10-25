// Generated from assets/art/catalog.json. Stable IDs preserve saved themes.
import 'dart:convert';

import 'package:flutter/services.dart';

class FocusArtwork {
  final String id, artist, label, file, source;
  const FocusArtwork(this.id, this.artist, this.label, this.file, this.source);
}

final focusArtists = {...bundledFocusArtists};
final focusArtworks = [...bundledFocusArtworks];

/// Optional device-build collection. The public asset is empty; the owner's
/// build may supply licensed personal reproductions without publishing them.
Future<void> loadPersonalFocusArt({AssetBundle? bundle}) async {
  final raw = await (bundle ?? rootBundle).loadString(
    'assets/art/personal-catalog.json',
  );
  final data = jsonDecode(raw) as Map<String, dynamic>;
  final artists = Map<String, String>.from(data['artists'] as Map);
  final works = <FocusArtwork>[];
  final ids = bundledFocusArtworks.map((a) => a.id).toSet();
  final files = bundledFocusArtworks.map((a) => a.file).toSet();
  for (final value in data['artworks'] as List) {
    final art = Map<String, String>.from(value as Map);
    final id = art['id']!, file = art['file']!, artist = art['artist']!;
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(id) ||
        !RegExp(r'^[a-z0-9-]+\.(jpg|png|webp)$').hasMatch(file) ||
        !artists.containsKey(artist) ||
        bundledFocusArtists.containsKey(artist) ||
        !ids.add(id) ||
        !files.add(file) ||
        Uri.tryParse(art['source']!)?.scheme != 'https' ||
        art['label']!.isEmpty) {
      throw const FormatException('Invalid personal art catalogue');
    }
    works.add(FocusArtwork(id, artist, art['label']!, file, art['source']!));
  }
  focusArtists
    ..clear()
    ..addAll(bundledFocusArtists)
    ..addAll(artists);
  focusArtworks
    ..clear()
    ..addAll(bundledFocusArtworks)
    ..addAll(works);
}

const bundledFocusArtists = {
  "monet": "Моне",
  "modigliani": "Модильяни",
  "renoir": "Ренуар",
  "pissarro": "Писсарро",
  "soutine": "Сутин",
  "levitan": "Левитан",
  "shishkin": "Шишкин",
};
const bundledFocusArtworks = [
  FocusArtwork(
    "monet",
    "monet",
    "Моне · Кувшинки (1906)",
    "monet-water-lilies-1906.jpg",
    "https://commons.wikimedia.org/wiki/File:Claude_Monet_-_Water_Lilies_-_1933.1157_-_Art_Institute_of_Chicago.jpg",
  ),
  FocusArtwork(
    "monet-2",
    "monet",
    "Моне · Кувшинки (Seerosen)",
    "monet-2.jpg",
    "https://commons.wikimedia.org/wiki/File:Claude_Monet_-_Seerosen.jpg",
  ),
  FocusArtwork(
    "monet-3",
    "monet",
    "Моне · Пруд с кувшинками",
    "monet-3.jpg",
    "https://commons.wikimedia.org/wiki/File:Claude_Monet_-_Pond_with_Water_Lilies_-_Google_Art_Project.jpg",
  ),
  FocusArtwork(
    "monet-4",
    "monet",
    "Моне · Кувшинки · Толидо",
    "monet-4.jpg",
    "https://commons.wikimedia.org/wiki/File:Claude_Monet_-_Water_Lilies_-_Google_Art_Project.jpg",
  ),
  FocusArtwork(
    "monet-5",
    "monet",
    "Моне · Кувшинки и отражения ив",
    "monet-5.jpg",
    "https://commons.wikimedia.org/wiki/File:Water_Lilies,_Reflections_of_Weeping_Willows_(1916)_Claude_Monet_-_NMWA,_Tokyo_(W_1971).jpg",
  ),
  FocusArtwork(
    "modigliani",
    "modigliani",
    "Модильяни · Мадам Помпадур",
    "modigliani-painting.jpg",
    "https://commons.wikimedia.org/wiki/File:Amedeo_Modigliani_004.jpg",
  ),
  FocusArtwork(
    "modigliani-2",
    "modigliani",
    "Модильяни · Алиса",
    "modigliani-2.jpg",
    "https://commons.wikimedia.org/wiki/File:Amedeo_Modigliani_-_Alice_-_Google_Art_Project.jpg",
  ),
  FocusArtwork(
    "modigliani-3",
    "modigliani",
    "Модильяни · Полетт Журден",
    "modigliani-3.jpg",
    "https://commons.wikimedia.org/wiki/File:Amedeo_Modigliani_-_Paulette_Jourdain.jpg",
  ),
  FocusArtwork(
    "modigliani-4",
    "modigliani",
    "Модильяни · Юноша в кепке",
    "modigliani-4.jpg",
    "https://commons.wikimedia.org/wiki/File:Modigliani_jeune_homme_%C3%A0_la_casquette_1919.jpg",
  ),
  FocusArtwork(
    "modigliani-5",
    "modigliani",
    "Модильяни · Эльвира с белым воротником",
    "modigliani-5.jpg",
    "https://commons.wikimedia.org/wiki/File:Amedeo_Modigliani_007.jpg",
  ),
  FocusArtwork(
    "renoir",
    "renoir",
    "Ренуар · Букет хризантем",
    "renoir-painting.jpg",
    "https://commons.wikimedia.org/wiki/File:WLA_metmuseum_Bouquet_of_Chrysanthemums_by_Auguste_Renoir.jpg",
  ),
  FocusArtwork(
    "renoir-2",
    "renoir",
    "Ренуар · Сад в Фонтене",
    "renoir-2.jpg",
    "https://commons.wikimedia.org/wiki/File:Pierre-Auguste_Renoir_-_Jardin_%C3%A0_Fontenay.jpg",
  ),
  FocusArtwork(
    "renoir-3",
    "renoir",
    "Ренуар · Сбор цветов",
    "renoir-3.jpg",
    "https://commons.wikimedia.org/wiki/File:Pierre-Auguste_Renoir_-_La_Cueillette_des_fleurs.jpg",
  ),
  FocusArtwork(
    "renoir-4",
    "renoir",
    "Ренуар · Осенний пейзаж",
    "renoir-4.jpg",
    "https://commons.wikimedia.org/wiki/File:Pierre-Auguste_Renoir_-_Autumn_Landscape_(Paysage_d%27automne)_-_BF933_-_Barnes_Foundation.jpg",
  ),
  FocusArtwork(
    "renoir-5",
    "renoir",
    "Ренуар · Речной пейзаж",
    "renoir-5.jpg",
    "https://commons.wikimedia.org/wiki/File:Pierre-Auguste_Renoir_-_River_Landscape,_1890_-_Google_Art_Project.jpg",
  ),
  FocusArtwork(
    "pissarro",
    "pissarro",
    "Писсарро · Хрустальный дворец",
    "pissarro-painting.jpg",
    "https://commons.wikimedia.org/wiki/File:Camille_Pissarro_-_Le_Crystal_Palace,_Londres.jpg",
  ),
  FocusArtwork(
    "pissarro-2",
    "pissarro",
    "Писсарро · Каштаны зимой в Лувесьенне",
    "pissarro-2.jpg",
    "https://commons.wikimedia.org/wiki/File:Bemberg_Fondation_Toulouse_-_Bois_de_ch%C3%A2taigniers_en_hiver,_Louveciennes_-_Camille_Pissarro_1872.jpg",
  ),
  FocusArtwork(
    "pissarro-3",
    "pissarro",
    "Писсарро · Пейзаж близ Понтуаза",
    "pissarro-3.jpg",
    "https://commons.wikimedia.org/wiki/File:Camille_Pissarro_-_Landscape_near_Pontoise,_the_Auvers_Road,_1881_-_Google_Art_Project.jpg",
  ),
  FocusArtwork(
    "pissarro-4",
    "pissarro",
    "Писсарро · Летний пейзаж в Эраньи",
    "pissarro-4.jpg",
    "https://commons.wikimedia.org/wiki/File:Camille_Pissarro_-_Summer_Landscape,_Eragny_(1887).jpg",
  ),
  FocusArtwork(
    "pissarro-5",
    "pissarro",
    "Писсарро · Сенокос в Эраньи",
    "pissarro-5.jpg",
    "https://commons.wikimedia.org/wiki/File:Heuernte_bei_Eragny-sur-Epte_(1889)_-_Camille_Pissarro.jpg",
  ),
  FocusArtwork(
    "soutine",
    "soutine",
    "Сутин · Пейзаж Сере",
    "soutine-painting.jpg",
    "https://commons.wikimedia.org/wiki/File:%27Landscape_with_Figures-C%C3%A9ret%27_by_Cha%C3%AFm_Soutine,_1922,_High_Museum_of_Art.JPG",
  ),
  FocusArtwork(
    "soutine-2",
    "soutine",
    "Сутин · Платаны в Сере",
    "soutine-2.jpg",
    "https://commons.wikimedia.org/wiki/File:%27Les_Platanes_%C3%A0_C%C3%A9ret%27_by_Cha%C3%AFm_Soutine,_c_1920.jpg",
  ),
  FocusArtwork(
    "soutine-3",
    "soutine",
    "Сутин · Дома",
    "soutine-3.jpg",
    "https://commons.wikimedia.org/wiki/File:Chaim_Soutine_-_Les_maisons,_1921.jpg",
  ),
  FocusArtwork(
    "soutine-4",
    "soutine",
    "Сутин · Большое дерево",
    "soutine-4.jpg",
    "https://commons.wikimedia.org/wiki/File:Cha%C3%AFm_Soutine_-_A_Grande_%C3%81rvore.jpg",
  ),
  FocusArtwork(
    "soutine-5",
    "soutine",
    "Сутин · Аллея деревьев",
    "soutine-5.jpg",
    "https://commons.wikimedia.org/wiki/File:Cha%C3%AFm_Soutine_-_L%27All%C3%A9e_d%27arbres.jpg",
  ),
  FocusArtwork(
    "levitan",
    "levitan",
    "Левитан · Золотая осень",
    "levitan-painting.jpg",
    "https://commons.wikimedia.org/wiki/File:Levitan_Zolotaya_Osen.jpg",
  ),
  FocusArtwork(
    "levitan-2",
    "levitan",
    "Левитан · Лесное озеро",
    "levitan-2.jpg",
    "https://commons.wikimedia.org/wiki/File:Isaac_Levitan-Lac_dans_la_for%C3%AAt-Mus%C3%A9e_Levitan.jpg",
  ),
  FocusArtwork(
    "levitan-3",
    "levitan",
    "Левитан · Волга",
    "levitan-3.jpg",
    "https://commons.wikimedia.org/wiki/File:Isaac_Levitan-Volga-Mus%C3%A9e_Levitan.jpg",
  ),
  FocusArtwork(
    "levitan-4",
    "levitan",
    "Левитан · Золотая осень · Слободка",
    "levitan-4.jpg",
    "https://commons.wikimedia.org/wiki/File:Isaac_Levitan_-_Golden_autumn._Slobodka_-_Google_Art_Project.jpg",
  ),
  FocusArtwork(
    "levitan-5",
    "levitan",
    "Левитан · Саввинская слобода",
    "levitan-5.jpg",
    "https://commons.wikimedia.org/wiki/File:Levitan_Savvinskaya_Sloboda-1884.jpg",
  ),
  FocusArtwork(
    "shishkin",
    "shishkin",
    "Шишкин · Рожь",
    "shishkin-painting.jpg",
    "https://commons.wikimedia.org/wiki/File:Ivan_Shishkin_-_%D0%A0%D0%BE%D0%B6%D1%8C_-_Google_Art_Project.jpg",
  ),
  FocusArtwork(
    "shishkin-2",
    "shishkin",
    "Шишкин · Дубы",
    "shishkin-2.jpg",
    "https://commons.wikimedia.org/wiki/File:Ivan_Ivanovich_Shishkin_-_Oaks,_1865.jpg",
  ),
  FocusArtwork(
    "shishkin-3",
    "shishkin",
    "Шишкин · Пейзаж Полесья",
    "shishkin-3.jpg",
    "https://commons.wikimedia.org/wiki/File:Ivan_Ivanovich_Shishkin_-_Polesie_Landscape,_1884.jpg",
  ),
  FocusArtwork(
    "shishkin-4",
    "shishkin",
    "Шишкин · Зима",
    "shishkin-4.jpg",
    "https://commons.wikimedia.org/wiki/File:Ivan_Shishkin_-_Winter.JPG",
  ),
  FocusArtwork(
    "shishkin-5",
    "shishkin",
    "Шишкин · Утро в сосновом лесу",
    "shishkin-5.jpg",
    "https://commons.wikimedia.org/wiki/File:Shishkin,_Ivan_-_Morning_in_a_Pine_Forest.jpg",
  ),
];
