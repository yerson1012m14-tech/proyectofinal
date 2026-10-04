#ifndef XF_FILE_SERVICE_LISTING_H
#define XF_FILE_SERVICE_LISTING_H

#include <stdbool.h>
#include <stddef.h>

/* Borrowed UTF-8 view: bytes must outlive this result. No allocation or I/O.
 * A false directoryByDescendant means that the entry's type is unknown.
 * A nested entry such as "Library/Caches/file" proves "Library" is a folder.
 */
typedef struct {
    const char *name;
    size_t nameLength;
    bool directoryByDescendant;
} XFFileServiceListingPath;

static inline bool XFFileServiceListingUTF8Valid(const char *bytes, size_t length) {
    const unsigned char *text = (const unsigned char *)bytes;
    size_t offset = 0;
    while (offset < length) {
        unsigned char first = text[offset];
        if (first == 0) return false;
        if (first < 0x80) {
            ++offset;
            continue;
        }
        size_t width;
        if (first >= 0xc2 && first <= 0xdf) width = 2;
        else if (first >= 0xe0 && first <= 0xef) width = 3;
        else if (first >= 0xf0 && first <= 0xf4) width = 4;
        else return false;
        if (length - offset < width) return false;
        for (size_t index = 1; index < width; ++index) {
            unsigned char next = text[offset + index];
            if (next < 0x80 || next > 0xbf) return false;
        }
        unsigned char second = text[offset + 1];
        if ((first == 0xe0 && second < 0xa0) ||
            (first == 0xed && second > 0x9f) ||
            (first == 0xf0 && second < 0x90) ||
            (first == 0xf4 && second > 0x8f)) return false;
        offset += width;
    }
    return true;
}

/* Reject absolute paths, NULs and empty, "." or ".." components.
 * length excludes a C string's terminator. Root "." is deliberately omitted.
 * Only '/' separates components; backslashes are ordinary iOS filename bytes.
 * Validate the entire path before exposing its first component.
 */
static inline bool XFFileServiceListingParsePath(const char *bytes, size_t length,
                                                XFFileServiceListingPath *out) {
    if (out) {
        out->name = NULL;
        out->nameLength = 0;
        out->directoryByDescendant = false;
    }
    if (!out || !bytes || !length || bytes[0] == '/' ||
        !XFFileServiceListingUTF8Valid(bytes, length)) return false;

    size_t start = 0, firstLength = 0;
    bool descendant = false;
    for (;;) {
        size_t end = start;
        while (end < length && bytes[end] != '/') ++end;
        size_t componentLength = end - start;
        if (!componentLength ||
            (componentLength == 1 && bytes[start] == '.') ||
            (componentLength == 2 && bytes[start] == '.' && bytes[start + 1] == '.'))
            return false;
        if (start == 0) firstLength = componentLength;
        if (end == length) break;
        descendant = true;
        start = end + 1;
    }
    out->name = bytes;
    out->nameLength = firstLength;
    out->directoryByDescendant = descendant;
    return true;
}

#endif
