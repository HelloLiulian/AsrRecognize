"""Generate a deterministic Xcode project for the AsrRecognize app."""

from __future__ import annotations

import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT_DIR = ROOT / "AsrRecognize.xcodeproj"
APP_DIR = ROOT / "AsrRecognize"

TARGET_NAME = "AsrRecognize"
BUNDLE_ID = "com.liulian.AsrRecognize"
DEPLOYMENT_TARGET = "18.0"
SPEECH_SWIFT_URL = "https://github.com/soniqo/speech-swift"

SAFE_VALUE = re.compile(r"^[A-Za-z0-9_./$+\-]+$")


def gid(key: str) -> str:
    return hashlib.md5(key.encode("utf-8")).hexdigest()[:24].upper()


def value(text: str) -> str:
    if SAFE_VALUE.match(text):
        return text
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def files_by_group() -> dict[str, list[Path]]:
    groups: dict[str, list[Path]] = {}
    for path in sorted(APP_DIR.rglob("*.swift")):
        relative = path.relative_to(APP_DIR)
        group = relative.parts[0] if len(relative.parts) > 1 else ""
        groups.setdefault(group, []).append(path)
    return groups


def build() -> str:
    groups = files_by_group()

    refs: list[str] = []
    build_files: list[str] = []
    source_build_ids: list[str] = []

    def file_ref(path: Path, file_type: str) -> str:
        key = "file-" + str(path.relative_to(ROOT)).replace("\\", "/")
        ref_id = gid(key)
        refs.append(
            f"\t\t{ref_id} /* {path.name} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = {value(file_type)}; path = {value(path.name)}; "
            'sourceTree = "<group>"; };\n'
        )
        return ref_id

    assets_ref = file_ref(APP_DIR / "Assets.xcassets", "folder.assetcatalog")
    info_ref = file_ref(APP_DIR / "Info.plist", "text.plist.xml")

    asset_build = gid("build-assets")
    build_files.append(
        f"\t\t{asset_build} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; "
        f"fileRef = {assets_ref} /* Assets.xcassets */; }};\n"
    )

    # 蓝色文件夹引用：模型由 tools/prepare-model.sh 或 CI 填入同一目录
    model_ref = gid("file-model-dir")
    refs.append(
        f"\t\t{model_ref} /* Qwen3ASR */ = {{isa = PBXFileReference; "
        "lastKnownFileType = folder; path = Resources/Qwen3ASR; "
        'sourceTree = "<group>"; };\n'
    )
    model_build = gid("build-model-dir")
    build_files.append(
        f"\t\t{model_build} /* Qwen3ASR in Resources */ = {{isa = PBXBuildFile; "
        f"fileRef = {model_ref} /* Qwen3ASR */; }};\n"
    )

    package_ref = gid("package-speech-swift")
    package_product = gid("product-qwen3asr")
    package_build = gid("build-qwen3asr")
    build_files.append(
        f"\t\t{package_build} /* Qwen3ASR in Frameworks */ = {{isa = PBXBuildFile; "
        f"productRef = {package_product} /* Qwen3ASR */; }};\n"
    )

    subgroup_lines: list[str] = []
    for group_name in sorted(groups):
        child_lines: list[str] = []
        for path in groups[group_name]:
            ref_id = file_ref(path, "sourcecode.swift")
            build_id = gid("build-" + str(path.relative_to(ROOT)).replace("\\", "/"))
            build_files.append(
                f"\t\t{build_id} /* {path.name} in Sources */ = {{isa = PBXBuildFile; "
                f"fileRef = {ref_id} /* {path.name} */; }};\n"
            )
            source_build_ids.append(build_id)
            child_lines.append(f"\t\t\t\t{ref_id} /* {path.name} */,\n")

        group_id = gid("group-" + group_name)
        subgroup_lines.append(
            f"\t\t{group_id} /* {group_name} */ = {{\n"
            "\t\t\tisa = PBXGroup;\n"
            "\t\t\tchildren = (\n"
            + "".join(child_lines)
            + "\t\t\t);\n"
            f"\t\t\tpath = {group_name};\n"
            "\t\t\tsourceTree = \"<group>\";\n"
            "\t\t};\n"
        )

    main_group = gid("group-main")
    products_group = gid("group-products")
    app_group = gid("group-app")
    product_ref = gid("product-app")
    target_id = gid("target-app")
    project_id = gid("project")
    sources_phase = gid("phase-sources")
    frameworks_phase = gid("phase-frameworks")
    resources_phase = gid("phase-resources")
    project_config_list = gid("configlist-project")
    target_config_list = gid("configlist-target")
    project_debug = gid("config-project-debug")
    project_release = gid("config-project-release")
    target_debug = gid("config-target-debug")
    target_release = gid("config-target-release")

    app_group_children = [
        f"\t\t\t\t{info_ref} /* Info.plist */,\n",
        f"\t\t\t\t{assets_ref} /* Assets.xcassets */,\n",
        f"\t\t\t\t{model_ref} /* Qwen3ASR */,\n",
    ]
    for group_name in sorted(groups):
        app_group_children.append(
            f"\t\t\t\t{gid('group-' + group_name)} /* {group_name} */,\n"
        )

    source_entries = "".join(
        f"\t\t\t\t{build_id} /* {path.name} in Sources */,\n"
        for build_id, path in zip(
            source_build_ids,
            [p for g in sorted(groups) for p in groups[g]],
        )
    )

    product_line = (
        f"\t\t{product_ref} /* {TARGET_NAME}.app */ = {{isa = PBXFileReference; "
        f"explicitFileType = wrapper.application; includeInIndex = 0; "
        f"path = {TARGET_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n"
    )

    project_debug_settings = """
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 18.0;
\t\t\t\tLOCALIZATION_PREFERS_STRING_CATALOGS = YES;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
"""

    project_release_settings = """
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_USER_SCRIPT_SANDBOXING = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 18.0;
\t\t\t\tLOCALIZATION_PREFERS_STRING_CATALOGS = YES;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tVALIDATE_PRODUCT = YES;
"""

    target_common = f"""
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = AsrRecognize/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = {DEPLOYMENT_TARGET};
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = 1;
"""

    content = "// !$*UTF8*$!\n{\n"
    content += "\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 56;\n\tobjects = {\n\n"

    content += "/* Begin PBXBuildFile section */\n"
    content += "".join(build_files)
    content += "/* End PBXBuildFile section */\n\n"

    content += "/* Begin PBXFileReference section */\n"
    content += "".join(refs)
    content += product_line
    content += "/* End PBXFileReference section */\n\n"

    content += "/* Begin PBXFrameworksBuildPhase section */\n"
    content += (
        f"\t\t{frameworks_phase} /* Frameworks */ = {{\n"
        "\t\t\tisa = PBXFrameworksBuildPhase;\n"
        "\t\t\tbuildActionMask = 2147483647;\n"
        "\t\t\tfiles = (\n"
        f"\t\t\t\t{package_build} /* Qwen3ASR in Frameworks */,\n"
        "\t\t\t);\n"
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        "\t\t};\n"
    )
    content += "/* End PBXFrameworksBuildPhase section */\n\n"

    content += "/* Begin PBXGroup section */\n"
    content += (
        f"\t\t{main_group} = {{\n"
        "\t\t\tisa = PBXGroup;\n"
        "\t\t\tchildren = (\n"
        f"\t\t\t\t{app_group} /* {TARGET_NAME} */,\n"
        f"\t\t\t\t{products_group} /* Products */,\n"
        "\t\t\t);\n"
        "\t\t\tsourceTree = \"<group>\";\n"
        "\t\t};\n"
    )
    content += (
        f"\t\t{products_group} /* Products */ = {{\n"
        "\t\t\tisa = PBXGroup;\n"
        "\t\t\tchildren = (\n"
        f"\t\t\t\t{product_ref} /* {TARGET_NAME}.app */,\n"
        "\t\t\t);\n"
        "\t\t\tname = Products;\n"
        "\t\t\tsourceTree = \"<group>\";\n"
        "\t\t};\n"
    )
    content += (
        f"\t\t{app_group} /* {TARGET_NAME} */ = {{\n"
        "\t\t\tisa = PBXGroup;\n"
        "\t\t\tchildren = (\n"
        + "".join(app_group_children)
        + "\t\t\t);\n"
        f"\t\t\tpath = {TARGET_NAME};\n"
        "\t\t\tsourceTree = \"<group>\";\n"
        "\t\t};\n"
    )
    content += "".join(subgroup_lines)
    content += "/* End PBXGroup section */\n\n"

    content += "/* Begin PBXNativeTarget section */\n"
    content += (
        f"\t\t{target_id} /* {TARGET_NAME} */ = {{\n"
        "\t\t\tisa = PBXNativeTarget;\n"
        f"\t\t\tbuildConfigurationList = {target_config_list} /* Build configuration list for PBXNativeTarget \"{TARGET_NAME}\" */;\n"
        "\t\t\tbuildPhases = (\n"
        f"\t\t\t\t{sources_phase} /* Sources */,\n"
        f"\t\t\t\t{frameworks_phase} /* Frameworks */,\n"
        f"\t\t\t\t{resources_phase} /* Resources */,\n"
        "\t\t\t);\n"
        "\t\t\tbuildRules = (\n"
        "\t\t\t);\n"
        "\t\t\tdependencies = (\n"
        "\t\t\t);\n"
        f"\t\t\tname = {TARGET_NAME};\n"
        f"\t\t\tproductName = {TARGET_NAME};\n"
        f"\t\t\tproductReference = {product_ref} /* {TARGET_NAME}.app */;\n"
        "\t\t\tproductType = \"com.apple.product-type.application\";\n"
        "\t\t};\n"
    )
    content += "/* End PBXNativeTarget section */\n\n"

    content += "/* Begin PBXProject section */\n"
    content += (
        f"\t\t{project_id} /* Project object */ = {{\n"
        "\t\t\tisa = PBXProject;\n"
        "\t\t\tattributes = {\n"
        "\t\t\t\tBuildIndependentTargetsInParallel = 1;\n"
        "\t\t\t\tLastSwiftUpdateCheck = 1600;\n"
        "\t\t\t\tLastUpgradeCheck = 1600;\n"
        "\t\t\t\tTargetAttributes = {\n"
        f"\t\t\t\t\t{target_id} = {{\n"
        "\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n"
        "\t\t\t\t\t};\n"
        "\t\t\t\t};\n"
        "\t\t\t};\n"
        f"\t\t\tbuildConfigurationList = {project_config_list} /* Build configuration list for PBXProject \"{TARGET_NAME}\" */;\n"
        "\t\t\tcompatibilityVersion = \"Xcode 14.0\";\n"
        "\t\t\tdevelopmentRegion = en;\n"
        "\t\t\thasScannedForEncodings = 0;\n"
        "\t\t\tknownRegions = (\n"
        "\t\t\t\ten,\n"
        "\t\t\t\tBase,\n"
        "\t\t\t\t\"zh-Hans\",\n"
        "\t\t\t);\n"
        f"\t\t\tmainGroup = {main_group};\n"
        f"\t\t\tproductRefGroup = {products_group} /* Products */;\n"
        "\t\t\tprojectDirPath = \"\";\n"
        "\t\t\tprojectRoot = \"\";\n"
        "\t\t\tpackageReferences = (\n"
        f"\t\t\t\t{package_ref} /* XCRemoteSwiftPackageReference \"speech-swift\" */,\n"
        "\t\t\t);\n"
        "\t\t\ttargets = (\n"
        f"\t\t\t\t{target_id} /* {TARGET_NAME} */,\n"
        "\t\t\t);\n"
        "\t\t};\n"
    )
    content += "/* End PBXProject section */\n\n"

    content += "/* Begin PBXResourcesBuildPhase section */\n"
    content += (
        f"\t\t{resources_phase} /* Resources */ = {{\n"
        "\t\t\tisa = PBXResourcesBuildPhase;\n"
        "\t\t\tbuildActionMask = 2147483647;\n"
        "\t\t\tfiles = (\n"
        f"\t\t\t\t{asset_build} /* Assets.xcassets in Resources */,\n"
        f"\t\t\t\t{model_build} /* Qwen3ASR in Resources */,\n"
        "\t\t\t);\n"
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        "\t\t};\n"
    )
    content += "/* End PBXResourcesBuildPhase section */\n\n"

    content += "/* Begin PBXSourcesBuildPhase section */\n"
    content += (
        f"\t\t{sources_phase} /* Sources */ = {{\n"
        "\t\t\tisa = PBXSourcesBuildPhase;\n"
        "\t\t\tbuildActionMask = 2147483647;\n"
        "\t\t\tfiles = (\n"
        f"{source_entries}"
        "\t\t\t);\n"
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        "\t\t};\n"
    )
    content += "/* End PBXSourcesBuildPhase section */\n\n"

    content += "/* Begin XCBuildConfiguration section */\n"

    def config(config_id: str, name: str, settings: str) -> str:
        return (
            f"\t\t{config_id} /* {name} */ = {{\n"
            "\t\t\tisa = XCBuildConfiguration;\n"
            "\t\t\tbuildSettings = {"
            + settings
            + "\t\t\t};\n"
            f"\t\t\tname = {name};\n"
            "\t\t};\n"
        )

    content += config(project_debug, "Debug", project_debug_settings)
    content += config(project_release, "Release", project_release_settings)
    content += config(target_debug, "Debug", target_common)
    content += config(target_release, "Release", target_common)
    content += "/* End XCBuildConfiguration section */\n\n"

    content += "/* Begin XCConfigurationList section */\n"

    def config_list(list_id: str, label: str, debug_id: str, release_id: str) -> str:
        return (
            f"\t\t{list_id} /* Build configuration list for {label} */ = {{\n"
            "\t\t\tisa = XCConfigurationList;\n"
            "\t\t\tbuildConfigurations = (\n"
            f"\t\t\t\t{debug_id} /* Debug */,\n"
            f"\t\t\t\t{release_id} /* Release */,\n"
            "\t\t\t);\n"
            "\t\t\tdefaultConfigurationIsVisible = 0;\n"
            "\t\t\tdefaultConfigurationName = Release;\n"
            "\t\t};\n"
        )

    content += config_list(
        project_config_list,
        f'PBXProject "{TARGET_NAME}"',
        project_debug,
        project_release,
    )
    content += config_list(
        target_config_list,
        f'PBXNativeTarget "{TARGET_NAME}"',
        target_debug,
        target_release,
    )
    content += "/* End XCConfigurationList section */\n\n"

    content += "/* Begin XCRemoteSwiftPackageReference section */\n"
    content += (
        f"\t\t{package_ref} /* XCRemoteSwiftPackageReference \"speech-swift\" */ = {{\n"
        "\t\t\tisa = XCRemoteSwiftPackageReference;\n"
        f"\t\t\trepositoryURL = \"{SPEECH_SWIFT_URL}\";\n"
        "\t\t\trequirement = {\n"
        "\t\t\t\tbranch = main;\n"
        "\t\t\t\tkind = branch;\n"
        "\t\t\t};\n"
        "\t\t};\n"
    )
    content += "/* End XCRemoteSwiftPackageReference section */\n\n"

    content += "/* Begin XCSwiftPackageProductDependency section */\n"
    content += (
        f"\t\t{package_product} /* Qwen3ASR */ = {{\n"
        "\t\t\tisa = XCSwiftPackageProductDependency;\n"
        f"\t\t\tpackage = {package_ref} /* XCRemoteSwiftPackageReference \"speech-swift\" */;\n"
        "\t\t\tproductName = Qwen3ASR;\n"
        "\t\t};\n"
    )
    content += "/* End XCSwiftPackageProductDependency section */\n"

    content += "\t};\n"
    content += f"\trootObject = {project_id} /* Project object */;\n"
    content += "}\n"
    return content


