import 'package:file_picker/file_picker.dart';
import '../models/request_letter.dart';

class RequestLetterPicker {
  RequestLetterPicker._();

  static Future<RequestLetter?> pick() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Attach absence or swap letter',
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (file == null) return null;
    return RequestLetter.read(
      name: file.name,
      reportedSize: file.lengthSync(),
      chunks: file.readAsByteStream(),
    );
  }
}
