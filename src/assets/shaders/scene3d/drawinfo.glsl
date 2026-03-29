#ifndef DRAWINFO_GLSL
#define DRAWINFO_GLSL

//#extension GL_EXT_shader_explicit_arithmetic_types_int64 : enable
//#extension GL_EXT_buffer_reference : enable
#extension GL_EXT_buffer_reference2 : enable
#extension GL_EXT_buffer_reference_uvec2 : enable

#include "vertex.glsl"

// Packed vertex types matching TGPUCachedVertex and TGPUStaticVertex

struct PackedCachedVertex { // TBN = Normal Oct (x: 12-bit, y: 12-bit), Tangent Oct (x: 12-bit, y: 12-bit), Bitangent sign (1-bit, stolen from ModelScaleX half sign) = 49 bits total
  float posX, posY, posZ;         // 12 bytes - position (3x float32)
  uint tbnPart0;                  //  4 bytes - N.x(12) | N.y(12) | T.x_lo(8)
  uint tbnPart1ModelScaleX;       //  4 bytes - T.x_hi(4) | T.y(12) | half(modelScaleX) with sign=bsign (16)
  uint modelScaleYZ;              //  4 bytes - packHalf2x16(scaleY, scaleZ)
}; // 24 bytes

struct PackedStaticVertex {
  float texCoord0X, texCoord0Y;   //  8 bytes - texcoord0 (2x float32)
  float texCoord1X, texCoord1Y;   //  8 bytes - texcoord1 (2x float32)
  uint colorRG;                   //  4 bytes - half(r) | half(g)
  uint colorBA;                   //  4 bytes - half(b) | half(a)
  uint materialID;                //  4 bytes - uint32
}; // 28 bytes, alignment 4, array stride 28

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

// GlobalBDAPointers - 48 bytes, single instance in SSBO at binding 7
// Contains the global buffer device addresses shared by all draws (big-buffer mode).
// For future per-group buffers, these would move back into DrawInfo or become per-group.
// Layout (std430):
//   offset  0: cachedVerticesBDA          (uvec2, 8 bytes)
//   offset  8: staticVerticesBDA          (uvec2, 8 bytes)
//   offset 16: previousCachedVerticesBDA  (uvec2, 8 bytes, velocity)
//   offset 24: generationBDA              (uvec2, 8 bytes, velocity)
//   offset 32: previousGenerationBDA      (uvec2, 8 bytes, velocity)
//   offset 40: _reserved                  (uvec2, 8 bytes, padding)
// Total: 48 bytes

struct GlobalBDAPointers {
  uvec2 cachedVerticesBDA;
  uvec2 staticVerticesBDA;
  uvec2 previousCachedVerticesBDA;
  uvec2 generationBDA;
  uvec2 previousGenerationBDA;
  uvec2 _reserved;
};

// DrawInfo struct - 128 bytes per draw, stored in SSBO at binding 0
// BDA pointers moved to GlobalBDAPointers at binding 7 (global for big-buffer mode)
// Matrices stored as mat3x4 (3 columns of vec4 = 48 bytes each) for affine transforms:
//   Each mat3x4 column stores original_column.xyz with translation component in .w
//   The implicit 4th row of the affine matrix is always (0, 0, 0, 1)
// Layout (std430):
//   offset   0: modelMatrix              (mat3x4, 48 bytes - affine world transform, Identity for pre-transformed)
//   offset  48: previousModelMatrix      (mat3x4, 48 bytes - previous frame, velocity)
//   offset  96: instanceDataIndex        (uint, 4 bytes)
//   offset 100: objectIndex              (uint, 4 bytes)
//   offset 104: flags                    (uint, 4 bytes)
//   offset 108: reserved                 (uint, 4 bytes)
//   offset 112: _padding                 (uvec4, 16 bytes - padding to 128 for power-of-two alignment)
// Total: 128 bytes

struct DrawInfo {
  // BDA pointers commented out - now in GlobalBDAPointers at binding 7
  // For future per-group buffers, uncomment these and remove from GlobalBDAPointers
  //uvec2 cachedVerticesBDA;
  //uvec2 staticVerticesBDA;
  //uvec2 previousCachedVerticesBDA;
  //uvec2 generationBDA;
  //uvec2 previousGenerationBDA;
  //uvec2 _reserved;
  mat3x4 modelMatrix;
  mat3x4 previousModelMatrix;
  uint instanceDataIndex;
  uint objectIndex;
  uint flags;
  uint reserved; 
  uvec4 _padding;
};

// Reconstruct a full mat4 from a packed mat3x4 affine transform.
// The mat3x4 stores the first 3 columns' xyz in .xyz and translation in .w:
//   m[0] = vec4(col0.xyz, translation.x)
//   m[1] = vec4(col1.xyz, translation.y)
//   m[2] = vec4(col2.xyz, translation.z)
mat4 mat3x4ToMat4(const in mat3x4 m) {
  return mat4(
    vec4(m[0].xyz, 0.0),
    vec4(m[1].xyz, 0.0),
    vec4(m[2].xyz, 0.0),
    vec4(m[0].w, m[1].w, m[2].w, 1.0)
  );
}

// Unpacking helpers for PackedCachedVertex

vec3 unpackPosition(in PackedCachedVertex v) {
  return vec3(v.posX, v.posY, v.posZ);
}

// Decode Oct12+Oct12+Sign1 TBN from PackedCachedVertex
void unpackTBNOct12(in PackedCachedVertex v, out vec4 normalSign, out vec3 tangent) {
  ivec2 inxy = ivec2(uvec2(v.tbnPart0) << uvec2(20u, 8u)) >> ivec2(20);
  ivec2 itxy = ivec2(uvec2((((v.tbnPart0 >> 24u) & 0xffu) | ((v.tbnPart1ModelScaleX & 0xfu) << 8u)) << 20u, (v.tbnPart1ModelScaleX >> 4u) << 20u)) >> ivec2(20);
  normalSign = vec4(vertexOctDecode(vec2(inxy.xy) / 2047.0), ((v.tbnPart1ModelScaleX & 0x80000000u) != 0u) ? -1.0 : 1.0);
  tangent = vertexOctDecode(vec2(itxy.xy) / 2047.0);
}

vec3 unpackModelScale(in PackedCachedVertex v) {
  // ModelScaleX: upper 16 bits of tbnPart1ModelScaleX, clear sign bit (stolen for bsign)
  return vec3(unpackHalf2x16((v.tbnPart1ModelScaleX >> 16u) & 0x7fffu).x, unpackHalf2x16(v.modelScaleYZ));
}

// Unpacking helpers for PackedStaticVertex

vec4 unpackColor0(in PackedStaticVertex v) {
  return vec4(unpackHalf2x16(v.colorRG), unpackHalf2x16(v.colorBA));
}

#endif // DRAWINFO_GLSL
