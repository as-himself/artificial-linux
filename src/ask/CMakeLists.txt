cmake_minimum_required(VERSION 3.10)
project(ask CXX)

find_package(CURL REQUIRED)
add_executable(ask ask.cpp)
target_link_libraries(ask PRIVATE CURL::libcurl)
target_compile_features(ask PRIVATE cxx_std_11)
install(TARGETS ask DESTINATION bin)
