import 'package:farmacia_backend/src/presentation/routes/routes.dart';
import 'package:test/test.dart';

void main() {
  group('interfacesDesdePowerShell', () {
    test('lee alias|ip conservando el orden (la activa primero)', () {
      const salida = 'Wi-Fi|192.168.1.25\r\nEthernet|192.168.1.24\r\n';

      expect(interfacesDesdePowerShell(salida), [
        ('Wi-Fi', '192.168.1.25'),
        ('Ethernet', '192.168.1.24'),
      ]);
    });

    test('varias IPs del mismo adaptador salen juntas', () {
      const salida = 'Wi-Fi|192.168.1.25,10.0.0.7\n';

      expect(interfacesDesdePowerShell(salida), [
        ('Wi-Fi', '192.168.1.25'),
        ('Wi-Fi', '10.0.0.7'),
      ]);
    });

    test('ignora líneas vacías y basura', () {
      const salida = '\n\nsin separador\n|sin nombre|\n\nWi-Fi|192.168.1.25\n';

      expect(interfacesDesdePowerShell(salida), [('Wi-Fi', '192.168.1.25')]);
    });

    test('salida vacía → lista vacía', () {
      expect(interfacesDesdePowerShell(''), isEmpty);
    });
  });
}
