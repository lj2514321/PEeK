class LocalMediaLibrary {
  const LocalMediaLibrary({
    required this.id,
    required this.name,
    required this.path,
    required this.addedAt,
  });

  final String id;
  final String name;
  final String path;
  final DateTime addedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'addedAt': addedAt.toUtc().toIso8601String(),
  };

  static LocalMediaLibrary? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    final path = value['path'];
    final addedAt = DateTime.tryParse('${value['addedAt']}');
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        name.isEmpty ||
        path is! String ||
        path.isEmpty ||
        addedAt == null) {
      return null;
    }
    return LocalMediaLibrary(id: id, name: name, path: path, addedAt: addedAt);
  }
}
