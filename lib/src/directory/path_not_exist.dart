library;

import 'directory_exception.dart';

class PathNotExist extends DirectoryException {
  PathNotExist([super.message = "Path does not exist", super.cause]);
}
