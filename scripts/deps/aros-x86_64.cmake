# CMake cross toolchain for AROS x86_64 static dependency builds.
# Everything comes from the environment (set by scripts/deps/common.sh),
# so the file carries no machine paths and can be reused by other ports.
#
# Why STATIC_LIBRARY try-compile: an executable link on this host goes
# through collect-aros and the AROS build volume, and nothing built here
# can run. Configure checks therefore compile only. That makes
# check_function_exists() report every function as present, so recipes
# seed the real answers in the cache (see HAVE_* in deps/*/recipe.env).

set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
# Generic sets neither; AROS is close enough to UNIX for install layout and
# the POSIX file code paths, and it is not Apple/Windows.
set(UNIX 1)

set(CMAKE_C_COMPILER   "$ENV{AROS_CC}")
set(CMAKE_CXX_COMPILER "$ENV{AROS_CXX}")
set(CMAKE_AR           "$ENV{AROS_AR}" CACHE FILEPATH "" FORCE)
set(CMAKE_RANLIB       "$ENV{AROS_RANLIB}" CACHE FILEPATH "" FORCE)
set(CMAKE_NM           "$ENV{AROS_NM}" CACHE FILEPATH "" FORCE)
set(CMAKE_STRIP        "$ENV{AROS_STRIP}" CACHE FILEPATH "" FORCE)

set(CMAKE_SYSROOT "$ENV{AROS_SDK}")
# GCC 13.4 needs its specs file on every link (DEPS_LINK_FLAGS).
set(CMAKE_EXE_LINKER_FLAGS_INIT "$ENV{DEPS_LINK_FLAGS}")
set(CMAKE_FIND_ROOT_PATH "$ENV{AROS_SDK}" "$ENV{DEPS_PREFIX}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(CMAKE_POSITION_INDEPENDENT_CODE OFF)
set(CMAKE_USER_MAKE_RULES_OVERRIDE "${CMAKE_CURRENT_LIST_DIR}/aros-rules.cmake")

# Threads: AROS GCC rejects -pthread, and pthreads live in a real static
# libpthread.a (not libc). FindThreads cannot find that out with compile-only
# checks (it would accept libc or even "-lpthreads"), so answer it here:
# Threads::Threads then means -lpthread and CMAKE_USE_PTHREADS_INIT is set.
set(CMAKE_HAVE_LIBC_PTHREAD 0 CACHE INTERNAL "")
set(THREADS_HAVE_PTHREAD_ARG 0 CACHE INTERNAL "")
set(CMAKE_HAVE_PTHREADS_CREATE 0 CACHE INTERNAL "")
set(CMAKE_HAVE_PTHREAD_CREATE 1 CACHE INTERNAL "")
