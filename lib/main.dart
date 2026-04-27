import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:confetti/confetti.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('token');
  runApp(OrbitgramApp(token: token));
}

class OrbitgramApp extends StatelessWidget {
  final String? token;
  const OrbitgramApp({super.key, this.token});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orbitgram',
      theme: ThemeData.light().copyWith(
        primaryColor: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(color: Colors.blue, elevation: 0),
      ),
      darkTheme: ThemeData.dark().copyWith(
        primaryColor: Colors.black,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(color: Colors.black, elevation: 0),
      ),
      themeMode: ThemeMode.system,
      home: token == null ? const RegisterScreen() : ChatListScreen(token: token!),
    );
  }
}

// ---------- АНИМАЦИЯ ПРЕМИУМА ----------
class PremiumCelebration extends StatefulWidget {
  final VoidCallback onDone;
  const PremiumCelebration({super.key, required this.onDone});

  @override
  State<PremiumCelebration> createState() => _PremiumCelebrationState();
}

class _PremiumCelebrationState extends State<PremiumCelebration> {
  late ConfettiController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ConfettiController(duration: const Duration(seconds: 3));
    _controller.play();
    Future.delayed(const Duration(seconds: 3), () {
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.celebration, size: 80, color: Colors.amber),
                const SizedBox(height: 20),
                const Text('🎉 Premium активирован!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                const Text('30 дней бесплатного премиума', style: TextStyle(fontSize: 16)),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () => widget.onDone(),
                  child: const Text('Продолжить'),
                ),
              ],
            ),
          ),
          ConfettiWidget(
            confettiController: _controller,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: false,
            colors: const [Colors.amber, Colors.green, Colors.red, Colors.blue],
            numberOfParticles: 50,
          ),
        ],
      ),
    );
  }
}

