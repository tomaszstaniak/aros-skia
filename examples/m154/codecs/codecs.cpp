// Skia m154 with the static deps on AROS ABIv11: JPEG and WebP round trips
// through Skia's codecs, and HarfBuzz shaping drawn with Skia, the way
// WebKit uses it (hb_shape, then glyph runs; no SkShaper/SkUnicode).
//
//   codecs <font.ttf> <outdir>
#include <cstdio>
#include <cstdlib>
#include <string>

#include "include/codec/SkCodec.h"
#include "include/codec/SkJpegDecoder.h"
#include "include/codec/SkWebpDecoder.h"
#include "include/core/SkBitmap.h"
#include "include/core/SkCanvas.h"
#include "include/core/SkData.h"
#include "include/core/SkFont.h"
#include "include/core/SkFontMgr.h"
#include "include/core/SkImage.h"
#include "include/core/SkPaint.h"
#include "include/core/SkStream.h"
#include "include/core/SkSurface.h"
#include "include/core/SkTextBlob.h"
#include "include/core/SkTypeface.h"
#include "include/encode/SkJpegEncoder.h"
#include "include/encode/SkPngEncoder.h"
#include "include/encode/SkWebpEncoder.h"
#include "include/ports/SkFontMgr_empty.h"

#include <harfbuzz/hb.h>

static int fails;
static void check(const char* name, bool ok) {
    std::printf("%s %s\n", ok ? "PASS" : "FAIL", name);
    fails += !ok;
}

static SkBitmap quadrants() {
    SkBitmap bm;
    bm.allocN32Pixels(128, 128);
    SkCanvas c(bm);
    SkPaint p;
    p.setColor(SkColorSetRGB(0xE0, 0x20, 0x20)); c.drawRect(SkRect::MakeXYWH(0, 0, 64, 64), p);
    p.setColor(SkColorSetRGB(0x20, 0xC0, 0x20)); c.drawRect(SkRect::MakeXYWH(64, 0, 64, 64), p);
    p.setColor(SkColorSetRGB(0x20, 0x40, 0xE0)); c.drawRect(SkRect::MakeXYWH(0, 64, 64, 64), p);
    p.setColor(SkColorSetRGB(0xF0, 0xF0, 0x40)); c.drawRect(SkRect::MakeXYWH(64, 64, 64, 64), p);
    return bm;
}

// Largest per-channel difference between two images, sampled at the
// centres of the quadrants (away from JPEG block edges).
static int maxdiff(const SkPixmap& a, const SkPixmap& b) {
    int worst = 0;
    const int pts[4][2] = {{32, 32}, {96, 32}, {32, 96}, {96, 96}};
    for (auto& q : pts) {
        SkColor x = a.getColor(q[0], q[1]), y = b.getColor(q[0], q[1]);
        int d[3] = {abs((int)SkColorGetR(x) - (int)SkColorGetR(y)),
                    abs((int)SkColorGetG(x) - (int)SkColorGetG(y)),
                    abs((int)SkColorGetB(x) - (int)SkColorGetB(y))};
        for (int v : d) worst = v > worst ? v : worst;
    }
    return worst;
}

static bool exact(const SkPixmap& a, const SkPixmap& b) {
    for (int y = 0; y < a.height(); ++y)
        for (int x = 0; x < a.width(); ++x)
            if (a.getColor(x, y) != b.getColor(x, y)) return false;
    return true;
}

static sk_sp<SkImage> decode(sk_sp<SkData> data, bool jpeg) {
    SkCodec::Result r;
    std::unique_ptr<SkCodec> codec = jpeg ? SkJpegDecoder::Decode(data, &r) : SkWebpDecoder::Decode(data, &r);
    if (!codec) { std::printf("  decoder: result %d\n", (int)r); return nullptr; }
    return std::get<0>(codec->getImage());
}

static void save(const std::string& path, sk_sp<SkData> d) {
    SkFILEWStream f(path.c_str());
    if (f.isValid()) f.write(d->data(), d->size());
}

