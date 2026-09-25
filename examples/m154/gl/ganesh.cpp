// Skia m154 Ganesh on AROS through GLA: the GrGLInterface is assembled from
// glAGetProcAddress (no EGL/epoxy). Renders the same scene through Ganesh
// and through the raster backend, compares pixels, and times both.
//
// Run with a large stack (Stack 8000000): Mesa softpipe needs it.
//
//   ganesh <font.ttf> <outdir> [frames]
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>


#include "include/core/SkBitmap.h"
#include "include/core/SkCanvas.h"
#include "include/core/SkColorSpace.h"
#include "include/core/SkFont.h"
#include "include/core/SkFontMgr.h"
#include "include/core/SkPaint.h"
#include "include/core/SkPathBuilder.h"
#include "include/core/SkStream.h"
#include "include/core/SkSurface.h"
#include "include/core/SkTypeface.h"
#include "include/effects/SkGradient.h"
#include "include/encode/SkPngEncoder.h"
#include "include/gpu/ganesh/GrDirectContext.h"
#include "include/gpu/ganesh/SkSurfaceGanesh.h"
#include "include/gpu/ganesh/gl/GrGLAssembleInterface.h"
#include "include/gpu/ganesh/gl/GrGLDirectContext.h"
#include "include/gpu/ganesh/gl/GrGLInterface.h"
#include "include/ports/SkFontMgr_empty.h"

// AROS headers after Skia: <inline/exec.h> defines an Allocate() macro that
// would rewrite SkTArray's Allocate member.
#include <proto/exec.h>
#include <proto/intuition.h>
#include <intuition/intuition.h>
#include <GL/gla.h>
#include <GL/gl.h>

static int fails;
static void check(const char* name, bool ok) {
    std::printf("%s %s\n", ok ? "PASS" : "FAIL", name);
    fails += !ok;
}

// GL 1.x entry points, in case glAGetProcAddress only serves extensions.
struct CoreProc { const char* name; GrGLFuncPtr fn; };
#define C(f) {#f, (GrGLFuncPtr)&f}
static const CoreProc kCore[] = {
    C(glBindTexture), C(glBlendFunc), C(glClear), C(glClearColor), C(glClearStencil),
    C(glColorMask), C(glCopyTexSubImage2D), C(glCullFace), C(glDeleteTextures), C(glDepthMask),
    C(glDisable), C(glDrawArrays), C(glDrawBuffer), C(glDrawElements), C(glEnable), C(glFinish),
    C(glFlush), C(glFrontFace), C(glGenTextures), C(glGetError), C(glGetIntegerv), C(glGetString),
    C(glGetTexLevelParameteriv), C(glLineWidth), C(glPixelStorei), C(glPolygonMode),
    C(glReadBuffer), C(glReadPixels), C(glScissor), C(glStencilFunc), C(glStencilMask),
    C(glStencilOp), C(glTexImage2D), C(glTexParameterf), C(glTexParameterfv), C(glTexParameteri),
    C(glTexParameteriv), C(glTexSubImage2D), C(glViewport), C(glGetFloatv), C(glHint),
};
#undef C

static int fromGLA, fromCore, missing;
static GrGLFuncPtr getProc(void*, const char name[]) {
    if (GLAProc p = glAGetProcAddress((const GLubyte*)name)) { ++fromGLA; return (GrGLFuncPtr)p; }
    for (const CoreProc& c : kCore)
        if (!std::strcmp(c.name, name)) { ++fromCore; return c.fn; }
    ++missing;
    std::printf("  no entry point: %s\n", name);
    return nullptr;
}

static sk_sp<SkTypeface> gFace;

static void scene(SkCanvas* c) {
    c->clear(SK_ColorWHITE);
    SkPaint solid; solid.setColor(SkColorSetRGB(0x20, 0x40, 0xC0));
    c->drawRect(SkRect::MakeXYWH(8, 8, 48, 48), solid);
    SkPoint pts[2] = {{0, 0}, {256, 0}};
    SkColor4f cols[2] = {SkColors::kRed, SkColors::kBlue};
    SkPaint grad;
    SkGradient g(SkGradient::Colors(SkSpan<const SkColor4f>(cols, 2), SkTileMode::kClamp), {});
    grad.setShader(SkShaders::LinearGradient(pts, g));
    c->drawRect(SkRect::MakeXYWH(0, 64, 256, 32), grad);
    SkPaint aa; aa.setAntiAlias(true); aa.setColor(SkColorSetRGB(0x10, 0xA0, 0x30));
    c->drawCircle(192, 32, 24, aa);
    SkPaint stroke; stroke.setAntiAlias(true); stroke.setStyle(SkPaint::kStroke_Style);
    stroke.setStrokeWidth(4); stroke.setColor(SK_ColorBLACK);
    SkPathBuilder pb; pb.moveTo(16, 200); pb.cubicTo(80, 120, 176, 280, 240, 200);
    c->drawPath(pb.detach(), stroke);
    if (gFace) {
        SkFont font(gFace, 22);
        font.setEdging(SkFont::Edging::kAntiAlias);
        SkPaint text; text.setAntiAlias(true);
        c->drawString("Skia m154 Ganesh", 16, 140, font, text);
    }
}

