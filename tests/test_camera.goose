// Camera and projection math, without a device: the matrices are checked
// directly, so this test says something on a machine with no GPU too.
import std;
import vec;
import math;
import hipgr from "../src/hipgr";
import verify from "./verify";

fn main() {
    // Yaw 0 looks down -Z, pitch up is +Y.
    let forward = hipgr::camera_direction(0.0, 0.0);
    verify::expect_near(forward.x, 0.0, 0.0001, "forward x");
    verify::expect_near(forward.y, 0.0, 0.0001, "forward y");
    verify::expect_near(forward.z, -1.0, 0.0001, "forward z");
    let right = hipgr::camera_direction(1.5707963, 0.0);
    verify::expect_near(right.x, 1.0, 0.0001, "yaw 90 looks down +X");

    // A camera 3 units up +Z looking at the origin maps the origin to -3 on Z
    // in view space.
    let cam = hipgr::camera_look_at(float3 { 0.0, 0.0, 3.0 }, float3_0, float3 { 0.0, 1.0, 0.0 },
                                    0.8);
    let view = hipgr::camera_view(cam);
    let origin_in_view = hipgr::mat4_point(view, float3_0);
    verify::expect_near(origin_in_view.z, -3.0, 0.0001, "origin is 3 in front");
    verify::expect_near(origin_in_view.x, 0.0, 0.0001, "origin is centred in x");
    verify::expect_near(origin_in_view.y, 0.0, 0.0001, "origin is centred in y");

    // The projection puts the origin at the centre of the screen: NDC 0,0,
    // with depth inside 0..1 for a right-handed 0..1 backend.
    let vp = hipgr::camera_view_projection(cam, 1.0);
    let clip = hipgr::mat4_mul_vec4(vp, float4 { 0.0, 0.0, 0.0, 1.0 });
    verify::expect(clip.w > 0.0, "point is in front of the camera");
    verify::expect_near(clip.x / clip.w, 0.0, 0.0001, "ndc x centred");
    verify::expect_near(clip.y / clip.w, 0.0, 0.0001, "ndc y centred");
    let depth = clip.z / clip.w;
    verify::expect(depth > 0.0 && depth < 1.0, "ndc depth is inside 0..1");

    // A point behind the camera has a negative w.
    let behind = hipgr::mat4_mul_vec4(vp, float4 { 0.0, 0.0, 4.0, 1.0 });
    verify::expect(behind.w < 0.0, "a point behind the camera is behind it");

    // Aspect ratio widens the field horizontally, not vertically.
    let wide = hipgr::camera_view_projection(cam, 2.0);
    let edge_x = hipgr::mat4_mul_vec4(wide, float4 { 1.0, 0.0, 0.0, 1.0 });
    let tall = hipgr::camera_view_projection(cam, 0.5);
    let edge_x_tall = hipgr::mat4_mul_vec4(tall, float4 { 1.0, 0.0, 0.0, 1.0 });
    verify::expect(edge_x.x / edge_x.w < edge_x_tall.x / edge_x_tall.w,
                   "a wider aspect spreads x less");

    // Orthographic projection maps the centre to the centre too.
    let ortho = hipgr::camera_orthographic(float3 { 0.0, 0.0, 3.0 }, float3_0,
                                           float3 { 0.0, 1.0, 0.0 }, 4.0, 0.1, 100.0);
    let ortho_clip = hipgr::mat4_mul_vec4(hipgr::camera_view_projection(ortho, 1.0),
                                          float4 { 0.0, 0.0, 0.0, 1.0 });
    verify::expect_near(ortho_clip.x / ortho_clip.w, 0.0, 0.0001, "ortho x centred");
    verify::expect_near(ortho_clip.y / ortho_clip.w, 0.0, 0.0001, "ortho y centred");

    // A transform composes as translate * rotate * scale.
    let trs = hipgr::mat4_trs(float3 { 1.0, 0.0, 0.0 }, float3 { 0.0, 1.0, 0.0 }, 0.0,
                              float3 { 2.0, 2.0, 2.0 });
    let p = hipgr::mat4_point(trs, float3 { 1.0, 0.0, 0.0 });
    verify::expect_near(p.x, 3.0, 0.0001, "scale then translate on x");

    verify::pass("test_camera");
}
