#!/bin/bash
# Copyright (c) 2021, NVIDIA CORPORATION. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


set -e

PYTHON_MAJOR_VERSION=${PYTHON_MAJOR_VERSION:-3}
PYTHON_MINOR_VERSION=${PYTHON_MINOR_VERSION:-12}
TARGET=${TARGET_ARCHITECTURE:-aarch64}
CUDA_ROOT=${CUDA_ROOT:-/usr/local/cuda}
ROOT_PATH=${TRT_OSSPATH:?Error: TRT_OSSPATH is not set}
EXT_PATH=${EXT_PATH}
WHEEL_OUTPUT_DIR=${ROOT_PATH}/python/build
HEADER_PATH=/usr/include/aarch64-linux-gnu

while getopts ":c:" opt; do
  case $opt in
    c)
      CUDA_VERSION=$OPTARG
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done
shift $((OPTIND-1))

# default CUDA_VERSION if not provided via argument
CUDA_VERSION=${CUDA_VERSION:-11.4}


mkdir -p "${WHEEL_OUTPUT_DIR}"
pushd "${WHEEL_OUTPUT_DIR}"

# Generate tensorrt.so
cmake .. -DCMAKE_BUILD_TYPE=Release \
         -DTARGET="${TARGET}" \
         -DPYTHON_MAJOR_VERSION="${PYTHON_MAJOR_VERSION}" \
         -DPYTHON_MINOR_VERSION="${PYTHON_MINOR_VERSION}" \
         -DEXT_PATH="${EXT_PATH}" \
         -DCUDA_INCLUDE_DIRS="${CUDA_ROOT}/include" \
         -DTENSORRT_ROOT="${ROOT_PATH}" \
         -DTENSORRT_BUILD="${ROOT_PATH}/build/" \
         -DTENSORRT_MODULE="${TENSORRT_MODULE}" \
         -DPY_INCLUDE=/usr/include/python3.12 \
         -DPYTHON_LIBRARY=/usr/lib/aarch64-linux-gnu/libpython3.12.so \
         -DPYTHON_EXECUTABLE=/usr/bin/python3.12 \
         -DCMAKE_VERBOSE_MAKEFILE=ON
make -j12


TENSORRT_MODULE_NAME="tensorrt"
COMPILED_SO_SOURCE="${WHEEL_OUTPUT_DIR}/${TENSORRT_MODULE_NAME}/tensorrt.so"
DEST_SO_DIR="${WHEEL_OUTPUT_DIR}/bindings_wheel/${TENSORRT_MODULE_NAME}"
mkdir -p "${DEST_SO_DIR}"
cp "${COMPILED_SO_SOURCE}" "${DEST_SO_DIR}/"


# Generate wheel
TRT_MAJOR=$(awk '/^\#define NV_TENSORRT_MAJOR/ {print $3}' "${HEADER_PATH}"/NvInferVersion.h)
TRT_MINOR=$(awk '/^\#define NV_TENSORRT_MINOR/ {print $3}' "${HEADER_PATH}"/NvInferVersion.h)
TRT_PATCH=$(awk '/^\#define NV_TENSORRT_PATCH/ {print $3}' "${HEADER_PATH}"/NvInferVersion.h)
TRT_BUILD=$(awk '/^\#define NV_TENSORRT_BUILD/ {print $3}' "${HEADER_PATH}"/NvInferVersion.h)
TRT_VERSION=${TRT_MAJOR}.${TRT_MINOR}.${TRT_PATCH}.${TRT_BUILD}
TRT_MAJMINPATCH=${TRT_MAJOR}.${TRT_MINOR}.${TRT_PATCH}

expand_vars_cp () {
    test -f "${1}" || (echo "ERROR: File: ${1} does not exist!" && exit 1); \
    sed -e "s|\#\#TENSORRT_VERSION\#\#|${TRT_VERSION}|g" \
        -e "s|\#\#TENSORRT_MAJMINPATCH\#\#|${TRT_MAJMINPATCH}|g" \
        -e "s|\#\#TENSORRT_PYTHON_VERSION\#\#|${TRT_VERSION}|g" \
        -e "s|\#\#TENSORRT_MODULE\#\#|${TENSORRT_MODULE}|g" \
        "${1}" > "${2}"
}


pushd "${ROOT_PATH}"/python/packaging
for dir in $(find . -type d); do mkdir -p "${WHEEL_OUTPUT_DIR}"/"${dir}"; done
for file in $(find . -type f); do expand_vars_cp "${file}" "${WHEEL_OUTPUT_DIR}"/"${file}"; done
popd

export CUDA="${CUDA_VERSION}"

# Iterate through each wheel directory and build its wheel
for WHEEL_DIR_PATH in "${WHEEL_OUTPUT_DIR}"/*_wheel; do
    if [ -d "$WHEEL_DIR_PATH" ]; then
        pushd "$WHEEL_DIR_PATH" > /dev/null
        /usr/bin/python3.12 setup.py -q bdist_wheel --python-tag=cp"${PYTHON_MAJOR_VERSION}""${PYTHON_MINOR_VERSION}" --plat-name=linux_"${TARGET}"
        popd > /dev/null
    fi
done

popd
