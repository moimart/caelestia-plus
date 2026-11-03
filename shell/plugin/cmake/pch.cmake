# One precompiled header for every module. Declared on an INTERFACE library,
# each module that linked it compiled its own copy: 13 identical ~220 MB
# .gch files. Instead it's built once, in this object library, and every
# module reuses it (REUSE_FROM in qml-module.cmake).
#
# GCC only takes a PCH built with the same options, and macros that differ
# between modules (QT_GUI_LIB, <target>_EXPORTS, ...) must not be used in it.
# -Winvalid-pch is on, so a module that can't use it says so and builds
# without it.
#
# A pkg-config dependency of Services adds -D_REENTRANT, which would make GCC
# reject the PCH there. It's a no-op with today's glibc (threads always work),
# so every module gets it and they all match.
add_compile_definitions(_REENTRANT)

set(caelestia_pch_source "${CMAKE_CURRENT_BINARY_DIR}/caelestia-pch.cpp")
file(WRITE "${caelestia_pch_source}" "// Only here to build the shared precompiled header\n")
add_library(caelestia-pch OBJECT "${caelestia_pch_source}")
set_target_properties(caelestia-pch PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_link_libraries(caelestia-pch PRIVATE Qt::Core Qt::Qml)
target_precompile_headers(caelestia-pch PRIVATE
    <qobject.h>
    <qqmlintegration.h>
    <qstring.h>
    <qqmlengine.h>
    <qloggingcategory.h>
    <qvariant.h>
    <qtimer.h>
    <qdir.h>
    <qlist.h>
    <qstringlist.h>
    <qpointer.h>
)
