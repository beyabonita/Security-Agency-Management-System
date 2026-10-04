import 'package:file_picker/file_picker.dart';
import '../models/accomplishment_photo.dart';

class AccomplishmentPhotoPicker {
  static Future<AccomplishmentPhoto?> pick() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Choose finished photo report',
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png'],
    );
    if (file == null) return null;
    return AccomplishmentPhoto.read(
      name: file.name,
      reportedSize: file.lengthSync(),
      chunks: file.readAsByteStream(),
    );
  }
}
