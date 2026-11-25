import 'dart:typed_data';

import '../constants.dart';

/// Length-prefixed binary frame encoder/decoder shared by TCP LAN, USB, and Bluetooth.
///
/// Format: [4-byte big-endian uint32 length][payload bytes]
class FrameCodec {
  FrameCodec._();

  static Uint8List encode(Uint8List payload) {
    if (payload.length > AppConstants.maxFrameBytes) {
      throw ArgumentError('Frame exceeds max size (${payload.length} bytes)');
    }
    final out = Uint8List(4 + payload.length);
    final view = ByteData.sublistView(out);
    view.setUint32(0, payload.length, Endian.big);
    out.setRange(4, out.length, payload);
    return out;
  }
}

/// Incremental stream decoder for length-prefixed frames.
class FrameStreamDecoder {
  FrameStreamDecoder({
    this.maxFrameBytes = AppConstants.maxFrameBytes,
  });

  final int maxFrameBytes;
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  /// Appends raw socket bytes and returns zero or more complete frame payloads.
  List<Uint8List> addChunk(List<int> chunk) {
    if (chunk.isNotEmpty) {
      _buffer.add(chunk);
    }

    final frames = <Uint8List>[];
    var bytes = _buffer.takeBytes();
    var offset = 0;

    while (bytes.length - offset >= 4) {
      final view = ByteData.sublistView(bytes, offset, offset + 4);
      final length = view.getUint32(0, Endian.big);

      if (length == 0 || length > maxFrameBytes) {
        throw FormatException('Invalid frame length: $length');
      }

      if (bytes.length - offset < 4 + length) {
        break;
      }

      frames.add(Uint8List.fromList(
        bytes.sublist(offset + 4, offset + 4 + length),
      ));
      offset += 4 + length;
    }

    if (offset < bytes.length) {
      _buffer.add(bytes.sublist(offset));
    }

    return frames;
  }

  void clear() {
    _buffer.clear();
  }
}