def scheme() -> str:
    target_id = gid("target-app")
    reference = f"""               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target_id}"
               BuildableName = "{TARGET_NAME}.app"
               BlueprintName = "{TARGET_NAME}"
               ReferencedContainer = "container:{TARGET_NAME}.xcodeproj">"""
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES"
      buildArchitectures = "Automatic">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
{reference}
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
{reference}
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
{reference}
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


WORKSPACE = """<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
"""


def main() -> None:
    (PROJECT_DIR / "project.xcworkspace").mkdir(parents=True, exist_ok=True)
    (PROJECT_DIR / "xcshareddata" / "xcschemes").mkdir(parents=True, exist_ok=True)

    (PROJECT_DIR / "project.pbxproj").write_text(build(), encoding="utf-8", newline="\n")
    (PROJECT_DIR / "project.xcworkspace" / "contents.xcworkspacedata").write_text(
        WORKSPACE, encoding="utf-8", newline="\n"
    )
    (PROJECT_DIR / "xcshareddata" / "xcschemes" / f"{TARGET_NAME}.xcscheme").write_text(
        scheme(), encoding="utf-8", newline="\n"
    )

    print(f"wrote {PROJECT_DIR / 'project.pbxproj'}")
    print(f"wrote {PROJECT_DIR / 'xcshareddata' / 'xcschemes' / (TARGET_NAME + '.xcscheme')}")


if __name__ == "__main__":
    main()
