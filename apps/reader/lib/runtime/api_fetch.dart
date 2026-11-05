final class ApiReply {
  const ApiReply({
    required this.status,
    required this.headers,
    required this.body,
    required this.redirected,
  });
  final int status;
  final Map<String, String> headers;
  final String body;
  final bool redirected;
}

abstract interface class ApiFetch {
  Future<ApiReply> fetchApi(
    String path, {
    String method = 'GET',
    Map<String, String> headers = const {},
    String? body,
  });
}
