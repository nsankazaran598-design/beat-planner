/// Гибридные логические часы (Hybrid Logical Clock).
///
/// Строковое представление сравнивается лексикографически и даёт
/// глобальный порядок событий между устройствами:
/// `<миллисекунды, 15 цифр>-<счётчик, 4 hex>-<id устройства>`.
class Hlc implements Comparable<Hlc> {
  const Hlc(this.millis, this.counter, this.node);

  final int millis;
  final int counter;
  final String node;

  static Hlc parse(String s) {
    final first = s.indexOf('-');
    final second = s.indexOf('-', first + 1);
    return Hlc(
      int.parse(s.substring(0, first)),
      int.parse(s.substring(first + 1, second), radix: 16),
      s.substring(second + 1),
    );
  }

  @override
  int compareTo(Hlc other) => toString().compareTo(other.toString());

  @override
  String toString() =>
      '${millis.toString().padLeft(15, '0')}-'
      '${counter.toRadixString(16).padLeft(4, '0')}-$node';

  @override
  bool operator ==(Object other) => other is Hlc && other.toString() == toString();

  @override
  int get hashCode => toString().hashCode;
}

class HlcClock {
  HlcClock(this.node, {int Function()? now})
      : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final String node;
  final int Function() _now;
  int _millis = 0;
  int _counter = 0;

  /// Метка для нового локального события.
  Hlc tick() {
    final physical = _now();
    if (physical > _millis) {
      _millis = physical;
      _counter = 0;
    } else {
      _counter++;
    }
    return Hlc(_millis, _counter, node);
  }

  /// Учитывает метку, пришедшую с другого устройства, чтобы
  /// следующие локальные события были гарантированно «позже».
  void observe(Hlc remote) {
    if (remote.millis > _millis) {
      _millis = remote.millis;
      _counter = remote.counter;
    } else if (remote.millis == _millis && remote.counter > _counter) {
      _counter = remote.counter;
    }
  }
}
