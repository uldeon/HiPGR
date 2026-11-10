// Assertions and pixel checks shared by the HiPGR tests.
//
// A test is a Goose program: it renders, checks what the GPU actually
// produced, and prints PASS on the last line. A failed check aborts with the
// reason and a non-zero exit status, which scripts/test.sh reports.
namespace verify;

import std;
import os;
import vec;

fn fail(what: const u8[:]) {
    write_stderr(str("FAIL: ", what, "\n"));
    abort("hipgr test failed");
}

fn expect(cond: bool, what: const u8[:]) { if !cond { fail(what); } }

// Not run at all: on a machine with no GPU device nothing was validated, and
// the runner says so rather than counting a pass.
fn skip(what: const u8[:]) { print("SKIP ", what, "\n"); }

fn expect_near(got: f32, want: f32, tolerance: f32, what: const u8[:]) {
    let d = got - want;
    let ad = if d < 0.0 { -d } else { d };
    if ad > tolerance {
        write_stderr(str("FAIL: ", what, ": got ", got, ", want ", want, "\n"));
        abort("hipgr test failed");
    }
}

fn expect_eq(got: i64, want: i64, what: const u8[:]) {
    if got != want {
        write_stderr(str("FAIL: ", what, ": got ", got, ", want ", want, "\n"));
        abort("hipgr test failed");
    }
}

fn expect_ne(a: i64, b: i64, what: const u8[:]) {
    if a == b {
        write_stderr(str("FAIL: ", what, ": both ", a, "\n"));
        abort("hipgr test failed");
    }
}

fn pixel(px: const u8[:], width: i64, x: i64, y: i64) -> u8[4] {
    let o = (y * width + x) * 4;
    return [px[o], px[o + 1], px[o + 2], px[o + 3]];
}

fn close_to(a: u8, b: u8, tolerance: i32) -> bool {
    let d = a as i32 - b;
    let ad = if d < 0 { -d } else { d };
    return ad <= tolerance;
}

fn same_color(a: u8[4], b: u8[4], tolerance: i32) -> bool {
    close_to(a[0], b[0], tolerance) && close_to(a[1], b[1], tolerance)
        && close_to(a[2], b[2], tolerance)
}

fn expect_pixel(px: const u8[:], width: i64, x: i64, y: i64, want: u8[4], tolerance: i32,
                what: const u8[:]) {
    let got = pixel(px, width, x, y);
    if !same_color(got, want, tolerance) {
        write_stderr(str("FAIL: ", what, " at ", x, ",", y, ": got ", got[0], ",", got[1], ",",
                         got[2], " want ", want[0], ",", want[1], ",", want[2], "\n"));
        abort("hipgr test failed");
    }
}

fn expect_not_pixel(px: const u8[:], width: i64, x: i64, y: i64, unwanted: u8[4], tolerance: i32,
                    what: const u8[:]) {
    let got = pixel(px, width, x, y);
    if same_color(got, unwanted, tolerance) {
        write_stderr(str("FAIL: ", what, " at ", x, ",", y, ": still ", got[0], ",", got[1], ",",
                         got[2], "\n"));
        abort("hipgr test failed");
    }
}

// How many pixels match a colour: proof that a texture filled an area rather
// than a single lucky sample point.
fn count_color(px: const u8[:], want: u8[4], tolerance: i32) -> i64 {
    var n = 0;
    var i = 0;
    while i + 3 < px.len {
        if same_color([px[i], px[i + 1], px[i + 2], px[i + 3]], want, tolerance) { n++; }
        i += 4;
    }
    return n;
}

// How many pixels differ between two frames of the same size.
fn count_different(a: const u8[:], b: const u8[:]) -> i64 {
    if a.len != b.len { return -1; }
    var n = 0;
    var i = 0;
    while i + 3 < a.len {
        if !same_color([a[i], a[i + 1], a[i + 2], a[i + 3]],
                       [b[i], b[i + 1], b[i + 2], b[i + 3]], 2) { n++; }
        i += 4;
    }
    return n;
}

fn pass(name: const u8[:]) { print("PASS ", name, "\n"); }
