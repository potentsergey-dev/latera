# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(latera LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "latera")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# === Rust DLL (flutter_rust_bridge) ===
# Copy Rust native library for flutter_rust_bridge.
# The DLL is built by cargo and needs to be next to the executable for FFI to work.
# This is critical for MSIX packaging where the DLL must be in the package.
#
# NOTE: We use install(CODE) with runtime EXISTS check instead of configure-time check.
# This ensures the DLL is installed even if it was built after CMake configure ran.
set(RUST_DLL_NAME "latera_rust.dll")

# Define paths for both debug and release builds
set(RUST_DLL_PATH_DEBUG "${CMAKE_CURRENT_SOURCE_DIR}/../../rust/target/debug/${RUST_DLL_NAME}")
set(RUST_DLL_PATH_RELEASE "${CMAKE_CURRENT_SOURCE_DIR}/../../rust/target/release/${RUST_DLL_NAME}")

# For single-config generators (Ninja, Make), use CMAKE_BUILD_TYPE
# For multi-config generators (Visual Studio), use generator expressions
if(IS_MULTICONFIG)
  # Multi-config: copy the appropriate DLL based on build configuration
  # Use install(CODE) to check existence at install-time, not configure-time
  install(CODE "
    if(CMAKE_INSTALL_CONFIG_NAME STREQUAL \"Debug\")
      set(RUST_DLL_PATH \"${RUST_DLL_PATH_DEBUG}\")
    else()
      set(RUST_DLL_PATH \"${RUST_DLL_PATH_RELEASE}\")
    endif()
    if(EXISTS \"\${RUST_DLL_PATH}\")
      message(STATUS \"Installing Rust DLL: \${RUST_DLL_PATH}\")
      file(INSTALL \"\${RUST_DLL_PATH}\" DESTINATION \"${INSTALL_BUNDLE_LIB_DIR}\")
    else()
      message(WARNING \"Rust DLL not found at \${RUST_DLL_PATH}. Build Rust first: cargo build --release\")
    endif()
  " COMPONENT Runtime)
  message(STATUS "Rust DLL install rules configured for multi-config generator")
else()
  # Single-config: determine build type from CMAKE_BUILD_TYPE
  if(CMAKE_BUILD_TYPE STREQUAL "Debug" OR CMAKE_BUILD_TYPE STREQUAL "")
    set(RUST_BUILD_TYPE "debug")
    set(RUST_ALT_BUILD_TYPE "release")
  else()
    set(RUST_BUILD_TYPE "release")
    set(RUST_ALT_BUILD_TYPE "debug")
  endif()
  
  set(RUST_DLL_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../../rust/target/${RUST_BUILD_TYPE}/${RUST_DLL_NAME}")
  set(RUST_DLL_ALT_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../../rust/target/${RUST_ALT_BUILD_TYPE}/${RUST_DLL_NAME}")
  
  # Use install(CODE) to check existence at install-time, not configure-time
  install(CODE "
    set(RUST_DLL_PATH \"${RUST_DLL_PATH}\")
    set(RUST_DLL_ALT_PATH \"${RUST_DLL_ALT_PATH}\")
    if(EXISTS \"\${RUST_DLL_PATH}\")
      message(STATUS \"Installing Rust DLL: \${RUST_DLL_PATH}\")
      file(INSTALL \"\${RUST_DLL_PATH}\" DESTINATION \"${INSTALL_BUNDLE_LIB_DIR}\")
    elseif(EXISTS \"\${RUST_DLL_ALT_PATH}\")
      message(STATUS \"Installing Rust DLL (alt): \${RUST_DLL_ALT_PATH}\")
      file(INSTALL \"\${RUST_DLL_ALT_PATH}\" DESTINATION \"${INSTALL_BUNDLE_LIB_DIR}\")
    else()
      message(WARNING \"Rust DLL not found. Build Rust first: cargo build --release\")
    endif()
  " COMPONENT Runtime)
  message(STATUS "Rust DLL install rules configured for ${RUST_BUILD_TYPE} build")
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
