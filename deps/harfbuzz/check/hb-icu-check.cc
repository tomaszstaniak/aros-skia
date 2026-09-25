// Link check for the optional HB_WITH_ICU=ON build (libharfbuzz-icu.a
// against the SDK's static ICU 61.1). Shapes Arabic text with ICU unicode
// functions on an empty face. Usage on AROS: hb-icu-check [result.txt]
#include <hb.h>
#include <hb-icu.h>
#include <cstdio>

int main(int argc, char **argv) {
  const char *out_path = argc > 1 ? argv[1] : "RAM:hb-icu-check.txt";
  hb_buffer_t *b = hb_buffer_create();
  hb_buffer_set_unicode_funcs(b, hb_icu_get_unicode_funcs());
  hb_buffer_add_utf8(b, "\xd8\xb3\xd9\x84\xd8\xa7\xd9\x85", -1, 0, -1);
  hb_buffer_guess_segment_properties(b);
  hb_font_t *f = hb_font_create(hb_face_get_empty());
  hb_shape(f, b, nullptr, 0);
  int pass = hb_buffer_get_script(b) == HB_SCRIPT_ARABIC &&
             hb_buffer_get_direction(b) == HB_DIRECTION_RTL &&
             hb_buffer_get_length(b) == 4;
  FILE *o = fopen(out_path, "w");
  if (o) {
    fprintf(o, "harfbuzz=%s\nlen=%u\npass=%d\n", hb_version_string(),
            hb_buffer_get_length(b), pass);
    fclose(o);
  }
  hb_font_destroy(f);
  hb_buffer_destroy(b);
  printf("hb-icu-check pass=%d\n", pass);
  return pass ? 0 : 5;
}
