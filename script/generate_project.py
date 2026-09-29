#!/usr/bin/env python3
"""Generate the Xcode project with pinned speech-engine packages. Run after adding Swift files."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parent.parent
def uid(value):
    return hashlib.sha1(value.encode()).hexdigest()[:24].upper()
def quoted(value):
    return '"' + str(value).replace('"', '\\"') + '"'

objects = []
def add(name, body):
    objects.append(f'{uid(name)} = {{ {body} }};')
    return uid(name)

groups = []
build_files = []
for folder in ['App', 'Core', 'Speech']:
    children = []
    for file in sorted((ROOT / folder).iterdir()):
        if file.suffix not in ['.swift', '.plist', '.entitlements']:
            continue
        kind = 'sourcecode.swift' if file.suffix == '.swift' else 'text.plist.xml'
        ref = add(str(file.relative_to(ROOT)), f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {quoted(file.name)}; sourceTree = "<group>";')
        children.append(ref)
        if file.suffix == '.swift':
            build_files.append(add('build:' + str(file.relative_to(ROOT)), f'isa = PBXBuildFile; fileRef = {ref};'))
    groups.append(add(folder, f'isa = PBXGroup; children = ({",".join(children)},); path = {folder}; sourceTree = "<group>";'))
product = add('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = Teleprompter.app; sourceTree = BUILT_PRODUCTS_DIR;')
resource_builds = []
for path, kind in [('Core/Licenses', 'folder'), ('LICENSE', 'text'), ('THIRD_PARTY_NOTICES.md', 'text')]:
    ref = add('resource:' + path, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {quoted(path)}; sourceTree = "<group>";')
    groups.append(ref)
    resource_builds.append(add('resource-build:' + path, f'isa = PBXBuildFile; fileRef = {ref};'))
products = add('products', f'isa = PBXGroup; children = ({product},); name = Products; sourceTree = "<group>";')
main = add('main', f'isa = PBXGroup; children = ({",".join(groups + [products])},); sourceTree = "<group>";')
source_phase = add('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(build_files)},); runOnlyForDeploymentPostprocessing = 0;')
resources = add('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(resource_builds)},); runOnlyForDeploymentPostprocessing = 0;')
package_refs = []
package_products = []
package_builds = []
for product_name, url, version in [
    ('MoonshineVoice', 'https://github.com/moonshine-ai/moonshine-swift.git', '0.1.5'),
    ('FluidAudio', 'https://github.com/FluidInference/FluidAudio.git', '0.17.4'),
    ('WhisperKit', 'https://github.com/argmaxinc/argmax-oss-swift.git', '1.1.0'),
]:
    ref = add('package:' + product_name, f'isa = XCRemoteSwiftPackageReference; repositoryURL = {quoted(url)}; requirement = {{ kind = exactVersion; version = {version}; }};')
    dependency = add('dependency:' + product_name, f'isa = XCSwiftPackageProductDependency; package = {ref}; productName = {product_name};')
    package_refs.append(ref)
    package_products.append(dependency)
    package_builds.append(add('link:' + product_name, f'isa = PBXBuildFile; productRef = {dependency};'))
frameworks = add('frameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({",".join(package_builds)},); runOnlyForDeploymentPostprocessing = 0;')
project_configs = []
target_configs = []
for name in ['Debug', 'Release']:
    project_configs.append(add('project' + name, f'isa = XCBuildConfiguration; buildSettings = {{ MACOSX_DEPLOYMENT_TARGET = 26.0; SDKROOT = macosx; ARCHS = arm64; SWIFT_VERSION = 6.0; CLANG_ENABLE_MODULES = YES; SWIFT_OPTIMIZATION_LEVEL = {quoted("-Onone" if name == "Debug" else "-O")}; SWIFT_ACTIVE_COMPILATION_CONDITIONS = {quoted("DEBUG" if name == "Debug" else "")}; }}; name = {name};'))
    target_configs.append(add('target' + name, f'isa = XCBuildConfiguration; buildSettings = {{ PRODUCT_NAME = Teleprompter; PRODUCT_BUNDLE_IDENTIFIER = com.bitl8byteshort.Teleprompter; INFOPLIST_FILE = App/Info.plist; CODE_SIGN_ENTITLEMENTS = App/Teleprompter.entitlements; CODE_SIGN_STYLE = Automatic; CODE_SIGN_IDENTITY = "Apple Development"; DEVELOPMENT_TEAM = 4WWK6TTABC; ENABLE_HARDENED_RUNTIME = YES; ENABLE_APP_SANDBOX = NO; GENERATE_INFOPLIST_FILE = NO; SWIFT_EMIT_LOC_STRINGS = YES; }}; name = {name};'))
pc = add('pc', f'isa = XCConfigurationList; buildConfigurations = ({",".join(project_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
tc = add('tc', f'isa = XCConfigurationList; buildConfigurations = ({",".join(target_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target = add('target', f'isa = PBXNativeTarget; buildConfigurationList = {tc}; buildPhases = ({source_phase},{frameworks},{resources},); buildRules = (); dependencies = (); name = Teleprompter; packageProductDependencies = ({",".join(package_products)},); productName = Teleprompter; productReference = {product}; productType = "com.apple.product-type.application";')
project = add('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; }}; buildConfigurationList = {pc}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en,Base,); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; packageReferences = ({",".join(package_refs)},); targets = ({target},);')
bundle = ROOT / 'Teleprompter.xcodeproj'
bundle.mkdir(exist_ok=True)
(bundle / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {project}; }}\n')
schemes = bundle / 'xcshareddata/xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Teleprompter.app" BlueprintName="Teleprompter" ReferencedContainer="container:Teleprompter.xcodeproj"/>'
(schemes / 'Teleprompter.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"/>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print('Generated Teleprompter.xcodeproj')
