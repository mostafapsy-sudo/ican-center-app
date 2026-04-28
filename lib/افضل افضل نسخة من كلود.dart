import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const IcanApp());
}

class IcanApp extends StatelessWidget {
  const IcanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ICAN Center',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00A6A6)),
        scaffoldBackgroundColor: const Color(0xFFF6FBFF),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: Color(0xFFBDF2E9),
          foregroundColor: Color(0xFF12343B),
        ),
      ),
      home: const Directionality(textDirection: TextDirection.rtl, child: AuthGate()),
    );
  }
}

InputDecoration inputDecoration(String label) {
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
    ),
  );
}


// تم نقل منطق الصلاحيات إلى UserProfileGate أعلى الملف.

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.hasData ? UserProfileGate(firebaseUser: snapshot.data!) : const LoginPage();
      },
    );
  }
}


String currentUserRole = 'manager';
String currentUserName = 'الإدارة';
String currentUserEmail = '';
double currentUserBaseSalary = 0;
String currentUserWorkStartTime = '09:00';
String currentUserWorkEndTime = '16:00';

bool isCurrentUserSenior() => currentUserRole == 'senior';
bool isCurrentUserManager() => currentUserRole == 'manager';
bool isCurrentUserSpecialist() => currentUserRole == 'specialist';
bool isCurrentUserParent() => currentUserRole == 'parent';

String currentUserDisplayName() {
  if (currentUserName.trim().isNotEmpty) return currentUserName;
  if (currentUserEmail.trim().isNotEmpty) return currentUserEmail;
  return 'مستخدم غير معروف';
}

class UserProfileGate extends StatelessWidget {
  final User firebaseUser;

  const UserProfileGate({super.key, required this.firebaseUser});

  @override
  Widget build(BuildContext context) {
    final email = firebaseUser.email?.toLowerCase().trim() ?? '';

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        String role = 'specialist';
        String name = email;
        double baseSalary = 0;
        String workStartTime = '09:00';
        String workEndTime = '16:00';

        // الحساب الإداري الأول الافتراضي، حتى لو لم تُضفه بعد في users.
        if (email == 'admin@ican.com') {
          role = 'manager';
          name = 'الإدارة';
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isNotEmpty) {
          final data = docs.first.data();
          role = (data['role'] ?? role).toString();
          name = (data['name'] ?? name).toString();
          baseSalary = parseMoney(data['baseSalary']);
          workStartTime = (data['workStartTime'] ?? workStartTime).toString();
          workEndTime = (data['workEndTime'] ?? workEndTime).toString();
        }

        currentUserRole = role;
        currentUserName = name;
        currentUserEmail = email;
        currentUserBaseSalary = baseSalary;
        currentUserWorkStartTime = workStartTime;
        currentUserWorkEndTime = workEndTime;

        return HomePage(role: role, userName: name);
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController(text: 'admin@ican.com');
  final passwordController = TextEditingController(text: '123456');
  bool loading = false;
  bool rememberMe = true; // تذكرني مفعّل افتراضيًا

  Future<void> login() async {
    setState(() => loading = true);
    try {
      // تفعيل الـ persistence للويب إن أمكن
      if (rememberMe) {
        try {
          await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
        } catch (_) {
          // قد لا تكون متاحة على بعض المنصات - تجاهل
        }
      } else {
        try {
          await FirebaseAuth.instance.setPersistence(Persistence.SESSION);
        } catch (_) {}
      }
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      String msg = 'بيانات الدخول غير صحيحة';
      if (e.code == 'invalid-email') msg = 'صيغة البريد الإلكتروني غير صحيحة';
      if (e.code == 'user-not-found') msg = 'المستخدم غير موجود';
      if (e.code == 'wrong-password') msg = 'كلمة المرور غير صحيحة';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE7FFF8), Color(0xFFFFF4D6), Color(0xFFF4ECFF)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Image.asset(
                          'assets/images/ican_logo.jpg',
                          height: 120,
                          errorBuilder: (_, __, ___) => const Icon(Icons.school_rounded, size: 80, color: Color(0xFF00A6A6)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('ICAN لإدارة المركز', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('تسجيل دخول حقيقي متصل بـ Firebase', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                      const SizedBox(height: 24),
                      TextField(controller: emailController, keyboardType: TextInputType.emailAddress, decoration: inputDecoration('البريد الإلكتروني')),
                      const SizedBox(height: 12),
                      TextField(controller: passwordController, obscureText: true, decoration: inputDecoration('كلمة المرور')),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        value: rememberMe,
                        onChanged: (v) => setState(() => rememberMe = v ?? true),
                        title: const Text('تذكرني على هذا الجهاز', style: TextStyle(fontSize: 14)),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: loading ? null : login,
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                        child: loading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('دخول'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final String role;
  final String userName;

  const HomePage({super.key, required this.role, required this.userName});

  @override
  State<HomePage> createState() => _HomePageState();
}

class TabItem {
  final String title;
  final IconData icon;
  final Widget page;
  const TabItem(this.title, this.icon, this.page);
}

class _HomePageState extends State<HomePage> {
  int index = 0;

  List<TabItem> get tabs {
    final list = <TabItem>[];

    if (widget.role == 'manager') {
      list.add(const TabItem('🏢 الإدارة', Icons.dashboard_rounded, ManagerDashboardPage()));
    }

    if (widget.role == 'manager' || widget.role == 'senior' || widget.role == 'specialist') {
      list.add(const TabItem('✅ الحضور', Icons.fingerprint_rounded, AttendancePage()));
      list.add(const TabItem('🎯 التقييم', Icons.assignment_rounded, AssessmentPage()));
      list.add(const TabItem('🧩 البرنامج', Icons.calendar_month_rounded, WeeklyProgramPage()));
      list.add(const TabItem('📊 التقارير', Icons.summarize_rounded, ReportsPage()));
    }

    if (widget.role == 'manager' || widget.role == 'senior') {
      list.add(const TabItem('⭐ السينيور', Icons.verified_rounded, SeniorFollowUpPage()));
    }

    if (widget.role == 'parent') {
      list.add(const TabItem('👪 ولي الأمر', Icons.family_restroom_rounded, ParentHomePage()));
    }

    if (widget.role == 'manager') {
      list.add(const TabItem('👥 العاملون', Icons.badge_rounded, UsersPage()));
      list.add(const TabItem('🗑️ السلة', Icons.delete_sweep_rounded, TrashPage()));
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final allTabs = tabs;
    if (index >= allTabs.length) index = 0;
    final current = allTabs[index];
    return Scaffold(
      appBar: AppBar(
        title: Text(current.title),
        actions: [
          IconButton(icon: const Icon(Icons.logout_rounded), onPressed: () => FirebaseAuth.instance.signOut()),
        ],
      ),
      body: current.page,
      bottomNavigationBar: allTabs.length < 2
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (value) => setState(() => index = value),
              destinations: allTabs.map((tab) => NavigationDestination(icon: Icon(tab.icon), label: tab.title)).toList(),
            ),
    );
  }
}

/* ===================== الإدارة: الأطفال ===================== */

class ManagerDashboardPage extends StatelessWidget {
  const ManagerDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageWrap(
      children: [
        HeroBox(title: '🏢 لوحة الإدارة', subtitle: 'الأطفال 👧🧒 يُحفظون فعليًا في Firestore.'),
        SizedBox(height: 12),
        AddChildCard(),
        SizedBox(height: 12),
        RealStatsRow(),
        SizedBox(height: 12),
        ChildrenListCard(),
        BackupCard(),
      ],
    );
  }
}

class AddChildCard extends StatefulWidget {
  const AddChildCard({super.key});

  @override
  State<AddChildCard> createState() => _AddChildCardState();
}

class _AddChildCardState extends State<AddChildCard> {
  final nameController = TextEditingController();
  final diagnosisController = TextEditingController();
  final parentController = TextEditingController();
  final phoneController = TextEditingController();
  final notesController = TextEditingController();
  String program = 'بورتاج + لوفاس';
  String? selectedParentId;
  String? selectedParentName;
  String? selectedParentEmail;
  DateTime? birthDate;
  bool saving = false;
  bool _expanded = false;

  String get ageText {
    if (birthDate == null) return 'لم يتم اختيار تاريخ الميلاد';
    final now = DateTime.now();
    int years = now.year - birthDate!.year;
    int months = now.month - birthDate!.month;
    if (now.day < birthDate!.day) months--;
    if (months < 0) {
      years--;
      months += 12;
    }
    return '$years سنة و $months شهر';
  }

  Future<void> pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2020, 1, 1),
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
      helpText: 'اختيار تاريخ ميلاد الطفل',
    );
    if (picked != null) setState(() => birthDate = picked);
  }

  void _clearForm() {
    nameController.clear();
    diagnosisController.clear();
    parentController.clear();
    phoneController.clear();
    notesController.clear();
    setState(() {
      birthDate = null;
      selectedParentId = null;
      selectedParentName = null;
      selectedParentEmail = null;
      program = 'بورتاج + لوفاس';
      _expanded = false;
    });
  }

  Future<void> saveChild() async {
    final name = nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب اسم الطفل أولًا')));
      return;
    }

    if (birthDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختَر تاريخ ميلاد الطفل')));
      return;
    }

    setState(() => saving = true);

    try {
      await FirebaseFirestore.instance.collection('children').add({
        'name': name,
        'dateOfBirth': Timestamp.fromDate(birthDate!),
        'ageText': ageText,
        'program': program,
        'diagnosis': diagnosisController.text.trim(),
        'parentId': selectedParentId,
        'parentName': selectedParentName ?? parentController.text.trim(),
        'parentEmail': selectedParentEmail,
        'phone': phoneController.text.trim(),
        'notes': notesController.text.trim(),
        'progress': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': FirebaseAuth.instance.currentUser?.email ?? 'unknown',
      }).timeout(const Duration(seconds: 12));

      _clearForm();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الطفل في Firebase بنجاح ✓')));
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ Firebase: ${e.code} - ${e.message ?? ''}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحفظ: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final birthDateText = birthDate == null
        ? 'اختيار تاريخ الميلاد'
        : '${birthDate!.year}-${birthDate!.month.toString().padLeft(2, '0')}-${birthDate!.day.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: GlobalKey(),
          initiallyExpanded: _expanded,
          onExpansionChanged: (v) => setState(() => _expanded = v),
          leading: const Icon(Icons.child_care_rounded, color: Color(0xFF00A6A6)),
          title: const Text(
            '➕ إضافة طفل جديد 👧',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          subtitle: const Text('اضغط لفتح نموذج الإضافة', style: TextStyle(fontSize: 12, color: Colors.black54)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const Divider(),
            const SizedBox(height: 8),
            TextField(controller: nameController, decoration: inputDecoration('اسم الطفل')),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: pickBirthDate, icon: const Icon(Icons.cake_rounded), label: Text(birthDateText)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(14)),
              child: Text('العمر الزمني: $ageText'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: program,
              decoration: inputDecoration('البرنامج'),
              items: ['بورتاج', 'لوفاس', 'بورتاج + لوفاس'].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
              onChanged: (v) => setState(() => program = v ?? 'بورتاج + لوفاس'),
            ),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'parent').snapshots(),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];
                return DropdownButtonFormField<String>(
                  value: selectedParentId,
                  decoration: inputDecoration('ربط الطفل بولي أمر موجود - اختياري'),
                  items: [
                    const DropdownMenuItem<String>(value: null, child: Text('بدون ربط')),
                    ...docs.map((doc) {
                      final parent = doc.data();
                      return DropdownMenuItem<String>(
                        value: doc.id,
                        child: Text('${parent['name'] ?? 'ولي أمر'} - ${parent['email'] ?? ''}'),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    final selected = docs.where((d) => d.id == value).toList();
                    setState(() {
                      selectedParentId = value;
                      selectedParentName = selected.isEmpty ? null : (selected.first.data()['name'] ?? '').toString();
                      selectedParentEmail = selected.isEmpty ? null : (selected.first.data()['email'] ?? '').toString();
                      if (selectedParentName != null && selectedParentName!.isNotEmpty) {
                        parentController.text = selectedParentName!;
                      }
                    });
                  },
                );
              },
            ),
            const SizedBox(height: 8),
            TextField(controller: diagnosisController, decoration: inputDecoration('التشخيص')),
            const SizedBox(height: 8),
            TextField(controller: parentController, decoration: inputDecoration('اسم ولي الأمر (نصي احتياطي)')),
            const SizedBox(height: 8),
            TextField(controller: phoneController, decoration: inputDecoration('رقم الهاتف')),
            const SizedBox(height: 8),
            TextField(controller: notesController, maxLines: 2, decoration: inputDecoration('ملاحظات')),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: saving ? null : saveChild,
                    icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded),
                    label: Text(saving ? 'جار الحفظ...' : 'حفظ الطفل'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: saving ? null : _clearForm,
                  icon: const Icon(Icons.clear_rounded),
                  label: const Text('إلغاء'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class RealStatsRow extends StatelessWidget {
  const RealStatsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('children').snapshots(),
      builder: (context, childrenSnap) {
        final childCount = childrenSnap.data?.docs.length ?? 0;
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('users').snapshots(),
          builder: (context, usersSnap) {
            final staffCount = (usersSnap.data?.docs ?? [])
                .where((d) {
                  final r = (d.data()['role'] ?? '').toString();
                  return r == 'specialist' || r == 'senior' || r == 'manager';
                })
                .length;
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('weeklyPlans').snapshots(),
              builder: (context, plansSnap) {
                final planDocs = plansSnap.data?.docs ?? [];
                final values = planDocs
                    .map((d) => d.data()['achievementPercent'])
                    .whereType<num>()
                    .toList();
                final avgText = values.isEmpty
                    ? '0%'
                    : '${(values.reduce((a, b) => a + b) / values.length).round()}%';
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance.collection('seniorReports').snapshots(),
                  builder: (context, seniorSnap) {
                    final seniorCount = seniorSnap.data?.docs.length ?? 0;
                    final totalReports = planDocs.length + seniorCount;
                    return Row(
                      children: [
                        Expanded(child: StatMiniCard(title: 'عدد الأطفال', value: '$childCount')),
                        const SizedBox(width: 8),
                        Expanded(child: StatMiniCard(title: 'متوسط التحسن', value: avgText)),
                        const SizedBox(width: 8),
                        Expanded(child: StatMiniCard(title: 'العاملون', value: '$staffCount')),
                        const SizedBox(width: 8),
                        Expanded(child: StatMiniCard(title: '📊 التقارير', value: '$totalReports')),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class StatMiniCard extends StatelessWidget {
  final String title;
  final String value;
  const StatMiniCard({super.key, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 105,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: const TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class ChildrenListCard extends StatelessWidget {
  const ChildrenListCard({super.key});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '👧🧒 قائمة الأطفال',
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('children').orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text('حدث خطأ: ${snapshot.error}');
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) return const Text('لا يوجد أطفال مضافون حتى الآن.');

          return Column(
            children: docs.map((doc) {
              final child = doc.data();
              final name = child['name'] ?? 'بدون اسم';
              final program = child['program'] ?? '-';
              final diagnosis = child['diagnosis'] ?? '-';
              final parentName = child['parentName'] ?? '-';
              final savedAge = child['ageText'] ?? '-';

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.child_care)),
                  title: Text(name),
                  subtitle: Text(
                    'العمر: $savedAge\n'
                    'البرنامج: $program\n'
                    'التشخيص: $diagnosis\n'
                    'ولي الأمر: ${child['parentName'] != null && child['parentName'].toString().isNotEmpty ? child['parentName'] : "غير مربوط بولي أمر"}',
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'report') {
                        showReportDialog(context, name, 'تقرير شامل للطفل $name');
                      }
                      if (value == 'edit') {
                        showDialog(
                          context: context,
                          builder: (_) => EditChildDialog(childId: doc.id, child: child),
                        );
                      }
                      if (value == 'delete') {
                        final ok = await confirmDialog(context, 'نقل للسلة', 'هل تريد نقل $name إلى السلة؟');
                        if (!ok) return;
                        await moveDocumentToTrash(
                          collectionName: 'children',
                          docId: doc.id,
                          data: child,
                          itemTitle: 'طفل: $name',
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم نقل $name إلى السلة')));
                        }
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'report', child: Text('عرض التقرير')),
                      PopupMenuItem(value: 'edit', child: Text('تعديل')),
                      PopupMenuItem(value: 'delete', child: Text('نقل للسلة')),
                    ],
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class EditChildDialog extends StatefulWidget {
  final String childId;
  final Map<String, dynamic> child;

  const EditChildDialog({super.key, required this.childId, required this.child});

  @override
  State<EditChildDialog> createState() => _EditChildDialogState();
}

class _EditChildDialogState extends State<EditChildDialog> {
  late final TextEditingController nameController;
  late final TextEditingController diagnosisController;
  late final TextEditingController phoneController;
  late final TextEditingController notesController;
  late String program;
  String? selectedParentId;
  String? selectedParentName;
  String? selectedParentEmail;
  DateTime? birthDate;
  bool saving = false;

  String get ageText {
    if (birthDate == null) return 'لم يتم اختيار تاريخ الميلاد';
    final now = DateTime.now();
    int years = now.year - birthDate!.year;
    int months = now.month - birthDate!.month;
    if (now.day < birthDate!.day) months--;
    if (months < 0) { years--; months += 12; }
    return '$years سنة و $months شهر';
  }

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: (widget.child['name'] ?? '').toString());
    diagnosisController = TextEditingController(text: (widget.child['diagnosis'] ?? '').toString());
    phoneController = TextEditingController(text: (widget.child['phone'] ?? '').toString());
    notesController = TextEditingController(text: (widget.child['notes'] ?? '').toString());
    program = (widget.child['program'] ?? 'بورتاج + لوفاس').toString();
    selectedParentId = widget.child['parentId']?.toString();
    selectedParentName = widget.child['parentName']?.toString();
    selectedParentEmail = widget.child['parentEmail']?.toString();
    final dob = widget.child['dateOfBirth'];
    if (dob is Timestamp) birthDate = dob.toDate();
  }

  Future<void> pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: birthDate ?? DateTime(2020, 1, 1),
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
      helpText: 'اختيار تاريخ ميلاد الطفل',
    );
    if (picked != null) setState(() => birthDate = picked);
  }

  Future<void> save() async {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب اسم الطفل أولًا')));
      return;
    }
    setState(() => saving = true);
    try {
      final data = <String, dynamic>{
        'name': name,
        'diagnosis': diagnosisController.text.trim(),
        'phone': phoneController.text.trim(),
        'notes': notesController.text.trim(),
        'program': program,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': currentUserDisplayName(),
      };
      if (birthDate != null) {
        data['dateOfBirth'] = Timestamp.fromDate(birthDate!);
        data['ageText'] = ageText;
      }
      if (selectedParentId != null) {
        data['parentId'] = selectedParentId;
        data['parentName'] = selectedParentName;
        data['parentEmail'] = selectedParentEmail;
      }
      await FirebaseFirestore.instance.collection('children').doc(widget.childId).update(data);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تعديل بيانات الطفل')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل التعديل: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final birthDateText = birthDate == null
        ? 'اختيار تاريخ الميلاد'
        : '${birthDate!.year}-${birthDate!.month.toString().padLeft(2, '0')}-${birthDate!.day.toString().padLeft(2, '0')}';

    return AlertDialog(
      title: const Text('تعديل بيانات الطفل'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: inputDecoration('اسم الطفل')),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: pickBirthDate,
                icon: const Icon(Icons.cake_rounded),
                label: Text(birthDateText),
              ),
              if (birthDate != null) ...[
                const SizedBox(height: 4),
                Text('العمر: $ageText', style: const TextStyle(color: Colors.black54)),
              ],
              const SizedBox(height: 8),
              TextField(controller: diagnosisController, decoration: inputDecoration('التشخيص')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: program,
                decoration: inputDecoration('البرنامج'),
                items: ['بورتاج', 'لوفاس', 'بورتاج + لوفاس']
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (v) => setState(() => program = v ?? program),
              ),
              const SizedBox(height: 8),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'parent').snapshots(),
                builder: (context, snapshot) {
                  final docs = snapshot.data?.docs ?? [];
                  return DropdownButtonFormField<String>(
                    value: selectedParentId,
                    decoration: inputDecoration('ولي الأمر'),
                    items: [
                      const DropdownMenuItem<String>(value: null, child: Text('بدون ربط')),
                      ...docs.map((doc) {
                        final parent = doc.data();
                        return DropdownMenuItem<String>(
                          value: doc.id,
                          child: Text('${parent['name'] ?? 'ولي أمر'} - ${parent['email'] ?? ''}'),
                        );
                      }),
                    ],
                    onChanged: (value) {
                      final selected = docs.where((d) => d.id == value).toList();
                      setState(() {
                        selectedParentId = value;
                        selectedParentName = selected.isEmpty ? null : (selected.first.data()['name'] ?? '').toString();
                        selectedParentEmail = selected.isEmpty ? null : (selected.first.data()['email'] ?? '').toString();
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
              TextField(controller: phoneController, decoration: inputDecoration('رقم الهاتف')),
              const SizedBox(height: 8),
              TextField(controller: notesController, maxLines: 2, decoration: inputDecoration('ملاحظات')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: saving ? null : save, child: Text(saving ? 'جار الحفظ...' : 'حفظ')),
      ],
    );
  }
}

class BackupCard extends StatefulWidget {
  const BackupCard({super.key});

  @override
  State<BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends State<BackupCard> {
  bool loading = false;

  String _backupFileName() {
    final now = DateTime.now();
    final y = now.year;
    final mo = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final h = now.hour.toString().padLeft(2, '0');
    final mi = now.minute.toString().padLeft(2, '0');
    return 'ican_backup_${y}_${mo}_${d}_${h}_$mi.json';
  }

  Future<void> makeBackup() async {
    setState(() => loading = true);
    try {
      final backup = await createBackupJson();
      final fileName = _backupFileName();
      // تنزيل مباشر عبر dart:html على Flutter Web
      final bytes = const Utf8Encoder().convert(backup);
      final blob = html.Blob([bytes], 'application/json');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..click();
      html.Url.revokeObjectUrl(url);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تنزيل النسخة الاحتياطية: $fileName')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل إنشاء النسخة الاحتياطية: $e')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> restoreFromFile() async {
    try {
      // فتح file picker عبر dart:html
      final uploadInput = html.FileUploadInputElement()..accept = '.json,application/json';
      uploadInput.click();
      await uploadInput.onChange.first;
      final file = uploadInput.files?.first;
      if (file == null) return;

      setState(() => loading = true);
      final reader = html.FileReader();
      reader.readAsText(file);
      await reader.onLoad.first;
      final text = reader.result as String;

      await restoreBackupJson(text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم استرداد النسخة الاحتياطية بنجاح')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الاسترداد: $e')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '💾 النسخ الاحتياطي',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: loading ? null : makeBackup,
            icon: loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.download_rounded),
            label: Text(loading ? '⏳ جار التنزيل...' : '💾 تنزيل نسخة احتياطية'),
          ),
          OutlinedButton.icon(
            onPressed: loading ? null : restoreFromFile,
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('📂 استرداد من ملف JSON'),
          ),
        ],
      ),
    );
  }
}

/* ===================== التقييم والأهداف ===================== */

class AssessmentPage extends StatefulWidget {
  const AssessmentPage({super.key});

  @override
  State<AssessmentPage> createState() => _AssessmentPageState();
}

class _AssessmentPageState extends State<AssessmentPage> {
  String? selectedChildId;
  String? selectedChildName;

  @override
  Widget build(BuildContext context) {
    return PageWrap(
      children: [
        const HeroBox(
          title: '🎯 تقييم الطفل والخطة الفردية',
          subtitle: 'اختر الطفل 👧 من Firebase ثم أضف أهدافًا 🎯 حقيقية مرتبطة به.',
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '🔍 اختيار الطفل',
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('children').orderBy('createdAt', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text('خطأ: ${snapshot.error}');
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) return const Text('لا يوجد أطفال. أضف طفلًا من لوحة الإدارة أولًا.');

              final items = docs.map((doc) => {'id': doc.id, 'label': (doc.data()['name'] ?? 'بدون اسم').toString()}).toList();
              return SearchableDropdown(
                label: 'اختر الطفل',
                value: selectedChildId,
                items: items,
                onChanged: (value) {
                  final doc = docs.where((d) => d.id == value).toList();
                  setState(() {
                    selectedChildId = value;
                    selectedChildName = doc.isEmpty ? 'الطفل' : (doc.first.data()['name'] ?? 'بدون اسم');
                  });
                },
              );
            },
          ),
        ),
        if (selectedChildId != null) ...[
          AddGoalCard(childId: selectedChildId!, childName: selectedChildName ?? 'الطفل'),
          GoalsListCard(childId: selectedChildId!, childName: selectedChildName ?? 'الطفل'),
        ],
      ],
    );
  }
}

class AddGoalCard extends StatefulWidget {
  final String childId;
  final String childName;

  const AddGoalCard({super.key, required this.childId, required this.childName});

  @override
  State<AddGoalCard> createState() => _AddGoalCardState();
}

class _AddGoalCardState extends State<AddGoalCard> {
  final goalController = TextEditingController();
  final specialistController = TextEditingController(text: 'أ. محمد');
  String program = 'بورتاج';
  String status = 'يحتاج تدريب';
  String goalStage = 'active';
  bool saving = false;
  bool _expanded = false;

  Future<void> saveGoal() async {
    final text = goalController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب الهدف أولًا')));
      return;
    }

    setState(() => saving = true);

    try {
      await FirebaseFirestore.instance.collection('goals').add({
        'childId': widget.childId,
        'childName': widget.childName,
        'text': text,
        'program': program,
        'status': status,
        'goalStage': goalStage,
        'createdBySpecialist': specialistController.text.trim(),
        'createdByEmail': FirebaseAuth.instance.currentUser?.email ?? 'unknown',
        'createdAt': FieldValue.serverTimestamp(),
        'movedToWeekly': false,
        'lastAchievementPercent': null,
        'lastWeeklyUpdateAt': null,
      }).timeout(const Duration(seconds: 12));

      goalController.clear();
      setState(() => _expanded = false); // إغلاق بعد الحفظ

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الهدف ✓')));
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ Firebase: ${e.code} - ${e.message ?? ''}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل حفظ الهدف: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> importLinesAsGoals() async {
    final raw = goalController.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الصق الأهداف أولًا، كل هدف في سطر')));
      return;
    }

    final lines = raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => line.replaceFirst(RegExp(r'^\d+[\.\-\)]\s*'), '').replaceFirst(RegExp(r'^[-•]\s*'), '').trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (lines.isEmpty) return;

    setState(() => saving = true);

    try {
      final batch = FirebaseFirestore.instance.batch();
      final goalsRef = FirebaseFirestore.instance.collection('goals');

      for (final line in lines) {
        final doc = goalsRef.doc();
        batch.set(doc, {
          'childId': widget.childId,
          'childName': widget.childName,
          'text': line,
          'program': program,
          'status': status,
          'goalStage': goalStage,
          'createdBySpecialist': specialistController.text.trim(),
          'createdByEmail': FirebaseAuth.instance.currentUser?.email ?? 'unknown',
          'createdAt': FieldValue.serverTimestamp(),
          'movedToWeekly': false,
          'lastAchievementPercent': null,
          'lastWeeklyUpdateAt': null,
        });
      }

      await batch.commit().timeout(const Duration(seconds: 12));
      goalController.clear();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم استيراد ${lines.length} هدف وربطهم بالطفل')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الاستيراد: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _expanded,
          onExpansionChanged: (v) => setState(() => _expanded = v),
          leading: const Icon(Icons.add_circle_rounded, color: Color(0xFF00A6A6)),
          title: Text('➕ إضافة أهداف جديدة 🎯 - ${widget.childName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          subtitle: const Text('اضغط لفتح نموذج إضافة الأهداف', style: TextStyle(fontSize: 12, color: Colors.black54)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const Divider(),
            const SizedBox(height: 8),
            TextField(
              controller: goalController,
              maxLines: 4,
              decoration: inputDecoration('اكتب هدفًا واحدًا أو الصق عدة أهداف: كل سطر = هدف مستقل'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: program,
              decoration: inputDecoration('البرنامج'),
              items: ['بورتاج', 'لوفاس'].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
              onChanged: (v) => setState(() => program = v ?? 'بورتاج'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: status,
              decoration: inputDecoration('حالة الهدف'),
              items: ['نجاح', 'بمساعدة', 'يحتاج تدريب'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => status = v ?? 'يحتاج تدريب'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: goalStage,
              decoration: inputDecoration('مرحلة الهدف'),
              items: const [
                DropdownMenuItem(value: 'active', child: Text('نشط الآن')),
                DropdownMenuItem(value: 'longTerm', child: Text('بعيد المدى')),
              ],
              onChanged: (v) => setState(() => goalStage = v ?? 'active'),
            ),
            const SizedBox(height: 8),
            TextField(controller: specialistController, decoration: inputDecoration('اسم الأخصائي الذي أضاف الهدف')),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: saving ? null : saveGoal,
                  icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
                  label: Text(saving ? 'جار الحفظ...' : 'حفظ كهدف واحد'),
                ),
                OutlinedButton.icon(
                  onPressed: saving ? null : importLinesAsGoals,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('استيراد كل سطر كهدف'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}



class GoalsListCard extends StatefulWidget {
  final String childId;
  final String childName;

  const GoalsListCard({super.key, required this.childId, required this.childName});

  @override
  State<GoalsListCard> createState() => _GoalsListCardState();
}

class _GoalsListCardState extends State<GoalsListCard> {
  String selectedStage = 'active';

  String titleForStage() {
    switch (selectedStage) {
      case 'active':
        return 'الأهداف النشطة';
      case 'longTerm':
        return 'الأهداف بعيدة المدى';
      case 'mastered':
        return 'أرشيف الأهداف المتقنة';
      default:
        return 'الأهداف';
    }
  }

  Future<void> updateGoalStage({
    required String goalId,
    required String stage,
    required String message,
  }) async {
    try {
      final data = <String, dynamic>{
        'goalStage': stage,
        'stageUpdatedAt': FieldValue.serverTimestamp(),
        'stageUpdatedBy': currentUserDisplayName(),
      };

      if (stage == 'mastered') {
        data['masteredAt'] = FieldValue.serverTimestamp();
        data['masteredBy'] = currentUserDisplayName();
      }

      if (stage == 'active') {
        data['activatedAt'] = FieldValue.serverTimestamp();
        data['activatedBy'] = currentUserDisplayName();
      }

      if (stage == 'longTerm') {
        data['longTermAt'] = FieldValue.serverTimestamp();
        data['longTermBy'] = currentUserDisplayName();
      }

      await FirebaseFirestore.instance.collection('goals').doc(goalId).update(data);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل تحديث الهدف: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '🎯 أهداف الطفل: ${widget.childName}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'active', label: Text('نشطة'), icon: Icon(Icons.play_circle_fill_rounded)),
              ButtonSegment(value: 'longTerm', label: Text('بعيدة المدى'), icon: Icon(Icons.schedule_rounded)),
              ButtonSegment(value: 'mastered', label: Text('متقنة'), icon: Icon(Icons.verified_rounded)),
            ],
            selected: {selectedStage},
            onSelectionChanged: (value) => setState(() => selectedStage = value.first),
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('goals')
                .where('childId', isEqualTo: widget.childId)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text('خطأ في قراءة الأهداف: ${snapshot.error}');
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

              final allDocs = snapshot.data?.docs ?? [];
              final docs = allDocs.where((doc) {
                final goal = doc.data();
                final stage = (goal['goalStage'] ?? 'active').toString();
                return stage == selectedStage;
              }).toList();

              if (docs.isEmpty) {
                return Text('لا توجد أهداف في قسم: ${titleForStage()}');
              }

              return Column(
                children: docs.map((doc) {
                  final goal = doc.data();
                  final text = goal['text'] ?? '';
                  final program = goal['program'] ?? '';
                  final status = goal['status'] ?? '';
                  final specialist = goal['createdBySpecialist'] ?? '';
                  final moved = goal['movedToWeekly'] == true;
                  final movedBy = goal['movedBy'] ?? '-';
                  final movedAt = goal['movedAt'];
                  final movedDate = movedAt is Timestamp ? movedAt.toDate().toString().split(' ').first : '-';
                  final lastPercent = goal['lastAchievementPercent'];
                  final lastPrompt = goal['lastPromptLevel'];
                  final lastReinforcement = goal['lastReinforcementSchedule'];

                  return Card(
                    color: goalStageColor(goal),
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. نص الهدف + زر القائمة
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: CircleAvatar(radius: 14, child: Icon(Icons.flag_rounded, size: 14)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, height: 1.4)),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (value) async {
                                  if (value == 'edit') showDialog(context: context, builder: (_) => EditGoalDialog(goalId: doc.id, goal: goal));
                                  if (value == 'delete') {
                                    final ok = await confirmDialog(context, 'نقل للسلة', 'هل تريد نقل هذا الهدف إلى السلة؟');
                                    if (!ok) return;
                                    await moveDocumentToTrash(collectionName: 'goals', docId: doc.id, data: goal, itemTitle: 'هدف: $text');
                                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نقل الهدف إلى السلة')));
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'edit', child: Text('تعديل')),
                                  PopupMenuItem(value: 'delete', child: Text('نقل للسلة')),
                                ],
                              ),
                            ],
                          ),
                          // 2. نسبة الإنجاز
                          if (lastPercent != null) ...[
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.only(right: 38),
                              child: Text(
                                'آخر نسبة إنجاز: $lastPercent%',
                                style: TextStyle(fontSize: 12, color: (lastPercent as num) >= 70 ? Colors.green : Colors.orange, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                          // 3. أزرار الإجراءات - ظاهرة دائمًا
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (selectedStage == 'active') ...[
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), minimumSize: Size.zero),
                                  onPressed: () => showDialog(context: context, builder: (_) => TransferGoalDialog(goalId: doc.id, goal: goal)),
                                  icon: const Icon(Icons.calendar_today_rounded, size: 14),
                                  label: const Text('📅 نقل للأسبوع', style: TextStyle(fontSize: 12)),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), minimumSize: Size.zero),
                                  onPressed: () => updateGoalStage(goalId: doc.id, stage: 'mastered', message: 'تم نقل الهدف إلى الأهداف المتقنة'),
                                  icon: const Icon(Icons.verified_rounded, size: 14),
                                  label: const Text('✅ متقنة', style: TextStyle(fontSize: 12)),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), minimumSize: Size.zero),
                                  onPressed: () => updateGoalStage(goalId: doc.id, stage: 'longTerm', message: 'تم تأجيل الهدف'),
                                  icon: const Icon(Icons.schedule_rounded, size: 14),
                                  label: const Text('تأجيل', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                              if (selectedStage == 'longTerm')
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), minimumSize: Size.zero),
                                  onPressed: () => updateGoalStage(goalId: doc.id, stage: 'active', message: 'تم تنشيط الهدف'),
                                  icon: const Icon(Icons.play_arrow_rounded, size: 14),
                                  label: const Text('تنشيط', style: TextStyle(fontSize: 12)),
                                ),
                              if (selectedStage == 'mastered')
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), minimumSize: Size.zero),
                                  onPressed: () => updateGoalStage(goalId: doc.id, stage: 'active', message: 'تم إعادة الهدف للنشط'),
                                  icon: const Icon(Icons.undo_rounded, size: 14),
                                  label: const Text('إعادة للنشط', style: TextStyle(fontSize: 12)),
                                ),
                            ],
                          ),
                          // 4. التفاصيل مخفية في الأسفل
                          Theme(
                            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              initiallyExpanded: false,
                              tilePadding: EdgeInsets.zero,
                              dense: true,
                              title: const Text('🔍 عرض التفاصيل', style: TextStyle(fontSize: 12, color: Colors.black45)),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (program.toString().isNotEmpty) _goalDetailRow('البرنامج', program.toString()),
                                      if (status.toString().isNotEmpty) _goalDetailRow('الحالة', status.toString()),
                                      _goalDetailRow('مرحلة الهدف', goalStageArabic(goal['goalStage'] ?? 'active')),
                                      if (specialist.toString().isNotEmpty) _goalDetailRow('الأخصائي', specialist.toString()),
                                      _goalDetailRow(moved ? 'نُقل بواسطة' : 'الحالة', moved ? '$movedBy - $movedDate' : 'لم يُنقل للبرنامج بعد'),
                                      if (lastPrompt != null) _goalDetailRow('آخر مساعدة', lastPrompt.toString()),
                                      if (lastReinforcement != null) _goalDetailRow('آخر تعزيز', lastReinforcement.toString()),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

Widget _goalDetailRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 110, child: Text('$label:', style: const TextStyle(fontSize: 11, color: Colors.black54))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 11))),
      ],
    ),
  );
}


class EditGoalDialog extends StatefulWidget {
  final String goalId;
  final Map<String, dynamic> goal;

  const EditGoalDialog({super.key, required this.goalId, required this.goal});

  @override
  State<EditGoalDialog> createState() => _EditGoalDialogState();
}

class _EditGoalDialogState extends State<EditGoalDialog> {
  late final TextEditingController textController;
  late String program;
  late String status;
  late String goalStage;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    textController = TextEditingController(text: (widget.goal['text'] ?? '').toString());
    program = (widget.goal['program'] ?? 'بورتاج').toString();
    status = (widget.goal['status'] ?? 'يحتاج تدريب').toString();
    goalStage = (widget.goal['goalStage'] ?? 'active').toString();
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      await FirebaseFirestore.instance.collection('goals').doc(widget.goalId).update({
        'text': textController.text.trim(),
        'program': program,
        'status': status,
        'goalStage': goalStage,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': currentUserDisplayName(),
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تعديل الهدف')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل تعديل الهدف: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تعديل الهدف'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: textController, maxLines: 4, decoration: inputDecoration('نص الهدف')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: program,
              decoration: inputDecoration('البرنامج'),
              items: ['بورتاج', 'لوفاس'].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
              onChanged: (v) => setState(() => program = v ?? program),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: status,
              decoration: inputDecoration('حالة الهدف'),
              items: ['نجاح', 'بمساعدة', 'يحتاج تدريب'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => status = v ?? status),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: goalStage,
              decoration: inputDecoration('مرحلة الهدف'),
              items: const [
                DropdownMenuItem(value: 'active', child: Text('نشط الآن')),
                DropdownMenuItem(value: 'longTerm', child: Text('بعيد المدى')),
                DropdownMenuItem(value: 'mastered', child: Text('متقن / مؤرشف')),
              ],
              onChanged: (v) => setState(() => goalStage = v ?? goalStage),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: saving ? null : save, child: Text(saving ? 'جار الحفظ...' : 'حفظ')),
      ],
    );
  }
}

class TransferGoalDialog extends StatefulWidget {
  final String goalId;
  final Map<String, dynamic> goal;

  const TransferGoalDialog({super.key, required this.goalId, required this.goal});

  @override
  State<TransferGoalDialog> createState() => _TransferGoalDialogState();
}

class _TransferGoalDialogState extends State<TransferGoalDialog> {
  late int year;
  late int month;
  late int week;
  String sessionType = 'تخاطب';
  final movedByController = TextEditingController(text: 'أ. محمد');
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    year = now.year;
    month = now.month;
    week = ((now.day - 1) ~/ 7) + 1;
    if (week > 5) week = 5;
  }

  Future<void> transfer() async {
    if ((widget.goal['goalStage'] ?? 'active') != 'active') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن نقل الهدف للأسبوع إلا إذا كان هدفًا نشطًا')),
      );
      return;
    }

