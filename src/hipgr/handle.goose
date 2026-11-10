// HiPGR: public handles.
//
// Every HiPGR resource is addressed by a 32-bit handle: an index into the
// device's record array in the low 24 bits, and a generation in the top 8.
// A handle to a released resource is detected, never dereferenced.
namespace hipgr;

// The resource handle types. They are declared here, in the module with no
// dependencies, so the device and the resource modules can all name them
// without importing each other.
struct Mesh { id: u32 }
struct Image { id: u32 }
struct Material { id: u32 }

let HANDLE_INDEX_BITS: i32 = 24;
let HANDLE_GENERATION_MAX: i32 = 255;
let HANDLE_INDEX_MASK: u32 = 16777215;

fn handle_make(index: i64, generation: i32) -> u32 {
    (generation as u32) << HANDLE_INDEX_BITS | (index as u32)
}

fn handle_index(id: u32) -> i64 {
    id & HANDLE_INDEX_MASK
}

fn handle_generation(id: u32) -> i32 {
    (id >> HANDLE_INDEX_BITS) as i32
}

// The next generation of a slot, wrapping to 1 (0 is never a live handle).
fn next_generation(g: i32) -> i32 {
    if g >= HANDLE_GENERATION_MAX { 1 } else { g + 1 }
}
