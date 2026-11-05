import 'dart:convert';
import 'dart:io';
import 'package:source_runtime/control_protocol.dart' as wire;

/// Official Dart codec oracle for the TS/Dart golden interoperability test.
Future<void> main() async {
  try {
    await for (final line
        in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      final input = jsonDecode(line);
      if (input is! Map || input['type'] is! String) {
        throw const FormatException('Expected a typed ProtoJSON fixture');
      }
      final message = switch (input['type']) {
        'ControlRequest' => wire.ControlRequest(),
        'ControlResponse' => wire.ControlResponse(),
        'SourceCall' => wire.SourceCall(),
        'SourceResult' => wire.SourceResult(),
        'SourceInfo' => wire.SourceInfo(),
        'Manga' => wire.Manga(),
        'Chapter' => wire.Chapter(),
        'PageList' => wire.PageList(),
        'ImageResource' => wire.ImageResource(),
        'BuildManifest' => wire.BuildManifest(),
        'ExtensionIndex' => wire.ExtensionIndex(),
        'Bootstrap' => wire.Bootstrap(),
        'ImageFrameControl' => wire.ImageFrameControl(),
        'RuntimeHello' => wire.RuntimeHello(),
        'RuntimeSession' => wire.RuntimeSession(),
        'RuntimeError' => wire.RuntimeError(),
        'WorkerCommand' => wire.WorkerCommand(),
        'WorkerResponse' => wire.WorkerResponse(),
        'StateMutation' => wire.StateMutation(),
        'StateMutationResponse' => wire.StateMutationResponse(),
        'MangaStateResponse' => wire.MangaStateResponse(),
        'LibraryPageResponse' => wire.LibraryPageResponse(),
        'ChapterProgressPageResponse' => wire.ChapterProgressPageResponse(),
        'CategoryMutation' => wire.CategoryMutation(),
        'CategoryMutationResponse' => wire.CategoryMutationResponse(),
        'CategoryCatalogResponse' => wire.CategoryCatalogResponse(),
        _ => throw const FormatException('Unknown protocol fixture type'),
      };
      wire.decodeProtoJson(message, input['value']);
      stdout.writeln(
        jsonEncode(
          wire.encodeProtoJson(message, maxBytes: wire.controlJsonLimit),
        ),
      );
    }
  } catch (error) {
    stderr.writeln('Protocol fixture rejected: $error');
    exitCode = 1;
  }
}
