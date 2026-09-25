// Link and runtime check for the static HarfBuzz + SDK FreeType chain.
// Usage on AROS: hb-check [font.ttf] [result.txt]
// Shapes "Hello AROS" with hb-ot (always) and, when a font file is given,
// through hb_ft_font_create_referenced. Writes pass=1 to the result file:
// guest evidence is that file, not the console.
#include <hb.h>
#include <hb-ft.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <cstdio>
#include <cstring>

static unsigned shape(hb_font_t *font, const char *text) {
  hb_buffer_t *buf = hb_buffer_create();
  hb_buffer_add_utf8(buf, text, -1, 0, -1);
  hb_buffer_guess_segment_properties(buf);
  hb_shape(font, buf, nullptr, 0);
  unsigned n = hb_buffer_get_length(buf);
  hb_buffer_destroy(buf);
  return n;
}

int main(int argc, char **argv) {
  const char *font_path = argc > 1 ? argv[1] : nullptr;
  const char *out_path = argc > 2 ? argv[2] : "RAM:hb-check.txt";
  const char *text = "Hello AROS";
  int pass = 1;

  // Empty face: exercises the shaper, buffer, and unicode funcs without a file.
  hb_font_t *empty = hb_font_create(hb_face_get_empty());
  unsigned n_empty = shape(empty, text);
  hb_font_destroy(empty);
  if (n_empty != strlen(text)) pass = 0;

  unsigned n_ft = 0;
  int ft_err = -1;
  if (font_path) {
    FT_Library lib;
    FT_Face face;
    ft_err = FT_Init_FreeType(&lib);
    if (!ft_err) ft_err = FT_New_Face(lib, font_path, 0, &face);
    if (!ft_err) {
      FT_Set_Char_Size(face, 0, 16 * 64, 72, 72);
      hb_font_t *font = hb_ft_font_create_referenced(face);
      n_ft = shape(font, text);
      hb_font_destroy(font);
      FT_Done_Face(face);
      FT_Done_FreeType(lib);
    }
    if (ft_err || n_ft == 0) pass = 0;
  }

  FILE *f = fopen(out_path, "w");
  if (f) {
    fprintf(f, "harfbuzz=%s\nempty_face_glyphs=%u\nft_error=%d\nft_glyphs=%u\npass=%d\n",
            hb_version_string(), n_empty, ft_err, n_ft, pass);
    fclose(f);
  }
  printf("hb-check %s pass=%d\n", hb_version_string(), pass);
  return pass ? 0 : 5;
}
