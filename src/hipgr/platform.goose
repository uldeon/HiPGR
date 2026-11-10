// HiPGR: the small amount of platform surface a renderer demo needs.
//
// This is a facade, not an input system: applications with their own input
// layer use that instead. It exists so that a HiPGR program never has to
// import the graphics backend to read a key or the clock.
namespace hipgr;

import vec;
import .gpu;

fn quit() { gpu_quit(); }

// Seconds since the device opened, and the last frame's duration.
fn time() -> f64 { gpu_time() }

fn delta_time() -> f64 { gpu_delta_time() }

// SDL key names: "A", "Space", "Left", "Escape".
fn key_down(name: const u8[:]) -> bool { gpu_key_down(name) }

fn key_pressed(name: const u8[:]) -> bool { gpu_key_pressed(name) }

// Mouse motion since the last frame, in screen pixels.
fn mouse_delta() -> float2 { gpu_mouse_delta() }

fn mouse_position() -> float2 { gpu_mouse_pos() }

// First-person mouse capture: confines the pointer and hides the cursor.
fn capture_mouse(on: bool) -> bool { gpu_set_mouse_relative(on) }
