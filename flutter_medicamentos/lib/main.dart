import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';
import 'firebase_options.dart'; // Generado por 'flutterfire configure'
import 'notification_service.dart'; // Importacion del servicio de notificaciones

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Iniciar Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Iniciar notificaciones
  await NotificationService().init();

  runApp(const MedicationApp());
}

class MedicationApp extends StatelessWidget {
  const MedicationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Med-Recordatorio',
      theme: ThemeData(
        primarySwatch: Colors.deepOrange, 
        useMaterial3: true,
      ),
      // AuthWrapper decide si muestra Home o Inicio de Sesion
      home: const AuthWrapper(),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. AUTH WRAPPER: Verificacion de Inicio de Sesion
// ---------------------------------------------------------------------------
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
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
// 2. LOGIN SCREEN
// ---------------------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _authAction({required bool isLogin}) async {
    setState(() => _isLoading = true);
    try {
      if (isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      }
      // AuthWrapper cambia de Inicio de Sesion a Home Automaticamente
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Error de autenticación'), backgroundColor: Colors.red),
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
            const Icon(Icons.local_hospital, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            Text("Med-Recordatorio", style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 40),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Contraseña', border: OutlineInputBorder()),
              obscureText: true,
            ),
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
                    child: const Text('Crear cuenta'),
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
// 3. HOME SCREEN: Firestore Integration
// ---------------------------------------------------------------------------
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  // Obtenemos ID de usuario
  String get uid => FirebaseAuth.instance.currentUser!.uid;

  Future<void> _addMedication(String name, String dosage, TimeOfDay time) async {
  // Inicializamos notification ID
  final int notificationId = Random().nextInt(100000);
  // Añadimos a una coleccion de 'Medications'
    await FirebaseFirestore.instance.collection('medications').add({
      'userId': uid,
      'name': name,
      'dosage': dosage,
      'hour': time.hour,
      'minute': time.minute,
      'notificationId': notificationId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  // PROGRAMACION DE NOTIFICACION LOCAL
    await NotificationService().scheduleDailyNotification(
      id: notificationId,
      title: "Hora de tu medicina: $name",
      body: "Toma $dosage ahora.",
      hour: time.hour,
      minute: time.minute
    );
  }

  Future<void> _deleteMedication(String docId, int notificationId) async {
    // Borra de la base de datos
    await FirebaseFirestore.instance.collection('medications').doc(docId).delete();
    // Desactiva notificacion
    await NotificationService().cancelNotification(notificationId);
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis medicamentos'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _signOut)
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Query: obtiene meds donde userId coincide con el usuario actual
        stream: FirebaseFirestore.instance
            .collection('medications')
            .where('userId', isEqualTo: uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text("Algo salió mal"));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text("No se encontraron medicamentos."));
          }

          // Sort manually on client side to avoid needing a composite index immediately
          // (Firestore requires special setup to sort by 'hour' AND filter by 'userId' simultaneously)
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

              // Obtenemos Id de notificacion guardada
              final int notifId = data['notificationId'] ?? 0;

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.deepOrange.shade100,
                    child: const Icon(Icons.medication, color: Colors.deepOrange),
                  ),
                  title: Text(data['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(data['dosage']),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(time.format(context), style: const TextStyle(fontWeight: FontWeight.bold)),
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => AddMedicationForm(onAdd: _addMedication),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ------------
// 4. FORMA
// ------------
class AddMedicationForm extends StatefulWidget {
  final Function(String, String, TimeOfDay) onAdd;
  const AddMedicationForm({super.key, required this.onAdd});

  @override
  State<AddMedicationForm> createState() => _AddMedicationFormState();
}

class _AddMedicationFormState extends State<AddMedicationForm> {
  final _nameController = TextEditingController();
  final _dosageController = TextEditingController();
  TimeOfDay? _selectedTime;

  void _submit() {
    if (_nameController.text.isEmpty || _dosageController.text.isEmpty || _selectedTime == null) return;
    widget.onAdd(_nameController.text, _dosageController.text, _selectedTime!);
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
        children: [
          Text("Añadir nuevo medicamento", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _dosageController, decoration: const InputDecoration(labelText: 'Dosis', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          ListTile(
            title: Text(_selectedTime == null ? "Selecciona un horario" : "Hora: ${_selectedTime!.format(context)}"),
            trailing: const Icon(Icons.access_time),
            onTap: () async {
              final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
              if (t != null) setState(() => _selectedTime = t);
            },
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _submit,
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            child: const Text("Guardar en la nube"),
          ),
        ],
      ),
    );
  }
}