    setState(() => saving = true);

    try {
      final batch = FirebaseFirestore.instance.batch();
      final weeklyRef = FirebaseFirestore.instance.collection('weeklyPlans').doc();
      final goalRef = FirebaseFirestore.instance.collection('goals').doc(widget.goalId);

      final movedBy = movedByController.text.trim().isEmpty ? 'غير محدد' : movedByController.text.trim();

      batch.set(weeklyRef, {
        'goalId': widget.goalId,
        'childId': widget.goal['childId'],
        'childName': widget.goal['childName'],
        'goalText': widget.goal['text'],
        'goalAuthor': widget.goal['createdBySpecialist'],
        'year': year,
        'month': month,
        'week': week,
        'sessionType': sessionType,
        'promptLevel': 'IND',
        'reinforcementSchedule': 'FR1',
        'achievementPercent': 0,
        'movedBy': movedBy,
        'movedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.update(goalRef, {
        'movedToWeekly': true,
        'movedBy': movedBy,
        'movedAt': FieldValue.serverTimestamp(),
        'movedYear': year,
        'movedMonth': month,
        'movedWeek': week,
        'movedSessionType': sessionType,
      });

      await batch.commit().timeout(const Duration(seconds: 12));

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نقل الهدف للبرنامج الأسبوعي')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل النقل: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('نقل الهدف للبرنامج الأسبوعي'),
      content: SingleChildScrollView(
        child: Column(
          children: [
            Text(widget.goal['text'] ?? ''),
            const SizedBox(height: 12),
            TextField(controller: movedByController, decoration: inputDecoration('اسم الشخص الذي نقل الهدف')),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: year,
              decoration: inputDecoration('السنة'),
              items: List.generate(5, (i) => DateTime.now().year - 1 + i)
                  .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                  .toList(),
              onChanged: (v) => setState(() => year = v ?? year),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: month,
              decoration: inputDecoration('الشهر'),
              items: List.generate(12, (i) => i + 1)
                  .map((m) => DropdownMenuItem(value: m, child: Text('$m')))
                  .toList(),
              onChanged: (v) => setState(() => month = v ?? month),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: week,
              decoration: inputDecoration('الأسبوع'),
              items: [1, 2, 3, 4, 5]
                  .map((w) => DropdownMenuItem(value: w, child: Text('الأسبوع $w')))
                  .toList(),
              onChanged: (v) => setState(() => week = v ?? week),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: sessionType,
              decoration: inputDecoration('نوع الجلسة'),
              items: sessionTypes.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => sessionType = v ?? sessionType),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: saving ? null : transfer, child: Text(saving ? 'جار النقل...' : 'نقل')),
      ],
    );
  }
}

const sessionTypes = [
  'تخاطب',
  'تنمية مهارات',
  'تكامل حسي',
  'تأهيل حركي ووظيفي',
  'تأهيل نمائي وأكاديمي',
  'اجتماعي',
  'دمج',
  'تعديل سلوك ومعرفي سلوكي',
  'تأهيل حياتي ومهني',
];

const goalStages = {
  'active': 'نشط الآن',
  'longTerm': 'بعيد المدى',
  'mastered': 'متقن / مؤرشف',
};

String goalStageArabic(String value) {
  return goalStages[value] ?? value;
}

Color? goalStageColor(Map<String, dynamic> goal) {
  final stage = (goal['goalStage'] ?? 'active').toString();
  final p = goal['lastAchievementPercent'];

  if (stage == 'mastered') return const Color(0xFFE7FBEA);
  if (stage == 'longTerm') return const Color(0xFFFFF8E1);
  if (p is num && p >= 70) return const Color(0xFFE7FBEA);
  return null;
}



class WeeklyProgramPage extends StatefulWidget {
  const WeeklyProgramPage({super.key});

  @override
  State<WeeklyProgramPage> createState() => _WeeklyProgramPageState();
}

class _WeeklyProgramPageState extends State<WeeklyProgramPage> {
  int year = DateTime.now().year;
  int month = DateTime.now().month;
  int week = ((DateTime.now().day - 1) ~/ 7) + 1;
  String sessionFilter = 'كل أنواع الجلسات';

  String? selectedChildId;
  String selectedChildName = '';

  @override
  Widget build(BuildContext context) {
    if (week > 5) week = 5;

    return PageWrap(
      children: [
        const HeroBox(
          title: '🧩 البرنامج الأسبوعي',
          subtitle: 'اختر الطفل 👧 أولًا، ثم تظهر أهدافه 🎯 مرتبة حسب نوع الجلسة 🧩 واسم الأخصائي 👨‍🏫.',
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '🔍 فلترة البرنامج',
          child: Column(
            children: [
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('children').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) return Text('خطأ في قراءة الأطفال: ${snapshot.error}');
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) return const Text('لا يوجد أطفال مضافون حتى الآن.');

                  final items = docs.map((doc) => {'id': doc.id, 'label': (doc.data()['name'] ?? 'بدون اسم').toString()}).toList();
                  return SearchableDropdown(
                    label: 'اختر الطفل',
                    value: selectedChildId,
                    items: items,
                    onChanged: (value) {
                      final selected = docs.where((d) => d.id == value).toList();
                      setState(() {
                        selectedChildId = value;
                        selectedChildName = selected.isEmpty ? '' : (selected.first.data()['name'] ?? 'بدون اسم');
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: year,
                decoration: inputDecoration('السنة'),
                items: List.generate(5, (i) => DateTime.now().year - 1 + i)
                    .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                    .toList(),
                onChanged: (v) => setState(() => year = v ?? year),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: month,
                decoration: inputDecoration('الشهر'),
                items: List.generate(12, (i) => i + 1)
                    .map((m) => DropdownMenuItem(value: m, child: Text('$m')))
                    .toList(),
                onChanged: (v) => setState(() => month = v ?? month),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: week,
                decoration: inputDecoration('الأسبوع'),
                items: [1, 2, 3, 4, 5].map((w) => DropdownMenuItem(value: w, child: Text('الأسبوع $w'))).toList(),
                onChanged: (v) => setState(() => week = v ?? week),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: sessionFilter,
                decoration: inputDecoration('نوع الجلسة'),
                items: ['كل أنواع الجلسات', ...sessionTypes].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setState(() => sessionFilter = v ?? sessionFilter),
              ),
            ],
          ),
        ),
        if (selectedChildId == null)
          const SectionCard(
            title: 'اختر الطفل',
            child: Text('من فضلك اختر الطفل أولًا لعرض برنامجه الأسبوعي فقط.'),
          )
        else
          WeeklyPlanList(
            childId: selectedChildId!,
            childName: selectedChildName,
            year: year,
            month: month,
            week: week,
            sessionFilter: sessionFilter,
          ),
      ],
    );
  }
}

class WeeklyPlanList extends StatelessWidget {
  final String childId;
  final String childName;
  final int year;
  final int month;
  final int week;
  final String sessionFilter;

  const WeeklyPlanList({
    super.key,
    required this.childId,
    required this.childName,
    required this.year,
    required this.month,
    required this.week,
    required this.sessionFilter,
  });

  Future<void> approveSession(
    BuildContext context,
    String sessionType,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (!isCurrentUserSenior()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اعتماد السينيور متاح لحساب السينيور فقط')),
      );
      return;
    }

