import 'package:flutter_timezone/flutter_timezone.dart';

/// IANA time zone of the device ("Europe/Paris"), or `null` when the
/// platform cannot tell.
abstract interface class DeviceTimezone {
  Future<String?> current();
}

class PlatformDeviceTimezone implements DeviceTimezone {
  const PlatformDeviceTimezone();

  static final _iana = RegExp(r'^(UTC|[A-Za-z]+(/[A-Za-z0-9_+\-]+)+)$');

  @override
  Future<String?> current() async {
    try {
      final zone = (await FlutterTimezone.getLocalTimezone()).identifier;
      return _iana.hasMatch(zone) ? zone : null;
    } on Object {
      return null;
    }
  }
}
