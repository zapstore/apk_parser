library;

import 'directory_exception.dart';

class PathAlreadyExists extends DirectoryException {
  PathAlreadyExists([super.message = "Path already exists", super.cause]);
}
