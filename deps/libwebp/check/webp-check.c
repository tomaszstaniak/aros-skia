/* Link and runtime check for static libwebp, libwebpdemux, libwebpmux and
 * libsharpyuv: lossy + lossless RGBA round trip, demux, mux.
 * Usage on AROS: webp-check [result.txt]  -> pass=1 in the result file. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <webp/decode.h>
#include <webp/encode.h>
#include <webp/demux.h>
#include <webp/mux.h>
#include <sharpyuv/sharpyuv.h>

#define W 24
#define H 16

int main(int argc, char **argv) {
  const char *out_path = argc > 1 ? argv[1] : "RAM:webp-check.txt";
  unsigned char rgba[W * H * 4];
  int pass = 1, i, w = 0, h = 0;
  for (i = 0; i < W * H; i++) {
    rgba[i * 4 + 0] = 30; rgba[i * 4 + 1] = 160; rgba[i * 4 + 2] = 220;
    rgba[i * 4 + 3] = (i & 1) ? 255 : 128;
  }

  uint8_t *ll = NULL;
  size_t ll_len = WebPEncodeLosslessRGBA(rgba, W, H, W * 4, &ll);
  uint8_t *dec = WebPDecodeRGBA(ll, ll_len, &w, &h);
  if (!dec || w != W || h != H || memcmp(dec, rgba, sizeof rgba) != 0) pass = 0;
  WebPFree(dec);

  uint8_t *lossy = NULL;
  size_t lossy_len = WebPEncodeRGBA(rgba, W, H, W * 4, 90.0f, &lossy);
  dec = WebPDecodeRGBA(lossy, lossy_len, &w, &h);
  if (!dec || w != W || h != H || abs(dec[1] - 160) > 16) pass = 0;
  WebPFree(dec);

  WebPData data = { ll, ll_len };
  WebPDemuxer *dmx = WebPDemux(&data);
  unsigned frames = dmx ? WebPDemuxGetI(dmx, WEBP_FF_FRAME_COUNT) : 0;
  if (frames != 1) pass = 0;
  WebPDemuxDelete(dmx);

  WebPMux *mux = WebPMuxCreate(&data, 1);
  WebPData assembled = { NULL, 0 };
  if (!mux || WebPMuxAssemble(mux, &assembled) != WEBP_MUX_OK || assembled.size == 0) pass = 0;
  WebPDataClear(&assembled);
  WebPMuxDelete(mux);

  int sharp = SharpYuvGetVersion();
  if (sharp == 0) pass = 0;

  FILE *f = fopen(out_path, "w");
  if (f) {
    fprintf(f, "webp_decoder=0x%06x\nwebp_encoder=0x%06x\nsharpyuv=0x%06x\n"
               "lossless_bytes=%lu\nlossy_bytes=%lu\nframes=%u\npass=%d\n",
            WebPGetDecoderVersion(), WebPGetEncoderVersion(), sharp,
            (unsigned long)ll_len, (unsigned long)lossy_len, frames, pass);
    fclose(f);
  }
  WebPFree(ll);
  WebPFree(lossy);
  printf("webp-check pass=%d\n", pass);
  return pass ? 0 : 5;
}
