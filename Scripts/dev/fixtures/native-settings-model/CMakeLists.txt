cmake_minimum_required(VERSION 3.24)
project(AtmospheraSettingsModelControls LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_AUTOMOC ON)
find_package(Qt6 REQUIRED COMPONENTS Core Qml)
find_package(configqml CONFIG REQUIRED)
if(NOT CONFIGQML_TEST_SOURCE)
  message(FATAL_ERROR "Exact archived library source is required for the test friend")
endif()
qt_add_qml_module(atmosphera_settings_test SHARED
  URI AtmospheraSettingsTest VERSION 1.0
  OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/AtmospheraSettingsTest"
  SOURCES owner.h owner.cpp probe.h probe.cpp)
target_link_libraries(atmosphera_settings_test PRIVATE configqml::configqml Qt6::Core Qt6::Qml)
target_include_directories(atmosphera_settings_test PRIVATE "${CONFIGQML_TEST_SOURCE}")
add_library(atmosphera_native_io SHARED native-io.cpp)
target_link_libraries(atmosphera_native_io PRIVATE configqml::core Qt6::Core ${CMAKE_DL_LIBS})
target_include_directories(atmosphera_native_io PRIVATE "${CONFIGQML_TEST_SOURCE}")
