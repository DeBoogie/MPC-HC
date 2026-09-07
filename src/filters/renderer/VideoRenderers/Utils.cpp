#include "stdafx.h"
#include <memory>

#include "Utils.h"

bool RetrieveBitmapData(unsigned w, unsigned h, unsigned bpp, BYTE* dst, BYTE* src, int srcpitch) {
    unsigned linesize = w * bpp / 8;
    if ((int)linesize > srcpitch) {
        return false;
    }

    src += srcpitch * (h - 1);

    for (unsigned y = 0; y < h; ++y) {
        memcpy(dst, src, linesize);
        src -= srcpitch;
        dst += linesize;
    }

    return true;
}
