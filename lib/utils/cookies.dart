/// Splits a folded `Set-Cookie` header on the commas that separate cookies,
/// while leaving the commas inside `Expires=Wed, 01 Jan …` dates alone.
final RegExp _cookieSplitRegex = RegExp(r',\s*(?=[a-zA-Z0-9_-]+\=)');

/// Parses a (possibly folded) `Set-Cookie` header and merges the name/value
/// pairs into [target].
void mergeSetCookie(String? rawHeader, Map<String, String> target) {
  if (rawHeader == null || rawHeader.isEmpty) return;
  for (final cookie in rawHeader.split(_cookieSplitRegex)) {
    final attributesStart = cookie.indexOf(';');
    final pair =
        attributesStart == -1 ? cookie : cookie.substring(0, attributesStart);
    final eq = pair.indexOf('=');
    if (eq <= 0) continue;
    final name = pair.substring(0, eq).trim();
    if (name.isEmpty) continue;
    target[name] = pair.substring(eq + 1).trim();
  }
}

/// Formats [cookies] as a `Cookie` request header value.
String cookieHeader(Map<String, String> cookies) =>
    cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
