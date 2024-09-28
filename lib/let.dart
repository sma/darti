extension LetExtension<T> on T {
  U let<U>(U Function(T) transform) => transform(this);
}
