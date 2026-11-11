import 'dart:async';
import 'dart:developer' as developer;

import 'data_error.dart';

/// How long the app waits for Supabase before giving up (T5).
///
/// One bound per operation, applied once in the Supabase repositories: it
/// covers postgrest's own automatic retries of reads (GET, up to 3 retries
/// after 2, 4 and 8 s), so no other timeout is configured on the client.
abstract final class DataTimeouts {
  static const read = Duration(seconds: 20);

  /// Writes run in the validating database functions, with row locks.
  static const write = Duration(seconds: 30);
}

/// Runs a read. Any failure becomes a [DataException] whose message never
/// mentions saving.
Future<T> guardRead<T>(
  String operation,
  Future<T> Function() request, {
  Duration timeout = DataTimeouts.read,
}) => _guard(operation, request, timeout, classifyDataError);

/// Runs a write. When the client stops waiting (timeout) the request keeps
/// its course on the server: the outcome is reported as uncertain, never as
/// cancelled. Only an explicit refusal from the server is a confirmed
/// failure.
Future<T> guardWrite<T>(
  String operation,
  Future<T> Function() request, {
  Duration timeout = DataTimeouts.write,
}) => _guard(operation, request, timeout, classifyWriteError);

Future<T> _guard<T>(
  String operation,
  Future<T> Function() request,
  Duration timeout,
  DataFailure Function(Object error) classify,
) async {
  Future<T>? running;
  var gaveUp = false;
  try {
    running = request();
    return await running.timeout(
      timeout,
      onTimeout: () {
        gaveUp = true;
        throw TimeoutException('$operation: no answer', timeout);
      },
    );
  } on Object catch (error, stack) {
    final failure = classify(error);
    developer.log(
      '$operation failed: ${describeDataErrorForLog(error)} -> ${failure.name}',
      name: 'evolup.data',
    );
    // The client stopped waiting but the request keeps its course: expose
    // when it ends (answer or network error), its result staying ignored.
    final settled = gaveUp && failure == DataFailure.writeUncertain
        ? running!.then<void>((_) {}, onError: (Object _) {})
        : null;
    Error.throwWithStackTrace(DataException(failure, settled: settled), stack);
  }
}
