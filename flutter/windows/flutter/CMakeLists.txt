# This file controls Flutter-level build steps. It should not be edited.
cmake_minimum_required(VERSION 3.14)

set(EPHEMERAL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ephemeral")

# Configuration provided via flutter tool.
include(${EPHEMERAL_DIR}/generated_config.cmake)

# === Workaround: pre-copy engine artifacts from SDK cache ===
# On some Windows setups tool_backend.bat fails to copy cpp_client_wrapper
# and other engine files to the ephemeral directory ("system cannot find
# the specified path").  We copy them at configure-time so the C++ sources
# are always available for compilation.  tool_backend still runs during
# build for Dart kernel compilation and asset bundling.
set(_ENGINE_CACHE "${FLUTTER_ROOT}/bin/cache/artifacts/engine/windows-x64")
if(EXISTS "${_ENGINE_CACHE}/cpp_client_wrapper")
  file(COPY "${_ENGINE_CACHE}/cpp_client_wrapper" DESTINATION "${EPHEMERAL_DIR}")
  foreach(_ef flutter_windows.dll flutter_windows.dll.lib flutter_windows.dll.exp
              flutter_windows.dll.pdb
              flutter_export.h flutter_windows.h flutter_messenger.h
              flutter_plugin_registrar.h flutter_texture_registrar.h
              icudtl.dat)
    if(EXISTS "${_ENGINE_CACHE}/${_ef}")
      file(COPY "${_ENGINE_CACHE}/${_ef}" DESTINATION "${EPHEMERAL_DIR}")
    endif()
  endforeach()
  message(STATUS "Flutter engine artifacts pre-copied from SDK cache to ephemeral")
endif()

# TODO: Move the rest of this into files in ephemeral. See
# https://github.com/flutter/flutter/issues/57146.
set(WRAPPER_ROOT "${EPHEMERAL_DIR}/cpp_client_wrapper")

# Set fallback configurations for older versions of the flutter tool.
if (NOT DEFINED FLUTTER_TARGET_PLATFORM)
  set(FLUTTER_TARGET_PLATFORM "windows-x64")
endif()

# === Flutter Library ===
set(FLUTTER_LIBRARY "${EPHEMERAL_DIR}/flutter_windows.dll")

# Published to parent scope for install step.
set(FLUTTER_LIBRARY ${FLUTTER_LIBRARY} PARENT_SCOPE)
set(FLUTTER_ICU_DATA_FILE "${EPHEMERAL_DIR}/icudtl.dat" PARENT_SCOPE)
set(PROJECT_BUILD_DIR "${PROJECT_DIR}/build/" PARENT_SCOPE)
set(AOT_LIBRARY "${PROJECT_DIR}/build/windows/app.so" PARENT_SCOPE)

list(APPEND FLUTTER_LIBRARY_HEADERS
  "flutter_export.h"
  "flutter_windows.h"
  "flutter_messenger.h"
  "flutter_plugin_registrar.h"
  "flutter_texture_registrar.h"
)
list(TRANSFORM FLUTTER_LIBRARY_HEADERS PREPEND "${EPHEMERAL_DIR}/")
add_library(flutter INTERFACE)
target_include_directories(flutter INTERFACE
  "${EPHEMERAL_DIR}"
)
target_link_libraries(flutter INTERFACE "${FLUTTER_LIBRARY}.lib")
add_dependencies(flutter flutter_assemble)

# === Wrapper ===
list(APPEND CPP_WRAPPER_SOURCES_CORE
  "core_implementations.cc"
  "standard_codec.cc"
)
list(TRANSFORM CPP_WRAPPER_SOURCES_CORE PREPEND "${WRAPPER_ROOT}/")
list(APPEND CPP_WRAPPER_SOURCES_PLUGIN
  "plugin_registrar.cc"
)
list(TRANSFORM CPP_WRAPPER_SOURCES_PLUGIN PREPEND "${WRAPPER_ROOT}/")
list(APPEND CPP_WRAPPER_SOURCES_APP
  "flutter_engine.cc"
  "flutter_view_controller.cc"
)
list(TRANSFORM CPP_WRAPPER_SOURCES_APP PREPEND "${WRAPPER_ROOT}/")

# Wrapper sources needed for a plugin.
add_library(flutter_wrapper_plugin STATIC
  ${CPP_WRAPPER_SOURCES_CORE}
  ${CPP_WRAPPER_SOURCES_PLUGIN}
)
apply_standard_settings(flutter_wrapper_plugin)
set_target_properties(flutter_wrapper_plugin PROPERTIES
  POSITION_INDEPENDENT_CODE ON)
set_target_properties(flutter_wrapper_plugin PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_link_libraries(flutter_wrapper_plugin PUBLIC flutter)
target_include_directories(flutter_wrapper_plugin PUBLIC
  "${WRAPPER_ROOT}/include"
)
add_dependencies(flutter_wrapper_plugin flutter_assemble)

# Wrapper sources needed for the runner.
add_library(flutter_wrapper_app STATIC
  ${CPP_WRAPPER_SOURCES_CORE}
  ${CPP_WRAPPER_SOURCES_APP}
)
apply_standard_settings(flutter_wrapper_app)
target_link_libraries(flutter_wrapper_app PUBLIC flutter)
target_include_directories(flutter_wrapper_app PUBLIC
  "${WRAPPER_ROOT}/include"
)
add_dependencies(flutter_wrapper_app flutter_assemble)

# === Flutter tool backend ===
# _phony_ is a non-existent file to force this command to run every time,
# since currently there's no way to get a full input/output list from the
# flutter tool.
set(PHONY_OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/_phony_")
set_source_files_properties("${PHONY_OUTPUT}" PROPERTIES SYMBOLIC TRUE)

# Build a helper script that copies engine artifacts from SDK cache into
# ephemeral AFTER tool_backend.bat runs.  tool_backend.bat on some Windows
# machines fails to copy cpp_client_wrapper (error: "system cannot find
# the specified path").  The script runs unconditionally and is idempotent.
set(_COPY_SCRIPT "${CMAKE_CURRENT_BINARY_DIR}/_copy_engine_artifacts.cmake")
set(_MATERIAL_FONTS_CACHE "${FLUTTER_ROOT}/bin/cache/artifacts/material_fonts")
file(WRITE "${_COPY_SCRIPT}" "
set(_SRC \"${_ENGINE_CACHE}\")
set(_DST \"${EPHEMERAL_DIR}\")
if(EXISTS \"\${_SRC}/cpp_client_wrapper\" AND NOT EXISTS \"\${_DST}/cpp_client_wrapper/core_implementations.cc\")
  file(COPY \"\${_SRC}/cpp_client_wrapper\" DESTINATION \"\${_DST}\")
  message(STATUS \"Copied cpp_client_wrapper from SDK cache\")
endif()
foreach(_f flutter_windows.dll flutter_windows.dll.lib flutter_export.h
           flutter_windows.h flutter_messenger.h flutter_plugin_registrar.h
           flutter_texture_registrar.h icudtl.dat)
  if(EXISTS \"\${_SRC}/\${_f}\" AND NOT EXISTS \"\${_DST}/\${_f}\")
    file(COPY \"\${_SRC}/\${_f}\" DESTINATION \"\${_DST}\")
  endif()
endforeach()

# Ensure MaterialIcons font is present in flutter_assets.
# flutter assemble sometimes skips this step when its stamp files are stale
# (stamp exists from a previous build but output files were cleaned away).
set(_FONTS_DST \"${PROJECT_DIR}/build/flutter_assets/fonts\")
set(_FONT_SRC \"${_MATERIAL_FONTS_CACHE}/materialicons-regular.otf\")
set(_FONT_DST \"\${_FONTS_DST}/MaterialIcons-Regular.otf\")
if(EXISTS \"\${_FONT_SRC}\" AND NOT EXISTS \"\${_FONT_DST}\")
  file(MAKE_DIRECTORY \"\${_FONTS_DST}\")
  file(COPY \"\${_FONT_SRC}\" DESTINATION \"\${_FONTS_DST}\")
  file(RENAME \"\${_FONTS_DST}/materialicons-regular.otf\" \"\${_FONT_DST}\")
  message(STATUS \"Copied MaterialIcons-Regular.otf from SDK cache to flutter_assets/fonts/\")
endif()
")

add_custom_command(
  OUTPUT ${FLUTTER_LIBRARY} ${FLUTTER_LIBRARY_HEADERS}
    ${CPP_WRAPPER_SOURCES_CORE} ${CPP_WRAPPER_SOURCES_PLUGIN}
    ${CPP_WRAPPER_SOURCES_APP}
    ${PHONY_OUTPUT}
  COMMAND ${CMAKE_COMMAND} -E env
    ${FLUTTER_TOOL_ENVIRONMENT}
    "${FLUTTER_ROOT}/packages/flutter_tools/bin/tool_backend.bat"
      ${FLUTTER_TARGET_PLATFORM} $<CONFIG>
  # Fallback: copy engine artifacts if tool_backend missed them
  COMMAND ${CMAKE_COMMAND} -P "${_COPY_SCRIPT}"
  VERBATIM
)
add_custom_target(flutter_assemble DEPENDS
  "${FLUTTER_LIBRARY}"
  ${FLUTTER_LIBRARY_HEADERS}
  ${CPP_WRAPPER_SOURCES_CORE}
  ${CPP_WRAPPER_SOURCES_PLUGIN}
  ${CPP_WRAPPER_SOURCES_APP}
)
