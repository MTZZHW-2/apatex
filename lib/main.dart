import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'apatex',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _selectedFileName = '选择文件';
  String _revealResult = '';
  String _selectedFilePath = '';
  String _savedDirectoryPath = '';

  @override
  void initState() {
    super.initState();
    _requestManageExternalStoragePermission();
    _loadSavedDirectoryPath();
  }

  Future<void> _requestManageExternalStoragePermission() async {
    final PermissionStatus status =
        await Permission.manageExternalStorage.status;

    if (!status.isGranted && mounted) {
      final bool? shouldRequest = await showDialog(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('需要所有文件访问权限'),
          content: const Text('应用需要该权限来保存文件，请授予权限。'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: const Text('授予权限'),
            ),
          ],
        ),
      );

      if (shouldRequest == true) {
        await Permission.manageExternalStorage.request();
      }
    }
  }

  Future<void> _loadSavedDirectoryPath() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? path = prefs.getString('savedDirectoryPath');

    if (path == null && mounted) {
      final bool confirm = await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('选择还原后的保存路径'),
            content: const Text('因权限问题需手动选择一个文件夹作为还原后文件的保存路径。'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('选择'),
              ),
            ],
          );
        },
      );

      if (confirm) {
        _selectSaveDirectoryPath();
      }

      return;
    }

    setState(() {
      _savedDirectoryPath = path ?? '';
    });
  }

  Future<void> _selectSaveDirectoryPath() async {
    final String? directoryPath = await FilePicker.platform.getDirectoryPath();
    if (directoryPath != null) {
      setState(() {
        _savedDirectoryPath = directoryPath;
      });

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('savedDirectoryPath', directoryPath);
    }
  }

  Future<void> _pickFile() async {
    setState(() {
      _selectedFileName = '加载文件中 ...';
      _selectedFilePath = '';
      _revealResult = '';
    });

    final FilePickerResult? result =
        await FilePicker.platform.pickFiles(allowMultiple: false);

    if (result != null) {
      setState(() {
        _selectedFileName = result.files.single.name;
        _selectedFilePath = result.files.single.path ?? '';
      });
      setState(() {
        _revealResult = '就绪';
      });
    } else {
      setState(() {
        _selectedFileName = '选择文件';
      });
    }
  }

  int maskLengthIndicatorLength = 4;

  Future<void> _revealFile(String filePath, String savedDirectoryPath) async {
    final PermissionStatus status =
        await Permission.manageExternalStorage.status;
    if (!status.isGranted) {
      setState(() {
        _revealResult = '权限不足';
      });
      return;
    }
    if (filePath == '') {
      setState(() {
        _revealResult = '未选择文件';
      });
      return;
    }
    if (savedDirectoryPath == '') {
      setState(() {
        _revealResult = '未选择保存目录';
      });
      return;
    }

    setState(() {
      _revealResult = '还原中 ...';
    });

    final File file = File(filePath);
    final RandomAccessFile raf = await file.open(mode: FileMode.read);
    final RandomAccessFile rafRead = await file.open(mode: FileMode.read);

    try {
      final int fileLength = await file.length();

      await raf.setPosition(fileLength - maskLengthIndicatorLength);
      final Uint8List byteLength = await raf.read(maskLengthIndicatorLength);
      final int maskHeadLength =
          ByteData.sublistView(byteLength).getInt32(0, Endian.little);
      await raf.close();

      Uint8List originalHead;
      final int originalHeadPosition =
          fileLength - maskLengthIndicatorLength - maskHeadLength;

      if (maskHeadLength <= originalHeadPosition) {
        await rafRead.setPosition(originalHeadPosition);
        originalHead = await rafRead.read(maskHeadLength);
      } else {
        await rafRead.setPosition(maskHeadLength);
        originalHead = await rafRead.read(originalHeadPosition);
      }
      await rafRead.close();

      final String fileName = filePath.substring(
          filePath.lastIndexOf('/') + 1, filePath.lastIndexOf('.'));
      final String saveFilePath = '$savedDirectoryPath/$fileName';

      final File outputFile = await File(saveFilePath).create();
      final RandomAccessFile rafWrite =
          await outputFile.open(mode: FileMode.write);
      final File originalContent = await file.writeAsBytes(await file
          .readAsBytes()
          .then((Uint8List bytes) => bytes.sublist(0, originalHeadPosition)));
      await rafWrite.writeFrom(await originalContent.readAsBytes());
      await rafWrite.setPosition(0);
      await rafWrite.writeFrom(originalHead.reversed.toList());
      await rafWrite.close();

      setState(() {
        _revealResult = '文件还原成功';
      });
    } catch (error) {
      print(error);
      setState(() {
        _revealResult = '文件还原失败: $error';
      });
    } finally {
      await raf.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Card(
              color: theme.colorScheme.primary,
              child: InkWell(
                onTap: _pickFile,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 20,
                  ),
                  child: Text(
                    _selectedFileName,
                    style: TextStyle(
                      color: theme.colorScheme.onPrimary,
                      fontSize: 24,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                await _revealFile(_selectedFilePath, _savedDirectoryPath);
              },
              child: const Text('还原'),
            ),
            const SizedBox(height: 16),
            Text(_revealResult),
            const SizedBox(height: 16),
            InkWell(
              onTap: _selectSaveDirectoryPath,
              child: Text('保存路径：$_savedDirectoryPath'),
            ),
          ],
        ),
      ),
    );
  }
}
