/// TXT is decoded as one string; illustrated EPUBs are read entry by entry.
const maxLocalTextBytes = 40 * 1024 * 1024;
const maxLocalEpubBytes = 256 * 1024 * 1024;

int localBookByteLimit(String name) => name.toLowerCase().endsWith('.epub')
    ? maxLocalEpubBytes
    : maxLocalTextBytes;

String localBookSizeMessage(String name) => name.toLowerCase().endsWith('.epub')
    ? '单本 EPUB 不能超过 256 MiB'
    : '单本 TXT 不能超过 40 MiB';
