import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://ywutwurawjlcbppshqoh.supabase.co',
    anonKey: 'sb_publishable_xAd5kd_GSJGOeDaJL7kL6g_sw5PZl0k',
  );

  runApp(const MedicationApp());
}

final supabase = Supabase.instance.client;

class MedicationApp extends StatelessWidget {
  const MedicationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dosifi-kt',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      // Verifica que el usuario esté log
      home: supabase.auth.currentUser == null
          ? const LoginScreen()
          : const HomeScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. PANTALLA INICIO DE SESIÓN: Autorización
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

  Future<void> _signIn() async {
    setState(() => _isLoading = true);
    try {
      await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (!mounted) return;

      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message), backgroundColor: Colors.red),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error inesperado'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signUp() async {
    setState(() => _isLoading = true);
    try {
      await supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cuenta creada ...')),
      );

      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_circle, size: 80, color: Colors.indigo),
              const SizedBox(height: 20),
              Text(
                "Dosifi-kt",
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 24),
              if (_isLoading)
                const CircularProgressIndicator()
              else
                Column(
                  children: [
                    ElevatedButton(
                      onPressed: _signIn,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      child: const Text('Inciar Sesión'),
                    ),
                    TextButton(
                      onPressed: _signUp,
                      child: const Text('Crear Cuenta'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. HOME SCREEN: Real-time List from Supabase
// ---------------------------------------------------------------------------
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    await supabase.auth.signOut();
    if (context.mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  Future<void> _addMedication(
    String nombre,
    String dosis,
    TimeOfDay hora,
  ) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    await supabase.from('medicamentos').insert({
      'user_id': user.id, // Important for RLS
      'nombre': nombre,
      'dosis': dosis,
      'frecuencia_horas': hora.hour,
      'minute': hora.minute,
    });
  }

  Future<void> _deleteMedication(String id) async {
    await supabase.from('medicamentos').delete().eq('id', id);
  }

  @override
  Widget build(BuildContext context) {
    // We use a Stream to get real-time updates from Supabase
    final medicationStream = supabase
        .from('medicamentos')
        .stream(primaryKey: ['id'])
        .order('hour', ascending: true)
        .order('minute', ascending: true);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis medicamentos'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _signOut(context),
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: medicationStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final medications = snapshot.data!;

          if (medications.isEmpty) {
            return const Center(child: Text("Aún no hay medicamentos. Agrega uno!"));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: medications.length,
            itemBuilder: (context, index) {
              final med = medications[index];
              final time = TimeOfDay(hour: med['hora'], minute: med['minutos']);

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.indigo.shade100,
                    child: const Icon(Icons.medication, color: Colors.indigo),
                  ),
                  title: Text(
                    med['nombre'],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(med['dosis']),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        time.format(context),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade700,
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteMedication(med['id']),
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

// ---------------------------------------------------------------------------
// 3. THE FORM: Same as before, but decoupled from logic
// ---------------------------------------------------------------------------
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
    if (_nameController.text.isEmpty ||
        _dosageController.text.isEmpty ||
        _selectedTime == null)
      return;
    widget.onAdd(_nameController.text, _dosageController.text, _selectedTime!);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Añadir nuevo medicamento", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dosageController,
            decoration: const InputDecoration(
              labelText: 'Dosis',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            title: Text(
              _selectedTime == null
                  ? "Selecciona el horario"
                  : "Horario: ${_selectedTime!.format(context)}",
            ),
            trailing: const Icon(Icons.access_time),
            onTap: () async {
              final t = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.now(),
              );
              if (t != null) setState(() => _selectedTime = t);
            },
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _submit,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: const Text("Guardar"),
          ),
        ],
      ),
    );
  }
}
