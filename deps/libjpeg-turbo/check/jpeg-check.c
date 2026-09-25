/* Link and runtime check for static libjpeg-turbo with the extensions Skia
 * m154 uses: JCS_EXT_RGBA in and out, JCS_RGB565 out, jpeg_skip_scanlines,
 * jpeg_crop_scanline, in-memory source/destination.
 * Usage on AROS: jpeg-check [result.txt]  -> pass=1 in the result file. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <jpeglib.h>

#define W 32
#define H 32

static int near(int a, int b) { return abs(a - b) <= 12; }

int main(int argc, char **argv) {
  const char *out_path = argc > 1 ? argv[1] : "RAM:jpeg-check.txt";
  unsigned char rgba[W * H * 4];
  int pass = 1, x, y;
  for (y = 0; y < H; y++)
    for (x = 0; x < W; x++) {
      unsigned char *p = rgba + (y * W + x) * 4;
      p[0] = 200; p[1] = 40; p[2] = 90; p[3] = 255;
    }

  struct jpeg_compress_struct c;
  struct jpeg_error_mgr jerr;
  unsigned char *jpg = NULL;
  unsigned long jpg_len = 0;
  c.err = jpeg_std_error(&jerr);
  jpeg_create_compress(&c);
  jpeg_mem_dest(&c, &jpg, &jpg_len);
  c.image_width = W; c.image_height = H;
  c.input_components = 4; c.in_color_space = JCS_EXT_RGBA;
  jpeg_set_defaults(&c);
  jpeg_set_quality(&c, 95, TRUE);
  jpeg_start_compress(&c, TRUE);
  while (c.next_scanline < c.image_height) {
    JSAMPROW row = rgba + c.next_scanline * W * 4;
    jpeg_write_scanlines(&c, &row, 1);
  }
  jpeg_finish_compress(&c);
  jpeg_destroy_compress(&c);

  /* RGBA decode, skip 8 rows, crop to a 16-pixel window. */
  struct jpeg_decompress_struct d;
  d.err = jpeg_std_error(&jerr);
  jpeg_create_decompress(&d);
  jpeg_mem_src(&d, jpg, jpg_len);
  jpeg_read_header(&d, TRUE);
  d.out_color_space = JCS_EXT_RGBA;
  jpeg_start_decompress(&d);
  JDIMENSION xoff = 8, cw = 16;
  jpeg_crop_scanline(&d, &xoff, &cw);
  JDIMENSION skipped = jpeg_skip_scanlines(&d, 8);
  unsigned char row[W * 4];
  JSAMPROW rp = row;
  jpeg_read_scanlines(&d, &rp, 1);
  int rgba_components = d.output_components;
  if (skipped != 8 || rgba_components != 4) pass = 0;
  if (!near(row[0], 200) || !near(row[1], 40) || !near(row[2], 90) || row[3] != 255) pass = 0;
  jpeg_abort_decompress(&d);

  /* RGB565 decode of the same stream. */
  jpeg_mem_src(&d, jpg, jpg_len);
  jpeg_read_header(&d, TRUE);
  d.out_color_space = JCS_RGB565;
  d.dither_mode = JDITHER_NONE;
  jpeg_start_decompress(&d);
  unsigned short px[W];
  JSAMPROW pp = (JSAMPROW)px;
  jpeg_read_scanlines(&d, &pp, 1);
  /* libjpeg-turbo reports 3 colour components for RGB565 (jdmaster.c) and
     writes 2 bytes per pixel. */
  int rgb565_components = d.output_components;
  if (rgb565_components != 3) pass = 0;
  if (!near((px[0] >> 11) << 3, 200)) pass = 0;
  jpeg_abort_decompress(&d);
  jpeg_destroy_decompress(&d);

  FILE *f = fopen(out_path, "w");
  if (f) {
    fprintf(f, "jpeg_lib_version=%d\njpeg_bytes=%lu\nskipped=%u\nrgba_components=%d\nrgba=%u,%u,%u,%u\nrgb565_components=%d\nrgb565=0x%04x\npass=%d\n",
            JPEG_LIB_VERSION, jpg_len, (unsigned)skipped, rgba_components, row[0], row[1], row[2], row[3], rgb565_components, px[0], pass);
    fclose(f);
  }
  free(jpg);
  printf("jpeg-check pass=%d\n", pass);
  return pass ? 0 : 5;
}
