cmake_minimum_required(VERSION 3.22.1)
project(fast_traversal LANGUAGES CXX CUDA)

set(CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake" ${CMAKE_MODULE_PATH})

if(NOT CMAKE_CONFIGURATION_TYPES AND NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

find_package(Python3 COMPONENTS Interpreter REQUIRED)
set(PYTHON_EXECUTABLE "${Python3_EXECUTABLE}")

find_package(Torch REQUIRED)
find_package(CGAL REQUIRED)
find_package(OptiX REQUIRED)
find_package(CUDAToolkit REQUIRED)
find_package(CUDA REQUIRED)

include(FetchContent)
FetchContent_Declare(
  pybind11
  GIT_REPOSITORY https://github.com/pybind/pybind11
  GIT_TAG v2.9.2
)
FetchContent_MakeAvailable(pybind11)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
set(BUILD_DIRECTORY "${CMAKE_BINARY_DIR}/build")
set(CUDA_GENERATED_OUTPUT_DIR "${BUILD_DIRECTORY}")

include_directories(${OptiX_INCLUDE} ${CUDA_INCLUDE_DIRS})

find_program(BIN2C bin2c
  HINTS
    "${CUDAToolkit_BIN_DIR}"
    "$ENV{CUDA_PATH}/bin"
  DOC "Path to the CUDA SDK bin2c executable")

if(NOT BIN2C)
  message(FATAL_ERROR "Could not find bin2c. Install CUDA toolkit samples/tools and ensure bin2c is on PATH.")
endif()

macro(cuda_compile_and_embed output_var generated_files_name)
  set(c_var_name ${output_var})
  set(generated_files "${${generated_files_name}}")
  list(GET generated_files 0 ptx_file)
  get_filename_component(embedded_file "${ptx_file}_embedded.cpp" NAME)
  set(embedded_file "${BUILD_DIRECTORY}/${embedded_file}")

  add_custom_command(
    OUTPUT ${embedded_file}
    COMMAND ${CMAKE_COMMAND}
      -DBIN2C=${BIN2C}
      -DINPUT_FILE=${ptx_file}
      -DOUTPUT_FILE=${embedded_file}
      -DVARIABLE_NAME=${c_var_name}
      -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunBin2C.cmake
    DEPENDS ${generated_files}
    COMMENT "Embedding PTX ${ptx_file} into ${embedded_file}"
    VERBATIM)

  set(${output_var} ${embedded_file})
  list(APPEND ${generated_files_name} ${embedded_file})
endmacro()

CUDA_WRAP_SRCS(traversal PTX generated_files_trace_rays
  src/optix_types.h
  src/optix/optix_trace_rays.cu
  src/utils/preprocessor.h
  src/utils/vec_math.h
  OPTIONS -rdc true)
cuda_compile_and_embed(ptx_code_file generated_files_trace_rays)

CUDA_WRAP_SRCS(traversal PTX generated_files_find_tetrahedra
  src/optix_types.h
  src/optix/optix_find_tetrahedra.cu
  src/utils/preprocessor.h
  src/utils/vec_math.h
  OPTIONS -rdc true)
cuda_compile_and_embed(ptx_code_file_find_tetrahedra generated_files_find_tetrahedra)

CUDA_WRAP_SRCS(traversal PTX generated_files_trace_rays_triangles
  src/optix_types.h
  src/optix/optix_trace_rays_triangles.cu
  src/utils/preprocessor.h
  src/utils/vec_math.h
  OPTIONS -rdc true)
cuda_compile_and_embed(ptx_code_file_triangles generated_files_trace_rays_triangles)

set(generated_files
  ${generated_files_trace_rays}
  ${generated_files_find_tetrahedra}
  ${generated_files_trace_rays_triangles})

pybind11_add_module(tetranerf_cpp_extension
  src/tetrahedra_tracer.cu
  src/tetrahedra_tracer.cpp
  src/triangulation.cpp
  src/py_binding.cpp
  ${generated_files})

target_link_libraries(tetranerf_cpp_extension PRIVATE
  ${TORCH_LIBRARIES}
  CGAL::CGAL
  ${CUDA_LIBRARIES}
  CUDA::cudart)

target_compile_features(tetranerf_cpp_extension PRIVATE cxx_std_17)
set_target_properties(tetranerf_cpp_extension PROPERTIES
  CUDA_SEPARABLE_COMPILATION ON
  ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tetranerf/utils/extension"
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

if(MSVC)
  target_compile_options(tetranerf_cpp_extension PRIVATE /bigobj)
else()
  target_link_options(tetranerf_cpp_extension PRIVATE -flto=auto)
endif()
