cmake_minimum_required(VERSION 3.20)
project(sippier_core C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_VISIBILITY_PRESET hidden)

# Static OpenSSL, Opus, libg722, libre and baresip come from
# native/scripts/build.sh, installed into the first entry of
# CMAKE_PREFIX_PATH.
list(GET CMAKE_PREFIX_PATH 0 SIPPIER_PREFIX)

find_package(libre CONFIG REQUIRED)
foreach(lib baresip g722 opus)
  string(TOUPPER ${lib} var)
  find_library(${var}_LIB NAMES lib${lib}.a
    PATHS "${SIPPIER_PREFIX}/lib" NO_DEFAULT_PATH NO_CMAKE_FIND_ROOT_PATH
    REQUIRED)
endforeach()

add_library(sippier_core SHARED
  src/sippier_core.c
  src/devices.c
  src/netwatch.c
  src/power.c
  src/ringtone.c)

if(WIN32)
  # sippier_core.dll, the name Dart's DynamicLoadingBundled looks for
  set_target_properties(sippier_core PROPERTIES PREFIX "" IMPORT_PREFIX "")
endif()

target_include_directories(sippier_core
  PUBLIC include
  PRIVATE "${SIPPIER_PREFIX}/include")

target_link_libraries(sippier_core PRIVATE
  ${BARESIP_LIB}
  ${G722_LIB}
  ${OPUS_LIB}
  libre::re)

# Echo cancellation at the audio device (aec.c, apm.cpp) with WebRTC audio
# processing and abseil, where build.sh built them
find_library(WEBRTC_APM_LIB NAMES libwebrtc-audio-processing-1.a
  PATHS "${SIPPIER_PREFIX}/lib" NO_DEFAULT_PATH NO_CMAKE_FIND_ROOT_PATH)
if(WEBRTC_APM_LIB)
  enable_language(CXX)
  target_sources(sippier_core PRIVATE src/aec.c src/apm.cpp)
  # flags from webrtc-audio-processing-1.pc
  if(WIN32)
    set(WEBRTC_PLATFORM WEBRTC_WIN)
  else()
    set(WEBRTC_PLATFORM WEBRTC_POSIX)
  endif()
  target_compile_definitions(sippier_core PRIVATE
    SIPPIER_AEC WEBRTC_LIBRARY_IMPL ${WEBRTC_PLATFORM})
  target_include_directories(sippier_core PRIVATE
    "${SIPPIER_PREFIX}/include/webrtc-audio-processing-1")
  set_target_properties(sippier_core PROPERTIES
    CXX_STANDARD 17
    CXX_VISIBILITY_PRESET hidden)
  # abseil 20230125 uses a builtin newer clang deprecates
  set_source_files_properties(src/apm.cpp PROPERTIES
    COMPILE_OPTIONS "-Wno-deprecated-builtins")
  file(GLOB ABSL_LIBS "${SIPPIER_PREFIX}/lib/libabsl_*.a")
  if(APPLE)
    target_link_libraries(sippier_core PRIVATE ${WEBRTC_APM_LIB} ${ABSL_LIBS})
  else()
    # abseil's libraries depend on each other in no single order
    target_link_libraries(sippier_core PRIVATE
      -Wl,--start-group ${WEBRTC_APM_LIB} ${ABSL_LIBS} -Wl,--end-group)
  endif()
  set_target_properties(sippier_core PROPERTIES LINKER_LANGUAGE CXX)
endif()

if(ANDROID)
  target_link_libraries(sippier_core PRIVATE aaudio log m)
elseif(APPLE)
  target_link_libraries(sippier_core PRIVATE
    "-framework CoreAudio"
    "-framework AudioToolbox"
    "-framework AudioUnit"
    "-framework IOKit"
    "-framework Network")
  set_target_properties(sippier_core PROPERTIES
    INSTALL_NAME_DIR "@rpath")
elseif(WIN32)
  # baresip's wasapi module and Windows parts, OpenSSL, devices.c, power.c,
  # netwatch.c and the CA export
  target_link_libraries(sippier_core PRIVATE
    ole32 oleaut32 uuid winmm avrt ksuser
    crypt32 ws2_32 iphlpapi dbghelp powrprof)
  # The MinGW-w64 runtime, libc++ and winpthreads go into the DLL, so it
  # needs nothing next to it and doesn't mix with Flutter's MSVC runtime.
  target_link_options(sippier_core PRIVATE -static)
endif()
