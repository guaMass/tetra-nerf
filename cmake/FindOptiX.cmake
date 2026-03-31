# Locate OptiX SDK headers.

set(_optix_default_paths
  "$ENV{OPTIX_PATH}"
  "$ENV{OPTIX_INSTALL_DIR}"
  "${CMAKE_SOURCE_DIR}/../../"
  "C:/ProgramData/NVIDIA Corporation"
  "C:/ProgramData/NVIDIA Corporation/OptiX SDK 8.0.0"
  "C:/ProgramData/NVIDIA Corporation/OptiX SDK 7.7.0"
  "C:/ProgramData/NVIDIA Corporation/OptiX SDK 7.6.0")

set(OptiX_INSTALL_DIR "" CACHE PATH "Path to OptiX SDK installation root (folder containing include/optix.h).")

if(OptiX_INSTALL_DIR)
  list(INSERT _optix_default_paths 0 "${OptiX_INSTALL_DIR}")
endif()

if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
  if(WIN32)
    message(SEND_ERROR "Make sure to use a 64-bit Visual Studio generator (e.g. -A x64).")
  endif()
  message(FATAL_ERROR "OptiX only supports 64-bit builds.")
endif()

find_path(OptiX_INCLUDE
  NAMES optix.h
  PATH_SUFFIXES include
  PATHS ${_optix_default_paths})

function(OptiX_report_error error_message required component)
  if(DEFINED OptiX_FIND_REQUIRED_${component} AND NOT OptiX_FIND_REQUIRED_${component})
    set(required FALSE)
  endif()
  if(OptiX_FIND_REQUIRED AND required)
    message(FATAL_ERROR "${error_message} Please locate before proceeding.")
  elseif(NOT OptiX_FIND_QUIETLY)
    message(STATUS "${error_message}")
  endif()
endfunction()

if(NOT OptiX_INCLUDE)
  OptiX_report_error("OptiX headers (optix.h and friends) not found." TRUE headers)
endif()
