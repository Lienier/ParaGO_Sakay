class ApiException implements Exception {
  final int statusCode;
  final String message;
  final List<String>? errors;
  final String? code;

  ApiException(this.statusCode, this.message, {this.errors, this.code});

  @override
  String toString() => message;
}
