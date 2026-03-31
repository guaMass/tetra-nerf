cmake_minimum_required(VERSION 3.22.1)
project(fast_traversal LANGUAGES CXX CUDA)

if(POLICY CMP0167)
  cmake_policy(SET CMP0167 OLD)
endif()

set(CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake" ${CMAKE_MODULE_PATH})

if(NOT CMAKE_CONFIGURATION_TYPES AND NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

find_package(Python3 COMPONENTS Interpreter Development.Module REQUIRED)
set(PYTHON_EXECUTABLE "${Python3_EXECUTABLE}")

find_package(Torch REQUIRED)
find_package(CGAL REQUIRED)
find_package(OptiX REQUIRED)
find_package(CUDAToolkit REQUIRED)

set(PYBIND11_FINDPYTHON ON)

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

include_directories(${OptiX_INCLUDE} ${CUDAToolkit_INCLUDE_DIRS})

find_program(BIN2C bin2c
  HINTS
    "${CUDAToolkit_BIN_DIR}"
    "$ENV{CUDA_PATH}/bin"
  DOC "Path to the CUDA SDK bin2c executable")

if(NOT BIN2C)
  message(FATAL_ERROR "Could not find bin2c. Install CUDA toolkit samples/tools and ensure bin2c is on PATH.")
endif()

set(_ptx_arch_candidates "")
foreach(arch IN LISTS CMAKE_CUDA_ARCHITECTURES)
  if(arch MATCHES "^[0-9]+$")
    list(APPEND _ptx_arch_candidates "${arch}")
  endif()
endforeach()
if(_ptx_arch_candidates)
  list(SORT _ptx_arch_candidates COMPARE NATURAL)
  list(GET _ptx_arch_candidates -1 PTX_ARCH)
else()
  set(PTX_ARCH 75)
endif()
set(PTX_ARCH_FLAG "--gpu-architecture=compute_${PTX_ARCH}")

function(compile_ptx_and_embed cuda_file output_var symbol_name)
  get_filename_component(cuda_name "${cuda_file}" NAME_WE)
  set(ptx_file "${BUILD_DIRECTORY}/${cuda_name}.ptx")
  set(embedded_file "${BUILD_DIRECTORY}/${cuda_name}_embedded.cpp")

  add_custom_command(
    OUTPUT "${ptx_file}"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${BUILD_DIRECTORY}"
    COMMAND "${CUDAToolkit_NVCC_EXECUTABLE}"
      --ptx "${CMAKE_CURRENT_SOURCE_DIR}/${cuda_file}"
      -o "${ptx_file}"
      -I"${CMAKE_CURRENT_SOURCE_DIR}/src"
      -I"${OptiX_INCLUDE}"
      ${PTX_ARCH_FLAG}
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/${cuda_file}"
    COMMENT "Generating PTX from ${cuda_file}"
    VERBATIM)

  add_custom_command(
    OUTPUT "${embedded_file}"
    COMMAND ${CMAKE_COMMAND}
      -DBIN2C=${BIN2C}
      -DINPUT_FILE=${ptx_file}
      -DOUTPUT_FILE=${embedded_file}
      -DVARIABLE_NAME=${symbol_name}
      -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/RunBin2C.cmake
    DEPENDS "${ptx_file}"
    COMMENT "Embedding PTX ${ptx_file} into ${embedded_file}"
    VERBATIM)

  set(${output_var} "${embedded_file}" PARENT_SCOPE)
endfunction()

compile_ptx_and_embed("src/optix/optix_trace_rays.cu" trace_rays_embedded "ptx_code_file")
compile_ptx_and_embed("src/optix/optix_find_tetrahedra.cu" find_tetrahedra_embedded "ptx_code_file_find_tetrahedra")
compile_ptx_and_embed("src/optix/optix_trace_rays_triangles.cu" trace_triangles_embedded "ptx_code_file_triangles")

pybind11_add_module(tetranerf_cpp_extension
  src/tetrahedra_tracer.cu
  src/tetrahedra_tracer.cpp
  src/triangulation.cpp
  src/py_binding.cpp
  ${trace_rays_embedded}
  ${find_tetrahedra_embedded}
  ${trace_triangles_embedded})

target_link_libraries(tetranerf_cpp_extension PRIVATE
  ${TORCH_LIBRARIES}
  CGAL::CGAL
  CUDA::cudart)

target_compile_features(tetranerf_cpp_extension PRIVATE cxx_std_17)
set_target_properties(tetranerf_cpp_extension PROPERTIES
  CUDA_SEPARABLE_COMPILATION ON
  ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tetranerf/utils/extension"
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

if(MSVC)
  target_compile_options(tetranerf_cpp_extension PRIVATE $<$<COMPILE_LANGUAGE:CXX>:/bigobj>)
else()
  target_link_options(tetranerf_cpp_extension PRIVATE -flto=auto)
endif()
