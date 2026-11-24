import 'package:flutter/material.dart';
import 'api.dart';
import 'store.dart';
import 'theme.dart';
import 'title_bar.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final server = TextEditingController(text: store.server);
  final user = TextEditingController(text: store.user);
  final pass = TextEditingController();
  bool busy = false;
  bool hide = true;
  String error = '';

  @override
  void initState() {
    super.initState();
    // Kullanıcı tam bir M3U / get.php linki yapıştırırsa alanları kendisi doldur
    server.addListener(() {
      final p = XtreamApi.parseFullLink(server.text);
      if (p != null) {
        server.text = p.server;
        user.text = p.user;
        pass.text = p.pass;
      }
    });
  }

  @override
  void dispose() {
    server.dispose();
    user.dispose();
    pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await store.login(server.text, user.text.trim(), pass.text.trim());
    } catch (e) {
      setState(() => error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        const TitleBar(),
        Expanded(
          child: Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(center: Alignment(0.6, -0.8), radius: 1.3, colors: [Color(0xFF3A1A10), kBg]),
            ),
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(26),
                        child: Image.asset('assets/icon.png', width: 104, height: 104),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: ShaderMask(
                        shaderCallback: (r) => kFireGradient.createShader(r),
                        child: const Text('Quetzalov',
                            style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: .5)),
                      ),
                    ),
                    const Text('Canlı TV · Filmler · Diziler',
                        textAlign: TextAlign.center, style: TextStyle(color: kDim, fontSize: 14)),
                    const SizedBox(height: 28),
                    TextField(
                      controller: server,
                      decoration: const InputDecoration(
                        labelText: 'Sunucu adresi',
                        hintText: 'http://ornek-sunucu.com:8080',
                        prefixIcon: Icon(Icons.dns_rounded),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text('  Tam M3U linkini de yapıştırabilirsin; bilgiler otomatik doldurulur.',
                        style: TextStyle(color: kDim, fontSize: 11.5)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: user,
                      decoration: const InputDecoration(labelText: 'Kullanıcı adı', prefixIcon: Icon(Icons.person_rounded)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pass,
                      obscureText: hide,
                      onSubmitted: (_) => _login(),
                      decoration: InputDecoration(
                        labelText: 'Şifre',
                        prefixIcon: const Icon(Icons.lock_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(hide ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                          onPressed: () => setState(() => hide = !hide),
                        ),
                      ),
                    ),
                    if (error.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: kEmber.withValues(alpha: .15), borderRadius: BorderRadius.circular(12)),
                        child: Text(error, style: const TextStyle(color: Color(0xFFFFB4A8))),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 52,
                      child: DecoratedBox(
                        decoration: BoxDecoration(gradient: kFireGradient, borderRadius: BorderRadius.circular(14)),
                        child: TextButton(
                          onPressed: busy ? null : _login,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: busy
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                              : const Text('Giriş yap', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Bilgilerin yalnızca bu bilgisayarda saklanır.',
                        textAlign: TextAlign.center, style: TextStyle(color: kDim, fontSize: 12)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
