import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'package:reader_app/features/library/data/models/book.dart';
import 'package:reader_app/features/library/data/models/imported_book.dart';

/// 书籍解析入口。
///
/// 第一版支持标准无 DRM EPUB，以及 TXT / Markdown 纯文本文件。解析器输出统一章节模型，
/// 上层书库和阅读页不需要关心原始文件格式。
class BookParserService {
  const BookParserService();

  /// 解析指定文件。
  Future<ImportedBook> parse(String filePath) async {
    final extension = p.extension(filePath).toLowerCase();

    return switch (extension) {
      '.epub' => _parseEpub(filePath),
      '.txt' || '.md' || '.markdown' => _parseText(filePath),
      _ => throw UnsupportedError('暂不支持 $extension 文件，请导入 EPUB、TXT 或 Markdown。'),
    };
  }

  Future<ImportedBook> _parseText(String filePath) async {
    final file = File(filePath);
    final raw = await file.readAsString();
    final normalized = _normalizeText(raw);
    final title = _titleFromPath(filePath);
    final chapters = _splitTextIntoChapters(normalized);

    return ImportedBook(
      title: title,
      author: '未知作者',
      format: BookFormat.text,
      chapters: chapters,
    );
  }

  Future<ImportedBook> _parseEpub(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final containerFile = _findArchiveFile(archive, 'META-INF/container.xml');
    if (containerFile == null) {
      throw const FormatException('EPUB 缺少 META-INF/container.xml。');
    }

    final containerXml = _decodeArchiveText(containerFile);
    final container = XmlDocument.parse(containerXml);
    final rootFilePath = _firstOrNull(
      container
          .findAllElements('rootfile')
          .map((node) => node.getAttribute('full-path'))
          .whereType<String>(),
    );
    if (rootFilePath == null || rootFilePath.isEmpty) {
      throw const FormatException('EPUB 未声明 OPF 文件路径。');
    }

    final opfFile = _findArchiveFile(archive, rootFilePath);
    if (opfFile == null) {
      throw FormatException('EPUB 找不到 OPF 文件：$rootFilePath');
    }

    final opfXml = _decodeArchiveText(opfFile);
    final opf = XmlDocument.parse(opfXml);
    final title = _firstMetadataText(opf, 'title') ?? _titleFromPath(filePath);
    final author = _firstMetadataText(opf, 'creator') ?? '未知作者';
    final manifest = _readManifest(opf);
    final spineIds = opf.findAllElements('itemref').map((node) {
      return node.getAttribute('idref');
    }).whereType<String>();

    final opfDirectory = p.posix.dirname(rootFilePath);
    final chapters = <ImportedChapter>[];

    for (final spineId in spineIds) {
      final href = manifest[spineId];
      if (href == null || href.isEmpty) continue;

      final chapterPath = _normalizeArchivePath(
        opfDirectory == '.' ? href : p.posix.join(opfDirectory, href),
      );
      final chapterFile = _findArchiveFile(archive, chapterPath);
      if (chapterFile == null) continue;

      final html = _decodeArchiveText(chapterFile);
      final document = html_parser.parse(html);
      final parsedTitle = document.querySelector('title')?.text.trim();
      final hTitle = document.querySelector('h1,h2,h3')?.text.trim();
      final content = _normalizeText(document.body?.text ?? document.documentElement?.text ?? '');
      if (content.isEmpty) continue;

      chapters.add(
        ImportedChapter(
          title: _cleanTitle(hTitle ?? parsedTitle) ?? '章节 ${chapters.length + 1}',
          content: content,
        ),
      );
    }

    if (chapters.isEmpty) {
      throw const FormatException('未能从 EPUB 中解析出可阅读章节。');
    }

    return ImportedBook(
      title: _cleanTitle(title) ?? _titleFromPath(filePath),
      author: _cleanTitle(author) ?? '未知作者',
      format: BookFormat.epub,
      chapters: chapters,
    );
  }

  ArchiveFile? _findArchiveFile(Archive archive, String path) {
    final normalized = _normalizeArchivePath(path);
    for (final file in archive.files) {
      if (_normalizeArchivePath(file.name) == normalized) {
        return file;
      }
    }
    return null;
  }

  String _decodeArchiveText(ArchiveFile file) {
    final content = file.content;
    if (content is List<int>) {
      return utf8.decode(content, allowMalformed: true);
    }
    throw FormatException('无法读取 EPUB 文件内容：${file.name}');
  }

  Map<String, String> _readManifest(XmlDocument opf) {
    final result = <String, String>{};
    for (final item in opf.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id != null && href != null) {
        result[id] = href;
      }
    }
    return result;
  }

  String? _firstMetadataText(XmlDocument opf, String localName) {
    for (final element in opf.descendantElements) {
      if (element.name.local == localName) {
        final text = element.innerText.trim();
        if (text.isNotEmpty) return text;
      }
    }
    return null;
  }

  List<ImportedChapter> _splitTextIntoChapters(String content) {
    if (content.isEmpty) {
      return const [ImportedChapter(title: '正文', content: '这个文档没有可读取的文字内容。')];
    }

    final headings = RegExp(r'(^|\n)\s*(第.{1,12}[章节回].*|Chapter\s+\d+.*)\n');
    final matches = headings.allMatches(content).toList();
    if (matches.length >= 2) {
      final chapters = <ImportedChapter>[];
      for (var i = 0; i < matches.length; i += 1) {
        final start = matches[i].start;
        final end = i + 1 < matches.length ? matches[i + 1].start : content.length;
        final block = content.substring(start, end).trim();
        final lines = block.split('\n');
        final title = lines.first.trim().isEmpty ? '章节 ${i + 1}' : lines.first.trim();
        chapters.add(ImportedChapter(title: title, content: block));
      }
      return chapters;
    }

    const chunkSize = 7000;
    final chapters = <ImportedChapter>[];
    for (var start = 0; start < content.length; start += chunkSize) {
      final end = start + chunkSize > content.length ? content.length : start + chunkSize;
      chapters.add(
        ImportedChapter(
          title: chapters.isEmpty ? '正文' : '正文 ${chapters.length + 1}',
          content: content.substring(start, end).trim(),
        ),
      );
    }
    return chapters;
  }

  T? _firstOrNull<T>(Iterable<T> values) {
    final iterator = values.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }

  String _normalizeArchivePath(String path) {
    return p.posix.normalize(path).replaceFirst(RegExp(r'^\./'), '');
  }

  String _normalizeText(String value) {
    final normalized = value
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isEmpty || !_isNoiseLine(line))
        .join('\n');

    return normalized.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  bool _isNoiseLine(String value) {
    return RegExp(r'^[\s\p{P}\p{S}]+$', unicode: true).hasMatch(value);
  }

  String _titleFromPath(String filePath) {
    return p.basenameWithoutExtension(filePath).trim();
  }

  String? _cleanTitle(String? value) {
    final text = value?.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }
}
