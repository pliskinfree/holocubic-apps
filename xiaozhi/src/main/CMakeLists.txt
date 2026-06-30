set(MODULE_ABI_DIR "" CACHE PATH "Directory containing module_abi.h")

if(NOT MODULE_ABI_DIR AND DEFINED ENV{CUBICLUA_ROOT} AND EXISTS "$ENV{CUBICLUA_ROOT}/src/dynmod/module_abi.h")
    set(MODULE_ABI_DIR "$ENV{CUBICLUA_ROOT}/src/dynmod")
endif()

if(NOT MODULE_ABI_DIR AND EXISTS "${CMAKE_CURRENT_LIST_DIR}/../../../src/dynmod/module_abi.h")
    set(MODULE_ABI_DIR "${CMAKE_CURRENT_LIST_DIR}/../../../src/dynmod")
endif()

if(NOT EXISTS "${MODULE_ABI_DIR}/module_abi.h")
    message(FATAL_ERROR "module_abi.h not found. Set MODULE_ABI_DIR=/path/to/src/dynmod or CUBICLUA_ROOT.")
endif()

idf_component_register(
    SRCS
        "xiaozhi_module.c"
    INCLUDE_DIRS
        "."
        "${MODULE_ABI_DIR}"
    REQUIRES
        78__esp-opus
)

target_compile_options(${COMPONENT_LIB} PRIVATE
    -fPIC
    -fvisibility=hidden
    -fno-jump-tables
    -fno-tree-switch-conversion
    -fno-builtin-memcpy
    -fno-builtin-memmove
    -fno-builtin-memset
    -fno-builtin-strlen
    -fno-builtin-strcpy
    -fno-builtin-malloc
    -fno-builtin-free
)
