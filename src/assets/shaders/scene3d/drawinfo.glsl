#ifndef DRAWINFO_GLSL
#define DRAWINFO_GLSL

#extension GL_EXT_shader_explicit_arithmetic_types_int64 : enable
//#extension GL_EXT_buffer_reference : enable
#extension GL_EXT_buffer_reference2 : enable
#extension GL_EXT_buffer_reference_uvec2 : enable

// Packed vertex types matching TGPUCachedVertex (32 bytes) and TGPUStaticVertex (32 bytes)

struct PackedCachedVertex {
  float posX, posY, posZ;        // 12 bytes — position (3x float32)
  uint normalXY;                  //  4 bytes — snorm16(normal.x) | snorm16(normal.y)
  uint normalZSign;               //  4 bytes — snorm16(normal.z) | snorm16(bitangentSign)
  uint tangentXY;                 //  4 bytes — snorm16(tangent.x) | snorm16(tangent.y)
  uint tangentZModelScaleX;       //  4 bytes — snorm16(tangent.z) | half(modelScaleX)
  uint modelScaleYZ;              //  4 bytes — half(modelScaleY) | half(modelScaleZ)
}; // 32 bytes

struct PackedStaticVertex {
  vec2 texCoord0;                 //  8 bytes — (2x float32)
  vec2 texCoord1;                 //  8 bytes — (2x float32)
  uint colorRG;                   //  4 bytes — half(r) | half(g)
  uint colorBA;                   //  4 bytes — half(b) | half(a)
  uint materialID;                //  4 bytes — uint32
  uint _unused;                   //  4 bytes
}; // 32 bytes

// Buffer reference types for vertex pulling via BDA

layout(buffer_reference, std430, buffer_reference_align = 4) readonly buffer CachedVertexBuffer {
  PackedCachedVertex vertices[];
};

layout(buffer_reference, std430, buffer_reference_align = 4) readonly buffer StaticVertexBuffer {
  PackedStaticVertex vertices[];
};

layout(buffer_reference, std430, buffer_reference_align = 4) readonly buffer GenerationBuffer {
  uint generations[];
};

// DrawInfo struct — 192 bytes per draw, stored in SSBO at binding 0
// Layout (std430):
//   offset  0: cachedVerticesBDA          (uvec2, 8 bytes)
//   offset  8: staticVerticesBDA          (uvec2, 8 bytes)
//   offset 16: previousCachedVerticesBDA  (uvec2, 8 bytes, velocity)
//   offset 24: generationBDA              (uvec2, 8 bytes, velocity)
//   offset 32: previousGenerationBDA      (uvec2, 8 bytes, velocity)
//   offset 40: _reserved                  (uvec2, 8 bytes, padding)
//   offset 48: modelMatrix                (mat4, 64 bytes)
//   offset 112: previousModelMatrix       (mat4, 64 bytes, velocity)
//   offset 176: instanceDataIndex         (uint, 4 bytes)
//   offset 180: objectIndex               (uint, 4 bytes)
//   offset 184: flags                     (uint, 4 bytes)
//   offset 188: indexOffset               (uint, 4 bytes, vertex index offset for per-group buffers)
// Total: 192 bytes

struct DrawInfo {
  uvec2 cachedVerticesBDA;
  uvec2 staticVerticesBDA;
  uvec2 previousCachedVerticesBDA;
  uvec2 generationBDA;
  uvec2 previousGenerationBDA;
  uvec2 _reserved;
  mat4 modelMatrix;
  mat4 previousModelMatrix;
  uint instanceDataIndex;
  uint objectIndex;
  uint flags;
  uint indexOffset;
};

// Unpacking helpers for PackedCachedVertex

vec3 unpackPosition(in PackedCachedVertex v) {
  return vec3(v.posX, v.posY, v.posZ);
}

vec4 unpackNormalSign(in PackedCachedVertex v) {
  vec2 xy = unpackSnorm2x16(v.normalXY);
  vec2 zw = unpackSnorm2x16(v.normalZSign);
  return vec4(xy, zw);
}

vec3 unpackTangent(in PackedCachedVertex v) {
  vec2 xy = unpackSnorm2x16(v.tangentXY);
  float z = unpackSnorm2x16(v.tangentZModelScaleX).x;
  return vec3(xy, z);
}

vec3 unpackModelScale(in PackedCachedVertex v) {
  float scaleX = unpackHalf2x16(v.tangentZModelScaleX).y;
  vec2 scaleYZ = unpackHalf2x16(v.modelScaleYZ);
  return vec3(scaleX, scaleYZ);
}

// Unpacking helpers for PackedStaticVertex

vec4 unpackColor0(in PackedStaticVertex v) {
  return vec4(unpackHalf2x16(v.colorRG), unpackHalf2x16(v.colorBA));
}

#endif // DRAWINFO_GLSL
