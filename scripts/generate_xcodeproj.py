#!/usr/bin/env python3
"""Generates ChromaRSS.xcodeproj/project.pbxproj deterministically.

Usage: python3 scripts/generate_xcodeproj.py   (run from anywhere)
"""
import hashlib
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_DIR = "ChromaRSS"
PROJ_DIR = os.path.join(ROOT, "ChromaRSS.xcodeproj")
BUNDLE_ID = "com.kitawu.ChromaRSS"


def uid(name: str) -> str:
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()


objects = []  # (id, comment, body)


def add(oid, comment, body):
    objects.append((oid, comment, body))


# ---- collect sources
swift_files = []
for dirpath, _, files in os.walk(os.path.join(ROOT, APP_DIR)):
    for f in sorted(files):
        if f.endswith(".swift"):
            swift_files.append(os.path.relpath(os.path.join(dirpath, f), os.path.join(ROOT, APP_DIR)))
swift_files.sort()

# ---- ids
PROJECT = uid("project")
MAIN_GROUP = uid("mainGroup")
APP_GROUP = uid("appGroup")
PRODUCTS_GROUP = uid("productsGroup")
TARGET = uid("target")
PRODUCT_REF = uid("productRef")
SOURCES_PHASE = uid("sourcesPhase")
FRAMEWORKS_PHASE = uid("frameworksPhase")
RESOURCES_PHASE = uid("resourcesPhase")
PROJ_CFG_LIST = uid("projCfgList")
TARGET_CFG_LIST = uid("targetCfgList")
PROJ_DEBUG, PROJ_RELEASE = uid("projDebug"), uid("projRelease")
TGT_DEBUG, TGT_RELEASE = uid("tgtDebug"), uid("tgtRelease")
LOCAL_PKG = uid("localPkg")
PKG_DEP = uid("pkgDep")
PKG_BUILD = uid("pkgBuild")
ASSETS_REF, ASSETS_BUILD = uid("assetsRef"), uid("assetsBuild")
EXT_REF, EXT_BUILD = uid("extFolderRef"), uid("extFolderBuild")
PLIST_REF = uid("plistRef")
EXT_PARENT_GROUP = uid("bundledExtGroup")

# ---- file references / groups
group_children = {}  # relative dir -> list of (id, name)
group_ids = {"": APP_GROUP}


def ensure_group(rel):
    if rel in group_ids:
        return group_ids[rel]
    gid = uid("group:" + rel)
    group_ids[rel] = gid
    parent = os.path.dirname(rel)
    ensure_group(parent)
    group_children.setdefault(parent, []).append((gid, os.path.basename(rel)))
    return gid


