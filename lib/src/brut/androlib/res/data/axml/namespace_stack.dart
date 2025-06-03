library brut_androlib_res_data_axml;

import 'dart:typed_data'; // For Int32List if more performant, but List<int> is fine.

class NamespaceStack {
  List<int> _data;
  int _dataLength;
  int _depth;

  NamespaceStack()
    : _data = List<int>.filled(
        32,
        0,
        growable: true,
      ), // growable to mimic dynamic array
      _dataLength = 0,
      _depth = 0;

  void reset() {
    _dataLength = 0;
    _depth = 0;
    // Optionally, re-initialize _data if it grew very large and want to shrink it.
    // _data = List<int>.filled(32, 0, growable: true);
  }

  int getCurrentCount() {
    if (_dataLength == 0) {
      return 0;
    }
    int offset = _dataLength - 1;
    return _data[offset];
  }

  int getAccumulatedCount(int depth) {
    if (_dataLength == 0 || depth < 0) {
      return 0;
    }
    if (depth > _depth) {
      depth = _depth;
    }
    int accumulatedCount = 0;
    int offset = 0;
    for (; depth != 0; --depth) {
      int count = _data[offset];
      accumulatedCount += count;
      offset += (2 + count * 2);
    }
    return accumulatedCount;
  }

  void push(int prefix, int uri) {
    if (_depth == 0) {
      increaseDepth();
    }
    _ensureDataCapacity(2);
    int offset = _dataLength - 1;
    int count = _data[offset];
    _data[offset - 1 - count * 2] = count + 1;
    _data[offset] = prefix;
    _data[offset + 1] = uri;
    _data[offset + 2] = count + 1;
    _dataLength += 2;
  }

  bool pop() {
    if (_dataLength == 0) {
      return false;
    }
    int offset = _dataLength - 1;
    int count = _data[offset];
    if (count == 0) {
      return false;
    }
    count -= 1;
    offset -= 2;
    _data[offset] = count;
    offset -= (1 + count * 2);
    _data[offset] = count;
    _dataLength -= 2;
    return true;
  }

  int getPrefix(int index) {
    return _get(index, true);
  }

  int getUri(int index) {
    return _get(index, false);
  }

  int findPrefix(int uri) {
    return _find(uri, false);
  }

  // Not in Java, but might be useful
  int findUri(int prefix) {
    return _find(prefix, true);
  }

  int getDepth() {
    return _depth;
  }

  void increaseDepth() {
    _ensureDataCapacity(2);
    int offset = _dataLength;
    _data[offset] = 0;
    _data[offset + 1] = 0;
    _dataLength += 2;
    _depth += 1;
  }

  void decreaseDepth() {
    if (_dataLength == 0) {
      return;
    }
    int offset = _dataLength - 1;
    int count = _data[offset];
    if ((offset - 1 - count * 2) == 0 && _depth != 1) {
      // _depth check added
      // This condition from Java seems to imply we shouldn't decrease depth
      // if it's the very first frame and it's empty.
      // However, it might also prevent popping the last actual depth frame if it was the root.
      // If depth is 1, it means it is the root, and we should be able to pop it.
      // Original: if ((offset - 1 - count * 2) == 0)
      return;
    }
    _dataLength -= (2 + count * 2);
    _depth -= 1;
    if (_depth < 0) _depth = 0; // Ensure depth doesn't go negative
    if (_dataLength < 0) _dataLength = 0; // Ensure length doesn't go negative
  }

  void _ensureDataCapacity(int capacity) {
    int available = (_data.length - _dataLength);
    if (available >= capacity) {
      // Changed > to >=
      return;
    }
    // Grow list. Java uses (mData.length + available) * 2, which is just mData.length * 2
    int newLength = _data.length * 2;
    if (newLength < _dataLength + capacity) {
      newLength = _dataLength + capacity + 10; // Ensure enough space + buffer
    }
    List<int> newData = List<int>.filled(newLength, 0, growable: true);
    for (int i = 0; i < _dataLength; ++i) {
      newData[i] = _data[i];
    }
    _data = newData;
  }

  // if prefix is true, find uri for prefix; if false, find prefix for uri
  int _find(int valueToFind, bool findUriForPrefix) {
    if (_dataLength == 0) {
      return -1;
    }
    int offset = _dataLength - 1;
    for (int i = _depth; i != 0; --i) {
      int count = _data[offset];
      offset -=
          2; // Point to last uri in frame or (count-1)*2 elements before that
      for (; count != 0; --count) {
        int prefixInStack = _data[offset];
        int uriInStack = _data[offset + 1];
        if (findUriForPrefix) {
          // we are looking for uri, valueToFind is prefix
          if (prefixInStack == valueToFind) {
            return uriInStack;
          }
        } else {
          // we are looking for prefix, valueToFind is uri
          if (uriInStack == valueToFind) {
            return prefixInStack;
          }
        }
        offset -= 2;
      }
    }
    return -1;
  }

  int _get(int index, bool isPrefix) {
    if (_dataLength == 0 || index < 0) {
      return -1;
    }
    int currentDepthOffset = 0;
    // Iterate through depth frames from the outermost
    for (int i = 0; i < _depth; ++i) {
      // Changed from mDepth down to 0, to 0 up to mDepth
      int countInFrame = _data[currentDepthOffset];
      if (index < countInFrame) {
        // Found in this frame
        int itemBase =
            currentDepthOffset + 1; // Skip count, point to first prefix
        int itemOffset = itemBase + (index * 2);
        return _data[isPrefix ? itemOffset : itemOffset + 1];
      }
      index -= countInFrame;
      currentDepthOffset += (2 + countInFrame * 2); // Move to next frame
    }
    return -1; // Index out of bounds across all frames
  }
}
