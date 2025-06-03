library brut_directory;

import 'directory_exception.dart';

class PathAlreadyExists extends DirectoryException {
  PathAlreadyExists([String message = "Path already exists", Object? cause])
    : super(message, cause);
}
