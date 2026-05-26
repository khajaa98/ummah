// lib/exceptions/app_exception.dart
// =============================================================================
// Typed exception hierarchy for the repository layer.
//
// Using a sealed class allows the presentation layer to exhaustively switch
// on failure cases without any runtime type-casting.
//
// Hierarchy:
//   AppException (sealed)
//   ├── LocationException (sealed)
//   │   ├── LocationPermissionDeniedException
//   │   ├── LocationPermissionPermanentlyDeniedException
//   │   └── LocationServiceDisabledException
//   ├── NetworkException (sealed)
//   │   ├── NoInternetException
//   │   ├── TimeoutException
//   │   └── ServerException          { statusCode, serverCode, message }
//   └── ParseException               { field, rawValue }
// =============================================================================

sealed class AppException implements Exception {
  const AppException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

// ---------------------------------------------------------------------------
// Location exceptions
// ---------------------------------------------------------------------------

sealed class LocationException extends AppException {
  const LocationException(super.message);
}

/// User tapped "Deny" on the permission dialog.
class LocationPermissionDeniedException extends LocationException {
  const LocationPermissionDeniedException()
      : super(
          'Location permission was denied. '
          'Please allow location access to find nearby mosques.',
        );
}

/// User has permanently denied location access (Android "Don't ask again" /
/// iOS "Never"). The app must direct them to system settings.
class LocationPermissionPermanentlyDeniedException extends LocationException {
  const LocationPermissionPermanentlyDeniedException()
      : super(
          'Location permission is permanently denied. '
          'Please enable it in your device settings.',
        );
}

/// The device's location service (GPS) is switched off.
class LocationServiceDisabledException extends LocationException {
  const LocationServiceDisabledException()
      : super(
          'Location services are disabled. '
          'Please enable GPS in your device settings.',
        );
}

// ---------------------------------------------------------------------------
// Network exceptions
// ---------------------------------------------------------------------------

sealed class NetworkException extends AppException {
  const NetworkException(super.message);
}

class NoInternetException extends NetworkException {
  const NoInternetException()
      : super('No internet connection. Please check your network and retry.');
}

class RequestTimeoutException extends NetworkException {
  const RequestTimeoutException()
      : super('The request timed out. Please retry.');
}

/// A non-2xx HTTP response from the Ummah backend.
class ServerException extends NetworkException {
  const ServerException({
    required this.statusCode,
    required this.serverCode,
    required String message,
  }) : super(message);

  final int    statusCode;
  final String serverCode;

  /// Factory — parses the standard error envelope from the backend:
  /// `{ "error": { "code": "...", "message": "..." } }`
  factory ServerException.fromBody(int statusCode, Map<String, dynamic> body) {
    final error  = body['error'] as Map<String, dynamic>? ?? {};
    final code   = error['code']    as String? ?? 'UNKNOWN_ERROR';
    final message= error['message'] as String? ?? 'An unexpected error occurred.';
    return ServerException(
      statusCode: statusCode,
      serverCode: code,
      message:    message,
    );
  }

  bool get isRateLimited     => statusCode == 429;
  bool get isUnauthorized    => statusCode == 401;
  bool get isNotFound        => statusCode == 404;
  bool get isServerError     => statusCode >= 500;

  @override
  String toString() =>
      'ServerException(status: $statusCode, code: $serverCode, msg: $message)';
}

// ---------------------------------------------------------------------------
// Parse exception
// ---------------------------------------------------------------------------

class ParseException extends AppException {
  const ParseException({
    required this.field,
    required this.rawValue,
    String? hint,
  }) : super(
          'Failed to parse response'
          '${field.isNotEmpty ? " (field: $field)" : ""}: $rawValue'
          '${hint != null ? ". $hint" : ""}',
        );

  final String field;
  final Object? rawValue;
}
