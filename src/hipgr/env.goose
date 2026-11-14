// HiPGR: image-based lighting, integrated from the sky on the CPU.
//
// The sky is a two-colour gradient, so the light it casts can be integrated
// directly instead of read back from the GPU: a small cosine-weighted cube of
// irradiance for diffuse light, and a prefiltered radiance cube with one mip per
// roughness band for specular reflections. Both are RGBA16F, so a sky brighter
// than 1.0 still reflects as brighter than 1.0.
//
// Rebuilding is a settings change, not a per-frame cost: a device builds the
// cubes when it opens and again when set_sky() changes the colours.
namespace hipgr;

import vec;
import gfx;
import .gpu;

let ENV_IRRADIANCE_SIZE: i64 = 16;
let ENV_PREFILTER_SIZE: i64 = 32;
// Mip n of the prefiltered cube is roughness n / (ENV_PREFILTER_MIPS - 1). The
// built-in fragment shader turns roughness into a mip level with the same
// constant; change one and the other has to follow.
let ENV_PREFILTER_MIPS: i64 = 5;

struct EnvCubes {
    irradiance: gfx::Texture = gfx::Texture { 0 },
    prefiltered: gfx::Texture = gfx::Texture { 0 },
}

// --- the sky as a function --------------------------------------------------------

// The sky's radiance in a direction: the gradient build_sky_cube() rasterizes,
// evaluated instead of drawn, so the cubes and the visible sky cannot disagree.
fn sky_radiance(horizon: float3, zenith: float3, dir: float3) -> float3 {
    let len = length(dir);
    let h = if len > 0.0 { dir.y / len } else { 0.0 };
    let t = if h < -0.2 { 0.0 } else if h > 0.7 { 1.0 } else { (h + 0.2) / 0.9 };
    return horizon + (zenith - horizon) * t;
}

// The direction through texel (x, y) of face `face` of a size-square cube: the
// same face layout build_sky_cube() writes and the backend samples.
fn cube_direction(face: i64, x: i64, y: i64, size: i64) -> float3 {
    let inv = 2.0 / (size - 1) as f32;
    let u = x * inv - 1.0;
    let v = y * inv - 1.0;
    if face == 0 { return float3 { 1.0, -v, -u }; }
    if face == 1 { return float3 { -1.0, -v, u }; }
    if face == 2 { return float3 { u, 1.0, v }; }
    if face == 3 { return float3 { u, -1.0, -v }; }
    if face == 5 { return float3 { -u, -v, -1.0 }; }
    return float3 { u, -v, 1.0 };
}

// One axis perpendicular to n, so a hemisphere sample can be rotated onto n.
fn tangent_of(n: float3) -> float3 {
    let up = if abs(n.y) > 0.999 { float3 { 0.0, 0.0, 1.0 } } else { float3 { 0.0, 1.0, 0.0 } };
    return normalize(cross(up, n));
}

// Van der Corput base 2, the second coordinate of a Hammersley set: the samples
// are the same on every run, which keeps a rebuild bit-identical.
fn radical_inverse(i: i64) -> f32 {
    var v: u32 = 0;
    var x = i as u32;
    for k in 16 {
        v = (v << 1) | (x & 1);
        x >>= 1;
    }
    return v / 65536.0;
}

// --- integrals ---------------------------------------------------------------------

// The mean sky radiance over the hemisphere around n, weighted by N·L: exactly
// the integral a Lambertian surface performs, i.e. the irradiance over PI.
fn hemisphere_mean(horizon: float3, zenith: float3, n: float3) -> float3 {
    let count: i64 = 64;
    let t = tangent_of(n);
    let b = cross(n, t);
    var sum = float3 { 0.0, 0.0, 0.0 };
    for i in count {
        // Cosine-weighted: cos(theta) = sqrt(u), so the weight is in the sample
        // distribution and every sample counts the same.
        let u = (i as f32 + 0.5) / count;
        let cos_t = sqrt(u);
        let sin_t = sqrt(1.0 - u);
        let phi = i as f32 * 2.39996323;   // the golden angle: an even spiral
        let dir = t * (sin_t * cos(phi)) + b * (sin_t * sin(phi)) + n * cos_t;
        sum += sky_radiance(horizon, zenith, dir);
    }
    return sum * (1.0 / count as f32);
}

// Fewer samples where the lobe is wide and the sky is smooth; a mirror direction
// needs none at all.
fn specular_samples(rough: f32) -> i64 {
    if rough < 0.5 { return 32; }
    if rough < 0.75 { return 24; }
    return 16;
}

