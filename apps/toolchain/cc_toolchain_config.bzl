"""C++ toolchain config that wraps the Debian aarch64-linux-gnu cross compiler.

This targets the Raspberry Pi Zero 2 W's 64-bit (ARMv8-A, aarch64) userland on a
Cortex-A53 and links fully statically, so the resulting binary can be dropped
straight into the Raspberry Pi OS rootfs regardless of its libc. The cross
compiler itself is installed in the builder Docker image (packages
gcc-aarch64-linux-gnu / g++-aarch64-linux-gnu).
"""

load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "ACTION_NAMES")
load(
    "@bazel_tools//tools/cpp:cc_toolchain_config_lib.bzl",
    "feature",
    "flag_group",
    "flag_set",
    "tool_path",
)

_TRIPLE = "aarch64-linux-gnu"
_BIN = "/usr/bin/" + _TRIPLE + "-"

_COMPILE_ACTIONS = [
    ACTION_NAMES.c_compile,
    ACTION_NAMES.cpp_compile,
    ACTION_NAMES.linkstamp_compile,
    ACTION_NAMES.assemble,
    ACTION_NAMES.preprocess_assemble,
    ACTION_NAMES.cpp_header_parsing,
    ACTION_NAMES.cpp_module_compile,
    ACTION_NAMES.cpp_module_codegen,
]

_LINK_ACTIONS = [
    ACTION_NAMES.cpp_link_executable,
    ACTION_NAMES.cpp_link_dynamic_library,
    ACTION_NAMES.cpp_link_nodeps_dynamic_library,
]

# Cortex-A53, 64-bit (ARMv8-A). aarch64 is hard-float by definition, so no
# -mfpu / -mfloat-abi flags (those are 32-bit ARM only).
_ARCH_FLAGS = [
    "-mcpu=cortex-a53",
    "-no-canonical-prefixes",
]

def _impl(ctx):
    # Use g++ as the driver for both compiling and linking so libstdc++ is
    # pulled in automatically and in the right order under -static.
    tool_paths = [
        tool_path(name = "gcc", path = _BIN + "g++"),
        tool_path(name = "cpp", path = _BIN + "cpp"),
        tool_path(name = "ar", path = _BIN + "ar"),
        tool_path(name = "ld", path = _BIN + "ld"),
        tool_path(name = "nm", path = _BIN + "nm"),
        tool_path(name = "objcopy", path = _BIN + "objcopy"),
        tool_path(name = "objdump", path = _BIN + "objdump"),
        tool_path(name = "strip", path = _BIN + "strip"),
        tool_path(name = "gcov", path = _BIN + "gcov"),
    ]

    default_compile = feature(
        name = "default_compile_flags",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = _COMPILE_ACTIONS,
                flag_groups = [flag_group(flags = _ARCH_FLAGS + ["-Wall"])],
            ),
            flag_set(
                actions = [
                    ACTION_NAMES.cpp_compile,
                    ACTION_NAMES.cpp_header_parsing,
                    ACTION_NAMES.cpp_module_compile,
                ],
                flag_groups = [flag_group(flags = ["-std=c++17"])],
            ),
        ],
    )

    # Toggled on by `-c opt` (set in .bazelrc): optimize, and strip symbols at
    # link time (-s) so the embedded binary stays small.
    opt = feature(
        name = "opt",
        flag_sets = [
            flag_set(
                actions = _COMPILE_ACTIONS,
                flag_groups = [flag_group(flags = ["-O2", "-DNDEBUG"])],
            ),
            flag_set(
                actions = _LINK_ACTIONS,
                flag_groups = [flag_group(flags = ["-s"])],
            ),
        ],
    )

    default_link = feature(
        name = "default_link_flags",
        enabled = True,
        flag_sets = [flag_set(
            actions = _LINK_ACTIONS,
            flag_groups = [flag_group(flags = _ARCH_FLAGS + ["-static"])],
        )],
    )

    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        toolchain_identifier = "yarik-aarch64",
        host_system_name = "local",
        target_system_name = _TRIPLE,
        target_cpu = "aarch64",
        target_libc = "glibc",
        compiler = "gcc",
        abi_version = "aarch64",
        abi_libc_version = "glibc",
        tool_paths = tool_paths,
        features = [default_compile, opt, default_link],
        # Prefixes Bazel accepts for compiler-discovered system headers. Broad
        # prefixes cover the gcc-version-specific subdirectories and both layouts:
        # a native aarch64 builder resolves headers under /usr/include, while a
        # true cross host (e.g. x86 CI) uses the /usr/<triple>/include sysroot.
        cxx_builtin_include_directories = [
            "/usr/include",
            "/usr/" + _TRIPLE + "/include",
            "/usr/lib/gcc-cross/" + _TRIPLE,
            "/usr/lib/gcc-cross",
            "/usr/lib/gcc",
        ],
    )

cc_toolchain_config = rule(
    implementation = _impl,
    attrs = {},
    provides = [CcToolchainConfigInfo],
)