    try {
      final seniorName = currentUserDisplayName();
      final batch = FirebaseFirestore.instance.batch();

      for (final doc in docs) {
        batch.update(doc.reference, {
          'seniorApproved': true,
          'seniorName': seniorName,
          'seniorApprovedAt': FieldValue.serverTimestamp(),
          'seniorApprovedSessionType': sessionType,
        });
      }

      await batch.commit().timeout(const Duration(seconds: 12));

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تمت مراجعة $sessionType بواسطة $seniorName')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل اعتماد السينيور: $e')),
      );
    }
  }

  Map<String, Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>> groupDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final grouped = <String, Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>>{};

    for (final doc in docs) {
      final item = doc.data();
      final session = (item['sessionType'] ?? 'غير محدد').toString();
      final specialist = (item['goalAuthor'] ?? 'أخصائي غير محدد').toString();

      grouped.putIfAbsent(session, () => {});
      grouped[session]!.putIfAbsent(specialist, () => []);
      grouped[session]![specialist]!.add(doc);
    }

    final sortedSessions = grouped.keys.toList()..sort((a, b) => a.compareTo(b));
    return {
      for (final session in sortedSessions)
        session: {
          for (final specialist in (grouped[session]!.keys.toList()..sort()))
            specialist: grouped[session]![specialist]!,
        }
    };
  }

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('weeklyPlans')
        .where('childId', isEqualTo: childId)
        .where('year', isEqualTo: year)
        .where('month', isEqualTo: month)
        .where('week', isEqualTo: week);

    if (sessionFilter != 'كل أنواع الجلسات') {
      query = query.where('sessionType', isEqualTo: sessionFilter);
    }

    return SectionCard(
      title: 'أهداف $childName - الأسبوع $week - شهر $month - سنة $year',
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text('خطأ في قراءة البرنامج: ${snapshot.error}');
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) return const Text('لا توجد أهداف منقولة لهذا الاختيار حتى الآن.');

          final grouped = groupDocs(docs);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: grouped.entries.map((sessionEntry) {
              final sessionType = sessionEntry.key;
              final specialistsMap = sessionEntry.value;
              final sessionDocs = specialistsMap.values.expand((list) => list).toList();

              final approvedDocs = sessionDocs.where((d) => d.data()['seniorApproved'] == true).toList();
              final approvedBy = approvedDocs.isNotEmpty ? approvedDocs.first.data()['seniorName']?.toString() : null;
              final isApproved = approvedBy != null && approvedBy.isNotEmpty;

              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FBFF),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFBDE8FF)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isApproved ? const Color(0xFFE7FBEA) : const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('نوع الجلسة: $sessionType', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          const SizedBox(height: 6),
                          Text(isApproved ? 'تمت المراجعة بواسطة: $approvedBy' : 'لم تتم مراجعة السينيور بعد'),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: isCurrentUserSenior()
                                ? () => approveSession(context, sessionType, sessionDocs)
                                : null,
                            icon: const Icon(Icons.verified_rounded),
                            label: Text(isApproved ? 'إعادة اعتماد $sessionType' : 'اعتماد السينيور لـ $sessionType'),
                          ),
                          if (!isCurrentUserSenior())
                            const Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: Text(
                                'ظاهر للمتابعة فقط — الاعتماد متاح للسينيور فقط.',
                                style: TextStyle(color: Colors.black54),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...specialistsMap.entries.map((specialistEntry) {
                      final specialist = specialistEntry.key;
                      final specialistDocs = specialistEntry.value;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('أهداف الأخصائي: $specialist', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 8),
                            ...specialistDocs.map((doc) => WeeklyPlanItemCard(id: doc.id, item: doc.data())),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class WeeklyPlanItemCard extends StatefulWidget {
  final String id;
  final Map<String, dynamic> item;

  const WeeklyPlanItemCard({super.key, required this.id, required this.item});

  @override
  State<WeeklyPlanItemCard> createState() => _WeeklyPlanItemCardState();
}

class _WeeklyPlanItemCardState extends State<WeeklyPlanItemCard> {
  late String promptLevel;
  late String reinforcementSchedule;
  late int achievementPercent;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    promptLevel = widget.item['promptLevel'] ?? 'IND';
    reinforcementSchedule = widget.item['reinforcementSchedule'] ?? 'FR1';
    achievementPercent = (widget.item['achievementPercent'] ?? 0) as int;
  }

  Color? get color => achievementPercent >= 70 ? const Color(0xFFE7FBEA) : null;

  Future<void> saveProgress() async {
    setState(() => saving = true);

    try {
      final weeklyRef = FirebaseFirestore.instance.collection('weeklyPlans').doc(widget.id);
      final goalRef = FirebaseFirestore.instance.collection('goals').doc(widget.item['goalId']);

      final batch = FirebaseFirestore.instance.batch();

      batch.update(weeklyRef, {
        'promptLevel': promptLevel,
        'reinforcementSchedule': reinforcementSchedule,
        'achievementPercent': achievementPercent,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.update(goalRef, {
        'lastPromptLevel': promptLevel,
        'lastReinforcementSchedule': reinforcementSchedule,
        'lastAchievementPercent': achievementPercent,
        'lastWeeklyUpdateAt': FieldValue.serverTimestamp(),
      });

      await batch.commit().timeout(const Duration(seconds: 12));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ التقدم وتحديث الخطة الفردية')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل حفظ التقدم: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ✅ 1. نص الهدف
            Text(widget.item['goalText'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, height: 1.4)),
            const SizedBox(height: 6),
            // ✅ 2. نسبة الإنجاز
            Row(
              children: [
                Icon(Icons.trending_up_rounded, size: 16, color: achievementPercent >= 70 ? Colors.green : Colors.orange),
                const SizedBox(width: 4),
                Text(
                  'نسبة الإنجاز: $achievementPercent%',
                  style: TextStyle(color: achievementPercent >= 70 ? Colors.green : Colors.orange, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
            ),
            // ✅ 3. التفاصيل + ضبط القيم داخل ExpansionTile
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: false,
                tilePadding: EdgeInsets.zero,
                dense: true,
                title: const Text('🔍 تفاصيل الهدف وضبط القيم', style: TextStyle(fontSize: 12, color: Colors.black45)),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _goalDetailRow('الطفل', widget.item['childName'] ?? '-'),
                        _goalDetailRow('نوع الجلسة', widget.item['sessionType'] ?? '-'),
                        _goalDetailRow('أضاف الهدف', widget.item['goalAuthor'] ?? '-'),
                        _goalDetailRow('نقله للأسبوع', widget.item['movedBy'] ?? '-'),
                        if (widget.item['seniorApproved'] == true)
                          _goalDetailRow('مراجعة السينيور', widget.item['seniorName'] ?? '-'),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: promptLevel,
                          decoration: inputDecoration('نوع المساعدة'),
                          items: ['IND', 'VP', 'GP', 'PP', 'FP'].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                          onChanged: (v) => setState(() => promptLevel = v ?? promptLevel),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: reinforcementSchedule,
                          decoration: inputDecoration('جدول التعزيز'),
                          items: ['FR1', 'FR2', 'FR3', 'VR2', 'VR3', 'FI', 'VI'].map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                          onChanged: (v) => setState(() => reinforcementSchedule = v ?? reinforcementSchedule),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int>(
                          value: achievementPercent,
                          decoration: inputDecoration('نسبة الإنجاز'),
                          items: [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100].map((p) => DropdownMenuItem(value: p, child: Text('$p%'))).toList(),
                          onChanged: (v) => setState(() => achievementPercent = v ?? achievementPercent),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ✅ 4. زر حفظ التقدم - ظاهر دائمًا
            const SizedBox(height: 6),
            FilledButton.icon(
              onPressed: saving ? null : saveProgress,
              icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
              label: Text(saving ? '⏳ جار الحفظ...' : '💾 حفظ التقدم'),
            ),
          ],
        ),
      ),
    );
  }
}


/* ===================== التقارير ===================== */

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  String? selectedChildId;
  String selectedChildName = '';
  String reportType = 'أسبوعي';
  int year = DateTime.now().year;
  int month = DateTime.now().month;
  int week = ((DateTime.now().day - 1) ~/ 7) + 1;
  String sessionFilter = 'كل أنواع الجلسات';

  @override
  Widget build(BuildContext context) {
    if (week > 5) week = 5;

    return PageWrap(
      children: [
        const HeroBox(
          title: 'التقارير',
          subtitle: 'تقارير منظمة ومبهجة لعرض تقدم الطفل أمام ولي الأمر، مقسمة حسب نوع الجلسة والأخصائي.',
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '📊 اختيارات التقرير',
          child: Column(
            children: [
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('children').snapshots(),
                builder: (context, snapshot) {
                  final docs = snapshot.data?.docs ?? [];
                  final items = docs.map((doc) => {'id': doc.id, 'label': (doc.data()['name'] ?? 'بدون اسم').toString()}).toList();
                  return SearchableDropdown(
                    label: 'اختر الطفل',
                    value: selectedChildId,
                    items: items,
                    onChanged: (value) {
                      final selected = docs.where((d) => d.id == value).toList();
                      setState(() {
                        selectedChildId = value;
                        selectedChildName = selected.isEmpty ? '' : (selected.first.data()['name'] ?? '');
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: reportType,
                decoration: inputDecoration('نوع التقرير'),
                items: ['أسبوعي', 'شهري', 'سنوي']
                    .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                    .toList(),
                onChanged: (v) => setState(() => reportType = v ?? reportType),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: year,
                decoration: inputDecoration('السنة'),
                items: List.generate(5, (i) => DateTime.now().year - 1 + i)
                    .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                    .toList(),
                onChanged: (v) => setState(() => year = v ?? year),
              ),
              const SizedBox(height: 8),
              if (reportType != 'سنوي')
                DropdownButtonFormField<int>(
                  value: month,
                  decoration: inputDecoration('الشهر'),
                  items: List.generate(12, (i) => i + 1)
                      .map((m) => DropdownMenuItem(value: m, child: Text('$m')))
                      .toList(),
                  onChanged: (v) => setState(() => month = v ?? month),
                ),
              if (reportType != 'سنوي') const SizedBox(height: 8),
              if (reportType == 'أسبوعي')
                DropdownButtonFormField<int>(
                  value: week,
                  decoration: inputDecoration('الأسبوع'),
                  items: [1, 2, 3, 4, 5]
                      .map((w) => DropdownMenuItem(value: w, child: Text('الأسبوع $w')))
                      .toList(),
                  onChanged: (v) => setState(() => week = v ?? week),
                ),
              if (reportType == 'أسبوعي') const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: sessionFilter,
                decoration: inputDecoration('نوع الجلسة'),
                items: ['كل أنواع الجلسات', ...sessionTypes]
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => sessionFilter = v ?? sessionFilter),
              ),
            ],
          ),
        ),
        if (selectedChildId == null)
          const SectionCard(
            title: 'اختر الطفل',
            child: Text('اختر طفلًا من القائمة بالأعلى لعرض التقرير.'),
          )
        else
          ReportPreviewCard(
            childId: selectedChildId!,
            childName: selectedChildName,
            reportType: reportType,
            year: year,
            month: month,
            week: week,
            sessionFilter: sessionFilter,
          ),

        // --- قسم تقرير السينيورز ---
        const SizedBox(height: 8),
        SeniorReportSection(
          preSelectedChildId: selectedChildId,
          preSelectedChildName: selectedChildName,
        ),
      ],
    );
  }
}

class ReportPreviewCard extends StatelessWidget {
  final String childId;
  final String childName;
  final String reportType;
  final int year;
  final int month;
  final int week;
  final String sessionFilter;

  const ReportPreviewCard({
    super.key,
    required this.childId,
    required this.childName,
    required this.reportType,
    required this.year,
    required this.month,
    required this.week,
    required this.sessionFilter,
  });

  String get periodText {
    if (reportType == 'سنوي') return 'تقرير سنوي عن عام $year';
    if (reportType == 'شهري') return 'تقرير شهري عن شهر $month / $year';
    final startDay = ((week - 1) * 7) + 1;
    final endDay = (startDay + 4).clamp(1, 31);
    return 'تقرير أسبوعي - الأسبوع $week - شهر $month / $year - الفترة من $year/$month/$startDay إلى $year/$month/$endDay';
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> filterDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.where((doc) {
      final item = doc.data();

      if (item['childId'] != childId) return false;
      if (item['year'] != year) return false;

      if (reportType == 'شهري' || reportType == 'أسبوعي') {
        if (item['month'] != month) return false;
      }

      if (reportType == 'أسبوعي') {
        if (item['week'] != week) return false;
      }

      if (sessionFilter != 'كل أنواع الجلسات' && item['sessionType'] != sessionFilter) return false;

      return true;
    }).toList();
  }

  Map<String, Map<String, List<Map<String, dynamic>>>> groupItems(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final grouped = <String, Map<String, List<Map<String, dynamic>>>>{};

    for (final doc in docs) {
      final item = doc.data();
      final session = (item['sessionType'] ?? 'غير محدد').toString();
      final specialist = (item['goalAuthor'] ?? 'أخصائي غير محدد').toString();

      grouped.putIfAbsent(session, () => {});
      grouped[session]!.putIfAbsent(specialist, () => []);
      grouped[session]![specialist]!.add(item);
    }

    final sortedSessions = grouped.keys.toList()..sort();
    return {
      for (final session in sortedSessions)
        session: {
          for (final specialist in (grouped[session]!.keys.toList()..sort()))
            specialist: grouped[session]![specialist]!,
        }
    };
  }

  int averageAchievement(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    if (docs.isEmpty) return 0;
    final values = docs.map((d) => d.data()['achievementPercent']).whereType<num>().toList();
    if (values.isEmpty) return 0;
    return (values.reduce((a, b) => a + b) / values.length).round();
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'معاينة التقرير',
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('weeklyPlans').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text('خطأ في قراءة بيانات التقرير: ${snapshot.error}');
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          final allDocs = snapshot.data?.docs ?? [];
          final docs = filterDocs(allDocs);
          final grouped = groupItems(docs);
          final avg = averageAchievement(docs);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE7FFF8), Color(0xFFFFF4D6), Color(0xFFF4ECFF)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFBDE8FF)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('مركز ICAN للتربية الخاصة والخدمات النفسية', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('اسم الطفل: $childName'),
                    Text(periodText),
                    Text('متوسط نسبة الإنجاز: $avg%'),
                    const SizedBox(height: 12),
                    const Text(
                      'بداية مشجعة: نثمن مجهود الطفل والأسرة والفريق، وكل تقدم مهما كان بسيطًا هو خطوة مهمة نحو الاستقلال والنمو.',
                      style: TextStyle(height: 1.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (docs.isEmpty)
                const Text('لا توجد أهداف مسجلة لهذه الفترة.')
              else
                ...grouped.entries.map((sessionEntry) {
                  final sessionType = sessionEntry.key;
                  final specialists = sessionEntry.value;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FBFF),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFBDE8FF)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('نوع الجلسة: $sessionType', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        ...specialists.entries.map((specialistEntry) {
                          final specialist = specialistEntry.key;
                          final items = specialistEntry.value;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF8E1),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text('الأخصائي: $specialist', style: const TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(height: 8),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  headingRowColor: WidgetStateProperty.all(const Color(0xFFBDF2E9)),
                                  columns: const [
                                    DataColumn(label: Text('الهدف')),
                                    DataColumn(label: Text('المساعدة')),
                                    DataColumn(label: Text('التعزيز')),
                                    DataColumn(label: Text('الإنجاز')),
                                    DataColumn(label: Text('مراجعة السينيور')),
                                  ],
                                  rows: items.map((item) {
                                    final achievement = item['achievementPercent'] ?? 0;
                                    return DataRow(
                                      color: WidgetStateProperty.all(
                                        achievement is num && achievement >= 70 ? const Color(0xFFE7FBEA) : Colors.white,
                                      ),
                                      cells: [
                                        DataCell(SizedBox(width: 220, child: Text(item['goalText'] ?? '-'))),
                                        DataCell(Text(item['promptLevel'] ?? '-')),
                                        DataCell(Text(item['reinforcementSchedule'] ?? '-')),
                                        DataCell(Text('$achievement%')),
                                        DataCell(Text(item['seniorApproved'] == true ? (item['seniorName'] ?? 'تمت') : 'لم تتم')),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                          );
                        }),
                      ],
                    ),
                  );
                }),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7FBEA),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Text(
                  'ختامًا: نشكر ولي الأمر على التعاون، ونوصي بالاستمرارية في التدريب المنزلي والمتابعة المنتظمة لدعم التقدم بشكل أفضل.',
                  style: TextStyle(height: 1.5, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      await exportReportPdf(
                        childName: childName,
                        periodText: periodText,
                        averagePercent: avg,
                        docs: docs,
                      );
                    },
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('تصدير PDF'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('المشاركة عبر واتساب سيتم ربطها بعد تفعيل PDF')),
                      );
                    },
                    icon: const Icon(Icons.share),
                    label: const Text('مشاركة'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}


/* ===================== تقرير السينيورز ===================== */

class SeniorReportSection extends StatefulWidget {
  final String? preSelectedChildId;
  final String preSelectedChildName;

  const SeniorReportSection({
    super.key,
    this.preSelectedChildId,
    this.preSelectedChildName = '',
  });

  @override
  State<SeniorReportSection> createState() => _SeniorReportSectionState();
}

class _SeniorReportSectionState extends State<SeniorReportSection> {
  String? selectedChildId;
  String selectedChildName = '';
  String srReportType = 'أسبوعي';
  int srYear = DateTime.now().year;
  int srMonth = DateTime.now().month;
  int srWeek = (() { final w = ((DateTime.now().day - 1) ~/ 7) + 1; return w > 5 ? 5 : w; })();
  String srSessionFilter = 'كل أنواع الجلسات';
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    selectedChildId = widget.preSelectedChildId;
    selectedChildName = widget.preSelectedChildName;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _expanded,
          onExpansionChanged: (v) => setState(() => _expanded = v),
          leading: const Icon(Icons.verified_user_rounded, color: Color(0xFF00A6A6)),
          title: const Text('📊 تقرير السينيورز ⭐', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          subtitle: const Text('اضغط لعرض وتصدير تقارير التقييم الإشرافي', style: TextStyle(fontSize: 12, color: Colors.black54)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const Divider(),
            const SizedBox(height: 8),
            // اختيار الطفل
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('children').snapshots(),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];
                return DropdownButtonFormField<String>(
                  value: selectedChildId,
                  decoration: inputDecoration('اختر الطفل'),
                  items: docs.map((doc) {
                    final child = doc.data();
                    return DropdownMenuItem<String>(
                      value: doc.id,
                      child: Text(child['name'] ?? 'بدون اسم'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    final sel = docs.where((d) => d.id == value).toList();
                    setState(() {
                      selectedChildId = value;
                      selectedChildName = sel.isEmpty ? '' : (sel.first.data()['name'] ?? '');
                    });
                  },
                );
              },
            ),
            const SizedBox(height: 8),
            // نوع التقرير
            DropdownButtonFormField<String>(
              value: srReportType,
              decoration: inputDecoration('نوع التقرير'),
              items: ['أسبوعي', 'شهري']
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => srReportType = v ?? srReportType),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: srYear,
                    decoration: inputDecoration('السنة'),
                    items: List.generate(5, (i) => DateTime.now().year - 1 + i)
                        .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                        .toList(),
                    onChanged: (v) => setState(() => srYear = v ?? srYear),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: srMonth,
                    decoration: inputDecoration('الشهر'),
                    items: List.generate(12, (i) => i + 1)
                        .map((m) => DropdownMenuItem(value: m, child: Text('$m')))
                        .toList(),
                    onChanged: (v) => setState(() => srMonth = v ?? srMonth),
                  ),
                ),
                if (srReportType == 'أسبوعي') ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: srWeek,
                      decoration: inputDecoration('الأسبوع'),
                      items: [1, 2, 3, 4, 5]
                          .map((w) => DropdownMenuItem(value: w, child: Text('الأسبوع $w')))
                          .toList(),
                      onChanged: (v) => setState(() => srWeek = v ?? srWeek),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: srSessionFilter,
              decoration: inputDecoration('نوع الجلسة'),
              items: ['كل أنواع الجلسات', ...sessionTypes]
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() => srSessionFilter = v ?? srSessionFilter),
            ),
            const SizedBox(height: 12),
            if (selectedChildId != null)
              SeniorReportPreview(
                childId: selectedChildId!,
                childName: selectedChildName,
                reportType: srReportType,
                year: srYear,
                month: srMonth,
                week: srWeek,
                sessionFilter: srSessionFilter,
              )
            else
              const Text('اختر طفلًا لعرض تقرير السينيورز.', style: TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

class SeniorReportPreview extends StatelessWidget {
  final String childId;
  final String childName;
  final String reportType;
  final int year;
  final int month;
  final int week;
  final String sessionFilter;

  const SeniorReportPreview({
    super.key,
    required this.childId,
    required this.childName,
    required this.reportType,
    required this.year,
    required this.month,
    required this.week,
    required this.sessionFilter,
  });

  String get periodText {
    if (reportType == 'شهري') return 'شهر $month / $year';
    return 'الأسبوع $week - شهر $month / $year';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('seniorReports').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Text('خطأ: ${snapshot.error}');
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

        var docs = (snapshot.data?.docs ?? []).where((doc) {
          final d = doc.data();
          if (d['childId'] != childId) return false;
          if ((d['year'] as num? ?? 0).toInt() != year) return false;
          if ((d['month'] as num? ?? 0).toInt() != month) return false;
          if (reportType == 'أسبوعي' && (d['week'] as num? ?? 0).toInt() != week) return false;
          if (sessionFilter != 'كل أنواع الجلسات' && d['sessionType'] != sessionFilter) return false;
          return true;
        }).toList();

        if (docs.isEmpty) {
          return const Text('لا توجد تقييمات لهذا الاختيار.', style: TextStyle(color: Colors.black54));
        }

        final totalGoals = docs.fold<int>(0, (s, d) => s + ((d.data()['goalsCount'] as num? ?? 0).toInt()));
        final totalVideos = docs.fold<int>(0, (s, d) => s + ((d.data()['videosCount'] as num? ?? 0).toInt()));
        final ratings = docs.map((d) => (d.data()['rating'] as num? ?? 0).toDouble()).where((r) => r > 0).toList();
        final avgRating = ratings.isEmpty ? 0.0 : ratings.reduce((a, b) => a + b) / ratings.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ملخص
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFE7FFF8), Color(0xFFFFF4D6)], begin: Alignment.topRight, end: Alignment.bottomLeft),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFBDE8FF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('تقرير السينيورز - $childName', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  Text(periodText, style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _SrStat(label: 'عدد التقييمات', value: '${docs.length}'),
                      _SrStat(label: 'متوسط النجوم', value: '${avgRating.toStringAsFixed(1)} ⭐'),
                      _SrStat(label: 'إجمالي الأهداف', value: '$totalGoals'),
                      _SrStat(label: 'إجمالي الفيديوهات', value: '$totalVideos'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // تفاصيل كل تقييم
            ...docs.map((doc) {
              final r = doc.data();
              final stars = (r['rating'] as num? ?? 0).toInt();
              return Card(
                color: const Color(0xFFF8FBFF),
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person_rounded, color: Color(0xFF00A6A6), size: 20),
                          const SizedBox(width: 6),
                          Expanded(child: Text(r['specialistName'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold))),
                          ...List.generate(5, (i) => Icon(
                            i < stars ? Icons.star_rounded : Icons.star_border_rounded,
                            color: Colors.amber, size: 16,
                          )),
                          Text(' $stars/5', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('الجلسة: ${r['sessionType'] ?? '-'} | أهداف: ${r['goalsCount'] ?? 0} | فيديوهات: ${r['videosCount'] ?? 0}',
                          style: const TextStyle(fontSize: 12)),
                      Text('دافعية: ${r['motivationLevel'] ?? '-'} | سلوك: ${r['behaviorLevel'] ?? '-'} | تحقق الأهداف: ${r['goalsAchievement'] ?? '-'} | ولي الأمر: ${r['parentInteraction'] ?? '-'}',
                          style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      if ((r['generalNotes'] ?? '').toString().isNotEmpty)
                        Text('التطورات: ${r['generalNotes']}', style: const TextStyle(fontSize: 12)),
                      if ((r['technicalGuidance'] ?? '').toString().isNotEmpty)
                        Text('التوجيهات: ${r['technicalGuidance']}', style: const TextStyle(fontSize: 12)),
                      if ((r['technicalSuggestions'] ?? '').toString().isNotEmpty)
                        Text('المقترحات: ${r['technicalSuggestions']}', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () async {
                await _exportSeniorReportPdf(
                  childName: childName,
                  periodText: periodText,
                  docs: docs.map((d) => d.data()).toList(),
                  avgRating: avgRating,
                  totalGoals: totalGoals,
                  totalVideos: totalVideos,
                );
              },
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('📊 تصدير تقرير السينيورز PDF'),
            ),
          ],
        );
      },
    );
  }
}

class _SrStat extends StatelessWidget {
  final String label;
  final String value;
  const _SrStat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
      ],
    );
  }
}

Future<void> _exportSeniorReportPdf({
  required String childName,
  required String periodText,
  required List<Map<String, dynamic>> docs,
  required double avgRating,
  required int totalGoals,
  required int totalVideos,
}) async {
  final pdf = pw.Document();
  final regularFont = await PdfGoogleFonts.notoNaskhArabicRegular();
  final boldFont = await PdfGoogleFonts.notoNaskhArabicBold();

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
      build: (ctx) => [
        pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#E7FFF8'),
            borderRadius: pw.BorderRadius.circular(12),
            border: pw.Border.all(color: PdfColor.fromHex('#00A6A6')),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('مركز ICAN - تقرير السينيورز', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Text('الطفل: $childName | $periodText'),
              pw.Text('عدد التقييمات: ${docs.length} | متوسط النجوم: ${avgRating.toStringAsFixed(1)}/5 | إجمالي الأهداف: $totalGoals | إجمالي الفيديوهات: $totalVideos'),
            ],
          ),
        ),
        pw.SizedBox(height: 14),
        ...docs.map((r) {
          final stars = (r['rating'] as num? ?? 0).toInt();
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 12),
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: PdfColor.fromHex('#BDE8FF')),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('الأخصائي: ${r['specialistName'] ?? '-'} | الجلسة: ${r['sessionType'] ?? '-'} | التقييم: $stars/5',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                pw.Text('أهداف: ${r['goalsCount'] ?? 0} | فيديوهات: ${r['videosCount'] ?? 0}', style: const pw.TextStyle(fontSize: 11)),
                pw.Text('دافعية: ${r['motivationLevel'] ?? '-'} | سلوك: ${r['behaviorLevel'] ?? '-'} | تحقق الأهداف: ${r['goalsAchievement'] ?? '-'} | ولي الأمر: ${r['parentInteraction'] ?? '-'}',
                    style: const pw.TextStyle(fontSize: 11)),
                if ((r['generalNotes'] ?? '').toString().isNotEmpty)
                  pw.Text('التطورات: ${r['generalNotes']}', style: const pw.TextStyle(fontSize: 11)),
                if ((r['technicalGuidance'] ?? '').toString().isNotEmpty)
                  pw.Text('التوجيهات: ${r['technicalGuidance']}', style: const pw.TextStyle(fontSize: 11)),
                if ((r['technicalSuggestions'] ?? '').toString().isNotEmpty)
                  pw.Text('المقترحات: ${r['technicalSuggestions']}', style: const pw.TextStyle(fontSize: 11)),
              ],
            ),
          );
        }),
        pw.SizedBox(height: 14),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(color: PdfColor.fromHex('#FFF8E1'), borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('ملخص التقرير:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text('متوسط تقييم الأخصائيين: ${avgRating.toStringAsFixed(1)} / 5'),
              pw.Text('إجمالي الأهداف: $totalGoals'),
              pw.Text('إجمالي الفيديوهات: $totalVideos'),
            ],
          ),
        ),
      ],
    ),
  );

  await Printing.layoutPdf(
    onLayout: (PdfPageFormat format) async => pdf.save(),
    name: 'SeniorReport_$childName.pdf',
  );
}


