///Thrown when a subtitle source cannot be turned into cues: the remote host
///answered with an error status, or the request failed outright.
///
///Without this, an error page or a redirect body is handed to the WebVTT parser
///and the result is indistinguishable from a subtitle track that legitimately
///has no cues. Callers use this exception to move on to the next candidate
///instead of silently showing an empty track.
class BetterPlayerSubtitlesLoadException implements Exception {
  BetterPlayerSubtitlesLoadException(
    this.message, {
    this.url,
    this.statusCode,
    this.cause,
  });

  ///Reason the load failed, safe to show to a user.
  final String message;

  ///Subtitle url that failed, kept for logs only - it can carry a signed token.
  final String? url;

  ///Http status code of the failed response, when the request completed.
  final int? statusCode;

  ///Underlying error, when the failure was not an http status.
  final Object? cause;

  @override
  String toString() {
    final details = [
      if (statusCode != null) 'HTTP $statusCode',
      if (cause != null) '$cause',
    ].join(', ');
    return details.isEmpty ? message : '$message ($details)';
  }
}
