import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const RedeemApp()); }

class RedeemApp extends StatelessWidget {
  const RedeemApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'COD Mobile Redeem', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.orange, brightness: Brightness.dark, useMaterial3: true),
    home: const RedeemHome());
}

class RedeemHome extends StatefulWidget {
  const RedeemHome({super.key});
  @override State<RedeemHome> createState() => _RedeemHomeState();
}

class _RedeemHomeState extends State<RedeemHome> {
  final uid = TextEditingController();
  final input = TextEditingController();
  final codes = <String>[];
  final results = <String, String>{};
  int current = 0;
  bool showPortal = false;
  bool processing = false;
  late final WebViewController browser;

  @override void initState() {
    super.initState();
    browser = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(onPageFinished: (_) { if (mounted) setState(() {}); }))
      ..loadRequest(Uri.parse('https://www.callofduty.com/redemption'));
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      uid.text = p.getString('uid') ?? '';
      codes.addAll(p.getStringList('codes') ?? []);
      current = (p.getInt('current') ?? 0).clamp(0, codes.length);
      for (final code in codes) {
        final status = p.getString('status_$code');
        if (status != null) results[code] = status;
      }
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('uid', uid.text.trim());
    await p.setStringList('codes', codes);
    await p.setInt('current', current);
    for (final entry in results.entries) {
      await p.setString('status_${entry.key}', entry.value);
    }
  }

  void _add() {
    final incoming = input.text.toUpperCase().split(RegExp(r'[\s,;]+')).map((e) => e.trim()).where((e) => e.isNotEmpty);
    setState(() { for (final code in incoming) { if (!codes.contains(code)) codes.add(code); } input.clear(); });
    _save();
  }

  void _mark(String status) {
    if (current >= codes.length) return;
    setState(() { results[codes[current]] = status; current++; });
    _save();
  }

  // Only populate form fields in the official page. Never solve CAPTCHAs,
  // auto-submit requests, or bypass verification controls.
  Future<void> _fill() async {
    if (current >= codes.length) return;
    await _save();
    setState(() => showPortal = true);
    final id = uid.text.trim();
    final code = codes[current];
    final script = '''
      (() => {
        const fields = [...document.querySelectorAll('input')];
        const visible = fields.filter(e => e.offsetWidth || e.offsetHeight || e.getClientRects().length);
        function choose(hints) {
          return visible.find(e => hints.some(h => ((e.name||'')+' '+(e.id||'')+' '+(e.placeholder||'')+' '+(e.getAttribute('aria-label')||'')).toLowerCase().includes(h)));
        }
        function set(el, value) {
          if (!el) return false;
          const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;
          setter.call(el,value);
          el.dispatchEvent(new Event('input',{bubbles:true}));
          el.dispatchEvent(new Event('change',{bubbles:true}));
          return true;
        }
        return { uid:set(choose(['uid','user id','player id']),${_js(id)}),
                 code:set(choose(['redeem','promo','gift','code']),${_js(code)}) };
      })()
    ''';
    try {
      final outcome = await browser.runJavaScriptReturningResult(script);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Preenchimento solicitado: $outcome. Confira os campos e resolva o CAPTCHA.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível preencher. A página pode bloquear a integração.')));
    }
  }

  Future<void> _submitCurrent() async {
    if (processing || current >= codes.length) return;
    setState(() => processing = true);
    try {
      // Submit only after the user has manually completed the official CAPTCHA.
      // Do not attempt to read, solve, or refresh it automatically.
      final result = await browser.runJavaScriptReturningResult("""
        (() => {
          const inputs = [...document.querySelectorAll('input')];
          const verification = inputs.find(e => /verification|captcha/i.test(
            (e.name||'')+' '+(e.id||'')+' '+(e.placeholder||'')));
          if (!verification || !verification.value.trim()) return 'captcha_missing';
          const submit = [...document.querySelectorAll('button,input[type=submit]')]
            .find(e => /submit|redeem/i.test(e.innerText||e.value||''));
          if (!submit) return 'submit_missing';
          submit.click();
          return 'submitted';
        })()
      """);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        result.toString().contains('submitted')
          ? 'Enviado ao portal. Confira a resposta antes de avançar.'
          : 'Verifique o CAPTCHA e o botão de envio na página oficial.'
      )));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O portal não permitiu o envio assistido.')));
    } finally {
      if (mounted) setState(() => processing = false);
    }
  }

  String _js(String value) => "'${value.replaceAll('\\', '\\\\').replaceAll("'", "\\'").replaceAll('\n', '\\n')}'";

  @override void dispose() { uid.dispose(); input.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final code = current < codes.length ? codes[current] : 'Fila concluída';
    return Scaffold(
      appBar: AppBar(title: const Text('COD Mobile Redeem'), actions: [
        IconButton(onPressed: () => setState(() => showPortal = !showPortal), icon: Icon(showPortal ? Icons.list : Icons.language)),
      ]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          TextField(controller: uid, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Seu UID', border: OutlineInputBorder()), onChanged: (_) => _save()),
          const SizedBox(height: 8),
          TextField(controller: input, minLines: 1, maxLines: 3, decoration: const InputDecoration(labelText: 'Cole códigos separados por linha', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: FilledButton.tonal(onPressed: _add, child: const Text('Adicionar códigos'))),
            const SizedBox(width: 8),
            Text('${codes.length - current} pendentes'),
          ]),
          const SizedBox(height: 8),
          Text('Atual: $code', style: Theme.of(context).textTheme.titleMedium),
          Row(children: [
            Expanded(child: FilledButton(onPressed: current < codes.length && uid.text.trim().isNotEmpty ? _fill : null, child: const Text('Preencher no portal'))),
            IconButton(onPressed: () => browser.reload(), tooltip: 'Atualizar portal', icon: const Icon(Icons.refresh)),
          ]),
          if (showPortal) FilledButton.icon(
            onPressed: processing || current >= codes.length ? null : _submitCurrent,
            icon: const Icon(Icons.send),
            label: const Text('CAPTCHA preenchido — enviar'),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            TextButton(onPressed: current < codes.length ? () => _mark('resgatado') : null, child: const Text('Resgatado')),
            TextButton(onPressed: current < codes.length ? () => _mark('falhou') : null, child: const Text('Falhou')),
            TextButton(onPressed: current < codes.length ? () => _mark('ignorado') : null, child: const Text('Pular')),
          ]),
        ])),
        Expanded(child: showPortal
          ? WebViewWidget(controller: browser)
          : ListView.builder(itemCount: codes.length, itemBuilder: (_, i) => ListTile(
              dense: true, leading: Icon(i == current ? Icons.play_arrow : Icons.confirmation_number_outlined),
              title: Text(codes[i]), subtitle: Text(results[codes[i]] ?? (i == current ? 'Atual' : 'Pendente')),
              onTap: () { setState(() => current = i); _save(); },
            ))),
      ]),
    );
  }
}
