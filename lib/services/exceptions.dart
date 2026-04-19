class SessionExpiredException implements Exception {
  final String message;
  SessionExpiredException([this.message = 'Session has expired']);

  @override
  String toString() => 'SessionExpiredException: $message';
}