// ---------- РЕГИСТРАЦИЯ / ЛОГИН ----------
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  String _error = '';
  String _serverIp = '192.168.1.100';  // замените на IP вашего сервера

  Future<void> _submit() async {
    final url = Uri.parse('http://$_serverIp:8000/${_isLogin ? "login" : "register"}');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': _usernameController.text, 'password': _passwordController.text}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['access_token'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', token);
        await prefs.setString('server_ip', _serverIp);

        if (!_isLogin) {
          // регистрация – анимация премиума
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => PremiumCelebration(
                onDone: () {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatListScreen(token: token)));
                },
              ),
            ),
          );
        } else {
          // логин – сразу в чаты
          if (!mounted) return;
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatListScreen(token: token)));
        }
      } else {
        setState(() => _error = 'Ошибка: неверные данные');
      }
    } catch (e) {
      setState(() => _error = 'Сервер не отвечает. Проверьте IP: $_serverIp');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Orbitgram', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(controller: _usernameController, decoration: const InputDecoration(labelText: 'Логин')),
              const SizedBox(height: 16),
              TextField(controller: _passwordController, decoration: const InputDecoration(labelText: 'Пароль'), obscureText: true),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(labelText: 'IP сервера (компьютера)'),
                controller: TextEditingController(text: _serverIp),
                onChanged: (v) => _serverIp = v,
              ),
              if (_error.isNotEmpty) Text(_error, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: _submit, child: Text(_isLogin ? 'Войти' : 'Регистрация')),
              TextButton(
                onPressed: () => setState(() => _isLogin = !_isLogin),
                child: Text(_isLogin ? 'Нет аккаунта? Создать' : 'Уже есть аккаунт? Войти'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- СПИСОК ЧАТОВ ----------
class ChatListScreen extends StatefulWidget {
  final String token;
  const ChatListScreen({super.key, required this.token});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<Map<String, dynamic>> chats = [];
  WebSocketChannel? channel;
  String? currentUserId;
  bool isPremium = false;
  String? serverIp;

  @override
  void initState() {
    super.initState();
    _loadServerIp();
  }

  Future<void> _loadServerIp() async {
    final prefs = await SharedPreferences.getInstance();
    serverIp = prefs.getString('server_ip') ?? '192.168.1.100';
    _connectWebSocket();
    await _fetchCurrentUser();
    await _fetchChats();
  }

  void _connectWebSocket() {
    final wsUrl = Uri.parse('ws://$serverIp:8000/ws?token=${widget.token}');
    channel = WebSocketChannel.connect(wsUrl);
    channel!.stream.listen((message) {
      final data = jsonDecode(message);
      if (data['type'] == 'message') {
        _fetchChats();
      }
    });
  }

  Future<void> _fetchCurrentUser() async {
    final response = await http.get(
      Uri.parse('http://$serverIp:8000/me'),
      headers: {'Authorization': widget.token},
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      currentUserId = data['id'].toString();
      setState(() => isPremium = data['is_premium'] ?? false);
    }
  }

  Future<void> _fetchChats() async {
    final response = await http.get(
      Uri.parse('http://$serverIp:8000/chats'),
      headers: {'Authorization': widget.token},
    );
    if (response.statusCode == 200) {
      setState(() => chats = List<Map<String, dynamic>>.from(jsonDecode(response.body)));
    }
  }

  void _showSearchDialog() {
    showDialog(context: context, builder: (_) => SearchDialog(token: widget.token, serverIp: serverIp!));
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    try {
      return DateFormat('HH:mm').format(DateTime.parse(iso).toLocal());
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Orbitgram'),
            if (isPremium) const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.star, color: Colors.amber, size: 20)),
          ],
        ),
        actions: [IconButton(icon: const Icon(Icons.search), onPressed: _showSearchDialog)],
      ),
      body: ListView.builder(
        itemCount: chats.length,
        itemBuilder: (_, i) {
          final chat = chats[i];
          return ListTile(
            leading: CircleAvatar(child: Text(chat['name'][0].toUpperCase()), backgroundColor: Colors.blue),
            title: Text(chat['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(chat['last_message'] ?? 'Нет сообщений', maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Text(_formatTime(chat['last_time']), style: const TextStyle(fontSize: 12)),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  chatId: chat['id'],
                  chatTitle: chat['name'],
                  token: widget.token,
                  channel: channel,
                  serverIp: serverIp!,
                  currentUserId: currentUserId!,
                  isPremium: isPremium,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------- ПОИСК ПОЛЬЗОВАТЕЛЕЙ ----------
class SearchDialog extends StatefulWidget {
  final String token;
  final String serverIp;
  const SearchDialog({super.key, required this.token, required this.serverIp});

  @override
  State<SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<SearchDialog> {
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> results = [];

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    final response = await http.get(
      Uri.parse('http://${widget.serverIp}:8000/search_users?q=$q'),
      headers: {'Authorization': widget.token},
    );
    if (response.statusCode == 200) {
      setState(() => results = List<Map<String, dynamic>>.from(jsonDecode(response.body)));
    }
  }

  Future<void> _sendRequest(int userId) async {
    await http.post(
      Uri.parse('http://${widget.serverIp}:8000/send_contact_request/$userId'),
      headers: {'Authorization': widget.token},
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Заявка отправлена')));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Поиск пользователей'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _controller, decoration: const InputDecoration(hintText: 'Логин'), autofocus: true),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: _search, child: const Text('Найти')),
          ...results.map((u) => ListTile(
            title: Text(u['username']),
            trailing: IconButton(icon: const Icon(Icons.person_add), onPressed: () => _sendRequest(u['id'])),
          )),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть'))],
    );
  }
}

// ---------- ЭКРАН ЧАТА ----------
class ChatScreen extends StatefulWidget {
  final int chatId;
  final String chatTitle;
  final String token;
  final WebSocketChannel? channel;
  final String serverIp;
  final String currentUserId;
  final bool isPremium;
  const ChatScreen({
    super.key,
    required this.chatId,
    required this.chatTitle,
    required this.token,
    this.channel,
    required this.serverIp,
    required this.currentUserId,
    required this.isPremium,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> messages = [];

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    widget.channel?.stream.listen((data) {
      final msg = jsonDecode(data);
      if (msg['type'] == 'message' && msg['chat_id'] == widget.chatId) {
        setState(() {
          messages.add({
            'id': msg['message_id'],
            'text': msg['text'],
            'sender_id': msg['sender_id'].toString(),
            'created_at': msg['created_at'],
            'is_own': msg['sender_id'].toString() == widget.currentUserId,
            'reactions': [],
          });
        });
      }
    });
  }

  Future<void> _fetchMessages() async {
    final response = await http.get(
      Uri.parse('http://${widget.serverIp}:8000/messages/${widget.chatId}'),
      headers: {'Authorization': widget.token},
    );
    if (response.statusCode == 200) {
      setState(() => messages = List<Map<String, dynamic>>.from(jsonDecode(response.body)));
    }
  }

  void sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.channel?.sink.add(jsonEncode({'chat_id': widget.chatId, 'text': text}));
    setState(() {
      messages.add({
        'id': DateTime.now().millisecondsSinceEpoch,
        'text': text,
        'sender_id': widget.currentUserId,
        'created_at': DateTime.now().toIso8601String(),
        'is_own': true,
        'reactions': [],
      });
    });
    _controller.clear();
  }

  void _showReactionDialog(Map<String, dynamic> message) async {
    final List<String> reactions = ['👍', '❤️', '😂', '😮', '😢', '😡'];
    final selected = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Выберите реакцию'),
        children: reactions.map((r) => SimpleDialogOption(
          child: Text(r, style: const TextStyle(fontSize: 24)),
          onPressed: () => Navigator.pop(context, r),
        )).toList(),
      ),
    );
    if (selected != null) {
      await http.post(
        Uri.parse('http://${widget.serverIp}:8000/reaction?message_id=${message['id']}&reaction=$selected'),
        headers: {'Authorization': widget.token, 'Content-Type': 'application/json'},
      );
      _fetchMessages();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(widget.chatTitle),
            if (widget.isPremium) const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.star, color: Colors.amber, size: 18)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: messages.length,
              itemBuilder: (_, i) {
                final msg = messages[messages.length - 1 - i];
                final isMe = msg['is_own'];
                return GestureDetector(
                  onLongPress: () => _showReactionDialog(msg),
                  child: MessageBubble(
                    text: msg['text'],
                    isMe: isMe,
                    time: DateTime.tryParse(msg['created_at']),
                    reactions: List<Map<String, dynamic>>.from(msg['reactions'] ?? []),
                    currentUserId: widget.currentUserId,
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              boxShadow: [BoxShadow(blurRadius: 2, color: Colors.grey.withOpacity(0.2))],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(hintText: 'Сообщение', border: InputBorder.none),
                  ),
                ),
                IconButton(icon: const Icon(Icons.send), onPressed: sendMessage),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- ПУЗЫРЁК СООБЩЕНИЯ С РЕАКЦИЯМИ ----------
class MessageBubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final DateTime? time;
  final List<Map<String, dynamic>> reactions;
  final String currentUserId;

  const MessageBubble({
    super.key,
    required this.text,
    required this.isMe,
    this.time,
    required this.reactions,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    Map<String, int> reactionCounts = {};
    for (var r in reactions) {
      String emoji = r['reaction'];
      reactionCounts[emoji] = (reactionCounts[emoji] ?? 0) + 1;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isMe ? Colors.blue[300] : Colors.grey[300],
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: isMe ? const Radius.circular(12) : Radius.zero,
                bottomRight: isMe ? Radius.zero : const Radius.circular(12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: TextStyle(color: isMe ? Colors.white : Colors.black)),
                if (time != null) const SizedBox(height: 4),
                if (time != null)
                  Text(
                    DateFormat('HH:mm').format(time!),
                    style: TextStyle(fontSize: 10, color: isMe ? Colors.white70 : Colors.black54),
                  ),
                if (reactionCounts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 4,
                      children: reactionCounts.entries.map((e) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
                        child: Text('${e.key} ${e.value}', style: const TextStyle(fontSize: 12)),
                      )).toList(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}