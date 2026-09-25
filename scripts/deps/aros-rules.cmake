# Loaded through CMAKE_USER_MAKE_RULES_OVERRIDE, i.e. after CMake's GNU
# compiler module, which is the only point where these can be overridden.
#
# AROS executables are not position independent. collect-aros leaves
# _GLOBAL_OFFSET_TABLE_ undefined for -fPIC objects that touch extern data
# (measured 2026-09-24: "There are undefined symbols ... _GLOBAL_OFFSET_TABLE_"),
# so a project that forces POSITION_INDEPENDENT_CODE (libwebp does for static
# builds) must get no PIC flag at all.
foreach(lang C CXX ASM)
  set(CMAKE_${lang}_COMPILE_OPTIONS_PIC "")
  set(CMAKE_${lang}_COMPILE_OPTIONS_PIE "")
  set(CMAKE_${lang}_LINK_OPTIONS_PIE "")
endforeach()
