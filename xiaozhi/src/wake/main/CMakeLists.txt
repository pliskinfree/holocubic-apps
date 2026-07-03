idf_component_register(
    SRCS
        "wake_module.c"
    INCLUDE_DIRS
        "."
        "${CMAKE_CURRENT_LIST_DIR}/../.."
    REQUIRES
        espressif__esp-sr
)

target_compile_definitions(${COMPONENT_LIB} PRIVATE WAKE_USE_ESP_SR=1)
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
