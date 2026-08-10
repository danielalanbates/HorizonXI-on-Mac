#!/usr/bin/env python3
"""Ask MoltenVK directly whether it can sample BC (S3TC/DXT) textures.

FFXI's world textures are DXT1/3/5; its UI textures are uncompressed. The Vulkan pathway
renders UI correctly and the world white, which is exactly what an unsupported BC format
would look like. This settles it rather than guessing.
"""
import ctypes, ctypes.util, sys

LIB = sys.argv[1] if len(sys.argv) > 1 else (
    "/Volumes/x10/Video Games/Mac HorizonXI/siku.app/Contents/Frameworks/libMoltenVK.dylib")
vk = ctypes.CDLL(LIB)

FORMATS = {
    "BC1_RGB_UNORM": 131, "BC1_RGBA_UNORM": 133, "BC2_UNORM": 135, "BC3_UNORM": 137,
    "R8G8B8A8_UNORM": 37, "B8G8R8A8_UNORM": 44, "A1R5G5B5": 8,
}
SAMPLED_IMAGE = 0x1


class VkApplicationInfo(ctypes.Structure):
    _fields_ = [("sType", ctypes.c_int), ("pNext", ctypes.c_void_p),
                ("pApplicationName", ctypes.c_char_p), ("applicationVersion", ctypes.c_uint32),
                ("pEngineName", ctypes.c_char_p), ("engineVersion", ctypes.c_uint32),
                ("apiVersion", ctypes.c_uint32)]


class VkInstanceCreateInfo(ctypes.Structure):
    _fields_ = [("sType", ctypes.c_int), ("pNext", ctypes.c_void_p), ("flags", ctypes.c_uint32),
                ("pApplicationInfo", ctypes.POINTER(VkApplicationInfo)),
                ("enabledLayerCount", ctypes.c_uint32), ("ppEnabledLayerNames", ctypes.c_void_p),
                ("enabledExtensionCount", ctypes.c_uint32),
                ("ppEnabledExtensionNames", ctypes.c_void_p)]


class VkFormatProperties(ctypes.Structure):
    _fields_ = [("linearTilingFeatures", ctypes.c_uint32),
                ("optimalTilingFeatures", ctypes.c_uint32),
                ("bufferFeatures", ctypes.c_uint32)]


class VkPhysicalDeviceFeatures(ctypes.Structure):
    _fields_ = [(n, ctypes.c_uint32) for n in [
        "robustBufferAccess", "fullDrawIndexUint32", "imageCubeArray", "independentBlend",
        "geometryShader", "tessellationShader", "sampleRateShading", "dualSrcBlend",
        "logicOp", "multiDrawIndirect", "drawIndirectFirstInstance", "depthClamp",
        "depthBiasClamp", "fillModeNonSolid", "depthBounds", "wideLines", "largePoints",
        "alphaToOne", "multiViewport", "samplerAnisotropy", "textureCompressionETC2",
        "textureCompressionASTC_LDR", "textureCompressionBC", "occlusionQueryPrecise",
        "pipelineStatisticsQuery", "vertexPipelineStoresAndAtomics", "fragmentStoresAndAtomics",
        "shaderTessellationAndGeometryPointSize", "shaderImageGatherExtended",
        "shaderStorageImageExtendedFormats", "shaderStorageImageMultisample",
        "shaderStorageImageReadWithoutFormat", "shaderStorageImageWriteWithoutFormat",
        "shaderUniformBufferArrayDynamicIndexing", "shaderSampledImageArrayDynamicIndexing",
        "shaderStorageBufferArrayDynamicIndexing", "shaderStorageImageArrayDynamicIndexing",
        "shaderClipDistance", "shaderCullDistance", "shaderFloat64", "shaderInt64",
        "shaderInt16", "shaderResourceResidency", "shaderResourceMinLod", "sparseBinding",
        "sparseResidencyBuffer", "sparseResidencyImage2D", "sparseResidencyImage3D",
        "sparseResidency2Samples", "sparseResidency4Samples", "sparseResidency8Samples",
        "sparseResidency16Samples", "sparseResidencyAliased", "variableMultisampleRate",
        "inheritedQueries"]]


app = VkApplicationInfo(0, None, b"fmtprobe", 1, b"none", 1, (1 << 22) | (2 << 12))
ci = VkInstanceCreateInfo(1, None, 0, ctypes.pointer(app), 0, None, 0, None)
inst = ctypes.c_void_p()
r = vk.vkCreateInstance(ctypes.byref(ci), None, ctypes.byref(inst))
if r != 0:
    raise SystemExit(f"vkCreateInstance failed: {r}")

n = ctypes.c_uint32(0)
vk.vkEnumeratePhysicalDevices(inst, ctypes.byref(n), None)
devs = (ctypes.c_void_p * n.value)()
vk.vkEnumeratePhysicalDevices(inst, ctypes.byref(n), devs)
pd = devs[0]

feats = VkPhysicalDeviceFeatures()
vk.vkGetPhysicalDeviceFeatures(pd, ctypes.byref(feats))
import sys
print(f"textureCompressionBC   = {feats.textureCompressionBC}")
print(f"textureCompressionASTC = {feats.textureCompressionASTC_LDR}")
print(f"textureCompressionETC2 = {feats.textureCompressionETC2}")

for name, f in FORMATS.items():
    p = VkFormatProperties()
    vk.vkGetPhysicalDeviceFormatProperties(pd, f, ctypes.byref(p))
    ok = bool(p.optimalTilingFeatures & SAMPLED_IMAGE)
    print(f"{name:16s} sampled={ok}  optimal=0x{p.optimalTilingFeatures:x}")
