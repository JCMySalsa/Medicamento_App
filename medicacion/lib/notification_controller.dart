import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';

class NotificationController {

  /// 1. INICIALIZACIÓN
  static Future<void> initializeLocalNotifications() async {
    await AwesomeNotifications().initialize(
      null, // Icono por defecto (null usa el de la app)
      [
        NotificationChannel(
          channelKey: 'med_channel_critical',
          channelName: 'Alertas de Medicación',
          channelDescription: 'Canal para recordatorios críticos de medicamentos',
          defaultColor: Colors.deepOrange,
          ledColor: Colors.white,
          importance: NotificationImportance.Max, // ¡CRÍTICO!
          channelShowBadge: true,
          criticalAlerts: true, // Permite sonar en modo No Molestar (requiere permiso extra)
          playSound: true,
          enableVibration: true,
        )
      ],
      debug: true, // Pon false en producción
    );
  }

  /// 2. LISTENERS (Para detectar cuando tocan la notificación)
  static Future<void> startListeningNotificationEvents() async {
    AwesomeNotifications().setListeners(
      onActionReceivedMethod: onActionReceivedMethod,
    );
  }

  @pragma("vm:entry-point")
  static Future<void> onActionReceivedMethod(ReceivedAction receivedAction) async {
    // Aquí puedes navegar a una pantalla específica si el usuario toca la alerta
    print("El usuario tocó la notificación o el botón de 'Tomar'");
  }

  /// 3. SOLICITUD DE PERMISOS (Vital para Android 13+)
  static Future<void> requestPermissions(BuildContext context) async {
    bool isAllowed = await AwesomeNotifications().isNotificationAllowed();
    if (!isAllowed) {
      // Muestra un diálogo amigable antes de pedir el permiso del sistema
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Permisos de Alerta'),
          content: const Text('Nuestra app necesita permisos para enviarte recordatorios de tus medicinas.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('No permitir', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                AwesomeNotifications().requestPermissionToSendNotifications();
              },
              child: const Text('Permitir', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
  }

  /// 4. CREAR RECORDATORIO
  static Future<void> scheduleMedication({
    required int id,
    required String medName,
    required String dosage,
    required int hour,
    required int minute,
  }) async {
    
    // Convertimos la hora local del usuario a la zona horaria correcta automáticamente
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: id,
        channelKey: 'med_channel_critical',
        title: '💊 Hora de tu medicina: $medName',
        body: 'Debes tomar $dosage ahora.',
        category: NotificationCategory.Alarm, // Hace que suene como alarma
        wakeUpScreen: true, // Enciende la pantalla
        fullScreenIntent: true, // Muestra alerta a pantalla completa
        autoDismissible: false, // No se borra sola hasta que interactúen
      ),
      actionButtons: [
        NotificationActionButton(
          key: 'TAKEN',
          label: 'Tomar Medicina',
          actionType: ActionType.Default,
        ),
        NotificationActionButton(
          key: 'SNOOZE',
          label: 'Posponer 10m',
          actionType: ActionType.SilentAction,
        )
      ],
      schedule: NotificationCalendar(
        hour: hour,
        minute: minute,
        second: 0,
        millisecond: 0,
        repeats: true, // Repite diariamente
        allowWhileIdle: true, // CRÍTICO: Suena incluso en modo ahorro de batería
        preciseAlarm: true,   // CRÍTICO: Usa hora exacta
      ),
    );
  }
  
  static Future<void> cancelid(int id) async {
      await AwesomeNotifications().cancel(id);
  }
}