/* ===================== إدارة العاملين والصلاحيات ===================== */



Future<UserCredential> createUserWithoutLoggingOutManager({
  required String email,
  required String password,
}) async {
  final secondaryAppName = 'userCreationApp-${DateTime.now().millisecondsSinceEpoch}';

  final secondaryApp = await Firebase.initializeApp(
    name: secondaryAppName,
    options: DefaultFirebaseOptions.currentPlatform,
  );

  try {
    final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
    final credential = await secondaryAuth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await secondaryAuth.signOut();
    return credential;
  } finally {
    await secondaryApp.delete();
  }
}

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final jobTitleController = TextEditingController();
  final nationalIdController = TextEditingController();
  final qualificationController = TextEditingController();
  final phoneController = TextEditingController();
  final salaryController = TextEditingController();
  final workStartController = TextEditingController(text: '09:00');
  final workEndController = TextEditingController(text: '16:00');
  final passwordController = TextEditingController(text: '123456');
  final relationController = TextEditingController(text: 'ولي أمر');

  DateTime? startDate;
  String role = 'specialist';
  String? linkedChildId;
  String? linkedChildName;
  bool saving = false;

  bool get isParent => role == 'parent';
  bool get isStaff => role == 'manager' || role == 'senior' || role == 'specialist';

  String roleArabic(String value) {
    switch (value) {
      case 'manager':
        return 'مدير';
      case 'senior':
        return 'سينيور';
      case 'specialist':
        return 'أخصائي';
      case 'parent':
        return 'ولي أمر';
      default:
        return value;
    }
  }

  Future<void> pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'اختيار تاريخ بداية العمل',
    );

    if (picked != null) {
      setState(() => startDate = picked);
    }
  }

  Future<void> addUser() async {
    final name = nameController.text.trim();
    final email = emailController.text.trim();

    if (name.isEmpty || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب الاسم والإيميل أولًا')),
      );
      return;
    }

    if (isParent && linkedChildId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختَر الطفل المرتبط بولي الأمر')),
      );
      return;
    }

    setState(() => saving = true);

    try {
      final password = passwordController.text.trim();

      if (password.length < 6) {
        throw Exception('كلمة المرور يجب ألا تقل عن 6 أحرف');
      }

      final authCredential = await createUserWithoutLoggingOutManager(
        email: email.toLowerCase(),
        password: password,
      ).timeout(const Duration(seconds: 20));

      final data = <String, dynamic>{
        'uid': authCredential.user?.uid,
        'name': name,
        'email': email.toLowerCase(),
        'role': role,
        'roleArabic': roleArabic(role),
        'phone': phoneController.text.trim(),
        'defaultPasswordForSetup': password,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': FirebaseAuth.instance.currentUser?.email ?? 'unknown',
      };

      if (isParent) {
        data.addAll({
          'relation': relationController.text.trim(),
          'linkedChildId': linkedChildId,
          'linkedChildName': linkedChildName,
        });
      } else {
        data.addAll({
          'jobTitle': jobTitleController.text.trim(),
          'nationalId': nationalIdController.text.trim(),
          'qualification': qualificationController.text.trim(),
          'baseSalary': salaryController.text.trim(),
          'workStartTime': workStartController.text.trim(),
          'workEndTime': workEndController.text.trim(),
          'startDate': startDate == null ? null : Timestamp.fromDate(startDate!),
        });
      }

      final userDoc = await FirebaseFirestore.instance.collection('users').add(data).timeout(const Duration(seconds: 12));

      if (isParent && linkedChildId != null) {
        await FirebaseFirestore.instance.collection('children').doc(linkedChildId).set({
          'parentId': userDoc.id,
          'parentName': name,
          'parentEmail': email.toLowerCase(),
          'parentPhone': phoneController.text.trim(),
          'parentLinkedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 12));
      }

      nameController.clear();
      emailController.clear();
      jobTitleController.clear();
      nationalIdController.clear();
      qualificationController.clear();
      phoneController.clear();
      salaryController.clear();
      relationController.text = 'ولي أمر';
      passwordController.text = '123456';

      setState(() {
        startDate = null;
        linkedChildId = null;
        linkedChildName = null;
        _formExpanded = false; // إغلاق الفورم بعد الحفظ
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ المستخدم في Firestore ✓')),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String msg = 'فشل إنشاء حساب الدخول';
      if (e.code == 'email-already-in-use') msg = 'هذا الإيميل مستخدم بالفعل';
      if (e.code == 'invalid-email') msg = 'صيغة الإيميل غير صحيحة';
      if (e.code == 'weak-password') msg = 'كلمة المرور ضعيفة';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل حفظ المستخدم: $e')),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  bool _formExpanded = false;

  @override
  Widget build(BuildContext context) {
    final startDateText = startDate == null
        ? 'اختيار تاريخ بداية العمل'
        : '${startDate!.year}-${startDate!.month.toString().padLeft(2, '0')}-${startDate!.day.toString().padLeft(2, '0')}';

    return PageWrap(
      children: [
        const HeroBox(
          title: '👥 إدارة العاملين والصلاحيات',
          subtitle: 'تتغير الحقول تلقائيًا حسب الدور: موظف 👨‍🏫 أو ولي أمر 👪.',
        ),
        const SizedBox(height: 12),
        // نموذج الإضافة داخل ExpansionTile
        Card(
          margin: const EdgeInsets.only(bottom: 14),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: _formExpanded,
              onExpansionChanged: (v) => setState(() => _formExpanded = v),
              leading: const Icon(Icons.person_add_rounded, color: Color(0xFF00A6A6)),
              title: const Text(
                '➕ إضافة عامل 👨‍🏫 أو ولي أمر جديد 👪',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('اضغط لفتح نموذج الإضافة', style: TextStyle(fontSize: 12, color: Colors.black54)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                const Divider(),
                const SizedBox(height: 8),
                TextField(controller: nameController, decoration: inputDecoration(isParent ? 'اسم ولي الأمر' : 'الاسم الكامل')),
                const SizedBox(height: 8),
                TextField(controller: emailController, keyboardType: TextInputType.emailAddress, decoration: inputDecoration('الإيميل / اسم المستخدم')),
                const SizedBox(height: 8),
                TextField(controller: passwordController, decoration: inputDecoration('كلمة المرور المبدئية')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: inputDecoration('الصلاحية / الدور'),
                  items: const [
                    DropdownMenuItem(value: 'manager', child: Text('مدير')),
                    DropdownMenuItem(value: 'senior', child: Text('سينيور')),
                    DropdownMenuItem(value: 'specialist', child: Text('أخصائي')),
                    DropdownMenuItem(value: 'parent', child: Text('ولي أمر')),
                  ],
                  onChanged: (v) {
                    setState(() {
                      role = v ?? role;
                      linkedChildId = null;
                      linkedChildName = null;
                    });
                  },
                ),
                const SizedBox(height: 8),
                TextField(controller: phoneController, decoration: inputDecoration('رقم الهاتف')),
                const SizedBox(height: 8),

                if (isParent) ...[
                  TextField(controller: relationController, decoration: inputDecoration('صلة القرابة')),
                  const SizedBox(height: 8),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance.collection('children').snapshots(),
                    builder: (context, snapshot) {
                      final docs = snapshot.data?.docs ?? [];
                      return DropdownButtonFormField<String>(
                        value: linkedChildId,
                        decoration: inputDecoration('ربط ولي الأمر بالطفل'),
                        items: docs.map((doc) {
                          final child = doc.data();
                          return DropdownMenuItem<String>(
                            value: doc.id,
                            child: Text(child['name'] ?? 'بدون اسم'),
                          );
                        }).toList(),
                        onChanged: (value) {
                          final selected = docs.where((d) => d.id == value).toList();
                          setState(() {
                            linkedChildId = value;
                            linkedChildName = selected.isEmpty ? null : (selected.first.data()['name'] ?? 'بدون اسم');
                          });
                        },
                      );
                    },
                  ),
                ],

                if (isStaff) ...[
                  TextField(controller: jobTitleController, decoration: inputDecoration('المسمى الوظيفي')),
                  const SizedBox(height: 8),
                  TextField(controller: nationalIdController, decoration: inputDecoration('الرقم القومي')),
                  const SizedBox(height: 8),
                  TextField(controller: qualificationController, decoration: inputDecoration('المؤهل')),
                  const SizedBox(height: 8),
                  TextField(controller: salaryController, decoration: inputDecoration('الراتب الأساسي')),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: workStartController, decoration: inputDecoration('بداية العمل 12 ساعة'))),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: workEndController, decoration: inputDecoration('نهاية العمل 12 ساعة'))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: pickStartDate,
                    icon: const Icon(Icons.date_range_rounded),
                    label: Text(startDateText),
                  ),
                ],

                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: saving ? null : addUser,
                  icon: saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.person_add_rounded),
                  label: Text(saving ? '⏳ جار إنشاء الحساب...' : isParent ? '👪 إنشاء حساب ولي الأمر' : '👤 إنشاء حساب المستخدم'),
                ),
                const SizedBox(height: 8),
                Text(
                  isParent
                      ? 'ولي الأمر يتم ربطه بطفل محدد، ولا تظهر له بيانات الراتب أو مواعيد العمل.'
                      : 'بيانات العامل تشمل الوظيفة، المؤهل، مواعيد العمل والراتب. عند الحفظ يتم إنشاء حساب دخول فعلي في Firebase Auth وحفظ الصلاحية في Firestore.',
                  style: const TextStyle(color: Colors.black54, height: 1.5),
                ),
              ],
            ),
          ),
        ),
        const UsersListCard(),
      ],
    );
  }
}

/// يعرض متوسط تقييم النجوم لأخصائي معين من seniorReports
class SpecialistRatingBadge extends StatelessWidget {
  final String specialistEmail;
  const SpecialistRatingBadge({super.key, required this.specialistEmail});

  @override
  Widget build(BuildContext context) {
    if (specialistEmail.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('seniorReports')
          .where('specialistEmail', isEqualTo: specialistEmail)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5));
        }
        final docs = snapshot.data?.docs ?? [];
        final ratings = docs
            .map((d) => (d.data()['rating'] as num? ?? 0).toDouble())
            .where((r) => r > 0)
            .toList();
        if (ratings.isEmpty) {
          return const Text('لا يوجد تقييم بعد', style: TextStyle(fontSize: 11, color: Colors.black45));
        }
        final avg = ratings.reduce((a, b) => a + b) / ratings.length;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...List.generate(5, (i) {
              if (i < avg.floor()) return const Icon(Icons.star_rounded, color: Colors.amber, size: 16);
              if (i < avg.ceil() && avg - avg.floor() >= 0.5) return const Icon(Icons.star_half_rounded, color: Colors.amber, size: 16);
              return const Icon(Icons.star_border_rounded, color: Colors.amber, size: 16);
            }),
            const SizedBox(width: 4),
            Text('${avg.toStringAsFixed(1)} / 5', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber)),
            Text(' (${ratings.length})', style: const TextStyle(fontSize: 11, color: Colors.black45)),
          ],
        );
      },
    );
  }
}

class UsersListCard extends StatelessWidget {
  const UsersListCard({super.key});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '👥 قائمة العاملين / المستخدمين',
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text('خطأ في قراءة المستخدمين: ${snapshot.error}');
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) return const Text('لا يوجد مستخدمون مضافون حتى الآن.');

          return Column(
            children: docs.map((doc) {
              final user = doc.data();
              final name = user['name'] ?? 'بدون اسم';
              final roleArabic = user['roleArabic'] ?? user['role'] ?? '-';
              final jobTitle = user['jobTitle'] ?? '-';
              final email = (user['email'] ?? '-').toString();
              final salary = user['baseSalary'] ?? '-';
              final role = (user['role'] ?? '').toString();
              final isSpecialist = role == 'specialist' || role == 'senior';

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(child: Icon(isSpecialist ? Icons.person_rounded : (role == 'parent' ? Icons.family_restroom_rounded : Icons.badge_rounded))),
                      title: Text('$name ${isSpecialist ? '👨‍🏫' : (role == 'parent' ? '👪' : (role == 'manager' ? '🏢' : ''))}'),
                      subtitle: Text(
                        role == 'parent'
                            ? 'الدور: $roleArabic\nالإيميل: $email\nالطفل المرتبط: ${user['linkedChildName'] ?? '-'}\nالهاتف: ${user['phone'] ?? '-'}\nUID: ${user['uid'] ?? '-'}'
                            : 'الدور: $roleArabic\nالوظيفة: $jobTitle\nالإيميل: $email\nالراتب الأساسي: $salary\nUID: ${user['uid'] ?? '-'}',
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) async {
                          if (value == 'edit') {
                            showDialog(context: context, builder: (_) => EditUserDialog(userId: doc.id, user: user));
                          }
                          if (value == 'perf') {
                            showDialog(context: context, builder: (_) => SpecialistPerformanceDialog(specialistEmail: email, specialistName: name));
                          }
                          if (value == 'delete') {
                            final ok = await confirmDialog(context, 'نقل للسلة', 'هل تريد نقل هذا المستخدم إلى السلة؟');
                            if (!ok) return;
                            await moveDocumentToTrash(collectionName: 'users', docId: doc.id, data: user, itemTitle: 'مستخدم: $name');
                            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نقل المستخدم إلى السلة')));
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'edit', child: Text('✏️ تعديل')),
                          if (isSpecialist) const PopupMenuItem(value: 'perf', child: Text('⭐ تقرير الأداء')),
                          const PopupMenuItem(value: 'delete', child: Text('🗑️ نقل للسلة')),
                        ],
                      ),
                    ),
                    // ⭐ عرض متوسط التقييم للأخصائيين
                    if (isSpecialist)
                      Padding(
                        padding: const EdgeInsets.only(right: 72, left: 16, bottom: 10),
                        child: Row(
                          children: [
                            const Text('تقييم الأداء: ', style: TextStyle(fontSize: 12, color: Colors.black54)),
                            SpecialistRatingBadge(specialistEmail: email),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}




class EditUserDialog extends StatefulWidget {
  final String userId;
  final Map<String, dynamic> user;

  const EditUserDialog({super.key, required this.userId, required this.user});

  @override
  State<EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<EditUserDialog> {
  late final TextEditingController nameController;
  late final TextEditingController phoneController;
  late final TextEditingController jobTitleController;
  late final TextEditingController salaryController;
  late final TextEditingController workStartController;
  late final TextEditingController workEndController;
  String? linkedChildId;
  String? linkedChildName;
  bool saving = false;

  bool get isParent => widget.user['role'] == 'parent';

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: (widget.user['name'] ?? '').toString());
    phoneController = TextEditingController(text: (widget.user['phone'] ?? '').toString());
    jobTitleController = TextEditingController(text: (widget.user['jobTitle'] ?? '').toString());
    salaryController = TextEditingController(text: (widget.user['baseSalary'] ?? '').toString());
    workStartController = TextEditingController(text: (widget.user['workStartTime'] ?? '09:00').toString());
    workEndController = TextEditingController(text: (widget.user['workEndTime'] ?? '16:00').toString());
    linkedChildId = widget.user['linkedChildId']?.toString();
    linkedChildName = widget.user['linkedChildName']?.toString();
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      final data = <String, dynamic>{
        'name': nameController.text.trim(),
        'phone': phoneController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': currentUserDisplayName(),
      };
      if (isParent) {
        data['linkedChildId'] = linkedChildId;
        data['linkedChildName'] = linkedChildName;
      } else {
        data['jobTitle'] = jobTitleController.text.trim();
        data['baseSalary'] = salaryController.text.trim();
        data['workStartTime'] = workStartController.text.trim();
        data['workEndTime'] = workEndController.text.trim();
      }
      await FirebaseFirestore.instance.collection('users').doc(widget.userId).update(data);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تعديل المستخدم')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل التعديل: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تعديل المستخدم'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: inputDecoration('الاسم')),
            const SizedBox(height: 8),
            TextField(controller: phoneController, decoration: inputDecoration('رقم الهاتف')),
            const SizedBox(height: 8),
            if (isParent)
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('children').snapshots(),
                builder: (context, snapshot) {
                  final docs = snapshot.data?.docs ?? [];
                  return DropdownButtonFormField<String>(
                    value: linkedChildId,
                    decoration: inputDecoration('الطفل المرتبط'),
                    items: docs.map((doc) => DropdownMenuItem<String>(
                      value: doc.id,
                      child: Text(doc.data()['name'] ?? 'بدون اسم'),
                    )).toList(),
                    onChanged: (value) {
                      final selected = docs.where((d) => d.id == value).toList();
                      setState(() {
                        linkedChildId = value;
                        linkedChildName = selected.isEmpty ? null : (selected.first.data()['name'] ?? 'بدون اسم');
                      });
                    },
                  );
                },
              )
            else ...[
              TextField(controller: jobTitleController, decoration: inputDecoration('المسمى الوظيفي')),
              const SizedBox(height: 8),
              TextField(controller: salaryController, decoration: inputDecoration('الراتب الأساسي')),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: TextField(controller: workStartController, decoration: inputDecoration('بداية العمل'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: workEndController, decoration: inputDecoration('نهاية العمل'))),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: saving ? null : save, child: Text(saving ? 'جار الحفظ...' : 'حفظ')),
      ],
    );
  }
}

/* ===================== بوابة ولي الأمر الحقيقية ===================== */

class ParentHomePage extends StatelessWidget {
  const ParentHomePage({super.key});

