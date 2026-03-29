#ifndef TBNMODE_GLSL
#define TBNMODE_GLSL

// When enabled, the shader uses the optimized TBN encoding that packs the tangent space into 32 bits (QTangent) 
/// When disabled, it uses a more traditional TBN encoding that may be less efficient but can be useful for debugging or compatibility purposes.
#define TBN_OPTIMIZED 

#ifdef TBN_OPTIMIZED
#include "tangentspace.glsl"
#endif

#endif // TBNMODE_GLSL