// The radiance a surface of roughness `rough` sees along its reflection
// direction r: GGX importance sampling of the half-vector distribution,
// weighted by N·L. This is the prefiltered half of the split-sum approximation.
fn reflection_mean(horizon: float3, zenith: float3, r: float3, rough: f32) -> float3 {
    if rough <= 0.001 { return sky_radiance(horizon, zenith, r); }
    let count = specular_samples(rough);
    // alpha = roughness^2 as in the shader's ndf_ggx, and the formula below
    // wants alpha^2.
    let a = rough * rough;
    let a2 = a * a;
    let t = tangent_of(r);
    let b = cross(r, t);
    var sum = float3 { 0.0, 0.0, 0.0 };
    var wsum: f32 = 0.0;
    for i in count {
        let u1 = (i as f32 + 0.5) / count;
        let u2 = radical_inverse(i + 1);
        let phi = u1 * 6.28318530718;
        let cos_t = sqrt((1.0 - u2) / (1.0 + (a2 - 1.0) * u2));
        let sin_t = sqrt(max(1.0 - cos_t * cos_t, 0.0));
        let h = t * (sin_t * cos(phi)) + b * (sin_t * sin(phi)) + r * cos_t;
        // Reflect the view direction, which is r itself here, about the sampled
        // half vector.
        let l = h * (2.0 * dot(r, h)) - r;
        let weight = dot(r, l);
        if weight > 0.0 {
            sum += sky_radiance(horizon, zenith, l) * weight;
            wsum += weight;
        }
    }
    if wsum <= 0.0 { return sky_radiance(horizon, zenith, r); }
    return sum * (1.0 / wsum);
}

// --- half floats ------------------------------------------------------------------

struct OneF32 { v: f32 }

// The bits of a float. Goose has no bit cast, so the value is read back through
// its own bytes; every target HiPGR builds for is little-endian.
fn f32_bits(v: f32) -> u32 {
    let one: OneF32[1] = [OneF32 { v: v }];
    let b = bytes_of(one);
    var bits: u32 = b[0];
    bits |= (b[1] as u32) << 8;
    bits |= (b[2] as u32) << 16;
    bits |= (b[3] as u32) << 24;
    return bits;
}

// A non-negative float as an IEEE-754 half, the storage RGBA16F wants. The
// environment is never negative and never near half's 65504 ceiling, so the only
// case worth handling is a value below the smallest normal, which flushes to 0.
fn half_bits(v: f32) -> u16 {
    let bits = f32_bits(if v < 0.0 { 0.0 } else { v });
    let exp = ((bits >> 23) & 0xFF) as i64 - 127 + 15;
    if exp > 30 { return 32767; }
    if exp < 1 { return 0; }
    var h: u32 = (exp as u32) << 10;
    h |= (bits >> 13) & 0x3FF;
    return h as u16;
}

// One RGBA16F texel at `o`, in half-float units from the start of the face.
fn put_texel(px: u16[>..]&, o: i64, c: float3) {
    px[o] = half_bits(c.x);
    px[o + 1] = half_bits(c.y);
    px[o + 2] = half_bits(c.z);
    px[o + 3] = 15360;   // 1.0: alpha is unused, but a cube face stays opaque
}

// --- building ---------------------------------------------------------------------

fn fill_irradiance(t: gfx::Texture, horizon: float3, zenith: float3) -> bool {
    let size = ENV_IRRADIANCE_SIZE;
    for face in 6 {
        var px: u16[>..] = [];
        px.resize(size * size * 4, 0);
        for y in size {
            for x in size {
                let n = normalize(cube_direction(face, x, y, size));
                put_texel(px, (y * size + x) * 4, hemisphere_mean(horizon, zenith, n));
            }
        }
        if !gpu_update_texture_mip(t, 0, face as i32, bytes_of(px)) { return false; }
    }
    return true;
}

fn fill_prefiltered(t: gfx::Texture, horizon: float3, zenith: float3) -> bool {
    for mip in ENV_PREFILTER_MIPS {
        let size = ENV_PREFILTER_SIZE >> mip;
        let rough = mip as f32 / (ENV_PREFILTER_MIPS - 1);
        for face in 6 {
            var px: u16[>..] = [];
            px.resize(size * size * 4, 0);
            for y in size {
                for x in size {
                    let r = normalize(cube_direction(face, x, y, size));
                    put_texel(px, (y * size + x) * 4, reflection_mean(horizon, zenith, r, rough));
                }
            }
            if !gpu_update_texture_mip(t, mip as i32, face as i32, bytes_of(px)) { return false; }
        }
    }
    return true;
}

// The two cubes for a sky, or zeros if either could not be created or filled.
// The caller owns what comes back.
fn env_build(horizon: float3, zenith: float3) -> EnvCubes {
    let irr = gpu_texture_cube(ENV_IRRADIANCE_SIZE, FORMAT_RGBA16F, TEXTURE_SAMPLED);
    if irr.id == 0 { return EnvCubes {}; }
    let pf = gpu_texture_cube_mips(ENV_PREFILTER_SIZE, FORMAT_RGBA16F, TEXTURE_SAMPLED);
    if pf.id == 0 {
        gpu_release_texture(irr);
        return EnvCubes {};
    }
    if !fill_irradiance(irr, horizon, zenith) || !fill_prefiltered(pf, horizon, zenith) {
        gpu_release_texture(irr);
        gpu_release_texture(pf);
        return EnvCubes {};
    }
    return EnvCubes { irradiance: irr, prefiltered: pf };
}
