// Flutter Note Taking App using File Storage
// File: main.dart

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NotesApp());
}

class NotesApp extends StatelessWidget {
  const NotesApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notes App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const NotesList(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// Note model class
class Note {
  final String id;
  final String title;
  final String content;
  final String date;
  final int color;

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.date,
    required this.color,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'date': date,
      'color': color,
    };
  }

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'],
      title: json['title'],
      content: json['content'],
      date: json['date'],
      color: json['color'],
    );
  }
}

// File storage helper
class FileStorage {
  static Future<Directory> getNotesDirectory() async {
    // Get the documents directory
    final Directory? externalDir = await getExternalStorageDirectory();

    if (externalDir == null) {
      throw Exception('External storage directory not available');
    }

    // Create a "Notes" folder inside documents if it doesn't exist
    final Directory notesDir = Directory('${externalDir.path}/Notes');
    if (!await notesDir.exists()) {
      await notesDir.create(recursive: true);
    }

    return notesDir;
  }

  static Future<bool> requestPermissions() async {
    // For Android 10 and above (API level 29+), we don't need to request storage permission
    // when using getExternalStorageDirectory() as it returns the app-specific directory
    // For older versions, we still need to request storage permission
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;

      if (androidInfo.version.sdkInt >= 29) {
        // For Android 10+, we don't need explicit permission for app-specific storage
        return true;
      } else {
        // For older Android versions, request storage permission
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }
        return status.isGranted;
      }
    } else if (Platform.isIOS) {
      // iOS doesn't need explicit permission for app documents directory
      return true;
    }

    // Default fallback to requesting storage permission
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    return status.isGranted;
  }

  static Future<void> saveNote(Note note) async {
    if (!(await requestPermissions())) {
      throw Exception('Storage permission not granted');
    }

    final dir = await getNotesDirectory();
    final file = File('${dir.path}/${note.id}.json');
    await file.writeAsString(jsonEncode(note.toJson()));
  }

  static Future<List<Note>> loadNotes() async {
    if (!(await requestPermissions())) {
      throw Exception('Storage permission not granted');
    }

    final dir = await getNotesDirectory();
    final List<Note> notes = [];

    try {
      final List<FileSystemEntity> entities = await dir.list().toList();

      for (var entity in entities) {
        if (entity is File && entity.path.endsWith('.json')) {
          final content = await entity.readAsString();
          notes.add(Note.fromJson(jsonDecode(content)));
        }
      }
    } catch (e) {
      print('Error loading notes: $e');
    }

    // Sort notes by date (newest first)
    notes.sort(
        (a, b) => DateTime.parse(b.date).compareTo(DateTime.parse(a.date)));
    return notes;
  }

  static Future<void> deleteNote(String id) async {
    if (!(await requestPermissions())) {
      throw Exception('Storage permission not granted');
    }

    final dir = await getNotesDirectory();
    final file = File('${dir.path}/$id.json');

    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<void> exportAllNotes() async {
    if (!(await requestPermissions())) {
      throw Exception('Storage permission not granted');
    }

    final dir = await getNotesDirectory();
    final exportFile = File('${dir.path}/notes_export.json');

    final notes = await loadNotes();
    final jsonData = jsonEncode(notes.map((note) => note.toJson()).toList());

    await exportFile.writeAsString(jsonData);

    // Share the file
    await Share.shareXFiles([XFile(exportFile.path)], text: 'My Notes Export');
  }
}

// List of all notes
class NotesList extends StatefulWidget {
  const NotesList({Key? key}) : super(key: key);

  @override
  _NotesListState createState() => _NotesListState();
}

class _NotesListState extends State<NotesList> {
  late Future<List<Note>> _notesFuture;

  @override
  void initState() {
    super.initState();
    _refreshNotesList();
  }

  void _refreshNotesList() {
    setState(() {
      _notesFuture = FileStorage.loadNotes();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Notes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            onPressed: () async {
              try {
                await FileStorage.exportAllNotes();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Notes exported successfully')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error exporting notes: $e')),
                );
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<List<Note>>(
        future: _notesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No notes yet. Create one!'));
          } else {
            final notes = snapshot.data!;
            return ListView.builder(
              itemCount: notes.length,
              itemBuilder: (context, index) {
                final note = notes[index];
                return Dismissible(
                  key: Key(note.id),
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (direction) async {
                    return await showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: const Text('Delete Note'),
                          content: const Text(
                              'Are you sure you want to delete this note?'),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('Delete'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                  onDismissed: (direction) async {
                    await FileStorage.deleteNote(note.id);
                    _refreshNotesList();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Note deleted')),
                    );
                  },
                  child: Card(
                    color: Color(note.color),
                    margin:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: ListTile(
                      title: Text(
                        note.title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            note.content.length > 50
                                ? '${note.content.substring(0, 50)}...'
                                : note.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat('MMM dd, yyyy HH:mm')
                                .format(DateTime.parse(note.date)),
                            style: const TextStyle(
                                fontSize: 12, fontStyle: FontStyle.italic),
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => NoteEditor(
                              note: note,
                              onSave: (updatedNote) async {
                                await FileStorage.saveNote(updatedNote);
                                _refreshNotesList();
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            );
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => NoteEditor(
                onSave: (newNote) async {
                  await FileStorage.saveNote(newNote);
                  _refreshNotesList();
                },
              ),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

// Note editor for creating and editing notes
class NoteEditor extends StatefulWidget {
  final Note? note;
  final Function(Note) onSave;

  const NoteEditor({Key? key, this.note, required this.onSave})
      : super(key: key);

  @override
  _NoteEditorState createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late int _selectedColor;
  late List<Color> _availableColors;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController =
        TextEditingController(text: widget.note?.content ?? '');
    _selectedColor = widget.note?.color ?? Colors.white.value;
    _availableColors = [
      Colors.white,
      Colors.yellow.shade100,
      Colors.lightBlue.shade100,
      Colors.lightGreen.shade100,
      Colors.orange.shade100,
      Colors.pink.shade100,
    ];
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note == null ? 'New Note' : 'Edit Note'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveNote,
          ),
          PopupMenuButton<int>(
            icon: const Icon(Icons.color_lens),
            onSelected: (colorValue) {
              setState(() {
                _selectedColor = colorValue;
              });
            },
            itemBuilder: (context) {
              return _availableColors
                  .map(
                    (color) => PopupMenuItem<int>(
                      value: color.value,
                      child: Container(
                        color: color,
                        height: 30,
                        width: 100,
                      ),
                    ),
                  )
                  .toList();
            },
          ),
        ],
      ),
      body: Container(
        color: Color(_selectedColor),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                hintText: 'Title',
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(8),
              ),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            Expanded(
              child: TextField(
                controller: _contentController,
                decoration: const InputDecoration(
                  hintText: 'Note content',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(8),
                ),
                maxLines: null,
                expands: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveNote() {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title')),
      );
      return;
    }

    final now = DateTime.now();
    final note = Note(
      id: widget.note?.id ?? '${now.millisecondsSinceEpoch}',
      title: _titleController.text,
      content: _contentController.text,
      date: now.toIso8601String(),
      color: _selectedColor,
    );

    widget.onSave(note);
    Navigator.pop(context);
  }
}
