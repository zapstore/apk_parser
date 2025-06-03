library;

import 'dart:async';
import 'dart:io' as dart_io;
import 'dart:typed_data';
import 'apktool_io_exception.dart';

abstract class Directory {
  static const String separator = '/';

  Set<String> getFiles({bool recursive = false});
  Map<String, Directory> getDirs({bool recursive = false});

  bool containsFile(String path);
  bool containsDir(String path);

  Future<AbstractInputStream> getFileInput(String path);
  Future<AbstractOutputStream> getFileOutput(String path);

  Future<Directory> getDir(String path);
  Future<Directory> createDir(String path);

  Future<bool> removeFile(String path);

  Future<void> copyToDir(Directory out);
  Future<void> copyToDirPaths(Directory out, List<String> fileNames);
  Future<void> copyToDirPath(Directory out, String fileName);

  Future<void> copyToDirFile(dart_io.File out);
  Future<void> copyToDirFilePaths(dart_io.File out, List<String> fileNames);
  Future<void> copyToDirFilePath(dart_io.File out, String fileName);

  Future<int> getSize(String fileName);
  Future<int> getCompressedSize(String fileName);
  Future<int> getCompressionLevel(String fileName);

  Future<void> close();
}

// Define abstract base classes for streams to allow for different implementations (e.g., memory, file)

abstract class AbstractInputStream {
  Future<int> read(Uint8List buffer, int offset, int length);
  Stream<List<int>> asStream();
  Future<void> close();
  bool get isClosed;
}

abstract class AbstractOutputStream {
  Future<void> write(List<int> buffer, [int offset = 0, int? length]);
  Future<void> flush();
  Future<void> close();
  bool get isClosed;
}

// Concrete implementation for streams based on dart:io (for file-based operations later)
class DartFileStreamInput extends AbstractInputStream {
  final Stream<List<int>> _stream;
  // TODO: Actual implementation for read, close, etc. based on a file stream.
  // This will likely involve a StreamIterator or consuming the stream carefully.
  bool _isClosed = false;

  DartFileStreamInput(String filePath)
    : _stream = dart_io.File(filePath).openRead();

  @override
  Future<int> read(Uint8List buffer, int offset, int length) async {
    if (_isClosed) throw ApktoolIOException('Stream is closed.');
    try {
      final chunk = await _stream.first;
      if (chunk.isEmpty) return -1;
      int bytesToCopy = length;
      if (bytesToCopy > chunk.length) bytesToCopy = chunk.length;
      if (offset + bytesToCopy > buffer.length) {
        bytesToCopy = buffer.length - offset;
      }
      buffer.setRange(
        offset,
        offset + bytesToCopy,
        chunk.sublist(0, bytesToCopy),
      );
      return bytesToCopy;
    } catch (e) {
      if (e is StateError) return -1;
      rethrow;
    }
  }

  @override
  Stream<List<int>> asStream() => _stream;

  @override
  Future<void> close() async {
    _isClosed = true;
  }

  @override
  bool get isClosed => _isClosed;
}

class DartFileStreamOutput extends AbstractOutputStream {
  final dart_io.IOSink _sink;
  bool _isClosed = false;

  DartFileStreamOutput(
    String filePath, {
    dart_io.FileMode mode = dart_io.FileMode.write,
  }) : _sink = dart_io.File(filePath).openWrite(mode: mode);

  @override
  Future<void> write(List<int> buffer, [int offset = 0, int? length]) async {
    if (_isClosed) throw ApktoolIOException('Stream is closed.');
    _sink.add(
      buffer.sublist(offset, length != null ? offset + length : buffer.length),
    );
  }

  @override
  Future<void> flush() async {
    if (_isClosed) throw ApktoolIOException('Stream is closed.');
    await _sink.flush();
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    await _sink.flush();
    await _sink.close();
  }

  @override
  bool get isClosed => _isClosed;
}

// Example of an in-memory input stream
class MemoryInputStream extends AbstractInputStream {
  final Uint8List _data;
  int _currentPosition = 0;
  bool _isClosed = false;

  MemoryInputStream(this._data);

  @override
  Future<int> read(Uint8List buffer, int offset, int length) async {
    if (_isClosed) throw ApktoolIOException('Stream is closed.');
    if (_currentPosition >= _data.length) return -1;

    int bytesToRead = length;
    if (_currentPosition + bytesToRead > _data.length) {
      bytesToRead = _data.length - _currentPosition;
    }
    if (bytesToRead <= 0) return -1;

    buffer.setRange(
      offset,
      offset + bytesToRead,
      _data.sublist(_currentPosition, _currentPosition + bytesToRead),
    );
    _currentPosition += bytesToRead;
    return bytesToRead;
  }

  @override
  Stream<List<int>> asStream() =>
      Stream.fromIterable([_data.sublist(_currentPosition)]);

  @override
  Future<void> close() async {
    _isClosed = true;
  }

  @override
  bool get isClosed => _isClosed;
}
