import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math'; // Para generar IDs únicos
import 'firebase_options.dart'; // Generado por FlutterFire
import 'notification_controller.dart'; // TU CONTROLADOR NUEVO

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Inicializar Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 2. Inicializar Awesome Notifications (Canales, grupos, etc.)
  await NotificationController.initializeLocalNotifications();

  runApp(const MyApp());
}

// Convertimos MyApp a StatefulWidget para escuchar eventos globales de notificaciones
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    // 3. Escuchar acciones (ej. si el usuario toca "Tomar medicina")
    NotificationController.startListeningNotificationEvents();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MedRemind',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.deepOrange,
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

// ---------------------------------------------------------------------------
// GESTIÓN DE SESIÓN (LOGIN O HOME)
// ---------------------------------------------------------------------------
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) {
          return const HomeScreen();
        }
        return const LoginScreen();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// PANTALLA DE LOGIN
// ---------------------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isLoading = false;

  Future<void> _authAction({required bool isLogin}) async {
    setState(() => _isLoading = true);
    try {
      if (isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text.trim(),
        );
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailCtrl.text.trim(),
          password: _passCtrl.text.trim(),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Error'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.medical_services_outlined, size: 80, color: Colors.deepOrange),
            const SizedBox(height: 20),
            Text("MedRecordatorios", style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 40),
            TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña', border: OutlineInputBorder())),
            const SizedBox(height: 24),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              Column(
                children: [
                  ElevatedButton(
                    onPressed: () => _authAction(isLogin: true),
                    style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    child: const Text('Iniciar Sesión'),
                  ),
                  TextButton(
                    onPressed: () => _authAction(isLogin: false),
                    child: const Text('Crear Cuenta'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PANTALLA PRINCIPAL (HOME)
// ---------------------------------------------------------------------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String get uid => FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    // 4. PEDIR PERMISOS AL CARGAR LA PANTALLA
    // Esto mostrará el popup al usuario si no tiene permisos activados.
    NotificationController.requestPermissions(context);
  }

  // --- LÓGICA DE AGREGAR ---
  Future<void> _addMedication(String name, String dosage, TimeOfDay time) async {
    // A. Generar ID único (Entero para AwesomeNotifications)
    final int notificationId = Random().nextInt(1000000);

    // B. Guardar en Firestore
    await FirebaseFirestore.instance.collection('medications').add({
      'userId': uid,
      'name': name,
      'dosage': dosage,
      'hour': time.hour,
      'minute': time.minute,
      'notificationId': notificationId, // Guardamos el ID para poder borrar luego
      'createdAt': FieldValue.serverTimestamp(),
    });

    // C. Programar Alarma REAL
    await NotificationController.scheduleMedication(
      id: notificationId,
      medName: name,
      dosage: dosage,
      hour: time.hour,
      minute: time.minute,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recordatorio programado con éxito')),
    );
  }

  // --- LÓGICA DE BORRAR ---
  Future<void> _deleteMedication(String docId, int notificationId) async {
    // A. Cancelar Alarma del teléfono
    await NotificationController.cancelid(notificationId);

    // B. Borrar de Firestore
    await FirebaseFirestore.instance.collection('medications').doc(docId).delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Medicamentos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          )
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('medications')
            .where('userId', isEqualTo: uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text("Error cargando datos"));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.notifications_off_outlined, size: 60, color: Colors.grey),
                  SizedBox(height: 10),
                  Text("No tienes medicamentos programados"),
                ],
              ),
            );
          }

          // Ordenar por hora
          final sortedDocs = List.from(docs);
          sortedDocs.sort((a, b) {
            final dataA = a.data() as Map<String, dynamic>;
            final dataB = b.data() as Map<String, dynamic>;
            if (dataA['hour'] != dataB['hour']) return (dataA['hour'] as int).compareTo(dataB['hour']);
            return (dataA['minute'] as int).compareTo(dataB['minute']);
          });

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sortedDocs.length,
            itemBuilder: (context, index) {
              final doc = sortedDocs[index];
              final data = doc.data() as Map<String, dynamic>;
              final time = TimeOfDay(hour: data['hour'], minute: data['minute']);
              final int notifId = data['notificationId'] ?? 0;

              return Card(
                elevation: 3,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: Colors.deepOrange.shade100,
                    child: const Icon(Icons.access_alarm, color: Colors.deepOrange),
                  ),
                  title: Text(data['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: Text("${data['dosage']} • Todos los días"),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        time.format(context),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueGrey),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteMedication(doc.id, notifId),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => AddMedicationForm(onAdd: _addMedication),
        ),
        label: const Text("Agregar"),
        icon: const Icon(Icons.add),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// FORMULARIO DE AGREGAR
// ---------------------------------------------------------------------------
class AddMedicationForm extends StatefulWidget {
  final Function(String, String, TimeOfDay) onAdd;
  const AddMedicationForm({super.key, required this.onAdd});

  @override
  State<AddMedicationForm> createState() => _AddMedicationFormState();
}

class _AddMedicationFormState extends State<AddMedicationForm> {
  final _nameCtrl = TextEditingController();
  final _dosageCtrl = TextEditingController();
  TimeOfDay? _selectedTime;

  void _submit() {
    if (_nameCtrl.text.isEmpty || _dosageCtrl.text.isEmpty || _selectedTime == null) return;
    widget.onAdd(_nameCtrl.text, _dosageCtrl.text, _selectedTime!);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 16, right: 16, top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("Nuevo Medicamento", style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Nombre del Medicamento', border: OutlineInputBorder(), prefixIcon: Icon(Icons.medication)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dosageCtrl,
            decoration: const InputDecoration(labelText: 'Dosis (ej. 1 pastilla, 5ml)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.info_outline)),
          ),
          const SizedBox(height: 12),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: const BorderSide(color: Colors.grey)),
            title: Text(_selectedTime == null ? "Seleccionar Hora" : "Hora: ${_selectedTime!.format(context)}"),
            trailing: const Icon(Icons.access_time),
            onTap: () async {
              final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
              if (t != null) setState(() => _selectedTime = t);
            },
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _submit,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            child: const Text("GUARDAR Y PROGRAMAR", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}