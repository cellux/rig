set(MODULE_DIR "${CMAKE_CURRENT_LIST_DIR}")
set(GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
file(MAKE_DIRECTORY "${GENERATED_DIR}")

set(MODULE_LIST_FILE "${MODULE_DIR}/modules.txt")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${MODULE_LIST_FILE}")
if(NOT EXISTS "${MODULE_LIST_FILE}")
    message(FATAL_ERROR "Module list file not found: ${MODULE_LIST_FILE}")
endif()

file(STRINGS "${MODULE_LIST_FILE}" MODULE_NAMES_RAW)
set(MODULE_NAMES "")
foreach(MODULE_LINE IN LISTS MODULE_NAMES_RAW)
    string(STRIP "${MODULE_LINE}" MODULE_NAME)
    if(MODULE_NAME STREQUAL "" OR MODULE_NAME MATCHES "^#")
        continue()
    endif()
    list(APPEND MODULE_NAMES "${MODULE_NAME}")
endforeach()
if(MODULE_NAMES STREQUAL "")
    message(FATAL_ERROR "No modules were found in ${MODULE_LIST_FILE}")
endif()

set(MODULE_BUILD_SCRIPT "${CMAKE_SOURCE_DIR}/cmake/scripts/build_embedded_module.lua")
set(MODULE_REGISTRY_SCRIPT "${CMAKE_SOURCE_DIR}/cmake/scripts/generate_module_registry.lua")
set(FENNEL_MODULE_SOURCE "${MODULE_DIR}/fennel.lua")

set(MODULE_C_FILES "")
set(BYTECODE_SOURCES "")
set(MODULE_REGISTRY_DEPENDS
    "${MODULE_LIST_FILE}"
    "${MODULE_REGISTRY_SCRIPT}"
)

foreach(MODULE_NAME IN LISTS MODULE_NAMES)
    set(MODULE_C "${MODULE_DIR}/${MODULE_NAME}.c")
    set(MODULE_LUA "${MODULE_DIR}/${MODULE_NAME}.lua")
    set(MODULE_FNL "${MODULE_DIR}/${MODULE_NAME}.fnl")

    set_property(
        DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
        "${MODULE_C}" "${MODULE_LUA}" "${MODULE_FNL}"
    )

    if(EXISTS "${MODULE_C}")
        list(APPEND MODULE_C_FILES "${MODULE_C}")
        list(APPEND MODULE_REGISTRY_DEPENDS "${MODULE_C}")
    endif()

    if(NOT EXISTS "${MODULE_C}" AND NOT EXISTS "${MODULE_LUA}" AND NOT EXISTS "${MODULE_FNL}")
        message(FATAL_ERROR "Module '${MODULE_NAME}' is listed but none of ${MODULE_C}, ${MODULE_LUA}, or ${MODULE_FNL} exists.")
    endif()

    if(EXISTS "${MODULE_LUA}")
        list(APPEND MODULE_REGISTRY_DEPENDS "${MODULE_LUA}")
        set(MODULE_LUA_C "${GENERATED_DIR}/${MODULE_NAME}_lua_bc.c")
        set(MODULE_LUA_SYMBOL "rig_lua_module_${MODULE_NAME}_bytecode")
        set(MODULE_LUA_CHUNK_NAME "@rig/${MODULE_NAME}.lua")

        add_custom_command(
            OUTPUT "${MODULE_LUA_C}"
            COMMAND "${LUAJIT_BIN}" "${MODULE_BUILD_SCRIPT}"
                "${MODULE_LUA}" "${MODULE_LUA_C}" "${MODULE_LUA_SYMBOL}" "${MODULE_LUA_CHUNK_NAME}" "${FENNEL_MODULE_SOURCE}" "${LUAJIT_BIN}"
            DEPENDS
                "${MODULE_LUA}"
                "${MODULE_BUILD_SCRIPT}"
                "${FENNEL_MODULE_SOURCE}"
            VERBATIM
        )

        list(APPEND BYTECODE_SOURCES "${MODULE_LUA_C}")
    endif()

    if(EXISTS "${MODULE_FNL}")
        list(APPEND MODULE_REGISTRY_DEPENDS "${MODULE_FNL}")
        set(MODULE_FNL_C "${GENERATED_DIR}/${MODULE_NAME}_fnl_bc.c")
        set(MODULE_FNL_SYMBOL "rig_fennel_module_${MODULE_NAME}_bytecode")
        set(MODULE_FNL_CHUNK_NAME "@rig/${MODULE_NAME}.fnl")

        add_custom_command(
            OUTPUT "${MODULE_FNL_C}"
            COMMAND "${LUAJIT_BIN}" "${MODULE_BUILD_SCRIPT}"
                "${MODULE_FNL}" "${MODULE_FNL_C}" "${MODULE_FNL_SYMBOL}" "${MODULE_FNL_CHUNK_NAME}" "${FENNEL_MODULE_SOURCE}" "${LUAJIT_BIN}"
            DEPENDS
                "${MODULE_FNL}"
                "${MODULE_BUILD_SCRIPT}"
                "${FENNEL_MODULE_SOURCE}"
            VERBATIM
        )

        list(APPEND BYTECODE_SOURCES "${MODULE_FNL_C}")
    endif()
endforeach()

set(MODULE_REGISTRY_C "${GENERATED_DIR}/module_registry.c")
add_custom_command(
    OUTPUT "${MODULE_REGISTRY_C}"
    COMMAND "${LUAJIT_BIN}" "${MODULE_REGISTRY_SCRIPT}"
        "${MODULE_LIST_FILE}" "${MODULE_DIR}" "${MODULE_REGISTRY_C}"
    DEPENDS
        ${MODULE_REGISTRY_DEPENDS}
    VERBATIM
)