build_files = []
for rel in swift_files:
    ref, bf = uid("ref:" + rel), uid("build:" + rel)
    d = os.path.dirname(rel)
    ensure_group(d)
    group_children.setdefault(d, []).append((ref, os.path.basename(rel)))
    add(ref, os.path.basename(rel), f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{os.path.basename(rel)}"; sourceTree = "<group>"; }}')
    add(bf, f"{os.path.basename(rel)} in Sources", f"{{isa = PBXBuildFile; fileRef = {ref}; }}")
    build_files.append((bf, os.path.basename(rel)))

# assets, plist, bundled extension folder reference
add(ASSETS_REF, "Assets.xcassets", '{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }')
add(ASSETS_BUILD, "Assets.xcassets in Resources", f"{{isa = PBXBuildFile; fileRef = {ASSETS_REF}; }}")
add(PLIST_REF, "Info.plist", '{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }')
add(EXT_REF, "bilingual-helper", '{isa = PBXFileReference; lastKnownFileType = folder; path = "bilingual-helper"; sourceTree = "<group>"; }')
add(EXT_BUILD, "bilingual-helper in Resources", f"{{isa = PBXBuildFile; fileRef = {EXT_REF}; }}")
add(PRODUCT_REF, "ChromaRSS.app", '{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = ChromaRSS.app; sourceTree = BUILT_PRODUCTS_DIR; }')
add(PKG_BUILD, "ChromaRSSCore in Frameworks", f"{{isa = PBXBuildFile; productRef = {PKG_DEP}; }}")

# bundled extensions group
add(EXT_PARENT_GROUP, "BundledExtensions", f'{{isa = PBXGroup; children = ({EXT_REF}); path = BundledExtensions; sourceTree = "<group>"; }}')

# groups for source dirs
for rel, gid in group_ids.items():
    if rel == "":
        continue
    kids = group_children.get(rel, [])
    kid_list = ", ".join(i for i, _ in sorted(kids, key=lambda x: x[1]))
    add(gid, os.path.basename(rel), f'{{isa = PBXGroup; children = ({kid_list}); path = "{os.path.basename(rel)}"; sourceTree = "<group>"; }}')

top_kids = [i for i, _ in sorted(group_children.get("", []), key=lambda x: x[1])]
top_kids += [EXT_PARENT_GROUP, ASSETS_REF, PLIST_REF]
add(APP_GROUP, "ChromaRSS", f'{{isa = PBXGroup; children = ({", ".join(top_kids)}); path = ChromaRSS; sourceTree = "<group>"; }}')
add(PRODUCTS_GROUP, "Products", f'{{isa = PBXGroup; children = ({PRODUCT_REF}); name = Products; sourceTree = "<group>"; }}')
add(MAIN_GROUP, "mainGroup", f'{{isa = PBXGroup; children = ({APP_GROUP}, {PRODUCTS_GROUP}); sourceTree = "<group>"; }}')

# build phases
add(SOURCES_PHASE, "Sources", f'{{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(b for b, _ in build_files)}); runOnlyForDeploymentPostprocessing = 0; }}')
add(FRAMEWORKS_PHASE, "Frameworks", f"{{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({PKG_BUILD}); runOnlyForDeploymentPostprocessing = 0; }}")
add(RESOURCES_PHASE, "Resources", f"{{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({ASSETS_BUILD}, {EXT_BUILD}); runOnlyForDeploymentPostprocessing = 0; }}")

# package
add(LOCAL_PKG, 'XCLocalSwiftPackageReference "Packages/ChromaRSSCore"', "{isa = XCLocalSwiftPackageReference; relativePath = Packages/ChromaRSSCore; }")
add(PKG_DEP, "ChromaRSSCore", "{isa = XCSwiftPackageProductDependency; productName = ChromaRSSCore; }")

# target
add(TARGET, "ChromaRSS", f'''{{
			isa = PBXNativeTarget;
			buildConfigurationList = {TARGET_CFG_LIST};
			buildPhases = ({SOURCES_PHASE}, {FRAMEWORKS_PHASE}, {RESOURCES_PHASE});
			buildRules = ();
			dependencies = ();
			name = ChromaRSS;
			packageProductDependencies = ({PKG_DEP});
			productName = ChromaRSS;
			productReference = {PRODUCT_REF};
			productType = "com.apple.product-type.application";
		}}''')

add(PROJECT, "Project object", f'''{{
			isa = PBXProject;
			attributes = {{BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 1630; LastUpgradeCheck = 1630;}};
			buildConfigurationList = {PROJ_CFG_LIST};
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (en, Base);
			mainGroup = {MAIN_GROUP};
			packageReferences = ({LOCAL_PKG});
			productRefGroup = {PRODUCTS_GROUP};
			projectDirPath = "";
			projectRoot = "";
			targets = ({TARGET});
		}}''')


def settings(d):
    return "{\n" + "".join(f"\t\t\t\t{k} = {v};\n" for k, v in d.items()) + "\t\t\t}"


common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": "18.4",
    "MACOSX_DEPLOYMENT_TARGET": "15.4",
    "SDKROOT": "auto",
    "SWIFT_VERSION": "6.0",
}
dbg = dict(common, **{
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "GCC_PREPROCESSOR_DEFINITIONS": '("DEBUG=1", "$(inherited)")',
    "ONLY_ACTIVE_ARCH": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": '"$(inherited) DEBUG"',
    "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
})
rel = dict(common, **{
    "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
    "ENABLE_NS_ASSERTIONS": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "VALIDATE_PRODUCT": "YES",
})
tgt = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "ChromaRSS/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks")',
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SUPPORTED_PLATFORMS": '"iphoneos iphonesimulator macosx"',
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "6.0",
    "TARGETED_DEVICE_FAMILY": '"1,2"',
}
add(PROJ_DEBUG, "Debug", f"{{isa = XCBuildConfiguration; buildSettings = {settings(dbg)}; name = Debug; }}")
add(PROJ_RELEASE, "Release", f"{{isa = XCBuildConfiguration; buildSettings = {settings(rel)}; name = Release; }}")
add(TGT_DEBUG, "Debug", f"{{isa = XCBuildConfiguration; buildSettings = {settings(tgt)}; name = Debug; }}")
add(TGT_RELEASE, "Release", f"{{isa = XCBuildConfiguration; buildSettings = {settings(tgt)}; name = Release; }}")
add(PROJ_CFG_LIST, 'Build configuration list for PBXProject "ChromaRSS"', f"{{isa = XCConfigurationList; buildConfigurations = ({PROJ_DEBUG}, {PROJ_RELEASE}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}")
add(TARGET_CFG_LIST, 'Build configuration list for PBXNativeTarget "ChromaRSS"', f"{{isa = XCConfigurationList; buildConfigurations = ({TGT_DEBUG}, {TGT_RELEASE}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}")

# ---- emit
sections = [
    "PBXBuildFile", "PBXFileReference", "PBXFrameworksBuildPhase", "PBXGroup", "PBXNativeTarget",
    "PBXProject", "PBXResourcesBuildPhase", "PBXSourcesBuildPhase", "XCBuildConfiguration",
    "XCConfigurationList", "XCLocalSwiftPackageReference", "XCSwiftPackageProductDependency",
]
out = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 56;", "\tobjects = {", ""]
for sec in sections:
    items = [(i, c, b) for i, c, b in objects if f"isa = {sec};" in b]
    if not items:
        continue
    out.append(f"/* Begin {sec} section */")
    for i, c, b in sorted(items, key=lambda x: x[0]):
        out.append(f"\t\t{i} /* {c} */ = {b};")
    out.append(f"/* End {sec} section */\n")
out += ["\t};", f"\trootObject = {PROJECT} /* Project object */;", "}", ""]

os.makedirs(os.path.join(PROJ_DIR, "xcshareddata", "xcschemes"), exist_ok=True)
with open(os.path.join(PROJ_DIR, "project.pbxproj"), "w") as f:
    f.write("\n".join(out))

scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1630" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{TARGET}" BuildableName = "ChromaRSS.app" BlueprintName = "ChromaRSS" ReferencedContainer = "container:ChromaRSS.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{TARGET}" BuildableName = "ChromaRSS.app" BlueprintName = "ChromaRSS" ReferencedContainer = "container:ChromaRSS.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''
with open(os.path.join(PROJ_DIR, "xcshareddata", "xcschemes", "ChromaRSS.xcscheme"), "w") as f:
    f.write(scheme)

print(f"Generated {PROJ_DIR} with {len(swift_files)} Swift files")
