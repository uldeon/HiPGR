// HiPGR - High Performance Goose Renderer: public entry point.
//
// Import this package and nothing else:
//
//   import hipgr from "../src/hipgr";
//
// Every public name lives in namespace hipgr. The modules it re-exports are
// organised by responsibility:
//
//   handle    public handle encoding and generations
//   math      Mat4 and the transforms applications build
//   gpu       the backend boundary: the only module issuing backend calls
//   device    Device, resource records, handle validation, lifetime
//   mesh      Vertex, Mesh, built-in geometry
//   image     Image: RGBA8 textures
//   camera    Camera and projections
//   material  Material, the built-in shaders, the directional light
//   renderer  frame lifecycle and draw submission
//   platform  keys, mouse, clock
//
// 0.1 is a GPU foundation, not the finished renderer: see ROADMAP.md for what
// each milestone adds and PROGRESS.md for what is actually verified.
namespace hipgr;

import .handle;
import .math;
import .gpu;
import .device;
import .mesh;
import .camera;
import .image;
import .material;
import .renderer;
import .platform;

fn version() -> u8[:] { "0.1.0" }
