class RouteSummaryModel {
  const RouteSummaryModel({
    required this.id,
    required this.name,
    required this.code,
    required this.direction,
    required this.status,
    this.description,
    this.stopsCount = 0,
  });

  final String id;
  final String name;
  final String code;
  final String direction;
  final String status;
  final String? description;
  final int stopsCount;

  factory RouteSummaryModel.fromJson(Map<String, dynamic> json) {
    final stops = json['stops'];
    return RouteSummaryModel(
      id: json['_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      direction: json['direction']?.toString() ?? 'circular',
      status: json['status']?.toString() ?? 'inactive',
      description: json['description']?.toString(),
      stopsCount: stops is List ? stops.length : 0,
    );
  }

  String get label => code.isEmpty ? name : '$code · $name';
}
