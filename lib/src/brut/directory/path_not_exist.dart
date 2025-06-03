library brut_directory;

import 'directory_exception.dart';

class PathNotExist extends DirectoryException {
  PathNotExist([String message = "Path does not exist", Object? cause])
    : super(message, cause);
}
