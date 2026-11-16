import 'package:flutter_test/flutter_test.dart';
import 'package:zapdl/engine/file_category.dart';

void main() {
  test('every category has a distinct, stable folder name', () {
    final names = FileCategory.values.map(categoryFolderName).toList();
    expect(names.toSet().length, names.length);
    expect(categoryFolderName(categoryFor('movie.mkv')), 'Videos');
    expect(categoryFolderName(categoryFor('song.mp3')), 'Music');
    expect(categoryFolderName(categoryFor('book.pdf')), 'Documents');
    expect(categoryFolderName(categoryFor('game.part1.rar')), 'Archives');
    expect(categoryFolderName(categoryFor('setup.exe')), 'Programs');
    expect(categoryFolderName(categoryFor('noext')), 'Other');
  });
}
