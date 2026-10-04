cmake_minimum_required(VERSION 3.22)
project(rshop_owned_storage LANGUAGES CXX)
# AGP can run two ABI build tasks concurrently. Give each Ninja build one
# shared compile/link slot so the two-worker Gradle profile bounds native work.
set_property(GLOBAL PROPERTY JOB_POOLS rshop_native=1)
set(CMAKE_JOB_POOL_COMPILE rshop_native)
set(CMAKE_JOB_POOL_LINK rshop_native)
add_library(rshop_owned_storage SHARED owned_storage.cpp owned_storage_jni.cpp)
target_compile_features(rshop_owned_storage PRIVATE cxx_std_17)
target_compile_definitions(rshop_owned_storage PRIVATE _FILE_OFFSET_BITS=64)
target_compile_options(rshop_owned_storage PRIVATE -Wall -Wextra -Werror)
target_link_libraries(rshop_owned_storage PRIVATE dl)