int main(int argc, char** argv) {
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    if (argc < 3) { std::printf("usage: codecs <font.ttf> <outdir>\n"); return 20; }
    std::string out = argv[2];
    SkBitmap src = quadrants();
    SkPixmap sp; src.peekPixels(&sp);

    // JPEG round trip (libjpeg-turbo).
    SkDynamicMemoryWStream js;
    SkJpegEncoder::Options jo; jo.fQuality = 95;
    check("jpeg encode", SkJpegEncoder::Encode(&js, sp, jo));
    sk_sp<SkData> jd = js.detachAsData();
    std::printf("jpeg bytes %zu\n", jd->size());
    save(out + "codecs-rt.jpg", jd);
    sk_sp<SkImage> ji = decode(jd, true);
    SkPixmap jp;
    check("jpeg decode", ji && ji->peekPixels(&jp) && jp.width() == 128);
    if (ji && ji->peekPixels(&jp)) {
        int d = maxdiff(sp, jp);
        std::printf("jpeg max channel diff %d\n", d);
        check("jpeg colours within 8", d <= 8);
    }

    // WebP lossless round trip must be exact (libwebp).
    SkDynamicMemoryWStream ws;
    SkWebpEncoder::Options wo; wo.fCompression = SkWebpEncoder::Compression::kLossless; wo.fQuality = 100;
    check("webp lossless encode", SkWebpEncoder::Encode(&ws, sp, wo));
    sk_sp<SkData> wd = ws.detachAsData();
    std::printf("webp lossless bytes %zu\n", wd->size());
    save(out + "codecs-rt.webp", wd);
    sk_sp<SkImage> wi = decode(wd, false);
    SkPixmap wp;
    check("webp decode", wi && wi->peekPixels(&wp) && wp.width() == 128);
    if (wi && wi->peekPixels(&wp)) check("webp lossless exact", exact(sp, wp));

    // WebP lossy, for the encoder's other path.
    SkDynamicMemoryWStream wls;
    SkWebpEncoder::Options wlo; wlo.fCompression = SkWebpEncoder::Compression::kLossy; wlo.fQuality = 90;
    check("webp lossy encode", SkWebpEncoder::Encode(&wls, sp, wlo));
    sk_sp<SkImage> wli = decode(wls.detachAsData(), false);
    SkPixmap wlp;
    if (wli && wli->peekPixels(&wlp)) {
        int d = maxdiff(sp, wlp);
        std::printf("webp lossy max channel diff %d\n", d);
        check("webp lossy within 12", d <= 12);
    } else check("webp lossy decode", false);

    // HarfBuzz: shape, then draw the glyph run with Skia.
    sk_sp<SkData> fontData = SkData::MakeFromFileName(argv[1]);
    check("font file", fontData != nullptr);
    if (!fontData) return 20;
    hb_blob_t* blob = hb_blob_create((const char*)fontData->data(), (unsigned)fontData->size(),
                                     HB_MEMORY_MODE_READONLY, nullptr, nullptr);
    hb_face_t* face = hb_face_create(blob, 0);
    hb_font_t* font = hb_font_create(face);
    const int size = 32;
    hb_font_set_scale(font, size * 64, size * 64);

    auto shape = [&](const char* text, unsigned* count) {
        hb_buffer_t* buf = hb_buffer_create();
        hb_buffer_add_utf8(buf, text, -1, 0, -1);
        hb_buffer_guess_segment_properties(buf);
        hb_shape(font, buf, nullptr, 0);
        *count = hb_buffer_get_length(buf);
        return buf;
    };

    unsigned n = 0;
    hb_buffer_t* office = shape("office", &n);
    std::printf("\"office\": 6 chars -> %u glyphs\n", n);
    check("ffi ligature (fewer glyphs than chars)", n < 6);
    hb_buffer_destroy(office);

    unsigned na = 0, nav = 0;
    hb_buffer_t* a = shape("A", &na);
    hb_buffer_t* av = shape("AV", &nav);
    int advA = hb_buffer_get_glyph_positions(a, nullptr)[0].x_advance;
    int advAinAV = hb_buffer_get_glyph_positions(av, nullptr)[0].x_advance;
    std::printf("advance A alone %d, A before V %d (1/64 px)\n", advA, advAinAV);
    check("AV kerning applied", advAinAV < advA);
    hb_buffer_destroy(a); hb_buffer_destroy(av);

    // Draw a shaped Polish line with Skia from HarfBuzz glyphs and positions.
    unsigned gn = 0;
    hb_buffer_t* line = shape("Zażółć gęślą jaźń office AV", &gn);
    hb_glyph_info_t* gi = hb_buffer_get_glyph_infos(line, nullptr);
    hb_glyph_position_t* gp = hb_buffer_get_glyph_positions(line, nullptr);
    sk_sp<SkTypeface> tf = SkFontMgr_New_Custom_Empty()->makeFromData(fontData);
    check("skia typeface from same data", tf != nullptr);
    sk_sp<SkSurface> surf = SkSurfaces::Raster(SkImageInfo::MakeN32Premul(560, 64));
    SkCanvas* c = surf->getCanvas();
    c->clear(SK_ColorWHITE);
    if (tf) {
        SkFont sf(tf, size);
        sf.setEdging(SkFont::Edging::kAntiAlias);
        SkTextBlobBuilder b;
        const auto& run = b.allocRunPos(sf, (int)gn);
        float x = 8, y = 44;
        for (unsigned i = 0; i < gn; ++i) {
            run.glyphs[i] = (SkGlyphID)gi[i].codepoint;
            run.points()[i] = {x + gp[i].x_offset / 64.f, y - gp[i].y_offset / 64.f};
            x += gp[i].x_advance / 64.f;
        }
        SkPaint p; p.setAntiAlias(true);
        c->drawTextBlob(b.make(), 0, 0, p);
        std::printf("shaped line: %u glyphs, width %.1f px\n", gn, x - 8);
    }
    SkPixmap lp; surf->peekPixels(&lp);
    int dark = 0;
    for (int yy = 0; yy < 64; ++yy)
        for (int xx = 0; xx < 560; ++xx)
            if (SkColorGetR(lp.getColor(xx, yy)) < 0x40) ++dark;
    std::printf("shaped line dark pixels %d\n", dark);
    check("shaped line drawn", dark > 500);
    SkFILEWStream po((out + "codecs-shaped.png").c_str());
    check("png write", po.isValid() && SkPngEncoder::Encode(&po, lp, {}));
    hb_buffer_destroy(line); hb_font_destroy(font); hb_face_destroy(face); hb_blob_destroy(blob);

    std::printf("summary fails=%d\n", fails);
    return fails ? 5 : 0;
}
