class ApiException implements Exception {
  final int statusCode;
  final String message;
  final List<String>? errors;
  final String? code;
  final String? action;

  ApiException(this.statusCode, this.message,
      {this.errors, this.code, this.action});

  @override
  String toString() => message;
}
