idf_component_register(
    SRCS
        "audio_module.c"
    INCLUDE_DIRS
        "."
    REQUIRES
        espressif__esp_audio_codec
        espressif__esp-dsp
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

idf_build_get_property(audio_build_dir BUILD_DIR)
idf_component_get_property(audio_codec_dir espressif__esp_audio_codec COMPONENT_DIR)
idf_component_get_property(audio_dsp_dir espressif__esp-dsp COMPONENT_DIR)
set(audio_patched_lib_dir "${audio_build_dir}/patched_libs")
set(audio_patched_simple_lib "${audio_patched_lib_dir}/libesp_audio_simple_dec_picfix.a")
set(audio_patched_codec_lib "${audio_patched_lib_dir}/libesp_audio_codec_picfix.a")
string(REPLACE "-elf-gcc" "-elf-objcopy" audio_objcopy "${CMAKE_C_COMPILER}")

add_custom_command(
    OUTPUT "${audio_patched_simple_lib}"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${audio_patched_lib_dir}"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${audio_codec_dir}/lib/${IDF_TARGET}/libesp_audio_simple_dec.a"
            "${audio_patched_simple_lib}"
    COMMAND "${audio_objcopy}"
            --rename-section .rodata=.data.audio_wav_reg,alloc,load,contents,data
            "${audio_patched_simple_lib}"
    DEPENDS "${audio_codec_dir}/lib/${IDF_TARGET}/libesp_audio_simple_dec.a"
    VERBATIM
)

add_custom_command(
    OUTPUT "${audio_patched_codec_lib}"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${audio_patched_lib_dir}"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${audio_codec_dir}/lib/${IDF_TARGET}/libesp_audio_codec.a"
            "${audio_patched_codec_lib}"
    COMMAND "${audio_objcopy}"
            --rename-section .rodata.dec_lib$0=.data.audio_dec_lib,alloc,load,contents,data
            --rename-section .iram1=.text.audio_iram,alloc,load,contents,code
            --rename-section .iram1.literal=.literal.audio_iram,alloc,load,contents
            "${audio_patched_codec_lib}"
    DEPENDS "${audio_codec_dir}/lib/${IDF_TARGET}/libesp_audio_codec.a"
    VERBATIM
)

add_custom_target(audio_picfix_libs
    DEPENDS "${audio_patched_simple_lib}" "${audio_patched_codec_lib}"
)

set(audio_so_include_dirs
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_BINARY_DIR}/config"
    "${IDF_PATH}/components/newlib/platform_include"
    "${IDF_PATH}/components/esp_common/include"
    "${IDF_PATH}/components/esp_system/include"
    "${IDF_PATH}/components/esp_rom/include"
    "${IDF_PATH}/components/esp_rom/${IDF_TARGET}/include"
    "${IDF_PATH}/components/log/include"
    "${IDF_PATH}/components/soc/include"
    "${IDF_PATH}/components/soc/${IDF_TARGET}/include"
    "${IDF_PATH}/components/soc/${IDF_TARGET}/register"
    "${IDF_PATH}/components/hal/include"
    "${IDF_PATH}/components/heap/include"
    "${IDF_PATH}/components/esp_hw_support/include"
    "${IDF_PATH}/components/esp_hw_support/port/${IDF_TARGET}/include"
    "${IDF_PATH}/components/freertos/config/include"
    "${IDF_PATH}/components/freertos/config/include/freertos"
    "${IDF_PATH}/components/freertos/config/xtensa/include"
    "${IDF_PATH}/components/freertos/FreeRTOS-Kernel/include"
    "${IDF_PATH}/components/freertos/FreeRTOS-Kernel/portable/xtensa/include"
    "${IDF_PATH}/components/freertos/FreeRTOS-Kernel/portable/xtensa/include/freertos"
    "${IDF_PATH}/components/freertos/esp_additions/include"
    "${IDF_PATH}/components/xtensa/include"
    "${IDF_PATH}/components/xtensa/${IDF_TARGET}/include"
    "${IDF_PATH}/components/vfs/include"
    "${audio_codec_dir}/include"
    "${audio_codec_dir}/include/decoder"
    "${audio_codec_dir}/include/decoder/impl"
    "${audio_codec_dir}/include/simple_dec"
    "${audio_codec_dir}/include/simple_dec/impl"
    "${audio_dsp_dir}/modules/common/include"
    "${audio_dsp_dir}/modules/iir/include"
)
foreach(audio_so_include_dir IN LISTS audio_so_include_dirs)
    idf_build_set_property(COMPILE_INCLUDE_DIRECTORIES "${audio_so_include_dir}" APPEND)
endforeach()

set(ELF_LIBS
    "${audio_build_dir}/esp-idf/espressif__esp_audio_codec/libespressif__esp_audio_codec.a"
    "${audio_build_dir}/esp-idf/espressif__esp-dsp/libespressif__esp-dsp.a"
    "${audio_patched_simple_lib}"
    "${audio_patched_codec_lib}"
)
set(ELF_SO_LINK_FLAGS
    "-Wl,-Bsymbolic"
    "-Wl,--exclude-libs,ALL"
    "-Wl,-z,notext"
    "-Wl,--no-check-sections"
    "-Wl,-N"
    "-Wl,-Map,${audio_build_dir}/audio_so.map"
)

include(elf_loader)
project_so(audio)
add_dependencies(so audio_picfix_libs)
