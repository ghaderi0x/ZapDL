/// Semantic version (https://semver.org). Build metadata is ignored when
/// comparing, as the spec requires.
class SemVer implements Comparable<SemVer> {
  const SemVer(this.major, this.minor, this.patch, [this.pre = const []]);

  final int major;
  final int minor;
  final int patch;

  /// Pre-release identifiers ("beta", "1"); empty for a normal release.
  final List<String> pre;

  bool get isPrerelease => pre.isNotEmpty;

  static final _re = RegExp(
    r'^[vV]?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
  );

  /// Parses "1.2.3", "v1.2.3", "1.2.3-beta.1", "1.2.3+4". Returns null if the
  /// text is not a semantic version.
  static SemVer? tryParse(String text) {
    final m = _re.firstMatch(text.trim());
    if (m == null) return null;
    return SemVer(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      m.group(4) == null ? const [] : m.group(4)!.split('.'),
    );
  }

  @override
  int compareTo(SemVer other) {
    for (final pair in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      if (pair.$1 != pair.$2) return pair.$1.compareTo(pair.$2);
    }
    // A pre-release is lower than the same version without one.
    if (pre.isEmpty && other.pre.isEmpty) return 0;
    if (pre.isEmpty) return 1;
    if (other.pre.isEmpty) return -1;
    final n = pre.length < other.pre.length ? pre.length : other.pre.length;
    for (var i = 0; i < n; i++) {
      final a = pre[i];
      final b = other.pre[i];
      final ai = int.tryParse(a);
      final bi = int.tryParse(b);
      final c = (ai != null && bi != null)
          ? ai.compareTo(bi)
          : (ai != null ? -1 : (bi != null ? 1 : a.compareTo(b)));
      if (c != 0) return c;
    }
    return pre.length.compareTo(other.pre.length);
  }

  bool operator >(SemVer o) => compareTo(o) > 0;
  bool operator <(SemVer o) => compareTo(o) < 0;

  @override
  bool operator ==(Object other) => other is SemVer && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, pre.join('.'));

  @override
  String toString() => '$major.$minor.$patch${pre.isEmpty ? '' : '-${pre.join('.')}'}';
}
