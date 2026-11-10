// 0.3 acceptance: metallic/roughness surfaces and normal maps.
//
// The quad faces the camera. A head-on light makes the diffuse term exactly its
// maximum, so a difference between two materials is a difference in the BRDF,
// not in the geometry: a metal loses its diffuse lobe, a rough metal spreads its
// reflection out, and a normal map tilts the shaded normal away from the vertex
// one.
import std;
import vec;
import hipgr from "../src/hipgr";
import verify from "./verify";

let SIZE: i64 = 64;
let WHITE = float4 { 1.0, 1.0, 1.0, 1.0 };

fn shot(dev: hipgr::Device&, quad: hipgr::Mesh, mat: hipgr::Material,
        cam: hipgr::Camera) -> u8[4] {
    verify::expect(hipgr::begin_frame(dev, cam, float4_0), "frame begins");
    verify::expect(hipgr::draw(dev, quad, mat, hipgr::mat4_identity()), "draw succeeds");
    verify::expect(hipgr::end_frame(dev), "frame ends");
    return verify::pixel(hipgr::frame_pixels(dev), SIZE, SIZE / 2, SIZE / 2);
}

fn main() {
    var dev = hipgr::Device { .. };
    guard hipgr::open_headless(dev, SIZE, SIZE) else {
        verify::skip("test_pbr: no GPU device");
        return;
    }
    defer hipgr::close(dev);
    hipgr::quality(dev, hipgr::QUALITY_LINEAR);

    let quad = hipgr::mesh_quad(dev);
    let cam = hipgr::camera_orthographic(float3 { 0.0, 0.0, 3.0 }, float3_0,
                                         float3 { 0.0, 1.0, 0.0 }, 2.0, 0.1, 10.0);
    // Straight at the quad's +Z face, no ambient: what is left is direct light.
    verify::expect(hipgr::set_light(dev, float3 { 0.0, 0.0, -1.0 }, float3_1, 0.0),
                   "light set");

    // --- metallic -------------------------------------------------------------
    let dielectric = hipgr::material_create(dev, hipgr::MaterialDesc {
        tint: WHITE, roughness: 1.0,
    });
    verify::expect(dielectric.id != 0, "dielectric material created");
    let d = shot(dev, quad, dielectric, cam);
    verify::expect(verify::close_to(d[0], 247, 4), "a matte white dielectric is nearly full white");

    let metal = hipgr::material_create(dev, hipgr::MaterialDesc {
        tint: WHITE, metallic: 1.0, roughness: 1.0,
    });
    verify::expect(metal.id != 0, "metal material created");
    let m = shot(dev, quad, metal, cam);
    verify::expect(m[0] < 120, "a metal has no diffuse lobe, so it is much darker");
    verify::expect(m[0] != d[0], "metal and dielectric shade differently");

    // A polished metal concentrates its reflection: at a head-on light that is a
    // bright highlight instead of a dull sheen.
    let polished = hipgr::material_create(dev, hipgr::MaterialDesc {
        tint: WHITE, metallic: 1.0, roughness: 0.05,
    });
    verify::expect(polished.id != 0, "polished metal created");
    let p = shot(dev, quad, polished, cam);
    verify::expect(p[0] > m[0], "a polished metal is brighter than a rough one head-on");

    // Out-of-range surface values are rejected rather than clamped silently.
    verify::expect(hipgr::material_create(dev, hipgr::MaterialDesc { metallic: 1.5 }).id == 0,
                   "metallic above 1 is rejected");
    verify::expect_eq(hipgr::error_code(dev), hipgr::ERR_BAD_ARGUMENT, "metallic error code");
    verify::expect(hipgr::material_create(dev, hipgr::MaterialDesc { roughness: -0.1 }).id == 0,
                   "a negative roughness is rejected");

    // --- normal maps ----------------------------------------------------------
    // The light comes in at 53 degrees from +Z, so a flat normal sees almost
    // nothing and a normal tilted to meet it sees everything.
    verify::expect(hipgr::set_light(dev, float3 { -0.6, -0.8, 0.0 }, float3_1, 0.0),
                   "side light set");
    let flat = shot(dev, quad, dielectric, cam);
    verify::expect(flat[0] < 20, "a surface edge-on to the light is dark");

    // A one-texel normal map pointing at (0.6, 0.8, 0), encoded the usual way.
    let px: u8[4] = [204, 230, 128, 255];
    let map = hipgr::image_rgba8(dev, 1, 1, px[..]);
    verify::expect(map.id != 0, "normal map created");

    let mapped = hipgr::material_create(dev, hipgr::MaterialDesc {
        tint: WHITE, roughness: 1.0, normal_map: map, normal_strength: 1.0,
    });
    verify::expect(mapped.id != 0, "normal mapped material created");
    let n = shot(dev, quad, mapped, cam);
    verify::expect(n[0] > 200, "the normal map turns the surface towards the light");

    // Strength 0 must be identical to no map at all: the map is still bound, so
    // this also checks the default flat-normal path against a real texture.
    let ignored = hipgr::material_create(dev, hipgr::MaterialDesc {
        tint: WHITE, roughness: 1.0, normal_map: map, normal_strength: 0.0,
    });
    verify::expect(ignored.id != 0, "zero-strength material created");
    let z = shot(dev, quad, ignored, cam);
    verify::expect(verify::same_color(z, flat, 1), "zero strength ignores the normal map");

    verify::pass("test_pbr");
}
