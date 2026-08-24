class IncidentVideoFormat {
  const IncidentVideoFormat._();

  static const int maxBytes = 15 * 1024 * 1024;
  static const Set<String> allowedContentTypes = {
    'video/mp4',
    'video/webm',
    'video/quicktime',
  };

  static String contentTypeFor({String? reportedMimeType, String? fileName}) {
    final normalized = reportedMimeType?.split(';').first.trim().toLowerCase();
    if (normalized != null && allowedContentTypes.contains(normalized)) {
      return normalized;
    }
    if (normalized == 'video/x-m4v' || normalized == 'video/m4v') {
      return 'video/mp4';
    }

    final path = (fileName ?? '').toLowerCase().split('?').first;
    if (path.endsWith('.webm')) return 'video/webm';
    if (path.endsWith('.mov') || path.endsWith('.qt')) {
      return 'video/quicktime';
    }
    return 'video/mp4';
  }

  static String extensionFor(String contentType) {
    return switch (contentTypeFor(reportedMimeType: contentType)) {
      'video/webm' => 'webm',
      'video/quicktime' => 'mov',
      _ => 'mp4',
    };
  }
}
