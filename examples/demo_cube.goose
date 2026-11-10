// HiPGR demo: a textured, lit, spinning cube over a grid of others, with a
// free camera. This is HiPGR's own application: it imports hipgr and nothing
// else from the renderer, and needs no engine.
//
//   goose build examples/demo_cube.goose && examples/demo_cube
//   examples/demo_cube --frames 120        // stop after 120 frames
//   GOOSE_GFX_HEADLESS=1 examples/demo_cube --frames 30
//
// Controls: WASD move, Q/E down/up, mouse look (Tab captures the pointer),
// Space pauses the spin, F12 saves demo.png, Escape quits.
import std;
import os;
import vec;
import hipgr from "../src/hipgr";

fn main() {
    var max_frames: i64 = -1;
    var shot_path: const u8[:] = "";
    let argv = args();
    for k in 1..argv.len {
        if argv[k] == "--frames" && k + 1 < argv.len {
            let n, ok = parse_int(argv[k + 1]);
            if ok { max_frames = n; }
        }
        if argv[k] == "--shot" && k + 1 < argv.len {
            shot_path = argv[k + 1];
        }
    }

    var dev = hipgr::Device { .. };
    guard hipgr::open(dev, "HiPGR: textured cube", 960, 540) else {
        write_stderr(str("hipgr: ", hipgr::error_text(hipgr::error_code(dev)), ": ",
                         hipgr::backend_error(), "\n"));
        return;
    }
    defer hipgr::close(dev);
    print("HiPGR ", hipgr::version(), " on ", hipgr::driver(dev), "\n");

    // Resources: one mesh and two materials, shared by every object.
    let cube = hipgr::mesh_cube(dev);
    let checker = hipgr::image_checker(dev, 64, 8, [35, 40, 55, 255], [225, 205, 130, 255]);
    let tiled = hipgr::material_textured(dev, checker, float4_1, false);
    let plain = hipgr::material_solid(dev, float4 { 0.85, 0.35, 0.2, 1.0 }, false);
    if cube.id == 0 || tiled.id == 0 || plain.id == 0 {
        write_stderr(str("hipgr: resources: ", hipgr::error_text(hipgr::error_code(dev)), "\n"));
        return;
    }
    hipgr::set_light(dev, float3 { -0.4, -0.8, -0.6 }, float3 { 1.0, 0.97, 0.9 }, 0.22);

    // A free camera: position plus yaw and pitch, rebuilt each frame.
    var eye = float3 { 0.0, 3.0, 7.0 };
    var yaw: f32 = 0.0;
    var pitch: f32 = -0.35;
    var captured = false;
    var spinning = true;
    var frames: i64 = 0;
    let started = hipgr::time();

    while true {
        if hipgr::key_pressed("Escape") { break; }
        if hipgr::key_pressed("Tab") {
            captured = !captured;
            hipgr::capture_mouse(captured);
        }
        if hipgr::key_pressed("Space") { spinning = !spinning; }
        if hipgr::key_pressed("F12") { hipgr::screenshot(dev, "demo.png"); }

        let dt = hipgr::delta_time() as! f32;
        // SDL key names: "Left Shift" with a space; an unknown name is a
        // backend misuse, so names are taken from SDL's table verbatim.
        let speed: f32 = if hipgr::key_down("Left Shift") { 9.0 } else { 3.5 };
        let forward = hipgr::camera_direction(yaw, pitch);
        let right = hipgr::camera_direction(yaw + 1.5707963, 0.0);
        if hipgr::key_down("W") { eye = eye + forward * (speed * dt); }
        if hipgr::key_down("S") { eye = eye - forward * (speed * dt); }
        if hipgr::key_down("A") { eye = eye - right * (speed * dt); }
        if hipgr::key_down("D") { eye = eye + right * (speed * dt); }
        if hipgr::key_down("E") { eye.y += speed * dt; }
        if hipgr::key_down("Q") { eye.y -= speed * dt; }
        if captured {
            let md = hipgr::mouse_delta();
            yaw += md.x * 0.0035;
            pitch -= md.y * 0.0035;
        }
        if pitch > 1.5 { pitch = 1.5; }
        if pitch < -1.5 { pitch = -1.5; }

        let cam = hipgr::camera_fps(eye, yaw, pitch, 0.9);
        let t = hipgr::time() as! f32;
        let spin = if spinning { t } else { 0.0 };

        if !hipgr::begin_frame(dev, cam, float4 { 0.045, 0.05, 0.07, 1.0 }) { break; }

        // A grid of tiled cubes, each turning with its distance from the middle.
        for i in 49 {
            let x = (i % 7) - 3;
            let z = (i / 7) - 3;
            let d = hipgr::mat4_spin(float3 { x * 1.6, 0.0, z * 1.6 - 1.0 },
                                     spin * 0.3 + (x + z) * 0.2, 0.45);
            hipgr::draw(dev, cube, tiled, d);
        }
        // The subject: one cube, larger, spinning the other way.
        let hero = hipgr::mat4_trs(float3 { 0.0, 1.4, 0.0 }, float3 { 0.0, 1.0, 0.0 }, -spin * 0.9,
                                   float3 { 1.1, 1.1, 1.1 });
        hipgr::draw(dev, cube, plain, hero);

        if !hipgr::end_frame(dev) { break; }
        frames++;
        if max_frames > 0 && frames >= max_frames { break; }
    }

    if shot_path.len != 0 { hipgr::screenshot(dev, shot_path); }

    let elapsed = hipgr::time() - started;
    let s = hipgr::stats(dev);
    print("frames ", s.frames, ", draws ", s.draws, ", triangles ", s.triangles, "\n");
    if elapsed > 0.0 {
        print("average ", elapsed / s.frames * 1000.0, " ms/frame\n");
    }
}
