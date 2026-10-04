#ifndef XF_ATC_ZIP_H
#define XF_ATC_ZIP_H
#include <stddef.h>
#include <stdint.h>
/* Store-only StreamingZip archive with a fixed directory marker, never app data.
   Caller owns *out_bytes (free). */
int xf_atc_build_directory_zip(const char *target_tail, const uint8_t *metadata,
                               size_t metadata_len, uint8_t **out_bytes,
                               size_t *out_len);
#endif