  int currentWeek() {
    final w = ((DateTime.now().day - 1) ~/ 7) + 1;
    return w > 5 ? 5 : w;
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email?.toLowerCase().trim() ?? '';

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .snapshots(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (userSnapshot.hasError) {
          return PageWrap(
            children: [
              HeroBox(title: 'بوابة ولي الأمر', subtitle: 'حدث خطأ في قراءة بيانات ولي الأمر: ${userSnapshot.error}'),
            ],
          );
        }

        final userDocs = userSnapshot.data?.docs ?? [];

        if (userDocs.isEmpty) {
          return const PageWrap(
            children: [
              HeroBox(
                title: 'بوابة ولي الأمر',
                subtitle: 'لم يتم ربط هذا الحساب ببيانات ولي أمر داخل النظام بعد.',
              ),
            ],
          );
        }

        final userData = userDocs.first.data();
        final parentDocId = userDocs.first.id;

        // الأولوية: linkedChildId في وثيقة ولي الأمر (الربط القديم)
        // ثم البحث في الأطفال بحقل parentId
        final linkedChildId = userData['linkedChildId'];
        final linkedChildName = userData['linkedChildName'] ?? 'الطفل';

        if (linkedChildId != null && linkedChildId.toString().isNotEmpty) {
          // الربط القديم: عبر linkedChildId في users
          final now = DateTime.now();
          return PageWrap(
            children: [
              HeroBox(
                title: 'مرحبًا بولي الأمر',
                subtitle: 'متابعة خاصة للطفل: $linkedChildName — عرض فقط بدون تعديل أو حذف.',
              ),
              const SizedBox(height: 12),
              ParentChildInfoCard(childId: linkedChildId.toString()),
              _ParentGoalsExpansion(childId: linkedChildId.toString(), childName: linkedChildName.toString()),
              ParentWeeklyCard(
                childId: linkedChildId.toString(),
                childName: linkedChildName.toString(),
                year: now.year,
                month: now.month,
                week: currentWeek(),
              ),
              ReportPreviewCard(
                childId: linkedChildId.toString(),
                childName: linkedChildName.toString(),
                reportType: 'أسبوعي',
                year: now.year,
                month: now.month,
                week: currentWeek(),
                sessionFilter: 'كل أنواع الجلسات',
              ),
            ],
          );
        }

        // الربط الجديد: البحث في children بحقل parentId = parentDocId أو parentEmail = email
        // نستخدم استعلامين منفصلين ونجمعهما
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('children')
              .where('parentId', isEqualTo: parentDocId)
              .snapshots(),
          builder: (context, byIdSnap) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('children')
                  .where('parentEmail', isEqualTo: email)
                  .snapshots(),
              builder: (context, byEmailSnap) {
                if (byIdSnap.connectionState == ConnectionState.waiting ||
                    byEmailSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                // دمج النتيجتين بدون تكرار
                final seenIds = <String>{};
                final combined = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                for (final doc in [...(byIdSnap.data?.docs ?? []), ...(byEmailSnap.data?.docs ?? [])]) {
                  if (seenIds.add(doc.id)) combined.add(doc);
                }

                if (combined.isEmpty) {
                  return const PageWrap(
                    children: [
                      HeroBox(
                        title: 'بوابة ولي الأمر',
                        subtitle: 'هذا الحساب غير مربوط بطفل حتى الآن. من فضلك راجع الإدارة.',
                      ),
                    ],
                  );
                }

                final now = DateTime.now();
                final week = currentWeek();

                return PageWrap(
                  children: [
                    HeroBox(
                      title: 'مرحبًا بولي الأمر',
                      subtitle: 'متابعة خاصة — عدد الأطفال المرتبطين: ${combined.length}',
                    ),
                    ...combined.expand((childDoc) {
                      final childData = childDoc.data();
                      final cId = childDoc.id;
                      final cName = (childData['name'] ?? 'الطفل').toString();
                      return [
                        const SizedBox(height: 12),
                        ParentChildInfoCard(childId: cId),
                        _ParentGoalsExpansion(childId: cId, childName: cName),
                        ParentWeeklyCard(childId: cId, childName: cName, year: now.year, month: now.month, week: week),
                        ReportPreviewCard(
                          childId: cId,
                          childName: cName,
                          reportType: 'أسبوعي',
                          year: now.year,
                          month: now.month,
                          week: week,
                          sessionFilter: 'كل أنواع الجلسات',
                        ),
                        ReportPreviewCard(
                          childId: cId,
                          childName: cName,
                          reportType: 'شهري',
                          year: now.year,
                          month: now.month,
                          week: week,
                          sessionFilter: 'كل أنواع الجلسات',
                        ),
                      ];
                    }),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class ParentChildInfoCard extends StatelessWidget {
  final String childId;

  const ParentChildInfoCard({super.key, required this.childId});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'بيانات الطفل الأساسية',
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('children').doc(childId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text('خطأ: ${snapshot.error}');
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          final child = snapshot.data?.data();
          if (child == null) return const Text('لم يتم العثور على بيانات الطفل.');

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoLine(label: 'الاسم', value: child['name'] ?? '-'),
              InfoLine(label: 'العمر', value: child['ageText'] ?? '-'),
              InfoLine(label: 'البرنامج', value: child['program'] ?? '-'),
              InfoLine(label: 'التشخيص', value: child['diagnosis'] ?? '-'),
              InfoLine(label: 'ملاحظات', value: child['notes'] ?? '-'),
            ],
          );
        },
      ),
    );
  }
}

// ولي الأمر: الخطة الفردية مخفية داخل ExpansionTile
class _ParentGoalsExpansion extends StatelessWidget {
  final String childId;
  final String childName;
  const _ParentGoalsExpansion({required this.childId, required this.childName});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          leading: const Icon(Icons.assignment_rounded, color: Color(0xFF00A6A6)),
          title: Text('عرض الخطة الفردية - $childName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          subtitle: const Text('اضغط لعرض أهداف طفلك', style: TextStyle(fontSize: 12, color: Colors.black54)),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          children: [
            ParentGoalsCard(childId: childId, childName: childName),
          ],
        ),
      ),
    );
  }
}

class ParentGoalsCard extends StatelessWidget {
  final String childId;
  final String childName;

  const ParentGoalsCard({super.key, required this.childId, required this.childName});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'الأهداف والخطة الفردية',
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('goals')
            .where('childId', isEqualTo: childId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text('خطأ في قراءة الأهداف: ${snapshot.error}');
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) return const Text('لا توجد أهداف مسجلة حتى الآن.');

          return Column(
            children: docs.map((doc) {
              final goal = doc.data();
              final percent = goal['lastAchievementPercent'];
              final isHigh = percent is num && percent >= 70;

              return Card(
                color: isHigh ? const Color(0xFFE7FBEA) : Colors.white,
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.flag_rounded)),
                  title: Text(goal['text'] ?? '-'),
                  subtitle: Text(
                    'البرنامج: ${goal['program'] ?? '-'}\n'
                    'الحالة: ${goal['status'] ?? '-'}\nمرحلة الهدف: ${goalStageArabic(goal['goalStage'] ?? 'active')}\n'
                    'الأخصائي: ${goal['createdBySpecialist'] ?? '-'}'
                    '${percent == null ? '' : '\nآخر نسبة إنجاز: $percent%'}'
                    '${goal['lastPromptLevel'] == null ? '' : '\nالمساعدة: ${goal['lastPromptLevel']}'}'
                    '${goal['lastReinforcementSchedule'] == null ? '' : '\nالتعزيز: ${goal['lastReinforcementSchedule']}'}',
                  ),
                  isThreeLine: true,
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class ParentWeeklyCard extends StatelessWidget {
  final String childId;
  final String childName;
  final int year;
  final int month;
  final int week;

  const ParentWeeklyCard({
    super.key,
    required this.childId,
    required this.childName,
    required this.year,
    required this.month,
    required this.week,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'البرنامج الأسبوعي الحالي',
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('weeklyPlans')
            .where('childId', isEqualTo: childId)
            .where('year', isEqualTo: year)
            .where('month', isEqualTo: month)
            .where('week', isEqualTo: week)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text('خطأ في قراءة البرنامج: ${snapshot.error}');
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) return const Text('لا توجد أهداف منقولة للأسبوع الحالي حتى الآن.');

          final grouped = <String, List<Map<String, dynamic>>>{};
          for (final doc in docs) {
            final item = doc.data();
            final session = (item['sessionType'] ?? 'غير محدد').toString();
            grouped.putIfAbsent(session, () => []);
            grouped[session]!.add(item);
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: grouped.entries.map((entry) {
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FBFF),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFBDE8FF)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('نوع الجلسة: ${entry.key}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    ...entry.value.map((item) {
                      final achievement = item['achievementPercent'] ?? 0;
                      final isHigh = achievement is num && achievement >= 70;

                      return Card(
                        color: isHigh ? const Color(0xFFE7FBEA) : Colors.white,
                        child: ListTile(
                          title: Text(item['goalText'] ?? '-'),
                          subtitle: Text(
                            'الأخصائي: ${item['goalAuthor'] ?? '-'}\n'
                            'المساعدة: ${item['promptLevel'] ?? '-'} | التعزيز: ${item['reinforcementSchedule'] ?? '-'} | الإنجاز: $achievement%\n'
                            'مراجعة السينيور: ${item['seniorApproved'] == true ? (item['seniorName'] ?? 'تمت') : 'لم تتم بعد'}',
                          ),
                          isThreeLine: true,
                        ),
                      );
                    }),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

// ======== بحث ذكي في القوائم ========
class SearchableDropdown extends StatefulWidget {
  final String label;
  final String? value;
  final List<Map<String, String>> items; // [{'id': ..., 'label': ...}]
  final ValueChanged<String?> onChanged;
  final String hint;

  const SearchableDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint = 'اكتب للبحث...',
  });

  @override
  State<SearchableDropdown> createState() => _SearchableDropdownState();
}

class _SearchableDropdownState extends State<SearchableDropdown> {
  late TextEditingController _controller;
  List<Map<String, String>> _filtered = [];
  bool _open = false;
  final FocusNode _focusNode = FocusNode();
  bool _selecting = false; // منع الإغلاق أثناء الاختيار

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.items.where((e) => e['id'] == widget.value).map((e) => e['label'] ?? '').firstOrNull ?? '',
    );
    _filtered = List.from(widget.items);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && !_selecting) {
        // تأخير بسيط لإتاحة معالجة onTap قبل الإغلاق
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && !_selecting) setState(() => _open = false);
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant SearchableDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      final match = widget.items.where((e) => e['id'] == widget.value).toList();
      final newText = match.isEmpty ? '' : (match.first['label'] ?? '');
      if (_controller.text != newText) _controller.text = newText;
    }
    if (widget.items.length != oldWidget.items.length) {
      _filtered = List.from(widget.items);
    }
  }

  void _filter(String query) {
    setState(() {
      _filtered = query.isEmpty
          ? List.from(widget.items)
          : widget.items.where((e) => (e['label'] ?? '').toLowerCase().contains(query.toLowerCase())).toList();
      _open = true;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          decoration: inputDecoration(widget.label).copyWith(
            hintText: widget.hint,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_controller.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _controller.clear();
                        _filtered = List.from(widget.items);
                        _open = true;
                      });
                      widget.onChanged(null);
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.clear_rounded, size: 18),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.search_rounded),
                ),
              ],
            ),
          ),
          onChanged: _filter,
          onTap: () {
            setState(() {
              _filtered = List.from(widget.items);
              _open = true;
            });
          },
        ),
        if (_open && _filtered.isNotEmpty)
          Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 240),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _filtered.length,
                itemBuilder: (context, index) {
                  final item = _filtered[index];
                  return InkWell(
                    onTap: () {
                      _selecting = true;
                      final selectedId = item['id'] ?? '';
                      final selectedLabel = item['label'] ?? '';
                      setState(() {
                        _controller.text = selectedLabel;
                        _open = false;
                      });
                      widget.onChanged(selectedId.isNotEmpty ? selectedId : null);
                      _focusNode.unfocus();
                      Future.delayed(const Duration(milliseconds: 300), () {
                        _selecting = false;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Text(item['label'] ?? '', style: const TextStyle(fontSize: 14)),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
// ======================================

class InfoLine extends StatelessWidget {
  final String label;
  final String value;

  const InfoLine({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 90, child: Text(label, style: const TextStyle(color: Colors.black54))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}



/* ===================== الحضور والانصراف ===================== */

const defaultWorkStartHour = 9;
const defaultWorkStartMinute = 0;

const absenceTypes = [
  'لا يوجد غياب',
  'أجازة رسمية مدفوعة',
  'أجازة بإذن مدفوعة',
  'أجازة بإذن مخصومة',
  'غياب بخصم يوم',
  'غياب بخصم يوم ونصف',
  'غياب بخصم يومين',
];

String formatDateKey(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String formatMonthKey(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}';
}

String formatTimeOnly(DateTime time) {
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

String formatTime12Arabic(DateTime time) {
  final suffix = time.hour >= 12 ? 'مساءً' : 'صباحًا';
  final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
  return '${hour12.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} $suffix';
}

double parseMoney(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().replaceAll(',', '').trim()) ?? 0;
}

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

bool isWeekendEgypt(DateTime date) => date.weekday == DateTime.friday || date.weekday == DateTime.saturday;

int workingDaysInMonth(int year, int month) {
  final totalDays = daysInMonth(year, month);
  int count = 0;
  for (int day = 1; day <= totalDays; day++) {
    if (!isWeekendEgypt(DateTime(year, month, day))) count++;
  }
  return count;
}

List<int>? parseTimePartsFlexible(String raw) {
  var value = raw.trim();
  if (value.isEmpty) return null;

  final lower = value.toLowerCase();
  final isPm = lower.contains('pm') || value.contains('م') || value.contains('مساء');
  final isAm = lower.contains('am') || value.contains('ص') || value.contains('صباح');
  value = value
      .replaceAll(RegExp(r'am|pm', caseSensitive: false), '')
      .replaceAll('صباحًا', '')
      .replaceAll('صباحا', '')
      .replaceAll('صباح', '')
      .replaceAll('مساءً', '')
      .replaceAll('مساءا', '')
      .replaceAll('مساء', '')
      .replaceAll('ص', '')
      .replaceAll('م', '')
      .trim();

  final parts = value.split(':');
  if (parts.length != 2) return null;
  var h = int.tryParse(parts[0].trim());
  final min = int.tryParse(parts[1].trim());
  if (h == null || min == null || min < 0 || min > 59) return null;
  if (isPm && h < 12) h += 12;
  if (isAm && h == 12) h = 0;
  if (h < 0 || h > 23) return null;
  return [h, min];
}

String safeEmailKey(String email) {
  return email.toLowerCase().trim().replaceAll('.', '_dot_').replaceAll('@', '_at_');
}

DateTime? parseDateKey(String value) {
  final parts = value.trim().split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

DateTime? combineDateAndTime(String dateKey, String timeText) {
  final date = parseDateKey(dateKey);
  final parts = parseTimePartsFlexible(timeText);
  if (date == null || parts == null) return null;
  return DateTime(date.year, date.month, date.day, parts[0], parts[1]);
}

int calculateLateMinutes(DateTime checkIn, {int startHour = defaultWorkStartHour, int startMinute = defaultWorkStartMinute}) {
  final start = DateTime(checkIn.year, checkIn.month, checkIn.day, startHour, startMinute);
  final diff = checkIn.difference(start).inMinutes;
  return diff > 0 ? diff : 0;
}

int calculateOvertimeMinutes(DateTime checkOut, {required int endHour, required int endMinute}) {
  final end = DateTime(checkOut.year, checkOut.month, checkOut.day, endHour, endMinute);
  final diff = checkOut.difference(end).inMinutes;
  return diff > 0 ? diff : 0;
}

int scheduledWorkMinutes(String startText, String endText) {
  final start = parseTimePartsFlexible(startText) ?? [defaultWorkStartHour, defaultWorkStartMinute];
  final end = parseTimePartsFlexible(endText) ?? [16, 0];
  final startMinutes = start[0] * 60 + start[1];
  final endMinutes = end[0] * 60 + end[1];
  final diff = endMinutes - startMinutes;
  return diff > 0 ? diff : 7 * 60;
}

double absenceDayDeduction(String absenceType) {
  switch (absenceType) {
    case 'أجازة رسمية مدفوعة':
    case 'أجازة بإذن مدفوعة':
    case 'لا يوجد غياب':
      return 0;
    case 'أجازة بإذن مخصومة':
    case 'غياب بخصم يوم':
      return 1;
    case 'غياب بخصم يوم ونصف':
      return 1.5;
    case 'غياب بخصم يومين':
      return 2;
    default:
      return 0;
  }
}

bool isPaidPermissionLeave(String absenceType) => absenceType == 'أجازة بإذن مدفوعة';
bool isUnpaidPermissionLeave(String absenceType) => absenceType == 'أجازة بإذن مخصومة';

int lateDeductionMinutesFromMonthlyTotal(int totalLateMinutes) {
  if (totalLateMinutes <= 30) return 0;
  if (totalLateMinutes <= 60) return totalLateMinutes - 30;
  return 30 + ((totalLateMinutes - 60) * 2);
}

String quarterKeyForDateKey(String dateKey) {
  final date = parseDateKey(dateKey) ?? DateTime.now();
  final quarter = ((date.month - 1) ~/ 3) + 1;
  return '${date.year}-Q$quarter';
}

class AttendanceMonthlySummary {
  final int totalLateMinutes;
  final int lateDeductionMinutes;
  final int totalOvertimeMinutes;
  final int overtimePaidMinutes;
  final double absenceDeductionDays;
  final int paidPermissionUsed;
  final int unpaidPermissionUsed;
  final int officialPaidUsed;
  final int absentDaysCount;
  final int monthDays;
  final int workingDays;
  final double baseSalary;
  final double dailyRate;
  final double minuteRate;
  final double lateDeductionAmount;
  final double absenceDeductionAmount;
  final double overtimeAmount;
  final double netSalary;
  // حقول جديدة للمستحق الفعلي
  final int attendanceDaysCount;    // عدد أيام الحضور المسجلة فعليًا
  final double earnedSoFar;         // المستحق حتى الآن
  final double expectedNetSalary;   // صافي الشهر المتوقع

  const AttendanceMonthlySummary({
    required this.totalLateMinutes,
    required this.lateDeductionMinutes,
    required this.totalOvertimeMinutes,
    required this.overtimePaidMinutes,
    required this.absenceDeductionDays,
    required this.paidPermissionUsed,
    required this.unpaidPermissionUsed,
    required this.officialPaidUsed,
    required this.absentDaysCount,
    required this.monthDays,
    required this.workingDays,
    required this.baseSalary,
    required this.dailyRate,
    required this.minuteRate,
    required this.lateDeductionAmount,
    required this.absenceDeductionAmount,
    required this.overtimeAmount,
    required this.netSalary,
    required this.attendanceDaysCount,
    required this.earnedSoFar,
    required this.expectedNetSalary,
  });
}

AttendanceMonthlySummary buildMonthlySummary(
  List<Map<String, dynamic>> records, {
  String? monthKey,
  double baseSalary = 0,
  String workStartText = '09:00',
  String workEndText = '16:00',
}) {
  int totalLate = 0;
  int totalOvertime = 0;
  int paidPermission = 0;
  int unpaidPermission = 0;
  int officialPaid = 0;
  double absenceDeductionDays = 0.0;
  int absentDaysCount = 0;

  for (final item in records) {
    final late = item['lateMinutes'];
    if (late is num) totalLate += late.round();

    final overtime = item['overtimeMinutes'];
    if (overtime is num) totalOvertime += overtime.round();

    final absenceType = (item['absenceType'] ?? 'لا يوجد غياب').toString();
    absenceDeductionDays += absenceDayDeduction(absenceType);

    if (absenceType == 'أجازة رسمية مدفوعة') officialPaid++;
    if (isPaidPermissionLeave(absenceType)) paidPermission++;
    if (isUnpaidPermissionLeave(absenceType)) unpaidPermission++;
    if (absenceType.startsWith('غياب بخصم')) absentDaysCount++;
  }

  final effectiveMonthKey = monthKey ?? (records.isNotEmpty ? (records.first['monthKey'] ?? '').toString() : formatMonthKey(DateTime.now()));
  final parts = effectiveMonthKey.split('-');
  final y = parts.isNotEmpty ? int.tryParse(parts[0]) ?? DateTime.now().year : DateTime.now().year;
  final m = parts.length > 1 ? int.tryParse(parts[1]) ?? DateTime.now().month : DateTime.now().month;
  final monthDays = daysInMonth(y, m);
  final workingDays = workingDaysInMonth(y, m);
  final int safeWorkingDays = workingDays == 0 ? 1 : workingDays;
  final double dailyRate = baseSalary <= 0 ? 0.0 : baseSalary / safeWorkingDays;
  final int minutesPerDay = scheduledWorkMinutes(workStartText, workEndText);
  final double minuteRate = minutesPerDay == 0 ? 0.0 : dailyRate / minutesPerDay;
  final int lateDeductionMinutes = lateDeductionMinutesFromMonthlyTotal(totalLate);
  final int overtimePaidMinutes = totalOvertime * 3;
  final double lateDeductionAmount = lateDeductionMinutes * minuteRate;
  final double absenceDeductionAmount = absenceDeductionDays * dailyRate;
  final double overtimeAmount = overtimePaidMinutes * minuteRate;
  final double netSalary = baseSalary - lateDeductionAmount - absenceDeductionAmount + overtimeAmount;

  // عدد أيام الحضور الفعلي (أيام سجّل فيها حضور بدون غياب بخصم)
  final int attendanceDaysCount = records.where((item) {
    final absType = (item['absenceType'] ?? 'لا يوجد غياب').toString();
    final hasCheckIn = item['checkInAt'] != null || (item['checkInText'] ?? '').toString().isNotEmpty;
    return hasCheckIn && absenceDayDeduction(absType) == 0;
  }).length;

  // المستحق حتى الآن = أيام الحضور × أجر اليوم + الإضافي - خصم التأخير
  final double earnedSoFar = (attendanceDaysCount * dailyRate) + overtimeAmount - lateDeductionAmount;

  // صافي الشهر المتوقع = الراتب الشهري + الإضافي - الخصومات - الغياب
  final double expectedNetSalary = baseSalary + overtimeAmount - lateDeductionAmount - absenceDeductionAmount;

  return AttendanceMonthlySummary(
    totalLateMinutes: totalLate,
    lateDeductionMinutes: lateDeductionMinutes,
    totalOvertimeMinutes: totalOvertime,
    overtimePaidMinutes: overtimePaidMinutes,
    absenceDeductionDays: absenceDeductionDays,
    paidPermissionUsed: paidPermission,
    unpaidPermissionUsed: unpaidPermission,
    officialPaidUsed: officialPaid,
    absentDaysCount: absentDaysCount,
    monthDays: monthDays,
    workingDays: workingDays,
    baseSalary: baseSalary,
    dailyRate: dailyRate,
    minuteRate: minuteRate,
    lateDeductionAmount: lateDeductionAmount,
    absenceDeductionAmount: absenceDeductionAmount,
    overtimeAmount: overtimeAmount,
    netSalary: baseSalary - lateDeductionAmount - absenceDeductionAmount + overtimeAmount,
    attendanceDaysCount: attendanceDaysCount,
    earnedSoFar: earnedSoFar < 0 ? 0 : earnedSoFar,
    expectedNetSalary: expectedNetSalary,
  );
}

class AttendanceQuarterSummary {
  final int paidPermissionUsed;
  final int unpaidPermissionUsed;

  const AttendanceQuarterSummary({required this.paidPermissionUsed, required this.unpaidPermissionUsed});
}

AttendanceQuarterSummary buildQuarterSummary(List<Map<String, dynamic>> records, String quarterKey) {
  int paid = 0;
  int unpaid = 0;
  for (final item in records) {
    if (quarterKeyForDateKey((item['dateKey'] ?? '').toString()) != quarterKey) continue;
    final absenceType = (item['absenceType'] ?? 'لا يوجد غياب').toString();
    if (isPaidPermissionLeave(absenceType)) paid++;
    if (isUnpaidPermissionLeave(absenceType)) unpaid++;
  }
  return AttendanceQuarterSummary(paidPermissionUsed: paid, unpaidPermissionUsed: unpaid);
}

class AttendancePage extends StatelessWidget {
  const AttendancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final today = formatDateKey(DateTime.now());
    return PageWrap(
      children: [
        const HeroBox(
          title: '✅ الحضور والانصراف',
          subtitle: 'النظام يحسب تأخير الشهر: أول 30 دقيقة بدون خصم، ثاني 30 دقيقة دقيقة بدقيقة، وبعدها الدقيقة بدقيقتين. والإدارة تقدر تعدل أي يوم أو تسجله كإجازة أو غياب.',
        ),
        const SizedBox(height: 12),
        AttendanceRulesCard(todayKey: today),
        const SizedBox(height: 12),
        AttendanceQuickCard(todayKey: today),
        const SizedBox(height: 12),
        if (isCurrentUserManager())
          const ManagerAttendanceView()
        else
          EmployeeAttendanceView(userEmail: currentUserEmail),
      ],
    );
  }
}

class AttendanceRulesCard extends StatelessWidget {
  final String todayKey;
  const AttendanceRulesCard({super.key, required this.todayKey});

  @override
  Widget build(BuildContext context) {
    final quarter = quarterKeyForDateKey(todayKey);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          leading: const Icon(Icons.rule_rounded, color: Color(0xFF00A6A6)),
          title: const Text('📋 عرض قواعد الحضور والانصراف والإجازات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            const InfoLine(label: 'التأخير 1', value: 'أول 30 دقيقة في الشهر لا تخصم'),
            const InfoLine(label: 'التأخير 2', value: 'ثاني 30 دقيقة في الشهر تخصم دقيقة بدقيقة'),
            const InfoLine(label: 'التأخير 3', value: 'بعد أول 60 دقيقة، كل دقيقة تخصم بدقيقتين'),
            const Divider(),
            InfoLine(label: 'الربع الحالي', value: quarter),
            const InfoLine(label: 'الرصيد', value: '6 أيام كل 3 شهور: 2 إذن مدفوع + 4 إذن مخصوم'),
            const InfoLine(label: 'الغياب', value: 'الإدارة تختار: رسمي مدفوع، إذن مدفوع، إذن مخصوم، خصم يوم، يوم ونصف، أو يومين'),
            const InfoLine(label: 'أيام العمل', value: 'الراتب يقسم على أيام العمل الفعلية في الشهر بدون الجمعة والسبت'),
            const InfoLine(label: 'الإضافي', value: 'الحضور قبل الميعاد لا يحتسب إضافي، والانصراف بعد نهاية العمل يحتسب × 3'),
          ],
        ),
      ),
    );
  }
}

class AttendanceQuickCard extends StatefulWidget {
  final String todayKey;

  const AttendanceQuickCard({super.key, required this.todayKey});

  @override
  State<AttendanceQuickCard> createState() => _AttendanceQuickCardState();
}

class _AttendanceQuickCardState extends State<AttendanceQuickCard> {
  bool saving = false;

  DocumentReference<Map<String, dynamic>> attendanceDocRef() {
    return FirebaseFirestore.instance.collection('attendance').doc('${widget.todayKey}_${safeEmailKey(currentUserEmail)}');
  }

  Future<void> checkIn(Map<String, dynamic>? currentData) async {
    if (currentData?['checkInAt'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل الحضور بالفعل اليوم')));
      return;
    }

    setState(() => saving = true);

    try {
      final now = DateTime.now();
      await attendanceDocRef().set({
        'dateKey': widget.todayKey,
        'monthKey': formatMonthKey(now),
        'quarterKey': quarterKeyForDateKey(widget.todayKey),
        'userEmail': currentUserEmail,
        'userName': currentUserDisplayName(),
        'role': currentUserRole,
        'workStartText': currentUserWorkStartTime,
        'workEndText': currentUserWorkEndTime,
        'checkInAt': Timestamp.fromDate(now),
        'checkInText': formatTime12Arabic(now),
        'lateMinutes': calculateLateMinutes(
          now,
          startHour: (parseTimePartsFlexible(currentUserWorkStartTime) ?? [defaultWorkStartHour, defaultWorkStartMinute])[0],
          startMinute: (parseTimePartsFlexible(currentUserWorkStartTime) ?? [defaultWorkStartHour, defaultWorkStartMinute])[1],
        ),
        'absenceType': 'لا يوجد غياب',
        'absenceDeductionDays': 0,
        'isManualEdit': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 12));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل الحضور بنجاح')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل تسجيل الحضور: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> checkOut(Map<String, dynamic>? currentData) async {
    if (currentData?['checkInAt'] == null && currentData?['absenceType'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يمكن تسجيل الانصراف قبل الحضور')));
      return;
    }

    if (currentData?['checkOutAt'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل الانصراف بالفعل اليوم')));
      return;
    }

    setState(() => saving = true);

    try {
      final now = DateTime.now();
      final endParts = parseTimePartsFlexible((currentData?['workEndText'] ?? currentUserWorkEndTime).toString()) ?? [16, 0];
      final overtime = calculateOvertimeMinutes(now, endHour: endParts[0], endMinute: endParts[1]);
      await attendanceDocRef().set({
        'workEndText': (currentData?['workEndText'] ?? currentUserWorkEndTime).toString(),
        'checkOutAt': Timestamp.fromDate(now),
        'checkOutText': formatTime12Arabic(now),
        'overtimeMinutes': overtime,
        'overtimePaidMinutes': overtime * 3,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 12));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل الانصراف بنجاح')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل تسجيل الانصراف: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'تسجيل سريع لليوم',
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: attendanceDocRef().snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data();
          final hasCheckIn = data?['checkInAt'] != null;
          final hasCheckOut = data?['checkOutAt'] != null;
          final absenceType = (data?['absenceType'] ?? 'لا يوجد غياب').toString();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InfoLine(label: 'المستخدم', value: currentUserDisplayName()),
              InfoLine(label: 'التاريخ', value: widget.todayKey),
              InfoLine(label: 'الحضور', value: data?['checkInText'] ?? 'لم يسجل بعد'),
              InfoLine(label: 'الانصراف', value: data?['checkOutText'] ?? 'لم يسجل بعد'),
              InfoLine(label: 'نوع اليوم', value: absenceType),
              InfoLine(label: 'تأخير اليوم', value: '${data?['lateMinutes'] ?? 0} دقيقة'),
              if (data?['isManualEdit'] == true) const InfoLine(label: 'تعديل', value: 'تم تعديل هذا اليوم بواسطة الإدارة'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: saving || hasCheckIn ? null : () => checkIn(data),
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('تسجيل حضور'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: saving || hasCheckOut ? null : () => checkOut(data),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('تسجيل انصراف'),
                    ),
                  ),
                ],
              ),
              if (saving) ...[
                const SizedBox(height: 10),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          );
        },
      ),
    );
  }
}

class EmployeeAttendanceView extends StatelessWidget {
  final String userEmail;

  const EmployeeAttendanceView({super.key, required this.userEmail});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'آخر تسجيلاتي وملخص الشهر',
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('attendance').where('userEmail', isEqualTo: userEmail).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text('خطأ في قراءة الحضور: ${snapshot.error}');
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) return const Text('لا توجد تسجيلات حضور بعد.');

          final month = formatMonthKey(DateTime.now());
          final records = docs.map((d) => d.data()).toList();
          final monthRecords = records.where((item) => (item['dateKey'] ?? '').toString().startsWith(month)).toList();
          final summary = buildMonthlySummary(
            monthRecords,
            monthKey: month,
            baseSalary: currentUserBaseSalary,
            workStartText: currentUserWorkStartTime,
            workEndText: currentUserWorkEndTime,
          );
          final quarter = quarterKeyForDateKey(formatDateKey(DateTime.now()));
          final quarterSummary = buildQuarterSummary(records, quarter);

          docs.sort((a, b) => (b.data()['dateKey'] ?? '').toString().compareTo((a.data()['dateKey'] ?? '').toString()));

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AttendanceSummaryPanel(summary: summary, quarterSummary: quarterSummary, quarterKey: quarter),
              const SizedBox(height: 12),
              ...docs.take(10).map((doc) => AttendanceListTile(item: doc.data())),
            ],
          );
        },
      ),
    );
  }
}

