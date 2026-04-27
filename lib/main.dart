import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('token');
  runApp(MyApp(token: token));
}

class MyApp extends StatelessWidget {
  final String? token;
  const MyApp({this.token});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Messenger',
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

// -------- ЭКРАН РЕГИСТРАЦИИ/ЛОГИНА --------
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  String _error = '';

  Future<void> _submit() async {
    final url = Uri.parse('http://localhost:8000/${_isLogin ? "login" : "register"}');
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
        if (!mounted) return;
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatListScreen(token: token)));
      } else {
        setState(() => _error = 'Ошибка: неверные данные');
      }
    } catch (e) {
      setState(() => _error = 'Сервер не отвечает');
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
              const Text('Telegram Clone', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 40),
              TextField(controller: _usernameController, decoration: const InputDecoration(labelText: 'Логин')),
              const SizedBox(height: 16),
              TextField(controller: _passwordController, decoration: const InputDecoration(labelText: 'Пароль'), obscureText: true),
              if (_error.isNotEmpty) Text(_error, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: _submit, child: Text(_isLogin ? 'Войти' : 'Зарегистрироваться')),
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

// -------- СПИСОК ЧАТОВ --------
class ChatListScreen extends StatefulWidget {
  final String token;
  const ChatListScreen({super.key, required this.token});

  @override
  _ChatListScreenState createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<Map<String, dynamic>> chats = [];
  WebSocketChannel? channel;
  String? currentUserId;

  @override
  void initState() {
    super.initState();
    connectWebSocket();
    fetchCurrentUser();
    fetchChats();
  }

  void connectWebSocket() {
    final wsUrl = Uri.parse('ws://localhost:8000/ws?token=${widget.token}');
    channel = WebSocketChannel.connect(wsUrl);
    channel!.stream.listen((message) {
      final data = jsonDecode(message);
      if (data['type'] == 'message') {
        fetchChats(); // обновить список чатов
      }
    });
  }

  Future<void> fetchCurrentUser() async {
    final response = await http.get(
      Uri.parse('http://localhost:8000/me'),
      headers: {'Authorization': widget.token},
    );
    if (response.statusCode == 200) {
      currentUserId = jsonDecode(response.body)['id'].toString();
    }
  }

  Future<void> fetchChats() async {
    final response = await http.get(
      Uri.parse('http://localhost:8000/chats'),
      headers: {'Authorization': widget.token},
    );
    if (response.statusCode == 200) {
      setState(() => chats = List<Map<String, dynamic>>.from(jsonDecode(response.body)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мессенджер'),
        actions: [IconButton(icon: const Icon(Icons.search), onPressed: () => _showSearchDialog())],
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
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showSearchDialog() {
    showDialog(context: context, builder: (_) => SearchDialog(token: widget.token));
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    try {
      return DateFormat('HH:mm').format(DateTime.parse(iso).toLocal());
    } catch (e) {
      return '';
    }
  }
}

// -------- ПОИСК --------
class SearchDialog extends StatefulWidget {
  final String token;
  const SearchDialog({super.key, required this.token});

  @override
  _SearchDialogState createState() => _SearchDialogState();
}

class _SearchDialogState extends State<SearchDialog> {
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> results = [];

  Future<void> search() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    final response = await http.get(
      Uri.parse('http://localhost:8000/search_users?q=$q'),
      headers: {'Authorization': widget.token},
    );
    if (response.statusCode == 200) {
      setState(() => results = List<Map<String, dynamic>>.from(jsonDecode(response.body)));
    }
  }

  Future<void> sendRequest(int userId) async {
    await http.post(
      Uri.parse('http://localhost:8000/send_contact_request/$userId'),
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
          ElevatedButton(onPressed: search, child: const Text('Найти')),
          ...results.map((u) => ListTile(
            title: Text(u['username']),
            trailing: IconButton(
              icon: const Icon(Icons.person_add),
              onPressed: () => sendRequest(u['id']),
            ),
          )),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть'))],
    );
  }
}

// -------- ЭКРАН ЧАТА --------
class ChatScreen extends StatefulWidget {
  final int chatId;
  final String chatTitle;
  final String token;
  final WebSocketChannel? channel;
  const ChatScreen({
    super.key,
    required this.chatId,
    required this.chatTitle,
    required this.token,
    this.channel,
  });

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> messages = [];
  String? currentUserId;

  @override
  void initState() {
    super.initState();
    fetchCurrentUser();
    fetchMessages();
    widget.channel?.stream.listen((data) {
      final msg = jsonDecode(data);
      if (msg['type'] == 'message' && msg['chat_id'] == widget.chatId) {
        if (mounted) {
          setState(() {
            messages.add({
              'text': msg['text'],
              'is_own': msg['sender_id'].toString() == currentUserId,
              'created_at': msg['created_at'],
            });
          });
        }
      }
    });
  }

  Future<void> fetchCurrentUser() async {
    final response = await http.get(
      Uri.parse('http://localhost:8000/me'),
      headers: {'Authorization': widget.token},
    );
    if (response.statusCode == 200) {
      currentUserId = jsonDecode(response.body)['id'].toString();
    }
  }

  Future<void> fetchMessages() async {
    final response = await http.get(
      Uri.parse('http://localhost:8000/messages/${widget.chatId}'),
      headers: {'Authorization': widget.token},
    );
    if (response.statusCode == 200) {
      if (mounted) {
        setState(() => messages = List<Map<String, dynamic>>.from(jsonDecode(response.body)));
      }
    }
  }

  void sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.channel?.sink.add(jsonEncode({'chat_id': widget.chatId, 'text': text}));
    setState(() {
      messages.add({
        'text': text,
        'is_own': true,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.chatTitle)),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: messages.length,
              itemBuilder: (_, i) {
                final msg = messages[messages.length - 1 - i];
                final isMe = msg['is_own'];
                return MessageBubble(
                  text: msg['text'],
                  isMe: isMe,
                  time: msg['created_at'] != null ? DateTime.tryParse(msg['created_at']) : null,
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
                IconButton(icon: const Icon(Icons.attach_file), onPressed: () {}),
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

// -------- ПУЗЫРЁК СООБЩЕНИЯ --------
class MessageBubble extends StatelessWidget {
  final String text;
  final bool isMe;
  final DateTime? time;

  const MessageBubble({super.key, required this.text, required this.isMe, this.time});

  @override
  Widget build(BuildContext context) {
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}