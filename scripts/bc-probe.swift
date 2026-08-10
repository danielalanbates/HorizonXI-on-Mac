import Metal
let d = MTLCreateSystemDefaultDevice()!
print("device:", d.name)
print("supportsBCTextureCompression:", d.supportsBCTextureCompression)
print("apple7:", d.supportsFamily(.apple7), " mac2:", d.supportsFamily(.mac2))