static void savePng(const std::string& path, const SkPixmap& pm) {
    SkFILEWStream f(path.c_str());
    if (f.isValid()) SkPngEncoder::Encode(&f, pm, {});
}

int main(int argc, char** argv) {
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    if (argc < 3) { std::printf("usage: ganesh <font.ttf> <outdir> [frames]\n"); return 20; }
    std::string out = argv[2];
    int frames = argc > 3 ? std::atoi(argv[3]) : 10;
    gFace = SkFontMgr_New_Custom_Empty()->makeFromFile(argv[1]);
    check("typeface", gFace != nullptr);
    const SkImageInfo info = SkImageInfo::MakeN32Premul(256, 256);

    // Raster reference.
    SkBitmap ref; ref.allocPixels(info);
    { SkCanvas rc(ref); scene(&rc); }
    SkPixmap refPm; ref.peekPixels(&refPm);
    savePng(out + "ganesh-raster.png", refPm);

    struct Window* win = OpenWindowTags(nullptr, WA_Title, (IPTR)"skia ganesh", WA_Left, 400,
        WA_Top, 60, WA_InnerWidth, 256, WA_InnerHeight, 256, WA_DragBar, TRUE, TAG_DONE);
    check("window", win != nullptr);
    if (!win) return 20;
    GLAContext gla = glACreateContextTags(GLA_Window, (IPTR)win, GLA_Left, win->BorderLeft,
        GLA_Top, win->BorderTop, GLA_Width, 256, GLA_Height, 256, GLA_RGBMode, TRUE,
        GLA_DoubleBuf, TRUE, GLA_AlphaFlag, TRUE, TAG_DONE);
    check("GLA context", gla != nullptr);
    if (!gla) { CloseWindow(win); return 20; }
    glAMakeCurrent(gla);
    std::printf("GL %s / %s\n", (const char*)glGetString(GL_VERSION), (const char*)glGetString(GL_RENDERER));

    int rc = 0;
    {
        sk_sp<const GrGLInterface> iface = GrGLMakeAssembledInterface(nullptr, getProc);
        std::printf("procs: %d from GLA, %d from core table, %d missing\n", fromGLA, fromCore, missing);
        check("GrGLInterface assembled", iface != nullptr);
        check("GrGLInterface validate", iface && iface->validate());
        sk_sp<GrDirectContext> ctx = iface ? GrDirectContexts::MakeGL(iface) : nullptr;
        check("GrDirectContext", ctx != nullptr);
        if (ctx) {
            sk_sp<SkSurface> gs = SkSurfaces::RenderTarget(ctx.get(), skgpu::Budgeted::kNo, info);
            check("Ganesh render target", gs != nullptr);
            if (gs) {
                scene(gs->getCanvas());
                ctx->flushAndSubmit(gs.get(), GrSyncCpu::kYes);
                SkBitmap got; got.allocPixels(info);
                check("readPixels", gs->readPixels(got.pixmap(), 0, 0));
                SkPixmap gp; got.peekPixels(&gp);
                savePng(out + "ganesh-gpu.png", gp);
                check("solid block exact", gp.getColor(30, 30) == SkColorSetRGB(0x20, 0x40, 0xC0));
                int differ = 0, worst = 0;
                for (int y = 0; y < 256; ++y)
                    for (int x = 0; x < 256; ++x) {
                        SkColor a = refPm.getColor(x, y), b = gp.getColor(x, y);
                        int d = std::abs((int)SkColorGetR(a) - (int)SkColorGetR(b));
                        d = std::max(d, std::abs((int)SkColorGetG(a) - (int)SkColorGetG(b)));
                        d = std::max(d, std::abs((int)SkColorGetB(a) - (int)SkColorGetB(b)));
                        worst = std::max(worst, d);
                        differ += d > 8;
                    }
                std::printf("pixels differing >8 from raster: %d of 65536, worst %d\n", differ, worst);
                check("matches raster within AA noise (<2% pixels)", differ < 1311);

                using clock = std::chrono::steady_clock;
                auto t0 = clock::now();
                for (int i = 0; i < frames; ++i) { SkCanvas rc2(ref); scene(&rc2); }
                auto t1 = clock::now();
                for (int i = 0; i < frames; ++i) {
                    scene(gs->getCanvas());
                    ctx->flushAndSubmit(gs.get(), GrSyncCpu::kYes);
                }
                auto t2 = clock::now();
                auto ms = [](auto d) { return (long)std::chrono::duration_cast<std::chrono::milliseconds>(d).count(); };
                std::printf("%d frames: raster %ld ms, ganesh %ld ms\n", frames, ms(t1 - t0), ms(t2 - t1));
            }
            gs = nullptr;
            ctx->flushAndSubmit(GrSyncCpu::kYes);
        }
        ctx = nullptr;
    }
    glADestroyContext(gla);
    CloseWindow(win);
    std::printf("summary fails=%d\n", fails);
    rc = fails ? 5 : 0;
    return rc;
}
