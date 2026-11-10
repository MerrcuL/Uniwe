class SessionExpiredException implements Exception {
  final String message;
  SessionExpiredException([this.message = 'Session has expired']);

  @override
  String toString() => 'SessionExpiredException: $message';
}

/// A server answered, but not with a usable response (maintenance, 5xx, …).
class HttpStatusException implements Exception {
  final int statusCode;
  final String what;
  HttpStatusException(this.statusCode, this.what);

  @override
  String toString() => 'HttpStatusException: $what returned $statusCode';
}

/// LSF answered within a valid session, but without the requested document
/// (for example because it is not available for this student).
class DocumentUnavailableException implements Exception {
  @override
  String toString() => 'DocumentUnavailableException';
}
