set(MODULE_DIR "${CMAKE_CURRENT_LIST_DIR}")
set(GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
file(MAKE_DIRECTORY "${GENERATED_DIR}")

# Explicit module load order (interleaved init: C then Lua for each module).
set(MODULE_NAMES
    core
)

set(MODULE_C_FILES "")
set(MODULE_LUA_FILES "")
foreach(MODULE_NAME IN LISTS MODULE_NAMES)
    set(MODULE_C "${MODULE_DIR}/${MODULE_NAME}.c")
    set(MODULE_LUA "${MODULE_DIR}/${MODULE_NAME}.lua")

    if(EXISTS "${MODULE_C}")
        list(APPEND MODULE_C_FILES "${MODULE_C}")
    endif()
    if(EXISTS "${MODULE_LUA}")
        list(APPEND MODULE_LUA_FILES "${MODULE_LUA}")
    endif()

    if(NOT EXISTS "${MODULE_C}" AND NOT EXISTS "${MODULE_LUA}")
        message(FATAL_ERROR "Module '${MODULE_NAME}' is listed but neither ${MODULE_C} nor ${MODULE_LUA} exists.")
    endif()
endforeach()

set(BYTECODE_SOURCES "")
foreach(MODULE_NAME IN LISTS MODULE_NAMES)
    set(MODULE_LUA "${MODULE_DIR}/${MODULE_NAME}.lua")
    if(EXISTS "${MODULE_LUA}")
        set(MODULE_LJBC "${GENERATED_DIR}/${MODULE_NAME}.ljbc")
        set(MODULE_LUA_C "${GENERATED_DIR}/${MODULE_NAME}_lua_bc.c")
        set(MODULE_SYMBOL "rig_lua_module_${MODULE_NAME}_bytecode")

        add_custom_command(
            OUTPUT "${MODULE_LJBC}"
            COMMAND "${LUAJIT_BIN}" -b "${MODULE_LUA}" "${MODULE_LJBC}"
            DEPENDS "${MODULE_LUA}"
            VERBATIM
        )

        add_custom_command(
            OUTPUT "${MODULE_LUA_C}"
            COMMAND "${CMAKE_COMMAND}"
                -DINPUT=${MODULE_LJBC}
                -DOUTPUT=${MODULE_LUA_C}
                -DSYMBOL=${MODULE_SYMBOL}
                -P "${CMAKE_SOURCE_DIR}/cmake/scripts/embed_lua_module.cmake"
            DEPENDS
                "${MODULE_LJBC}"
                "${CMAKE_SOURCE_DIR}/cmake/scripts/embed_lua_module.cmake"
            VERBATIM
        )

        list(APPEND BYTECODE_SOURCES "${MODULE_LUA_C}")
    endif()
endforeach()

set(MODULE_REGISTRY_C "${GENERATED_DIR}/module_registry.c")

set(C_MODULE_PROTOTYPES "")
set(LUA_MODULE_EXTERNS "")
set(MODULE_ENTRIES "")

foreach(MODULE_NAME IN LISTS MODULE_NAMES)
    set(MODULE_C "${MODULE_DIR}/${MODULE_NAME}.c")
    set(MODULE_LUA "${MODULE_DIR}/${MODULE_NAME}.lua")

    if(EXISTS "${MODULE_C}")
        string(APPEND C_MODULE_PROTOTYPES "void rig_register_${MODULE_NAME}(lua_State *L);\n")
        set(MODULE_REGISTER_FN "rig_register_${MODULE_NAME}")
    else()
        set(MODULE_REGISTER_FN "NULL")
    endif()

    if(EXISTS "${MODULE_LUA}")
        string(APPEND LUA_MODULE_EXTERNS "extern const unsigned char rig_lua_module_${MODULE_NAME}_bytecode[];\n")
        string(APPEND LUA_MODULE_EXTERNS "extern const size_t rig_lua_module_${MODULE_NAME}_bytecode_len;\n")
        set(MODULE_BYTECODE "rig_lua_module_${MODULE_NAME}_bytecode")
        set(MODULE_BYTECODE_LEN "&rig_lua_module_${MODULE_NAME}_bytecode_len")
    else()
        set(MODULE_BYTECODE "NULL")
        set(MODULE_BYTECODE_LEN "NULL")
    endif()

    string(APPEND MODULE_ENTRIES "    { \"${MODULE_NAME}\", ${MODULE_REGISTER_FN}, ${MODULE_BYTECODE}, ${MODULE_BYTECODE_LEN} },\n")
endforeach()

if(MODULE_ENTRIES STREQUAL "")
    set(MODULE_ENTRIES "    { NULL, NULL, NULL, NULL },\n")
    set(MODULE_COUNT_EXPR "0")
else()
    set(MODULE_COUNT_EXPR "(sizeof(rig_modules) / sizeof(rig_modules[0]))")
endif()

file(WRITE "${MODULE_REGISTRY_C}" "/* Generated file. Do not edit. */\n")
file(APPEND "${MODULE_REGISTRY_C}" "#include <stddef.h>\n")
file(APPEND "${MODULE_REGISTRY_C}" "#include <lua.h>\n\n")
file(APPEND "${MODULE_REGISTRY_C}" "#include \"runtime.h\"\n\n")
file(APPEND "${MODULE_REGISTRY_C}" "${C_MODULE_PROTOTYPES}\n")
file(APPEND "${MODULE_REGISTRY_C}" "${LUA_MODULE_EXTERNS}\n")
file(APPEND "${MODULE_REGISTRY_C}" "const rig_module_desc rig_modules[] = {\n${MODULE_ENTRIES}};\n")
file(APPEND "${MODULE_REGISTRY_C}" "const size_t rig_module_count = ${MODULE_COUNT_EXPR};\n")
