// HiPGR: pipeline and sampler state, as data.
//
// These are HiPGR's own values, not the backend's. gpu.goose maps them, so
// nothing above the boundary depends on the backend's numbering and swapping
// the backend cannot change what an application asked for.
namespace hipgr;

// What happens to a triangle whose winding faces away from the camera.
let CULL_NONE: i32 = 0;
let CULL_BACK: i32 = 1;      // the default: the inside of a closed mesh is hidden
let CULL_FRONT: i32 = 2;

// How a fragment's colour combines with what is already in the target.
let BLEND_NONE: i32 = 0;     // the default: opaque
let BLEND_ALPHA: i32 = 1;    // src.a, 1 - src.a: the usual transparency
let BLEND_ADD: i32 = 2;      // src + dst: glows and additive effects

// Texture sampling.
let FILTER_NEAREST: i32 = 0;
let FILTER_LINEAR: i32 = 1;  // the default
let WRAP_CLAMP: i32 = 0;     // the default: a UV outside 0..1 repeats the edge texel
let WRAP_REPEAT: i32 = 1;

// How the final image is mapped from the HDR scene to the screen.
let TONEMAP_NONE: i32 = 0;      // clamp only: linear out, exactly 0.2's output
let TONEMAP_REINHARD: i32 = 1;  // c / (1 + c)
let TONEMAP_ACES: i32 = 2;      // the filmic curve

// Whole-renderer presets, so an application does not have to know which
// switches add up to a modern pipeline.
//
//   LINEAR  the 0.2 output exactly: no tone mapping, no bloom, no shadows, no
//           sky. Tests that assert exact colours use this.
//   MODERN  ACES tone mapping, bloom, a shadow map and a procedural sky, all
//           at their defaults. This is the default profile.
let QUALITY_LINEAR: i32 = 0;
let QUALITY_MODERN: i32 = 1;

fn tonemap_valid(m: i32) -> bool { m >= TONEMAP_NONE && m <= TONEMAP_ACES }

fn cull_valid(c: i32) -> bool { c >= CULL_NONE && c <= CULL_FRONT }

fn blend_valid(b: i32) -> bool { b >= BLEND_NONE && b <= BLEND_ADD }

fn filter_valid(f: i32) -> bool { f == FILTER_NEAREST || f == FILTER_LINEAR }

fn wrap_valid(w: i32) -> bool { w == WRAP_CLAMP || w == WRAP_REPEAT }
