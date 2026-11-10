/// Resultado típico de una operación sin efectos secundarios.
sealed class Result<T> {
  const Result();

  R when<R>({
    required R Function(T data) success,
    required R Function(Object error, StackTrace stack) failure,
  }) => switch (this) {
    Success<T>(:final data) => success(data),
    Failure<T>(:final error, :final stack) => failure(error, stack),
  };

  T get requireValue => switch (this) {
    Success<T>(:final data) => data,
    Failure<T>(:final error) => throw StateError(
      'El resultado es un fallo: $error',
    ),
  };
}

final class Success<T> extends Result<T> {
  const Success(this.data);
  final T data;
}

final class Failure<T> extends Result<T> {
  const Failure(this.error, [this.stack = StackTrace.empty]);
  final Object error;
  final StackTrace stack;
}
