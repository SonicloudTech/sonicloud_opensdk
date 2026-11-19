/// 原始传输字节数校验，不包含 WAV/Ogg 容器或解码后的 PCM 数据。
class FileTransferSizeCheck {
  const FileTransferSizeCheck({
    required this.fileName,
    required this.receivedBytes,
    required this.expectedBytes,
  });

  final String fileName;
  final int receivedBytes;
  final int? expectedBytes;

  bool? get matches =>
      expectedBytes == null ? null : receivedBytes == expectedBytes;
}