class ManagerAttendanceView extends StatefulWidget {
  const ManagerAttendanceView({super.key});

  @override
  State<ManagerAttendanceView> createState() => _ManagerAttendanceViewState();
}

class _ManagerAttendanceViewState extends State<ManagerAttendanceView> {
  int selectedYear = DateTime.now().year;
  int selectedMonthNum = DateTime.now().month;
  String selectedEmail = '';
  String selectedUserName = '';
  final Map<String, Map<String, dynamic>> userDataByEmail = {};

  String get selectedMonth => '$selectedYear-${selectedMonthNum.toString().padLeft(2, '0')}';

  String _arabicDay(int weekday) {
    const days = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
    return days[(weekday - 1) % 7];
  }

  bool _isWeekend(DateTime date) => date.weekday == 5 || date.weekday == 6; // جمعة أو سبت

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '✅ متابعة حضور العاملين',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // فلاتر: السنة + الشهر + العامل
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<int>(
                  value: selectedYear,
                  decoration: inputDecoration('السنة'),
                  items: List.generate(5, (i) => DateTime.now().year - 2 + i)
                      .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                      .toList(),
                  onChanged: (v) => setState(() => selectedYear = v ?? selectedYear),
                ),
              ),
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<int>(
                  value: selectedMonthNum,
                  decoration: inputDecoration('الشهر'),
                  items: List.generate(12, (i) => i + 1)
                      .map((m) => DropdownMenuItem(value: m, child: Text('$m')))
                      .toList(),
                  onChanged: (v) => setState(() => selectedMonthNum = v ?? selectedMonthNum),
                ),
              ),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('users').snapshots(),
                builder: (context, usersSnapshot) {
                  final userDocs = usersSnapshot.data?.docs ?? [];
                  userDataByEmail.clear();
                  for (final doc in userDocs) {
                    final data = doc.data();
                    final role = (data['role'] ?? '').toString();
                    if (role == 'parent') continue;
                    final email = (data['email'] ?? '').toString().toLowerCase().trim();
                    if (email.isNotEmpty) userDataByEmail[email] = data;
                  }
                  final staffList = userDataByEmail.entries.toList();
                  return SizedBox(
                    width: 280,
                    child: DropdownButtonFormField<String>(
                      value: staffList.any((e) => e.key == selectedEmail) ? selectedEmail : null,
                      decoration: inputDecoration('اختر العامل'),
                      hint: const Text('اختر عاملًا لعرض جدوله'),
                      items: staffList.map((e) {
                        final name = (e.value['name'] ?? e.key).toString();
                        return DropdownMenuItem<String>(value: e.key, child: Text(name));
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedEmail = value ?? '';
                          selectedUserName = value != null ? (userDataByEmail[value]?['name'] ?? value).toString() : '';
                        });
                      },
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => showDialog(context: context, builder: (_) => const AttendanceEditDialog()),
            icon: const Icon(Icons.add_task_rounded),
            label: const Text('✏️ تسجيل/تعديل يوم لعامل'),
          ),
          const SizedBox(height: 12),
          if (selectedEmail.isEmpty)
            const Text('اختر عاملًا من القائمة لعرض جدوله الشهري.', style: TextStyle(color: Colors.black54))
          else
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('attendance')
                  .where('userEmail', isEqualTo: selectedEmail)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Text('خطأ: ${snapshot.error}');
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

                // فلترة سجلات الشهر المختار
                final allDocs = snapshot.data?.docs ?? [];
                final monthDocs = allDocs.where((doc) {
                  return (doc.data()['dateKey'] ?? '').toString().startsWith(selectedMonth);
                }).toList();

                // بناء خريطة dateKey → data
                final recordMap = <String, Map<String, dynamic>>{};
                for (final doc in monthDocs) {
                  final item = doc.data();
                  final dateKey = (item['dateKey'] ?? '').toString();
                  if (dateKey.isNotEmpty) recordMap[dateKey] = {...item, '__docId': doc.id};
                }

                // بناء قائمة كل أيام الشهر
                final totalDays = daysInMonth(selectedYear, selectedMonthNum);
                final daysList = List.generate(totalDays, (i) {
                  return DateTime(selectedYear, selectedMonthNum, i + 1);
                });

                final userData = userDataByEmail[selectedEmail];
                final baseSalary = userData == null ? 0.0 : parseMoney(userData['baseSalary']);
                final workStart = userData == null ? '09:00' : (userData['workStartTime'] ?? '09:00').toString();
                final workEnd = userData == null ? '16:00' : (userData['workEndTime'] ?? '16:00').toString();

                // حساب الملخص مع احتساب الغياب التلقائي
                // بناء سجلات فعلية + غياب تلقائي لأيام العمل بدون تسجيل في الماضي
                final today = DateTime.now();
                final isPastMonth = DateTime(selectedYear, selectedMonthNum + 1).isBefore(DateTime(today.year, today.month, today.day));
                
                final augmentedRecords = <Map<String, dynamic>>[];
                for (final day in daysList) {
                  if (_isWeekend(day)) continue;
                  final dateKey = formatDateKey(day);
                  if (recordMap.containsKey(dateKey)) {
                    augmentedRecords.add(Map.from(recordMap[dateKey]!)..remove('__docId'));
                  } else {
                    // يوم عمل بدون تسجيل
                    final isFutureDay = day.isAfter(today);
                    if (!isFutureDay) {
                      // شهر سابق كله غياب، أو اليوم مضى بدون تسجيل
                      augmentedRecords.add({
                        'dateKey': dateKey,
                        'userEmail': selectedEmail,
                        'userName': selectedUserName,
                        'absenceType': 'غياب بخصم يوم',
                        'isAutoAbsence': true,
                        'lateMinutes': 0,
                        'overtimeMinutes': 0,
                      });
                    }
                  }
                }

                final summary = buildMonthlySummary(
                  augmentedRecords,
                  monthKey: selectedMonth,
                  baseSalary: baseSalary,
                  workStartText: workStart,
                  workEndText: workEnd,
                );
                final quarterKey = quarterKeyForDateKey('$selectedMonth-01');
                final quarterSummary = buildQuarterSummary(augmentedRecords, quarterKey);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ملخص مالي
                    AttendanceSummaryPanel(
                      summary: summary,
                      quarterSummary: quarterSummary,
                      quarterKey: quarterKey,
                      showFinancials: true,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'جدول حضور $selectedUserName - $selectedMonth',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 6),
                    // جدول كل أيام الشهر
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(const Color(0xFFBDF2E9)),
                        dataRowMinHeight: 36,
                        dataRowMaxHeight: 48,
                        columnSpacing: 10,
                        columns: const [
                          DataColumn(label: Text('التاريخ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          DataColumn(label: Text('اليوم', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          DataColumn(label: Text('حضور', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          DataColumn(label: Text('انصراف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          DataColumn(label: Text('تأخير (د)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          DataColumn(label: Text('إضافي (د)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          DataColumn(label: Text('نوع اليوم', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          DataColumn(label: Text('الحالة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          DataColumn(label: Text('ملاحظات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          DataColumn(label: Text('تعديل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        ],
                        rows: daysList.map((date) {
                          final dateKey = formatDateKey(date);
                          final isWeekend = _isWeekend(date);
                          final arabicDay = _arabicDay(date.weekday);
                          final record = recordMap[dateKey];
                          final today = DateTime.now();
                          final isFutureDay = date.isAfter(today);

                          if (isWeekend) {
                            return DataRow(
                              color: WidgetStateProperty.all(const Color(0xFFEEEEEE)),
                              cells: [
                                DataCell(Text(dateKey, style: const TextStyle(fontSize: 11))),
                                DataCell(Text(arabicDay, style: const TextStyle(fontSize: 11, color: Colors.grey))),
                                const DataCell(Text('-')),
                                const DataCell(Text('-')),
                                const DataCell(Text('-')),
                                const DataCell(Text('-')),
                                const DataCell(Text('عطلة أسبوعية', style: TextStyle(fontSize: 11, color: Colors.grey))),
                                const DataCell(Text('عطلة', style: TextStyle(color: Colors.grey, fontSize: 11))),
                                const DataCell(Text('-')),
                                const DataCell(Text('-')),
                              ],
                            );
                          }

                          // يوم في المستقبل
                          if (isFutureDay && record == null) {
                            return DataRow(
                              color: WidgetStateProperty.all(const Color(0xFFF0F4FF)),
                              cells: [
                                DataCell(Text(dateKey, style: const TextStyle(fontSize: 11, color: Colors.black38))),
                                DataCell(Text(arabicDay, style: const TextStyle(fontSize: 11, color: Colors.black38))),
                                const DataCell(Text('-', style: TextStyle(color: Colors.black38))),
                                const DataCell(Text('-', style: TextStyle(color: Colors.black38))),
                                const DataCell(Text('-')),
                                const DataCell(Text('-')),
                                const DataCell(Text('يوم عمل', style: TextStyle(fontSize: 11))),
                                const DataCell(Text('لم يحن بعد', style: TextStyle(color: Colors.blue, fontSize: 11))),
                                const DataCell(Text('-')),
                                DataCell(IconButton(
                                  icon: const Icon(Icons.add_rounded, size: 16),
                                  tooltip: 'تسجيل مسبق',
                                  onPressed: () => showDialog(
                                    context: context,
                                    builder: (_) => AttendanceEditDialog(
                                      existingData: {'dateKey': dateKey, 'userEmail': selectedEmail, 'userName': selectedUserName},
                                    ),
                                  ),
                                )),
                              ],
                            );
                          }

                          // يوم ماضٍ بدون تسجيل = غياب تلقائي
                          if (record == null) {
                            return DataRow(
                              color: WidgetStateProperty.all(const Color(0xFFFFE0E0)),
                              cells: [
                                DataCell(Text(dateKey, style: const TextStyle(fontSize: 11))),
                                DataCell(Text(arabicDay, style: const TextStyle(fontSize: 11))),
                                const DataCell(Text('-', style: TextStyle(color: Colors.grey))),
                                const DataCell(Text('-', style: TextStyle(color: Colors.grey))),
                                const DataCell(Text('-')),
                                const DataCell(Text('-')),
                                const DataCell(Text('يوم عمل', style: TextStyle(fontSize: 11))),
                                const DataCell(Text('غياب تلقائي', style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold))),
                                const DataCell(Text('بدون تسجيل', style: TextStyle(fontSize: 10, color: Colors.red))),
                                DataCell(IconButton(
                                  icon: const Icon(Icons.add_rounded, size: 16),
                                  tooltip: 'تسجيل هذا اليوم',
                                  onPressed: () => showDialog(
                                    context: context,
                                    builder: (_) => AttendanceEditDialog(
                                      existingData: {'dateKey': dateKey, 'userEmail': selectedEmail, 'userName': selectedUserName},
                                    ),
                                  ),
                                )),
                              ],
                            );
                          }

                          final late = (record['lateMinutes'] as num? ?? 0).round();
                          final overtime = (record['overtimeMinutes'] as num? ?? 0).round();
                          final absType = (record['absenceType'] ?? 'لا يوجد غياب').toString();
                          final hasDeduction = absenceDayDeduction(absType) > 0;
                          final docId = (record['__docId'] ?? '').toString();
                          final recordForEdit = Map<String, dynamic>.from(record)..remove('__docId');
                          
                          // تحديد الحالة
                          String statusText;
                          if (absType.startsWith('غياب')) {
                            statusText = 'غياب مخصوم';
                          } else if (absType.contains('أجازة رسمية') || absType.contains('مدفوع')) {
                            statusText = 'إجازة مدفوعة';
                          } else if (absType.contains('مخصوم') || absType.contains('بخصم')) {
                            statusText = 'إجازة مخصومة';
                          } else {
                            statusText = 'حاضر';
                          }

                          return DataRow(
                            color: WidgetStateProperty.all(
                              hasDeduction ? const Color(0xFFFFEAEA) : (late > 0 ? const Color(0xFFFFF8E1) : const Color(0xFFEEFFF6)),
                            ),
                            cells: [
                              DataCell(Text(dateKey, style: const TextStyle(fontSize: 11))),
                              DataCell(Text(arabicDay, style: const TextStyle(fontSize: 11))),
                              DataCell(Text(record['checkInText'] ?? '-', style: const TextStyle(fontSize: 11))),
                              DataCell(Text(record['checkOutText'] ?? '-', style: const TextStyle(fontSize: 11))),
                              DataCell(Text(late > 0 ? '$late' : '-', style: TextStyle(fontSize: 11, color: late > 0 ? Colors.orange : Colors.black54))),
                              DataCell(Text(overtime > 0 ? '$overtime' : '-', style: TextStyle(fontSize: 11, color: overtime > 0 ? Colors.green : Colors.black54))),
                              DataCell(Text('يوم عمل', style: const TextStyle(fontSize: 11))),
                              DataCell(SizedBox(width: 110, child: Text(statusText, style: TextStyle(fontSize: 10, color: hasDeduction ? Colors.red : Colors.green.shade700, fontWeight: FontWeight.w600)))),
                              DataCell(SizedBox(width: 90, child: Text((record['notes'] ?? absType).toString(), style: const TextStyle(fontSize: 10)))),
                              DataCell(IconButton(
                                icon: const Icon(Icons.edit_rounded, size: 15),
                                tooltip: 'تعديل',
                                onPressed: () => showDialog(
                                  context: context,
                                  builder: (_) => AttendanceEditDialog(existingDocId: docId.isNotEmpty ? docId : null, existingData: recordForEdit),
                                ),
                              )),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class AttendanceSummaryPanel extends StatelessWidget {
  final AttendanceMonthlySummary summary;
  final AttendanceQuarterSummary quarterSummary;
  final String quarterKey;
  final bool showFinancials; // المدير فقط يرى المالية

  const AttendanceSummaryPanel({
    super.key,
    required this.summary,
    required this.quarterSummary,
    required this.quarterKey,
    this.showFinancials = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('📋 ملخص الحضور', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          // بيانات يراها الجميع
          InfoLine(label: 'أيام الشهر', value: '${summary.monthDays} يوم'),
          InfoLine(label: 'أيام العمل الفعلية', value: '${summary.workingDays} يوم (بدون الجمعة والسبت)'),
          InfoLine(label: 'أيام الحضور المسجلة', value: '${summary.attendanceDaysCount} يوم'),
          InfoLine(label: 'تأخير الشهر', value: '${summary.totalLateMinutes} دقيقة'),
          InfoLine(label: 'إضافي الشهر', value: '${summary.totalOvertimeMinutes} دقيقة (× 3 = ${summary.overtimePaidMinutes} دقيقة مدفوعة)'),
          InfoLine(label: 'إذن مدفوع', value: '${quarterSummary.paidPermissionUsed} / 2 في $quarterKey'),
          InfoLine(label: 'إذن مخصوم', value: '${quarterSummary.unpaidPermissionUsed} / 4 في $quarterKey'),
          // بيانات مالية للمدير فقط - تظهر حتى لو الراتب صفر
          if (showFinancials) ...[
            const Divider(),
            Text('💰 التفاصيل المالية', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.brown)),
            const SizedBox(height: 4),
            InfoLine(label: 'الراتب الشهري', value: summary.baseSalary > 0 ? '${summary.baseSalary.toStringAsFixed(2)} جنيه' : 'غير محدد'),
            InfoLine(label: 'أجر اليوم الفعلي', value: summary.dailyRate > 0 ? '${summary.dailyRate.toStringAsFixed(2)} جنيه' : '-'),
            InfoLine(label: 'أجر الدقيقة', value: summary.minuteRate > 0 ? '${summary.minuteRate.toStringAsFixed(4)} جنيه' : '-'),
            InfoLine(label: 'خصم التأخير', value: '${summary.lateDeductionMinutes} دقيقة = ${summary.lateDeductionAmount.toStringAsFixed(2)} جنيه'),
            InfoLine(label: 'قيمة الإضافي', value: '${summary.overtimePaidMinutes} دقيقة = ${summary.overtimeAmount.toStringAsFixed(2)} جنيه'),
            InfoLine(label: 'خصم الغياب', value: '${summary.absenceDeductionDays} يوم = ${summary.absenceDeductionAmount.toStringAsFixed(2)} جنيه'),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFE7FFF8), borderRadius: BorderRadius.circular(10)),
              child: Column(
                children: [
                  InfoLine(label: 'صافي المستحق حتى الآن', value: '${summary.earnedSoFar.toStringAsFixed(2)} جنيه  (${summary.attendanceDaysCount} يوم × أجر اليوم + إضافي - تأخير)'),
                  InfoLine(label: 'صافي الشهر المتوقع', value: '${summary.expectedNetSalary.toStringAsFixed(2)} جنيه  (الراتب + إضافي - خصومات)'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class AttendanceEditDialog extends StatefulWidget {
  final String? existingDocId;
  final Map<String, dynamic>? existingData;

  const AttendanceEditDialog({super.key, this.existingDocId, this.existingData});

  @override
  State<AttendanceEditDialog> createState() => _AttendanceEditDialogState();
}

class _AttendanceEditDialogState extends State<AttendanceEditDialog> {
  final dateController = TextEditingController(text: formatDateKey(DateTime.now()));
  final checkInController = TextEditingController();
  final checkOutController = TextEditingController();
  final workStartController = TextEditingController(text: '09:00');
  final workEndController = TextEditingController(text: '16:00');
  final notesController = TextEditingController();

  String selectedEmail = '';
  String selectedName = '';
  String selectedRole = 'specialist';
  String absenceType = 'لا يوجد غياب';
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final data = widget.existingData;
    if (data != null) {
      dateController.text = (data['dateKey'] ?? formatDateKey(DateTime.now())).toString();
      checkInController.text = (data['checkInText'] ?? '').toString();
      checkOutController.text = (data['checkOutText'] ?? '').toString();
      workStartController.text = (data['workStartText'] ?? '09:00').toString();
      workEndController.text = (data['workEndText'] ?? '16:00').toString();
      notesController.text = (data['adminNotes'] ?? '').toString();
      selectedEmail = (data['userEmail'] ?? '').toString();
      selectedName = (data['userName'] ?? '').toString();
      selectedRole = (data['role'] ?? 'specialist').toString();
      absenceType = (data['absenceType'] ?? 'لا يوجد غياب').toString();
    }
  }

  @override
  void dispose() {
    dateController.dispose();
    checkInController.dispose();
    checkOutController.dispose();
    workStartController.dispose();
    workEndController.dispose();
    notesController.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final email = selectedEmail.toLowerCase().trim();
    final dateKey = dateController.text.trim();
    final date = parseDateKey(dateKey);
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختَر العامل أولًا')));
      return;
    }
    if (date == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب التاريخ بصيغة صحيحة YYYY-MM-DD')));
      return;
    }

    final workStartParts = parseTimePartsFlexible(workStartController.text.trim()) ?? [defaultWorkStartHour, defaultWorkStartMinute];
    final startHour = workStartParts[0];
    final startMinute = workStartParts[1];
    final workEndParts = parseTimePartsFlexible(workEndController.text.trim()) ?? [16, 0];
    final endHour = workEndParts[0];
    final endMinute = workEndParts[1];

    final checkIn = checkInController.text.trim().isEmpty ? null : combineDateAndTime(dateKey, checkInController.text.trim());
    final checkOut = checkOutController.text.trim().isEmpty ? null : combineDateAndTime(dateKey, checkOutController.text.trim());

    if (checkInController.text.trim().isNotEmpty && checkIn == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('وقت الحضور لازم يكون مثل 09:15 صباحًا أو 09:15')));
      return;
    }
    if (checkOutController.text.trim().isNotEmpty && checkOut == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('وقت الانصراف لازم يكون مثل 05:00 مساءً أو 17:00')));
      return;
    }

    setState(() => saving = true);

    try {
      final docId = widget.existingDocId ?? '${dateKey}_${safeEmailKey(email)}';
      final late = checkIn == null ? 0 : calculateLateMinutes(checkIn, startHour: startHour, startMinute: startMinute);
      final overtime = checkOut == null ? 0 : calculateOvertimeMinutes(checkOut, endHour: endHour, endMinute: endMinute);
      final data = <String, dynamic>{
        'dateKey': dateKey,
        'monthKey': '${date.year}-${date.month.toString().padLeft(2, '0')}',
        'quarterKey': quarterKeyForDateKey(dateKey),
        'userEmail': email,
        'userName': selectedName.trim().isEmpty ? email : selectedName.trim(),
        'role': selectedRole,
        'workStartText': workStartController.text.trim(),
        'workEndText': workEndController.text.trim(),
        'checkInText': checkIn == null ? null : formatTime12Arabic(checkIn),
        'checkOutText': checkOut == null ? null : formatTime12Arabic(checkOut),
        'checkInAt': checkIn == null ? null : Timestamp.fromDate(checkIn),
        'checkOutAt': checkOut == null ? null : Timestamp.fromDate(checkOut),
        'lateMinutes': late,
        'overtimeMinutes': overtime,
        'overtimePaidMinutes': overtime * 3,
        'absenceType': absenceType,
        'absenceDeductionDays': absenceDayDeduction(absenceType),
        'adminNotes': notesController.text.trim(),
        'isManualEdit': true,
        'manualEditedBy': currentUserDisplayName(),
        'manualEditedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection('attendance').doc(docId).set(data, SetOptions(merge: true)).timeout(const Duration(seconds: 12));

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ تعديل الحضور/الغياب بنجاح')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحفظ: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existingData == null ? 'تسجيل يوم لعامل' : 'تعديل يوم حضور/غياب'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('users').snapshots(),
                builder: (context, snapshot) {
                  final docs = snapshot.data?.docs ?? [];
                  final entries = docs.map((doc) {
                    final data = doc.data();
                    return {
                      'email': (data['email'] ?? '').toString().toLowerCase().trim(),
                      'name': (data['name'] ?? '').toString(),
                      'role': (data['role'] ?? 'specialist').toString(),
                    };
                  }).where((e) => e['email']!.isNotEmpty).toList();

                  if (selectedEmail.isNotEmpty && !entries.any((e) => e['email'] == selectedEmail)) {
                    entries.insert(0, {'email': selectedEmail, 'name': selectedName, 'role': selectedRole});
                  }

                  return DropdownButtonFormField<String>(
                    value: selectedEmail.isEmpty ? null : selectedEmail,
                    decoration: inputDecoration('اختيار العامل'),
                    items: entries.map((e) => DropdownMenuItem<String>(
                      value: e['email'],
                      child: Text('${e['name']!.isEmpty ? e['email'] : e['name']} - ${e['email']}'),
                    )).toList(),
                    onChanged: (value) {
                      final entry = entries.firstWhere((e) => e['email'] == value, orElse: () => {'email': value ?? '', 'name': value ?? '', 'role': 'specialist'});
                      setState(() {
                        selectedEmail = entry['email'] ?? '';
                        selectedName = entry['name'] ?? selectedEmail;
                        selectedRole = entry['role'] ?? 'specialist';
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
              TextField(controller: dateController, decoration: inputDecoration('التاريخ YYYY-MM-DD')),
              const SizedBox(height: 8),
              TextField(controller: workStartController, decoration: inputDecoration('موعد بداية العمل 12 ساعة مثل 09:00 صباحًا')),
              const SizedBox(height: 8),
              TextField(controller: workEndController, decoration: inputDecoration('موعد نهاية العمل 12 ساعة مثل 04:30 مساءً')),
              const SizedBox(height: 8),
              TextField(controller: checkInController, decoration: inputDecoration('وقت الحضور 12 ساعة مثل 09:15 صباحًا - اتركه فارغًا لو غياب')),
              const SizedBox(height: 8),
              TextField(controller: checkOutController, decoration: inputDecoration('وقت الانصراف 12 ساعة مثل 05:00 مساءً')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: absenceTypes.contains(absenceType) ? absenceType : 'لا يوجد غياب',
                decoration: inputDecoration('حالة اليوم / الغياب'),
                items: absenceTypes.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
                onChanged: (value) => setState(() => absenceType = value ?? 'لا يوجد غياب'),
              ),
              const SizedBox(height: 8),
              TextField(controller: notesController, maxLines: 2, decoration: inputDecoration('ملاحظات الإدارة')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: saving ? null : save, child: Text(saving ? 'جار الحفظ...' : 'حفظ')),
      ],
    );
  }
}

class AttendanceListTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback? onEdit;
  final VoidCallback? onPerformanceReport;

  const AttendanceListTile({super.key, required this.item, this.onEdit, this.onPerformanceReport});

  @override
  Widget build(BuildContext context) {
    final lateValue = item['lateMinutes'];
    final late = lateValue is num ? lateValue.round() : 0;
    final absenceType = (item['absenceType'] ?? 'لا يوجد غياب').toString();
    final overtimeValue = item['overtimeMinutes'];
    final overtime = overtimeValue is num ? overtimeValue.round() : 0;
    final hasAbsenceDeduction = absenceDayDeduction(absenceType) > 0;
    final isLate = late > 0;
    final role = (item['role'] ?? '').toString();
    final isSpecialistOrSenior = role == 'specialist' || role == 'senior';

    return Card(
      color: hasAbsenceDeduction ? const Color(0xFFFFEAEA) : (isLate ? const Color(0xFFFFF8E1) : Colors.white),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(child: Icon(hasAbsenceDeduction ? Icons.event_busy_rounded : (isLate ? Icons.timer_rounded : Icons.check_rounded))),
        title: Text('${item['userName'] ?? '-'} - ${item['dateKey'] ?? '-'}'),
        subtitle: Text(
          'الحضور: ${item['checkInText'] ?? '-'} | الانصراف: ${item['checkOutText'] ?? '-'}\n'
          'التأخير: $late دقيقة | الإضافي: $overtime دقيقة × 3 = ${overtime * 3} دقيقة مدفوعة | حالة اليوم: $absenceType\n'
          'خصم الغياب: ${item['absenceDeductionDays'] ?? absenceDayDeduction(absenceType)} يوم${item['isManualEdit'] == true ? ' | معدل يدويًا' : ''}',
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onEdit != null)
              IconButton(icon: const Icon(Icons.edit_rounded), tooltip: 'تعديل', onPressed: onEdit),
            if (isSpecialistOrSenior && onPerformanceReport != null)
              IconButton(
                icon: const Icon(Icons.bar_chart_rounded, color: Color(0xFF00A6A6)),
                tooltip: 'تقرير الأداء',
                onPressed: onPerformanceReport,
              ),
          ],
        ),
      ),
    );
  }
}


/* ===================== صفحات مؤقتة ===================== */

class PlaceholderPage extends StatelessWidget {
  final String title;
  final String subtitle;
  const PlaceholderPage({super.key, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => PageWrap(children: [HeroBox(title: title, subtitle: subtitle)]);
}

/* ===================== تقرير أداء الأخصائي من صفحة الحضور ===================== */

class SpecialistPerformanceDialog extends StatelessWidget {
  final String specialistEmail;
  final String specialistName;

  const SpecialistPerformanceDialog({
    super.key,
    required this.specialistEmail,
    required this.specialistName,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 600,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('seniorReports')
                .where('specialistEmail', isEqualTo: specialistEmail)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data?.docs ?? [];

              // حساب الإجماليات
              final totalReports = docs.length;
              final ratings = docs.map((d) => (d.data()['rating'] as num? ?? 0).toDouble()).where((r) => r > 0).toList();
              final avgRating = ratings.isEmpty ? 0.0 : ratings.reduce((a, b) => a + b) / ratings.length;
              final totalGoals = docs.fold<int>(0, (s, d) => s + ((d.data()['goalsCount'] as num? ?? 0).toInt()));
              final totalVideos = docs.fold<int>(0, (s, d) => s + ((d.data()['videosCount'] as num? ?? 0).toInt()));

              // تفصيل حسب نوع الجلسة
              final bySession = <String, Map<String, dynamic>>{};
              for (final doc in docs) {
                final d = doc.data();
                final session = (d['sessionType'] ?? 'غير محدد').toString();
                bySession.putIfAbsent(session, () => {'count': 0, 'ratingSum': 0.0, 'goals': 0, 'videos': 0});
                bySession[session]!['count'] = (bySession[session]!['count'] as int) + 1;
                bySession[session]!['ratingSum'] = (bySession[session]!['ratingSum'] as double) + (d['rating'] as num? ?? 0).toDouble();
                bySession[session]!['goals'] = (bySession[session]!['goals'] as int) + ((d['goalsCount'] as num? ?? 0).toInt());
                bySession[session]!['videos'] = (bySession[session]!['videos'] as int) + ((d['videosCount'] as num? ?? 0).toInt());
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // العنوان
                  Row(
                    children: [
                      const Icon(Icons.bar_chart_rounded, color: Color(0xFF00A6A6), size: 28),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('تقرير أداء الأخصائي', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            Text(specialistName, style: const TextStyle(color: Colors.black54)),
                          ],
                        ),
                      ),
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),

                  if (totalReports == 0)
                    const Text('لا توجد تقييمات لهذا الأخصائي حتى الآن.',
                        style: TextStyle(color: Colors.black54))
                  else ...[
                    // ملخص عام
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE7FFF8),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Wrap(
                        spacing: 20,
                        runSpacing: 8,
                        children: [
                          _PerfStat(label: 'عدد التقييمات', value: '$totalReports'),
                          _PerfStat(label: 'متوسط النجوم', value: '${avgRating.toStringAsFixed(1)} / 5 ⭐'),
                          _PerfStat(label: 'إجمالي الأهداف', value: '$totalGoals'),
                          _PerfStat(label: 'إجمالي الفيديوهات', value: '$totalVideos'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // تفصيل حسب نوع الجلسة
                    Text('تفصيل حسب نوع الجلسة:', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...bySession.entries.map((entry) {
                      final s = entry.key;
                      final v = entry.value;
                      final count = v['count'] as int;
                      final ratingAvg = count == 0 ? 0.0 : (v['ratingSum'] as double) / count;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              Expanded(child: Text(s, style: const TextStyle(fontWeight: FontWeight.w600))),
                              Text('${count} تقييم | ${ratingAvg.toStringAsFixed(1)}⭐ | أهداف: ${v['goals']} | فيديو: ${v['videos']}',
                                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                    // زر تصدير PDF
                    FilledButton.icon(
                      onPressed: () async {
                        await _exportSpecialistPdf(
                          name: specialistName,
                          email: specialistEmail,
                          avgRating: avgRating,
                          totalReports: totalReports,
                          totalGoals: totalGoals,
                          totalVideos: totalVideos,
                          bySession: bySession,
                        );
                      },
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('📊 تصدير PDF تقرير الأداء'),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PerfStat extends StatelessWidget {
  final String label;
  final String value;
  const _PerfStat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
      ],
    );
  }
}

Future<void> _exportSpecialistPdf({
  required String name,
  required String email,
  required double avgRating,
  required int totalReports,
  required int totalGoals,
  required int totalVideos,
  required Map<String, Map<String, dynamic>> bySession,
}) async {
  final pdf = pw.Document();
  final regularFont = await PdfGoogleFonts.notoNaskhArabicRegular();
  final boldFont = await PdfGoogleFonts.notoNaskhArabicBold();

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
      build: (ctx) => [
        pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#E7FFF8'),
            borderRadius: pw.BorderRadius.circular(12),
            border: pw.Border.all(color: PdfColor.fromHex('#00A6A6')),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('مركز ICAN - تقرير أداء الأخصائي', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Text('الاسم: $name | الإيميل: $email'),
              pw.Text('عدد التقييمات: $totalReports | متوسط النجوم: ${avgRating.toStringAsFixed(1)}/5'),
              pw.Text('إجمالي الأهداف: $totalGoals | إجمالي الفيديوهات: $totalVideos'),
            ],
          ),
        ),
        pw.SizedBox(height: 14),
        pw.Text('تفصيل حسب نوع الجلسة:', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColor.fromHex('#BDE8FF'), width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(2),
            1: pw.FlexColumnWidth(1),
            2: pw.FlexColumnWidth(1.2),
            3: pw.FlexColumnWidth(1),
            4: pw.FlexColumnWidth(1),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: PdfColor.fromHex('#BDF2E9')),
              children: [
                pdfCell('نوع الجلسة', bold: true),
                pdfCell('التقييمات', bold: true),
                pdfCell('متوسط النجوم', bold: true),
                pdfCell('الأهداف', bold: true),
                pdfCell('الفيديوهات', bold: true),
              ],
            ),
            ...bySession.entries.map((entry) {
              final s = entry.key;
              final v = entry.value;
              final count = v['count'] as int;
              final ratingAvg = count == 0 ? 0.0 : (v['ratingSum'] as double) / count;
              return pw.TableRow(children: [
                pdfCell(s),
                pdfCell('$count'),
                pdfCell(ratingAvg.toStringAsFixed(1)),
                pdfCell('${v['goals']}'),
                pdfCell('${v['videos']}'),
              ]);
            }),
          ],
        ),
      ],
    ),
  );

  await Printing.layoutPdf(
    onLayout: (PdfPageFormat format) async => pdf.save(),
    name: 'Performance_$name.pdf',
  );
}

/* ===================== صفحة متابعة السينيور - نموذج التقييم الإشرافي ===================== */

const List<String> _levelOptions = ['ضعيف', 'مقبول', 'جيد', 'جيد جدا'];

class SeniorFollowUpPage extends StatefulWidget {
  const SeniorFollowUpPage({super.key});

  @override
  State<SeniorFollowUpPage> createState() => _SeniorFollowUpPageState();
}

class _SeniorFollowUpPageState extends State<SeniorFollowUpPage> {
  // --- اختيار الطفل والفترة ---
  String? selectedChildId;
  String selectedChildName = '';
  int year = DateTime.now().year;
  int month = DateTime.now().month;
  int week = (() { final w = ((DateTime.now().day - 1) ~/ 7) + 1; return w > 5 ? 5 : w; })();

  // --- حقول النموذج ---
  String? specialistId;
  String specialistName = '';
  String specialistEmail = '';
  String sessionType = 'تخاطب';
  int rating = 0;
  final goalsCountCtrl = TextEditingController();
  final videosCountCtrl = TextEditingController();
  String motivationLevel = 'جيد';
  String behaviorLevel = 'جيد';
  String goalsAchievement = 'جيد';
  String parentInteraction = 'جيد';
  final generalNotesCtrl = TextEditingController();
  final technicalGuidanceCtrl = TextEditingController();
  final technicalSuggestionsCtrl = TextEditingController();
  bool saving = false;

  void _clearFormFields() {
    goalsCountCtrl.clear();
    videosCountCtrl.clear();
    generalNotesCtrl.clear();
    technicalGuidanceCtrl.clear();
    technicalSuggestionsCtrl.clear();
    setState(() {
      rating = 0;
      motivationLevel = 'جيد';
      behaviorLevel = 'جيد';
      goalsAchievement = 'جيد';
      parentInteraction = 'جيد';
      specialistId = null;
      specialistName = '';
      specialistEmail = '';
      sessionType = 'تخاطب';
    });
  }

  Future<void> _saveReport() async {
    if (selectedChildId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختَر الطفل أولًا')));
      return;
    }
    if (specialistId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختَر الأخصائي أولًا')));
      return;
    }
    if (rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حدد تقييم النجوم')));
      return;
    }
    setState(() => saving = true);
    try {
      await FirebaseFirestore.instance.collection('seniorReports').add({
        'childId': selectedChildId,
        'childName': selectedChildName,
        'specialistId': specialistId,
        'specialistName': specialistName,
        'specialistEmail': specialistEmail,
        'sessionType': sessionType,
        'year': year,
        'month': month,
        'week': week,
        'rating': rating,
        'goalsCount': int.tryParse(goalsCountCtrl.text.trim()) ?? 0,
        'videosCount': int.tryParse(videosCountCtrl.text.trim()) ?? 0,
        'motivationLevel': motivationLevel,
        'behaviorLevel': behaviorLevel,
        'goalsAchievement': goalsAchievement,
        'parentInteraction': parentInteraction,
        'generalNotes': generalNotesCtrl.text.trim(),
        'technicalGuidance': technicalGuidanceCtrl.text.trim(),
        'technicalSuggestions': technicalSuggestionsCtrl.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': currentUserDisplayName(),
        'createdByEmail': currentUserEmail,
      }).timeout(const Duration(seconds: 12));

      _clearFormFields();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ تقييم السينيور بنجاح ✓')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحفظ: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageWrap(
      children: [
        const HeroBox(
          title: '⭐ متابعة السينيور',
          subtitle: 'نموذج التقييم الإشرافي ⭐ - سجّل تقييمك لأداء الأخصائي 👨‍🏫 مع الطفل 👧.',
        ),
        const SizedBox(height: 12),

        // --- بطاقة اختيار الطفل والفترة ---
        SectionCard(
          title: '🔍 اختيار الطفل والفترة',
          child: Column(
            children: [
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('children').orderBy('createdAt', descending: true).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) return const Text('لا يوجد أطفال مضافون بعد.');
                  final items = docs.map((doc) => {'id': doc.id, 'label': (doc.data()['name'] ?? 'بدون اسم').toString()}).toList();
                  return SearchableDropdown(
                    label: 'اختر الطفل',
                    value: selectedChildId,
                    items: items,
                    onChanged: (value) {
                      final selected = docs.where((d) => d.id == value).toList();
                      setState(() {
                        selectedChildId = value;
                        selectedChildName = selected.isEmpty ? '' : (selected.first.data()['name'] ?? '');
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: year,
                      decoration: inputDecoration('السنة'),
                      items: List.generate(5, (i) => DateTime.now().year - 1 + i)
                          .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                          .toList(),
                      onChanged: (v) => setState(() => year = v ?? year),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: month,
                      decoration: inputDecoration('الشهر'),
                      items: List.generate(12, (i) => i + 1)
                          .map((m) => DropdownMenuItem(value: m, child: Text('$m')))
                          .toList(),
                      onChanged: (v) => setState(() => month = v ?? month),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: week,
                      decoration: inputDecoration('الأسبوع'),
                      items: [1, 2, 3, 4, 5]
                          .map((w) => DropdownMenuItem(value: w, child: Text('الأسبوع $w')))
                          .toList(),
                      onChanged: (v) => setState(() => week = v ?? week),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // --- نموذج التقييم ---
        SectionCard(
          title: '📝 نموذج التقييم الإشرافي',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              // 1. اسم الأخصائي
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('users').snapshots(),
                builder: (context, snapshot) {
                  final allDocs = snapshot.data?.docs ?? [];
                  final docs = allDocs.where((d) {
                    final r = (d.data()['role'] ?? '').toString();
                    return r == 'specialist' || r == 'senior';
                  }).toList();
                  final items = docs.map((doc) {
                    final u = doc.data();
                    return {'id': doc.id, 'label': '${u['name'] ?? '-'} (${u['role'] ?? ''})'};
                  }).toList();
                  return SearchableDropdown(
                    label: 'اسم الأخصائي',
                    value: specialistId,
                    items: items,
                    onChanged: (value) {
                      final sel = docs.where((d) => d.id == value).toList();
                      setState(() {
                        specialistId = value;
                        specialistName = sel.isEmpty ? '' : (sel.first.data()['name'] ?? '').toString();
                        specialistEmail = sel.isEmpty ? '' : (sel.first.data()['email'] ?? '').toString();
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 10),

              // 2. نوع الجلسة
              DropdownButtonFormField<String>(
                value: sessionType,
                decoration: inputDecoration('نوع الجلسة'),
                items: sessionTypes.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setState(() => sessionType = v ?? sessionType),
              ),
              const SizedBox(height: 10),

              // 3. التقييم بالنجوم
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('التقييم العام للأخصائي مع هذا الطفل', style: TextStyle(color: Colors.black54, fontSize: 13)),
                    const SizedBox(height: 8),
                    Row(
                      children: List.generate(5, (i) {
                        final star = i + 1;
                        return GestureDetector(
                          onTap: () => setState(() => rating = star),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              star <= rating ? Icons.star_rounded : Icons.star_border_rounded,
                              color: star <= rating ? Colors.amber : Colors.grey,
                              size: 36,
                            ),
                          ),
                        );
                      }),
                    ),
                    if (rating > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('التقييم: $rating / 5', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 4 & 5. عدد الأهداف والفيديوهات
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: goalsCountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: inputDecoration('عدد الأهداف'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: videosCountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: inputDecoration('عدد الفيديوهات'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 6. دافعية الطفل
              DropdownButtonFormField<String>(
                value: motivationLevel,
                decoration: inputDecoration('مستوى دافعية الطفل'),
                items: _levelOptions.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                onChanged: (v) => setState(() => motivationLevel = v ?? motivationLevel),
              ),
              const SizedBox(height: 10),

              // 7. السلوك العام
              DropdownButtonFormField<String>(
                value: behaviorLevel,
                decoration: inputDecoration('السلوك العام للطفل'),
                items: _levelOptions.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                onChanged: (v) => setState(() => behaviorLevel = v ?? behaviorLevel),
              ),
              const SizedBox(height: 10),

              // 8. تحقق الأهداف
              DropdownButtonFormField<String>(
                value: goalsAchievement,
                decoration: inputDecoration('تحقق الأهداف'),
                items: _levelOptions.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                onChanged: (v) => setState(() => goalsAchievement = v ?? goalsAchievement),
              ),
              const SizedBox(height: 10),

              // 9. تفاعل ولي الأمر
              DropdownButtonFormField<String>(
                value: parentInteraction,
                decoration: inputDecoration('تفاعل ولي الأمر'),
                items: _levelOptions.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                onChanged: (v) => setState(() => parentInteraction = v ?? parentInteraction),
              ),
              const SizedBox(height: 10),

              // 10. التطورات العامة
              TextField(
                controller: generalNotesCtrl,
                maxLines: 3,
                decoration: inputDecoration('التطورات العامة'),
              ),
              const SizedBox(height: 10),

              // 11. التوجيهات الفنية
              TextField(
                controller: technicalGuidanceCtrl,
                maxLines: 3,
                decoration: inputDecoration('التوجيهات الفنية'),
              ),
              const SizedBox(height: 10),

              // 12. المقترحات الفنية
              TextField(
                controller: technicalSuggestionsCtrl,
                maxLines: 3,
                decoration: inputDecoration('المقترحات الفنية'),
              ),
              const SizedBox(height: 16),

              // زر الحفظ
              FilledButton.icon(
                onPressed: saving ? null : _saveReport,
                icon: saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded),
                label: Text(saving ? '⏳ جار الحفظ...' : '💾 حفظ تقييم السينيور'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),

        // --- عرض التقييمات السابقة ---
        if (selectedChildId != null)
          _PreviousSeniorReportsCard(
            childId: selectedChildId!,
            childName: selectedChildName,
            year: year,
            month: month,
            week: week,
          ),
      ],
    );
  }
}

class _PreviousSeniorReportsCard extends StatelessWidget {
  final String childId;
  final String childName;
  final int year;
  final int month;
  final int week;

  const _PreviousSeniorReportsCard({
    required this.childId,
    required this.childName,
    required this.year,
    required this.month,
    required this.week,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'تقييمات هذا الأسبوع: $childName',
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('seniorReports')
            .where('childId', isEqualTo: childId)
            .where('year', isEqualTo: year)
            .where('month', isEqualTo: month)
            .where('week', isEqualTo: week)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text('خطأ: ${snapshot.error}');
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) return const Text('لا توجد تقييمات لهذا الأسبوع بعد.');
          return Column(
            children: docs.map((doc) {
              final r = doc.data();
              final stars = (r['rating'] as num? ?? 0).toInt();
              return Card(
                color: const Color(0xFFF8FBFF),
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person_rounded, color: Color(0xFF00A6A6)),
                          const SizedBox(width: 6),
                          Expanded(child: Text(r['specialistName'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold))),
                          ...List.generate(5, (i) => Icon(
                            i < stars ? Icons.star_rounded : Icons.star_border_rounded,
                            color: Colors.amber, size: 18,
                          )),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('الجلسة: ${r['sessionType'] ?? '-'} | أهداف: ${r['goalsCount'] ?? 0} | فيديوهات: ${r['videosCount'] ?? 0}',
                          style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      Text('الدافعية: ${r['motivationLevel'] ?? '-'} | السلوك: ${r['behaviorLevel'] ?? '-'} | الأهداف: ${r['goalsAchievement'] ?? '-'} | ولي الأمر: ${r['parentInteraction'] ?? '-'}',
                          style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      if ((r['generalNotes'] ?? '').toString().isNotEmpty)
                        Text('التطورات: ${r['generalNotes']}', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}


/* ===================== الحذف الآمن والسلة والنسخ الاحتياطي ===================== */

Future<void> moveDocumentToTrash({
  required String collectionName,
  required String docId,
  required Map<String, dynamic> data,
  required String itemTitle,
}) async {
  final trashRef = FirebaseFirestore.instance.collection('trash').doc();
  final originalRef = FirebaseFirestore.instance.collection(collectionName).doc(docId);
  final batch = FirebaseFirestore.instance.batch();

  batch.set(trashRef, {
    'sourceCollection': collectionName,
    'collectionName': collectionName,
    'originalId': docId,
    'originalDocId': docId,
    'itemTitle': itemTitle,
    'type': collectionName,
    'data': data,
    'deletedAt': FieldValue.serverTimestamp(),
    'deletedBy': currentUserDisplayName(),
    'deletedByEmail': currentUserEmail,
  });
  batch.delete(originalRef);
  await batch.commit().timeout(const Duration(seconds: 12));
}

Future<void> restoreTrashDocument(String trashId, Map<String, dynamic> trashData) async {
  final collectionName = (trashData['collectionName'] ?? trashData['sourceCollection'] ?? '').toString();
  final originalDocId = (trashData['originalDocId'] ?? trashData['originalId'] ?? '').toString();
  final rawData = trashData['data'];
  if (collectionName.isEmpty || originalDocId.isEmpty || rawData is! Map) return;

  final restoreData = Map<String, dynamic>.from(rawData as Map);
  restoreData['restoredAt'] = FieldValue.serverTimestamp();
  restoreData['restoredBy'] = currentUserDisplayName();

  final batch = FirebaseFirestore.instance.batch();
  batch.set(FirebaseFirestore.instance.collection(collectionName).doc(originalDocId), restoreData, SetOptions(merge: true));
  batch.delete(FirebaseFirestore.instance.collection('trash').doc(trashId));
  await batch.commit().timeout(const Duration(seconds: 12));
}

Future<String> createBackupJson() async {
  final collections = ['children', 'users', 'goals', 'weeklyPlans', 'attendance', 'trash'];
  final result = <String, dynamic>{
    'backupVersion': 2,
    'app': 'ICAN Center',
    'createdAt': DateTime.now().toIso8601String(),
    'createdBy': currentUserDisplayName(),
    'collections': <String, dynamic>{},
  };

  for (final collection in collections) {
    final snap = await FirebaseFirestore.instance.collection(collection).get().timeout(const Duration(seconds: 20));
    result['collections'][collection] = snap.docs.map((doc) => {
      'id': doc.id,
      'data': _cleanForJson(doc.data()),
    }).toList();
  }

  return const JsonEncoder.withIndent('  ').convert(result);
}

dynamic _cleanForJson(dynamic value) {
  if (value is Timestamp) return {'__timestamp': value.toDate().toIso8601String()};
  if (value is Map) return value.map((k, v) => MapEntry(k.toString(), _cleanForJson(v)));
  if (value is List) return value.map(_cleanForJson).toList();
  return value;
}

dynamic _restoreFromJson(dynamic value) {
  if (value is Map && value.containsKey('__timestamp')) {
    return Timestamp.fromDate(DateTime.parse(value['__timestamp'].toString()));
  }
  if (value is Map) return value.map((k, v) => MapEntry(k.toString(), _restoreFromJson(v)));
  if (value is List) return value.map(_restoreFromJson).toList();
  return value;
}

Future<void> restoreBackupJson(String text) async {
  final decoded = jsonDecode(text);
  if (decoded is! Map || decoded['collections'] is! Map) {
    throw Exception('ملف النسخة الاحتياطية غير صحيح');
  }

  final collections = Map<String, dynamic>.from(decoded['collections'] as Map);
  // دعم النسخ القديمة التي تستخدم deletedItems
  if (collections.containsKey('deletedItems') && !collections.containsKey('trash')) {
    collections['trash'] = collections['deletedItems'];
  }
  final batch = FirebaseFirestore.instance.batch();
  int writes = 0;

  for (final entry in collections.entries) {
    final collectionName = entry.key;
    if (collectionName == 'deletedItems') continue; // تجاهل المسمى القديم
    if (entry.value is! List) continue;
    for (final item in entry.value as List) {
      if (item is! Map) continue;
      final id = item['id']?.toString();
      final data = item['data'];
      if (id == null || id.isEmpty || data is! Map) continue;
      batch.set(FirebaseFirestore.instance.collection(collectionName).doc(id), Map<String, dynamic>.from(_restoreFromJson(data) as Map), SetOptions(merge: true));
      writes++;
      if (writes >= 450) break;
    }
  }

  await batch.commit().timeout(const Duration(seconds: 30));
}

class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  final selectedIds = <String>{};
  bool loading = false;
  String filterType = 'الكل';

  Future<void> restoreSelected(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    setState(() => loading = true);
    try {
      final targets = docs.where((doc) => selectedIds.contains(doc.id)).toList();
      for (final doc in targets) {
        await restoreTrashDocument(doc.id, doc.data());
      }
      setState(() => selectedIds.clear());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم استعادة ${targets.length} عنصر')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الاستعادة: $e')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> restoreAll(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final ok = await confirmDialog(context, 'استعادة الكل', 'هل تريد استعادة جميع عناصر السلة؟');
    if (!ok) return;
    setState(() => loading = true);
    try {
      for (final doc in docs) {
        await restoreTrashDocument(doc.id, doc.data());
      }
      setState(() => selectedIds.clear());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم استعادة ${docs.length} عنصر')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الاستعادة: $e')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> restoreByType(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, String type) async {
    final filtered = docs.where((d) => (d.data()['sourceCollection'] ?? d.data()['collectionName'] ?? '') == type).toList();
    if (filtered.isEmpty) return;
    final ok = await confirmDialog(context, 'استعادة المجموعة', 'هل تريد استعادة ${filtered.length} عنصر من نوع "$type"؟');
    if (!ok) return;
    setState(() => loading = true);
    try {
      for (final doc in filtered) {
        await restoreTrashDocument(doc.id, doc.data());
      }
      setState(() => selectedIds.clear());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم استعادة ${filtered.length} عنصر')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الاستعادة: $e')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> deleteSelectedForever(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final ok = await confirmDialog(context, 'حذف نهائي', 'سيتم حذف العناصر المحددة نهائيًا. هل أنت متأكد؟');
    if (!ok) return;
    setState(() => loading = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in docs.where((doc) => selectedIds.contains(doc.id))) {
        batch.delete(doc.reference);
      }
      await batch.commit().timeout(const Duration(seconds: 12));
      setState(() => selectedIds.clear());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحذف النهائي للعناصر المحددة')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> deleteAllForever(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final ok = await confirmDialog(context, 'حذف نهائي للكل', 'سيتم حذف جميع عناصر السلة نهائيًا بدون استعادة. هل أنت متأكد؟');
    if (!ok) return;
    setState(() => loading = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in docs) {
        batch.delete(doc.reference);
      }
      await batch.commit().timeout(const Duration(seconds: 30));
      setState(() => selectedIds.clear());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف جميع عناصر السلة نهائيًا')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> deleteByTypeForever(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, String type) async {
    final filtered = docs.where((d) => (d.data()['sourceCollection'] ?? d.data()['collectionName'] ?? '') == type).toList();
    if (filtered.isEmpty) return;
    final ok = await confirmDialog(context, 'حذف نهائي للمجموعة', 'سيتم حذف ${filtered.length} عنصر من نوع "$type" نهائيًا. هل أنت متأكد؟');
    if (!ok) return;
    setState(() => loading = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in filtered) {
        batch.delete(doc.reference);
      }
      await batch.commit().timeout(const Duration(seconds: 12));
      setState(() => selectedIds.clear());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حذف ${filtered.length} عنصر نهائيًا')));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageWrap(
      children: [
        const HeroBox(title: 'السلة المتقدمة', subtitle: 'استعادة عنصر أو مجموعة أو الكل، أو حذف نهائي.'),
        const SizedBox(height: 12),
        SectionCard(
          title: '🗑️ العناصر المحذوفة',
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('trash').orderBy('deletedAt', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text('خطأ في قراءة السلة: ${snapshot.error}');
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              final allDocs = snapshot.data?.docs ?? [];
              if (allDocs.isEmpty) return const Text('السلة فارغة.');

              // استخراج أنواع المجموعات المتاحة
              final types = allDocs
                  .map((d) => (d.data()['sourceCollection'] ?? d.data()['collectionName'] ?? 'غير محدد').toString())
                  .toSet()
                  .toList()
                ..sort();

              final docs = filterType == 'الكل'
                  ? allDocs
                  : allDocs.where((d) => (d.data()['sourceCollection'] ?? d.data()['collectionName'] ?? '') == filterType).toList();

              final allSelected = docs.isNotEmpty && selectedIds.length >= docs.length &&
                  docs.every((d) => selectedIds.contains(d.id));

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // فلتر النوع
                  DropdownButtonFormField<String>(
                    value: filterType,
                    decoration: inputDecoration('فلتر حسب النوع'),
                    items: ['الكل', ...types]
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setState(() {
                      filterType = v ?? 'الكل';
                      selectedIds.clear();
                    }),
                  ),
                  const SizedBox(height: 12),
                  // أزرار التحديد والعمليات
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: loading ? null : () => setState(() {
                          if (allSelected) {
                            for (final d in docs) selectedIds.remove(d.id);
                          } else {
                            selectedIds.addAll(docs.map((d) => d.id));
                          }
                        }),
                        icon: Icon(allSelected ? Icons.clear_all : Icons.select_all),
                        label: Text(allSelected ? 'إلغاء تحديد الكل' : 'تحديد الكل'),
                      ),
                      FilledButton.icon(
                        onPressed: loading || selectedIds.isEmpty ? null : () => restoreSelected(docs),
                        icon: const Icon(Icons.restore_rounded),
                        label: Text('استعادة المحدد (${selectedIds.length})'),
                      ),
                      OutlinedButton.icon(
                        onPressed: loading || selectedIds.isEmpty ? null : () => deleteSelectedForever(docs),
                        icon: const Icon(Icons.delete_forever_rounded),
                        label: const Text('حذف نهائي للمحدد'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: Colors.green),
                        onPressed: loading ? null : () => restoreAll(allDocs),
                        icon: const Icon(Icons.restore_page_rounded),
                        label: const Text('استعادة الكل'),
                      ),
                      if (filterType != 'الكل') ...[
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                          onPressed: loading ? null : () => restoreByType(allDocs, filterType),
                          icon: const Icon(Icons.restore_rounded),
                          label: Text('استعادة مجموعة "$filterType"'),
                        ),
                        OutlinedButton.icon(
                          onPressed: loading ? null : () => deleteByTypeForever(allDocs, filterType),
                          icon: const Icon(Icons.delete_sweep_rounded),
                          label: Text('حذف نهائي "$filterType"'),
                        ),
                      ],
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                        onPressed: loading ? null : () => deleteAllForever(allDocs),
                        icon: const Icon(Icons.delete_forever_rounded),
                        label: const Text('حذف نهائي للكل'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('إجمالي عناصر السلة: ${allDocs.length} | معروض: ${docs.length}',
                      style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 8),
                  ...docs.map((doc) {
                    final item = doc.data();
                    final title = item['itemTitle'] ?? 'عنصر محذوف';
                    final collection = item['sourceCollection'] ?? item['collectionName'] ?? '-';
                    final deletedAt = item['deletedAt'];
                    final deletedAtText = deletedAt is Timestamp
                        ? deletedAt.toDate().toIso8601String().split('T').first
                        : '-';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: CheckboxListTile(
                        value: selectedIds.contains(doc.id),
                        onChanged: (v) => setState(() {
                          if (v == true) selectedIds.add(doc.id);
                          else selectedIds.remove(doc.id);
                        }),
                        title: Text(title),
                        subtitle: Text('المصدر: $collection | التاريخ: $deletedAtText\nحذف بواسطة: ${item['deletedBy'] ?? '-'}'),
                        secondary: IconButton(
                          icon: const Icon(Icons.restore_rounded),
                          tooltip: 'استعادة',
                          onPressed: loading ? null : () async {
                            setState(() => loading = true);
                            try {
                              await restoreTrashDocument(doc.id, item);
                              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الاستعادة')));
                            } catch (e) {
                              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e')));
                            } finally {
                              if (mounted) setState(() => loading = false);
                            }
                          },
                        ),
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

Future<bool> confirmDialog(BuildContext context, String title, String message) async {
  return await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تأكيد')),
          ],
        ),
      ) ??
      false;
}

class BackupRestoreDialog extends StatefulWidget {
  const BackupRestoreDialog({super.key});

  @override
  State<BackupRestoreDialog> createState() => _BackupRestoreDialogState();
}

class _BackupRestoreDialogState extends State<BackupRestoreDialog> {
  final controller = TextEditingController();
  bool loading = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('استرداد نسخة احتياطية'),
      content: SizedBox(
        width: 600,
        child: TextField(
          controller: controller,
          maxLines: 12,
          decoration: inputDecoration('الصق محتوى JSON هنا'),
        ),
      ),
      actions: [
        TextButton(onPressed: loading ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: loading
              ? null
              : () async {
                  setState(() => loading = true);
                  try {
                    await restoreBackupJson(controller.text.trim());
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم استرداد النسخة الاحتياطية')));
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الاسترداد: $e')));
                  } finally {
                    if (mounted) setState(() => loading = false);
                  }
                },
          child: Text(loading ? 'جار الاسترداد...' : 'استرداد'),
        ),
      ],
    );
  }
}

class PageWrap extends StatelessWidget {
  final List<Widget> children;
  const PageWrap({super.key, required this.children});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: children);
}

class HeroBox extends StatelessWidget {
  final String title;
  final String subtitle;
  const HeroBox({super.key, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFBDF2E9), Color(0xFFFFE8A3), Color(0xFFE7D8FF)], begin: Alignment.topRight, end: Alignment.bottomLeft),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(subtitle, style: const TextStyle(height: 1.5, color: Colors.black87)),
      ]),
    );
  }
}

class SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const SectionCard({super.key, required this.title, required this.child});
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          child,
        ]),
      ),
    );
  }
}


Future<void> exportReportPdf({
  required String childName,
  required String periodText,
  required int averagePercent,
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
}) async {
  final pdf = pw.Document();

  final regularFont = await PdfGoogleFonts.notoNaskhArabicRegular();
  final boldFont = await PdfGoogleFonts.notoNaskhArabicBold();

  // تحميل اللوجو
  pw.MemoryImage? logoImage;
  try {
    final byteData = await rootBundle.load('assets/images/ican_logo.jpg');
    logoImage = pw.MemoryImage(byteData.buffer.asUint8List());
  } catch (_) {
    logoImage = null;
  }

  final grouped = <String, Map<String, List<Map<String, dynamic>>>>{};

  for (final doc in docs) {
    final item = doc.data();
    final session = (item['sessionType'] ?? 'غير محدد').toString();
    final specialist = (item['goalAuthor'] ?? 'أخصائي غير محدد').toString();

    grouped.putIfAbsent(session, () => {});
    grouped[session]!.putIfAbsent(specialist, () => []);
    grouped[session]![specialist]!.add(item);
  }

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(
        base: regularFont,
        bold: boldFont,
      ),
      build: (context) {
        return [
          // اللوجو + الهيدر
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#E7FFF8'),
              borderRadius: pw.BorderRadius.circular(14),
              border: pw.Border.all(color: PdfColor.fromHex('#00A6A6')),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logoImage != null) ...[
                  pw.Image(logoImage, width: 60, height: 60),
                  pw.SizedBox(width: 12),
                ],
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'مركز ICAN للتربية الخاصة والخدمات النفسية',
                        style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text('اسم الطفل: $childName', style: const pw.TextStyle(fontSize: 14)),
                      pw.Text(periodText, style: const pw.TextStyle(fontSize: 14)),
                      pw.Text('متوسط نسبة الإنجاز: $averagePercent%', style: const pw.TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#FFF8E1'),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Text(
              'بداية مشجعة: نثمن مجهود الطفل والأسرة والفريق، وكل تقدم مهما كان بسيطًا هو خطوة مهمة نحو الاستقلال والنمو.',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 16),
          if (docs.isEmpty)
            pw.Text('لا توجد أهداف مسجلة لهذه الفترة.')
          else
            ...grouped.entries.expand((sessionEntry) {
              final sessionType = sessionEntry.key;
              final specialists = sessionEntry.value;

              return [
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#BDF2E9'),
                    borderRadius: pw.BorderRadius.circular(10),
                  ),
                  child: pw.Text(
                    'نوع الجلسة: $sessionType',
                    style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.SizedBox(height: 8),
                ...specialists.entries.expand((specialistEntry) {
                  final specialist = specialistEntry.key;
                  final items = specialistEntry.value;

                  return [
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromHex('#F4ECFF'),
                        borderRadius: pw.BorderRadius.circular(8),
                      ),
                      child: pw.Text(
                        'الأخصائي: $specialist',
                        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Table(
                      border: pw.TableBorder.all(color: PdfColor.fromHex('#D0D7DE'), width: 0.5),
                      columnWidths: const {
                        0: pw.FlexColumnWidth(3),
                        1: pw.FlexColumnWidth(1.2),
                        2: pw.FlexColumnWidth(1.2),
                        3: pw.FlexColumnWidth(1),
                        4: pw.FlexColumnWidth(1.6),
                      },
                      children: [
                        pw.TableRow(
                          decoration: pw.BoxDecoration(color: PdfColor.fromHex('#E7FFF8')),
                          children: [
                            pdfCell('الهدف', bold: true),
                            pdfCell('المساعدة', bold: true),
                            pdfCell('التعزيز', bold: true),
                            pdfCell('الإنجاز', bold: true),
                            pdfCell('السينيور', bold: true),
                          ],
                        ),
                        ...items.map((item) {
                          final achievement = item['achievementPercent'] ?? 0;
                          final senior = item['seniorApproved'] == true ? (item['seniorName'] ?? 'تمت') : 'لم تتم';

                          return pw.TableRow(
                            decoration: pw.BoxDecoration(
                              color: achievement is num && achievement >= 70
                                  ? PdfColor.fromHex('#E7FBEA')
                                  : PdfColors.white,
                            ),
                            children: [
                              pdfCell(item['goalText']?.toString() ?? '-'),
                              pdfCell(item['promptLevel']?.toString() ?? '-'),
                              pdfCell(item['reinforcementSchedule']?.toString() ?? '-'),
                              pdfCell('$achievement%'),
                              pdfCell(senior.toString()),
                            ],
                          );
                        }),
                      ],
                    ),
                    pw.SizedBox(height: 12),
                  ];
                }),
                pw.SizedBox(height: 8),
              ];
            }),
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#E7FBEA'),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Text(
              'ختامًا: نشكر ولي الأمر على التعاون، ونوصي بالاستمرارية في التدريب المنزلي والمتابعة المنتظمة لدعم التقدم بشكل أفضل.',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ];
      },
    ),
  );

  await Printing.layoutPdf(
    onLayout: (PdfPageFormat format) async => pdf.save(),
    name: 'ICAN_Report_$childName.pdf',
  );
}

pw.Widget pdfCell(String text, {bool bold = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 10,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}

void showReportDialog(BuildContext context, String title, String period) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(period, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          const Text('بداية مشجعة: نُقدّر مجهود الطفل والأسرة والفريق، ونؤكد أن كل خطوة صغيرة تمثل تقدمًا مهمًا في رحلة التطور.'),
          const SizedBox(height: 14),
          const Text('ختامًا: نشكر ولي الأمر على التعاون، ونؤكد أن الاستمرارية والمتابعة المنزلية تساعد الطفل على تحقيق نتائج أفضل.'),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.picture_as_pdf), label: const Text('تصدير PDF')),
      ],
    ),
  );
}
