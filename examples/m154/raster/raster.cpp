// First real render with Skia m154 on AROS ABIv11: CPU raster backend only.
// Draws known shapes and text, checks pixels it can predict, and writes the
// frame as PNG through Skia's own encoder.
//
//   raster <font.ttf> <out.png>
#include <cstdio>

#include "include/core/SkCanvas.h"
#include "include/core/SkColorSpace.h"
#include "include/core/SkData.h"
#include "include/core/SkFont.h"
#include "include/core/SkFontMgr.h"
#include "include/core/SkPaint.h"
#include "include/core/SkPath.h"
#include "include/core/SkPathBuilder.h"
#include "include/core/SkStream.h"
#include "include/core/SkSurface.h"
#include "include/core/SkTypeface.h"
#include "include/effects/SkGradient.h"
#include "include/encode/SkPngEncoder.h"
#include "include/ports/SkFontMgr_empty.h"

static int fails;
static void check(const char* name, bool ok) {
    std::printf("%s %s\n", ok ? "PASS" : "FAIL", name);
    fails += !ok;
}

int main(int argc, char** argv) {
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    if (argc < 3) { std::printf("usage: raster <font.ttf> <out.png>\n"); return 20; }

    sk_sp<SkSurface> surface = SkSurfaces::Raster(SkImageInfo::MakeN32Premul(256, 256));
    check("raster surface", surface != nullptr);
    if (!surface) return 20;
    SkCanvas* c = surface->getCanvas();
    c->clear(SK_ColorWHITE);

    // Solid block: exact colour is predictable.
    SkPaint solid; solid.setColor(SkColorSetRGB(0x20, 0x40, 0xC0));
    c->drawRect(SkRect::MakeXYWH(8, 8, 48, 48), solid);

    // Linear gradient strip, left red to right blue.
    SkPoint pts[2] = {{0, 0}, {256, 0}};
    SkColor4f cols[2] = {SkColors::kRed, SkColors::kBlue};
    SkPaint grad;
    SkGradient g(SkGradient::Colors(SkSpan<const SkColor4f>(cols, 2), SkTileMode::kClamp), {});
    grad.setShader(SkShaders::LinearGradient(pts, g));
    c->drawRect(SkRect::MakeXYWH(0, 64, 256, 32), grad);

    // Anti-aliased circle and a stroked path.
    SkPaint aa; aa.setAntiAlias(true); aa.setColor(SkColorSetRGB(0x10, 0xA0, 0x30));
    c->drawCircle(192, 32, 24, aa);
    SkPaint stroke; stroke.setAntiAlias(true); stroke.setStyle(SkPaint::kStroke_Style);
    stroke.setStrokeWidth(4); stroke.setColor(SK_ColorBLACK);
    SkPathBuilder pb; pb.moveTo(16, 200); pb.cubicTo(80, 120, 176, 280, 240, 200);
    c->drawPath(pb.detach(), stroke);

    // Text through FreeType, from a font file (no system font manager).
    sk_sp<SkFontMgr> mgr = SkFontMgr_New_Custom_Empty();
    sk_sp<SkTypeface> face = mgr ? mgr->makeFromFile(argv[1]) : nullptr;
    check("typeface from file", face != nullptr);
    if (face) {
        SkFont font(face, 22);
        font.setEdging(SkFont::Edging::kAntiAlias);
        SkPaint text; text.setColor(SK_ColorBLACK); text.setAntiAlias(true);
        c->drawString("Skia m154 AROS", 16, 140, font, text);
    }

    SkPixmap pm;
    check("peekPixels", surface->peekPixels(&pm));
    SkColor block = pm.getColor(30, 30);
    std::printf("block %08x\n", (unsigned)block);
    check("solid block colour", block == SkColorSetRGB(0x20, 0x40, 0xC0));
    SkColor left = pm.getColor(2, 80), right = pm.getColor(253, 80);
    std::printf("gradient left %08x right %08x\n", (unsigned)left, (unsigned)right);
    check("gradient ends", SkColorGetR(left) > 0xF0 && SkColorGetB(left) < 0x10 &&
                           SkColorGetB(right) > 0xF0 && SkColorGetR(right) < 0x10);
    check("circle centre", pm.getColor(192, 32) == SkColorSetRGB(0x10, 0xA0, 0x30));
    // Some pixel of the text row must be dark.
    int dark = 0;
    for (int x = 16; x < 240; ++x)
        for (int y = 118; y < 146; ++y)
            if (SkColorGetR(pm.getColor(x, y)) < 0x40) ++dark;
    std::printf("text dark pixels %d\n", dark);
    check("text rendered", dark > 100);

    SkFILEWStream out(argv[2]);
    check("png encode", out.isValid() && SkPngEncoder::Encode(&out, pm, {}));
    out.flush();
    std::printf("summary fails=%d\n", fails);
    return fails ? 5 : 0;
}
