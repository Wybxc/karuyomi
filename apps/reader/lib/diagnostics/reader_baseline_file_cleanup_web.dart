import 'package:web/web.dart' as web;

// cross_file owns the download implementation but has no URL disposal API.
void releaseBaselineDownload(String path) => web.URL.revokeObjectURL(path);
